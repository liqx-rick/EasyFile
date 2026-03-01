import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/duplicate_file_scan_config.dart';
import 'package:easyfile/core/models/junk_file_scan_config.dart';
import 'package:easyfile/core/models/large_file_scan_config.dart';
import 'package:easyfile/core/services/duplicate_file_service.dart';
import 'package:easyfile/core/services/enhanced_duplicate_file_scan_service.dart';
import 'package:easyfile/core/services/large_file_service.dart';
import 'package:easyfile/core/services/smart_task_generator.dart';
import 'package:easyfile/data/models/task_card.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/pages/apk_management_page.dart';
import 'package:easyfile/ui/pages/app_management_page.dart';
import 'package:easyfile/ui/pages/duplicate_files_page.dart';
import 'package:easyfile/ui/pages/junk_files_page.dart';
import 'package:easyfile/ui/pages/large_files_page.dart';
import 'package:easyfile/ui/pages/new_files_page.dart';
import 'package:easyfile/ui/pages/storage_management_page.dart';
import 'package:easyfile/ui/pages/trash_files_page.dart';
import 'package:easyfile/ui/widgets/task_card_widget.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 智能助手页（负一屏）
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _taskGenerator = SmartTaskGenerator();
  List<TaskCard> _tasks = [];
  bool _isRefreshing = false;
  bool _isBackgroundScanning = false;
  String _backgroundScanStatus = ''; // 后台扫描状态提示
  int _backgroundScanAttempts = 0; // 后台扫描尝试次数
  static const int _maxBackgroundScanAttempts = 1; // 最多尝试1次

  // 存储统计数据
  double? _totalSpace;
  double? _freeSpace;

  // 最近活动（简化版，占位数据）
  final List<String> _recentActivities = [];

  // 已忽略的任务类型（Map<TaskType, DateTime> 存储忽略时间）
  final Map<TaskType, DateTime> _dismissedTasks = {};

  // 忽略任务的有效期（天）
  static const int _dismissExpireDays = 7;

  @override
  void initState() {
    super.initState();
    _loadDismissedTasks();
    _loadTasks();
    _loadStorageStats();
    _loadRecentActivities();
  }

  /// 加载已忽略的任务
  Future<void> _loadDismissedTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getStringList('dismissed_tasks') ?? [];

      final now = DateTime.now();
      for (final item in dismissed) {
        final parts = item.split('|');
        if (parts.length == 2) {
          final type = TaskType.values.firstWhere(
            (t) => t.toString() == parts[0],
            orElse: () => TaskType.duplicateFiles,
          );
          final timestamp = int.tryParse(parts[1]) ?? 0;
          final dismissTime = DateTime.fromMillisecondsSinceEpoch(timestamp);

          // 只加载未过期的忽略任务（7天内）
          if (now.difference(dismissTime).inDays < _dismissExpireDays) {
            _dismissedTasks[type] = dismissTime;
          }
        }
      }

      logger.d('加载已忽略任务: ${_dismissedTasks.length}个');
    } catch (e) {
      logger.e('加载已忽略任务失败: $e');
    }
  }

  /// 保存已忽略的任务
  Future<void> _saveDismissedTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed =
          _dismissedTasks.entries.map((e) => '${e.key.toString()}|${e.value.millisecondsSinceEpoch}').toList();
      await prefs.setStringList('dismissed_tasks', dismissed);
      logger.d('保存已忽略任务: ${dismissed.length}个');
    } catch (e) {
      logger.e('保存已忽略任务失败: $e');
    }
  }

  /// 加载任务列表
  Future<void> _loadTasks({bool forceRefresh = false}) async {
    if (forceRefresh) {
      setState(() {
        _isRefreshing = true;
        _backgroundScanStatus = '';
      });
      // 手动刷新时，清除所有忽略状态（用户想看最新的所有任务）
      _dismissedTasks.clear();
      await _saveDismissedTasks();
      // 手动刷新时重置扫描尝试计数器
      _backgroundScanAttempts = 0;
    }

    try {
      final tasks = await _taskGenerator.generateTasks(
        onTaskAction: _handleTaskAction,
        onTaskDismiss: _handleTaskDismiss,
      );

      // 过滤掉已忽略且未过期的任务
      final now = DateTime.now();
      final filteredTasks = tasks.where((task) {
        final dismissTime = _dismissedTasks[task.type];
        if (dismissTime == null) return true;

        // 检查是否过期
        final isExpired = now.difference(dismissTime).inDays >= _dismissExpireDays;
        if (isExpired) {
          _dismissedTasks.remove(task.type);
          return true;
        }
        return false;
      }).toList();

      if (mounted) {
        setState(() {
          _tasks = filteredTasks;
          _isRefreshing = false;
        });
      }

      // 只在首次加载或手动刷新时检查后台扫描（避免死循环）
      // startBackgroundScan 会智能地只扫描缺失的类型
      if (!_isBackgroundScanning && _backgroundScanAttempts < _maxBackgroundScanAttempts) {
        _startBackgroundScanIfNeeded();
      }
    } catch (e) {
      logger.e('加载任务失败: $e');
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _backgroundScanStatus = '';
        });
      }
    }
  }

  /// 如果需要，启动后台扫描
  Future<void> _startBackgroundScanIfNeeded() async {
    logger.i('检查是否需要启动后台扫描...');

    final cacheStatus = await _taskGenerator.checkCacheStatus();
    final hasDuplicateCache = cacheStatus['hasDuplicateCache'] as bool;
    final hasLargeFileCache = cacheStatus['hasLargeFileCache'] as bool;
    final hasTrashCache = cacheStatus['hasTrashCache'] as bool;

    // 如果所有类型都有缓存，跳过后台扫描
    if (hasDuplicateCache && hasLargeFileCache && hasTrashCache) {
      logger.d('所有类型都有缓存数据，跳过后台扫描');
      return;
    }

    // 记录需要扫描的类型
    final missingTypes = <String>[];
    if (!hasDuplicateCache) missingTypes.add('重复文件');
    if (!hasLargeFileCache) missingTypes.add('大文件');
    if (!hasTrashCache) missingTypes.add('系统回收站');

    logger.i('缺失缓存类型: ${missingTypes.join(", ")}，启动后台扫描（第${_backgroundScanAttempts + 1}次尝试）...');

    setState(() {
      _isBackgroundScanning = true;
      _backgroundScanStatus = '智能助手正在检查是否有可优化的任务，请稍候...';
      _backgroundScanAttempts++; // 增加尝试次数
    });

    try {
      await _taskGenerator.startBackgroundScan(
        onProgress: (message) {
          // 保持固定文案，不显示具体进度
          logger.d('后台扫描进度: $message');
        },
        onComplete: () async {
          logger.i('后台扫描完成，刷新任务列表');
          if (mounted) {
            setState(() {
              _isBackgroundScanning = false;
              _backgroundScanStatus = '';
            });
            // 重新加载任务（但不会再次触发后台扫描，因为已达到最大尝试次数）
            await _loadTasks();
          }
        },
      );
    } catch (e) {
      logger.e('后台扫描失败: $e');
      if (mounted) {
        setState(() {
          _isBackgroundScanning = false;
          _backgroundScanStatus = '';
        });
      }
    }
  }

  /// 加载存储统计数据
  Future<void> _loadStorageStats() async {
    try {
      final diskSpace = DiskSpacePlus();
      final totalSpace = await diskSpace.getTotalDiskSpace;
      final freeSpace = await diskSpace.getFreeDiskSpace;

      if (mounted) {
        setState(() {
          _totalSpace = totalSpace;
          _freeSpace = freeSpace;
        });
      }
    } catch (e) {
      logger.e('加载存储统计失败: $e');
    }
  }

  /// 加载最近活动
  Future<void> _loadRecentActivities() async {
    // TODO: 从AppTrashManager和操作日志获取真实数据
    // 这里先使用占位数据
    if (mounted) {
      setState(() {
        _recentActivities.addAll([
          '清理了 234 MB 垃圾文件',
          '整理了 12 个重复文件',
          '移入隐私空间 3 个文件',
        ]);
      });
    }
  }

  /// 处理任务操作
  void _handleTaskAction(TaskType type) {
    logger.i('执行任务: $type');

    switch (type) {
      case TaskType.duplicateFiles:
        _navigateToDuplicateFiles();
        break;
      case TaskType.largeFiles:
        _navigateToLargeFiles();
        break;
      case TaskType.junkFiles:
        _navigateToJunkFiles();
        break;
      case TaskType.apkFiles:
        _navigateToApkManagement();
        break;
      case TaskType.systemTrash:
        _navigateToTrashFiles();
        break;
      case TaskType.appCache:
        _openAppSettings();
        break;
    }
  }

  /// 处理任务忽略
  void _handleTaskDismiss(TaskType type) {
    logger.i('忽略任务: $type');

    setState(() {
      _dismissedTasks[type] = DateTime.now();
      _tasks.removeWhere((task) => task.type == type);
    });

    // 持久化忽略状态
    _saveDismissedTasks();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已忽略此任务（$_dismissExpireDays天后自动恢复）'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            setState(() {
              _dismissedTasks.remove(type);
            });
            _saveDismissedTasks();
            _loadTasks();
          },
        ),
      ),
    );
  }

  /// 跳转到重复文件页面
  void _navigateToDuplicateFiles() {
    final presenter = locator<FilePresenter>();
    final duplicateService = DuplicateFileService(presenter);
    final enhancedService = EnhancedDuplicateFileScanService(duplicateService);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DuplicateFilesPage(
          enhancedScanService: enhancedService,
          initialConfig: DuplicateFileScanConfig(
            scanMode: DuplicateScanMode.full,
          ),
        ),
      ),
    );
  }

  /// 跳转到大文件页面
  void _navigateToLargeFiles() {
    // 直接创建LargeFileService实例（不使用依赖注入，因为它没有注册）
    final presenter = locator<FilePresenter>();
    final largeFileService = LargeFileService(presenter);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LargeFilesPage(
          largeFileService: largeFileService,
          initialConfig: const LargeFileScanConfig(
            minSizeInMB: 100,
          ),
        ),
      ),
    );
  }

  /// 跳转到垃圾文件页面
  void _navigateToJunkFiles() async {
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const JunkFilesPage(
          initialConfig: JunkFileScanConfig(),
        ),
      ),
    );
  }

  /// 跳转到系统回收站页面
  void _navigateToTrashFiles() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TrashFilesPage(),
      ),
    );
  }

  /// 跳转到APK安装包管理页面
  void _navigateToApkManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ApkManagementPage(),
      ),
    );
  }

  /// 跳转到新文件列表页面
  void _navigateToNewFiles() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NewFilesPage(retentionDays: 7),
      ),
    );
  }

  /// 打开应用管理页面（查看应用缓存）
  void _openAppSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AppManagementPage(),
      ),
    );
  }

  /// 跳转到存储管理页
  void _navigateToStorageManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const StorageManagementPage(),
      ),
    );
  }

  /// 刷新页面
  Future<void> _refresh() async {
    await _loadTasks(forceRefresh: true);
    await _loadStorageStats();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('智能助手'),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refresh,
            tooltip: '刷新',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 智能任务卡片
            _buildTasksSection(theme),
            const SizedBox(height: 24),

            // 快速操作
            _buildQuickActionsSection(theme),
            const SizedBox(height: 24),

            // 简要统计
            _buildStatisticsSection(theme),
            const SizedBox(height: 24),

            // 最近活动
            _buildRecentActivitiesSection(theme),
            const SizedBox(height: 24),

            // 提示：向右滑动
            _buildSwipeHint(theme),
          ],
        ),
      ),
    );
  }

  /// 构建任务卡片区域
  Widget _buildTasksSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('🎯', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(
              '待办任务',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isBackgroundScanning && _tasks.isEmpty)
          _buildScanningTaskCard(theme)
        else if (_tasks.isEmpty)
          _buildEmptyTaskCard(theme)
        else
          ..._tasks.map((task) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TaskCardWidget(task: task),
              )),
        // 后台扫描提示（有任务时显示在底部）
        if (_isBackgroundScanning && _tasks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _buildBackgroundScanningHint(theme),
          ),
      ],
    );
  }

  /// 构建扫描中的状态卡片
  Widget _buildScanningTaskCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              '智能扫描中',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _backgroundScanStatus.isNotEmpty ? _backgroundScanStatus : '智能助手正在检查是否有可优化的任务，请稍候...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建后台扫描提示
  Widget _buildBackgroundScanningHint(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '智能助手正在检查是否有可优化的任务，请稍候...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建空状态任务卡
  Widget _buildEmptyTaskCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Colors.green[400],
            ),
            const SizedBox(height: 16),
            Text(
              '设备状态良好',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '暂无优化建议',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建快速操作区域
  Widget _buildQuickActionsSection(ThemeData theme) {
    final quickActions = [
      _QuickAction(
        icon: Icons.storage,
        label: '大文件',
        color: Colors.blue,
        onTap: _navigateToLargeFiles,
      ),
      _QuickAction(
        icon: Icons.content_copy,
        label: '重复文件',
        color: Colors.orange,
        onTap: _navigateToDuplicateFiles,
      ),
      _QuickAction(
        icon: Icons.delete_outline,
        label: '系统回收站',
        color: Colors.brown,
        onTap: _navigateToTrashFiles,
      ),
      _QuickAction(
        icon: Icons.android,
        label: '安装包',
        color: Colors.green,
        onTap: _navigateToApkManagement,
      ),
      _QuickAction(
        icon: Icons.cached,
        label: '应用缓存',
        color: Colors.purple,
        onTap: _openAppSettings,
      ),
      _QuickAction(
        icon: Icons.fiber_new,
        label: '新文件',
        color: Colors.teal,
        onTap: _navigateToNewFiles,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('⚡', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(
              '快速操作',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: quickActions.map((action) => _buildQuickActionCard(action, theme)).toList(),
        ),
      ],
    );
  }

  /// 构建快速操作卡片
  Widget _buildQuickActionCard(_QuickAction action, ThemeData theme) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              action.icon,
              size: 32,
              color: action.color,
            ),
            const SizedBox(height: 8),
            Text(
              action.label,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建简要统计区域
  Widget _buildStatisticsSection(ThemeData theme) {
    final freeSpacePercent = (_freeSpace != null && _totalSpace != null) ? (_freeSpace! / _totalSpace! * 100) : 0.0;

    // 根据可用空间百分比确定状态
    final isCritical = freeSpacePercent < 10; // 告急：<10%
    final isLow = freeSpacePercent >= 10 && freeSpacePercent < 20; // 紧张：10-20%

    // 确定状态颜色和图标
    Color statusColor;
    IconData statusIcon;
    String statusText;
    Color? cardColor;

    if (isCritical) {
      statusColor = Colors.red[700]!;
      statusIcon = Icons.error;
      statusText = '存储空间告急！';
      cardColor = Colors.red[50];
    } else if (isLow) {
      statusColor = Colors.orange[700]!;
      statusIcon = Icons.warning_amber;
      statusText = '存储空间紧张';
      cardColor = Colors.orange[50];
    } else {
      statusColor = Colors.green[700]!;
      statusIcon = Icons.check_circle;
      statusText = '存储空间充足';
      cardColor = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('📊', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(
              '空间健康',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _navigateToStorageManagement,
          borderRadius: BorderRadius.circular(12),
          child: Card(
            color: cardColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_freeSpace != null && _totalSpace != null) ...[
                    // 状态标题
                    Row(
                      children: [
                        Icon(statusIcon, color: statusColor, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          statusText,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 剩余空间
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '剩余空间',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          '${FileSizeFormatter.formatBytesWithSpace((_freeSpace! * 1024 * 1024).toInt())} (${freeSpacePercent.toStringAsFixed(1)}%)',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                    // 告急状态：建议清理量
                    if (isCritical) ...[
                      const SizedBox(height: 8),
                      Text(
                        '建议清理至少 ${FileSizeFormatter.formatBytesWithSpace(((_totalSpace! * 0.1 - _freeSpace!) * 1024 * 1024).toInt())}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red[600],
                        ),
                      ),
                    ],
                  ] else
                    const Text('正在加载...'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        isCritical || isLow ? '立即清理' : '查看详情',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 12,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建最近活动区域
  Widget _buildRecentActivitiesSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('📝', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(
              '最近活动',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _recentActivities.isEmpty
                ? const Text('暂无操作记录')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _recentActivities
                        .map((activity) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(activity, style: theme.textTheme.bodyMedium),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ),
      ],
    );
  }

  /// 构建滑动提示
  Widget _buildSwipeHint(ThemeData theme) {
    return Center(
      child: Text(
        '← 向右滑动返回主页',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
        ),
      ),
    );
  }
}

/// 快速操作数据类
class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}
