import 'package:easyfile/analytics/analytics_helper.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/services/app_file_list_cache.dart';
import 'package:easyfile/core/services/cache_manager_service.dart';
import 'package:easyfile/core/services/duplicate_file_service.dart';
import 'package:easyfile/core/services/enhanced_duplicate_file_scan_service.dart';
import 'package:easyfile/core/services/file_count_cache.dart';
import 'package:easyfile/core/services/file_display_settings_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/recommendation_service.dart';
import 'package:easyfile/core/services/trash_file_service.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/dialogs/quick_cache_clear_dialog.dart';
import 'package:easyfile/ui/pages/file_display_settings_page.dart';
import 'package:easyfile/ui/pages/mediastore_scan_test_page.dart';
import 'package:easyfile/ui/pages/new_files_settings_page.dart';
import 'package:easyfile/ui/pages/trash_config_page.dart';
import 'package:easyfile/ui/utils/system_trash_diagnostics.dart';
import 'package:easyfile/ui/widgets/quick_access_section.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settingsService = PageSettingsService();
  final _displaySettings = FileDisplaySettingsService();

  int _minFileSize = FileDisplaySettingsService.defaultMinFileSize;
  int _recommendationThreshold = 5; // 将从AppConfig加载

  // 推荐选择信息
  bool _hasRecommendationSelection = false;
  int _selectedRecommendationCount = 0;
  DateTime? _recommendationSelectionTime;
  int? _savedSelectionThreshold;

  @override
  void initState() {
    super.initState();
    AnalyticsHelper.logSettingsEnter();

    // 初始化重复文件扫描服务：注入依赖到CacheManagerService，供缓存清理页面使用
    final presenter = locator<FilePresenter>();
    final duplicateFileService = DuplicateFileService(presenter);
    final enhancedScanService = EnhancedDuplicateFileScanService(duplicateFileService);
    CacheManagerService().setDuplicateFileScanService(enhancedScanService);

    // 初始化统一应用扫描器：注入依赖到CacheManagerService
    _initAppScanner();

    // 初始化系统回收站服务：注入依赖到CacheManagerService
    _initTrashFileService();

    _loadSettings();
  }

  /// 初始化统一应用扫描器
  Future<void> _initAppScanner() async {
    try {
      final appScanner = await locator.getAsync<UnifiedAppScanner>();
      CacheManagerService().setAppScanner(appScanner);
    } catch (e) {
      logger.e('Failed to initialize UnifiedAppScanner for cache management: $e');
    }
  }

  /// 初始化系统回收站服务
  Future<void> _initTrashFileService() async {
    try {
      final trashFileService = await locator.getAsync<TrashFileService>();
      CacheManagerService().setTrashFileService(trashFileService);
    } catch (e) {
      logger.e('Failed to initialize TrashFileService for cache management: $e');
    }
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    final minSize = await _displaySettings.getMinFileSize();
    final recThreshold = AppConfig.instance.fileScan.recommendationFileCountThreshold;

    // 加载推荐选择信息
    await _loadRecommendationSelectionInfo();

    setState(() {
      _minFileSize = minSize;
      _recommendationThreshold = recThreshold;
    });
  }

  /// 加载推荐选择信息
  Future<void> _loadRecommendationSelectionInfo() async {
    try {
      final detectionService = AppDetectionService();
      final fileCountCache = await locator.getAsync<FileCountCache>();
      final fileListCache = await locator.getAsync<AppFileListCache>();
      final scanner = UnifiedAppScanner(
        detectionService,
        fileCountCache: fileCountCache,
        fileListCache: fileListCache,
      );
      final recommendationService = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
      );

      final info = await recommendationService.getSelectionInfo();

      logger.d('📊 加载推荐选择信息:');
      logger.d('  hasSelection: ${info['hasSelection']}');
      logger.d('  selectedCount: ${info['selectedCount']}');
      logger.d('  selectionTime: ${info['selectionTime']}');
      logger.d('  selectionThreshold: ${info['selectionThreshold']}');
      logger.d('  selectedAppKeys: ${info['selectedAppKeys']}');

      if (mounted) {
        setState(() {
          _hasRecommendationSelection = info['hasSelection'] as bool;
          _selectedRecommendationCount = info['selectedCount'] as int;
          _recommendationSelectionTime = info['selectionTime'] as DateTime?;
          _savedSelectionThreshold = info['selectionThreshold'] as int?;
        });
      }
    } catch (e) {
      logger.e('加载推荐选择信息失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        elevation: 0,
      ),
      body: ListView(
        children: [
          // 显示偏好部分
          _buildSectionHeader('显示偏好', Icons.visibility),
          _buildThemeModeTile(context),
          const Divider(height: 1, indent: 56),
          _buildViewSortRestoreTile(context),
          const Divider(height: 1, indent: 56),
          _buildFileDisplayTile(context),
          const Divider(height: 1, indent: 56),
          _buildHideEmptyFoldersTile(context),

          const Divider(height: 32),

          // 存储与缓存管理
          _buildSectionHeader('存储与缓存', Icons.storage),
          _buildCacheManagementTile(context),

          const Divider(height: 32),

          // 功能设置（至少有一个功能启用时才显示）
          if (AppConfig.instance.feature.isNewFilesEnabled || AppConfig.instance.feature.isTrashEnabled) ...[
            _buildSectionHeader('功能设置', Icons.tune),
            if (AppConfig.instance.feature.isNewFilesEnabled) ...[
              _buildNewFilesPrivacyTile(context),
              if (AppConfig.instance.feature.isTrashEnabled) const Divider(height: 1, indent: 56),
            ],
            // 回收站设置
            if (AppConfig.instance.feature.isTrashEnabled) _buildTrashTile(context),
            const Divider(height: 32),
          ],

          // 开发者选项（根据配置决定是否显示）
          if (AppConfig.instance.feature.isDeveloperOptionsEnabled) ...[
            _buildSectionHeader('开发者选项', Icons.developer_mode),
            _buildRecommendationThresholdTile(context),
            const Divider(height: 1, indent: 56),
            _buildDuplicateScanSettingTile(context),
            const Divider(height: 1, indent: 56),
            _buildSystemTrashDiagnosticsTile(context),
            const Divider(height: 1, indent: 56),
            _buildScanTestTile(context, 'APK扫描性能测试', CategoryType.apk, Icons.android),
            _buildScanTestTile(context, '压缩包扫描性能测试', CategoryType.archive, Icons.archive),
            const Divider(height: 32),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 构建分节标题
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  /// 主题模式设置
  Widget _buildThemeModeTile(BuildContext context) {
    final viewModel = context.watch<FileViewModel>();
    final currentTheme = viewModel.themeMode;

    String getThemeText(ThemeMode mode) {
      switch (mode) {
        case ThemeMode.light:
          return '浅色';
        case ThemeMode.dark:
          return '深色';
        case ThemeMode.system:
          return '跟随系统';
      }
    }

    IconData getThemeIcon(ThemeMode mode) {
      switch (mode) {
        case ThemeMode.light:
          return Icons.light_mode;
        case ThemeMode.dark:
          return Icons.dark_mode;
        case ThemeMode.system:
          return Icons.brightness_auto;
      }
    }

    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(getThemeIcon(currentTheme), color: colorScheme.primary),
      title: const Text('外观主题'),
      subtitle: Text('当前：${getThemeText(currentTheme)}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showThemeDialog(context, viewModel),
    );
  }

  /// 显示主题选择对话框
  void _showThemeDialog(BuildContext context, FileViewModel viewModel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题模式'),
        content: SingleChildScrollView(
          child: RadioGroup<ThemeMode>(
            groupValue: viewModel.themeMode,
            onChanged: (value) async {
              if (value != null) {
                logger.i('Theme selected in dialog: $value');
                AnalyticsHelper.logSettingsChange('theme_mode', value.toString());
                // 通过 Presenter 保存，确保同时保存到JSON和SharedPreferences
                final presenter = locator<FilePresenter>();
                await presenter.setThemeMode(value);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<ThemeMode>(
                  title: const Row(
                    children: [
                      Icon(Icons.light_mode, size: 20),
                      SizedBox(width: 12),
                      Text('浅色'),
                    ],
                  ),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: const Row(
                    children: [
                      Icon(Icons.dark_mode, size: 20),
                      SizedBox(width: 12),
                      Text('深色'),
                    ],
                  ),
                  value: ThemeMode.dark,
                ),
                RadioListTile<ThemeMode>(
                  title: const Row(
                    children: [
                      Icon(Icons.brightness_auto, size: 20),
                      SizedBox(width: 12),
                      Text('跟随系统'),
                    ],
                  ),
                  subtitle: const Text(
                    '根据系统设置自动切换',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: ThemeMode.system,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 视图与排序恢复（ExpansionTile形式）
  Widget _buildViewSortRestoreTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      leading: Icon(Icons.view_module, color: colorScheme.primary),
      title: const Text('视图与排序'),
      subtitle: const Text('一键恢复所有页面为推荐设置'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '这将重置所有页面的视图模式、排序方式和分组设置',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _showRestoreDialog(context),
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('恢复推荐设置'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 文件显示配置入口
  Widget _buildFileDisplayTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.description, color: colorScheme.primary),
      title: const Text('文件显示'),
      subtitle: const Text('文件信息、路径、隐藏文件等'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const FileDisplaySettingsPage(),
          ),
        );
      },
    );
  }

  /// 隐藏空文件夹开关
  Widget _buildHideEmptyFoldersTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<bool>(
      future: _displaySettings.getHideEmptyFolders(),
      builder: (context, snapshot) {
        final hideEmpty = snapshot.data ?? true;

        return SwitchListTile(
          secondary: Icon(
            hideEmpty ? Icons.folder_off : Icons.folder_open,
            color: colorScheme.primary,
          ),
          title: const Text('隐藏空文件夹'),
          subtitle: Text(
            hideEmpty ? '快速访问菜单中不显示空目录' : '快速访问菜单中显示所有目录',
            style: const TextStyle(fontSize: 13),
          ),
          value: hideEmpty,
          onChanged: (value) async {
            AnalyticsHelper.logSettingsChange('hide_empty_folders', value.toString());
            await _displaySettings.setHideEmptyFolders(value);
            setState(() {}); // 触发重建以更新UI
          },
        );
      },
    );
  }

  /// 显示恢复确认对话框
  void _showRestoreDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复推荐设置'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('这将重置以下内容为推荐值：'),
            SizedBox(height: 8),
            Text('• 所有页面的视图模式（列表/网格）'),
            Text('• 所有页面的排序方式'),
            Text('• 所有页面的分组设置'),
            SizedBox(height: 8),
            Text(
              '您之前的个性化设置将被覆盖。',
              style: TextStyle(color: Colors.orange, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await _settingsService.resetToDefaults();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已恢复推荐设置')),
                );
              }
            },
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
  }

  /// 重复文件扫描设置（展开式）
  Widget _buildDuplicateScanSettingTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      leading: Icon(Icons.content_copy, color: colorScheme.primary),
      title: const Text('重复文件清理'),
      subtitle: Text(
        '最小文件阈值：${FileDisplaySettingsService.formatFileSize(_minFileSize)}',
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.of(context).size.width * 0.1,
            vertical: 2,
          ),
          child: Row(
            children: [
              Text(
                FileDisplaySettingsService.formatFileSize(
                  FileDisplaySettingsService.minFileSizeMin,
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Slider(
                  value: _minFileSize.toDouble(),
                  min: FileDisplaySettingsService.minFileSizeMin.toDouble(),
                  max: FileDisplaySettingsService.minFileSizeMax.toDouble(),
                  divisions: 99, // 100 steps from 10KB to 10MB
                  label: FileDisplaySettingsService.formatFileSize(_minFileSize),
                  onChanged: (value) {
                    setState(() {
                      _minFileSize = value.toInt();
                    });
                  },
                  onChangeEnd: (value) async {
                    AnalyticsHelper.logSettingsChange('min_file_size', value.toInt().toString());
                    await _displaySettings.setMinFileSize(value.toInt());
                  },
                ),
              ),
              Text(
                FileDisplaySettingsService.formatFileSize(
                  FileDisplaySettingsService.minFileSizeMax,
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 缓存管理入口
  Widget _buildCacheManagementTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.cleaning_services, color: colorScheme.primary),
      title: const Text('缓存清理'),
      subtitle: const Text('清理应用缩略图、扫描等产生的缓存'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        logger.d('Opening quick cache clear dialog');
        final cacheManager = locator<CacheManagerService>();
        await showDialog(
          context: context,
          builder: (context) => QuickCacheClearDialog(
            cacheManager: cacheManager,
          ),
        );
      },
    );
  }

  /// 回收站入口
  Widget _buildTrashTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.settings, color: colorScheme.primary),
      title: const Text('回收站设置'),
      subtitle: const Text('启用回收站，自动清理周期等'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const TrashConfigPage(),
          ),
        );
      },
    );
  }

  /// 扫描性能测试入口
  Widget _buildScanTestTile(
    BuildContext context,
    String title,
    CategoryType categoryType,
    IconData icon,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(icon, color: colorScheme.primary),
      title: Text(title),
      subtitle: const Text('对比 MediaStore 和文件系统的扫描性能'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MediaStoreScanTestPage(
              categoryType: categoryType,
            ),
          ),
        );
      },
    );
  }

  /// 新文件设置入口
  Widget _buildNewFilesPrivacyTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.fiber_new, color: colorScheme.primary),
      title: const Text('新文件'),
      subtitle: const Text('设置主页新文件发现功能模块的扫描范围、时间跨度等'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const NewFilesSettingsPage(),
          ),
        );
      },
    );
  }

  /// 首页推荐文件数量阈值设置
  Widget _buildRecommendationThresholdTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 检查阈值是否与保存的选择阈值不同
    final thresholdChanged = _hasRecommendationSelection &&
        _savedSelectionThreshold != null &&
        _savedSelectionThreshold != _recommendationThreshold;

    // 调试日志
    logger.d('🔍 推荐阈值调试信息:');
    logger.d('  _hasRecommendationSelection: $_hasRecommendationSelection');
    logger.d('  _savedSelectionThreshold: $_savedSelectionThreshold');
    logger.d('  _recommendationThreshold: $_recommendationThreshold');
    logger.d('  _selectedRecommendationCount: $_selectedRecommendationCount');
    logger.d('  _recommendationSelectionTime: $_recommendationSelectionTime');
    logger.d('  thresholdChanged: $thresholdChanged');

    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.filter_list, color: colorScheme.primary),
          title: const Text('首页推荐应用文件数量阈值'),
          subtitle: Text(_hasRecommendationSelection
              ? '当前阈值：$_recommendationThreshold 个文件\n已选定 $_selectedRecommendationCount 个应用'
              : '当前阈值：$_recommendationThreshold 个文件\n将在首次打开首页时生效'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final selected = await showDialog<int>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('选择文件数量阈值'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _hasRecommendationSelection ? '修改阈值后需要点击"重置推荐"才能重新选择应用' : '应用文件数量大于此阈值时才会显示在首页推荐',
                        style: TextStyle(
                          color: _hasRecommendationSelection ? Colors.orange : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Flexible(
                        child: SingleChildScrollView(
                          child: RadioGroup<int>(
                            groupValue: _recommendationThreshold,
                            onChanged: (value) {
                              Navigator.of(context).pop(value);
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: AppConfig.instance.fileScan.recommendationThresholdOptions.map((threshold) {
                                return RadioListTile<int>(
                                  title: Text('$threshold 个文件'),
                                  value: threshold,
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ],
              ),
            );

            if (selected != null) {
              // 保存设置到AppConfig
              await AppConfig.instance.fileScan.setRecommendationFileCountThreshold(selected);

              logger.i('📌 开发者选项：阈值已修改为 $selected');

              // 重新加载推荐选择信息（以便检测阈值变化）
              await _loadRecommendationSelectionInfo();

              setState(() {
                _recommendationThreshold = selected;
              });

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('文件数量阈值已设置为 $selected'),
                    action: _hasRecommendationSelection
                        ? SnackBarAction(
                            label: '重置推荐',
                            onPressed: () => _resetRecommendations(),
                          )
                        : null,
                  ),
                );
              }
            }
          },
        ),
        // 如果阈值已更改且有已选定列表，显示提示卡片
        if (thresholdChanged)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '阈值已更改',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '需要重置推荐才能应用新阈值（$_savedSelectionThreshold → $_recommendationThreshold）',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _resetRecommendations(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: const Text('重置'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // 重置推荐按钮（仅在有已选定列表时显示）
        if (_hasRecommendationSelection)
          ListTile(
            leading: Icon(Icons.refresh, color: colorScheme.secondary),
            title: const Text('重置首页推荐'),
            subtitle: Text(
              _recommendationSelectionTime != null
                  ? '上次选择：${_formatDateTime(_recommendationSelectionTime!)}'
                  : '清除已选定应用，重新扫描',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _resetRecommendations(),
          ),
      ],
    );
  }

  /// 重置推荐
  Future<void> _resetRecommendations() async {
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认重置推荐'),
        content: const Text(
          '这将清除当前已选定的应用推荐，并根据当前阈值重新扫描所有应用。\n\n'
          '此操作可能需要几秒钟时间。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;

    // 显示加载提示
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在重新扫描应用...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // 执行重置
      final detectionService = AppDetectionService();
      final fileCountCache = await locator.getAsync<FileCountCache>();
      final fileListCache = await locator.getAsync<AppFileListCache>();
      final scanner = UnifiedAppScanner(
        detectionService,
        fileCountCache: fileCountCache,
        fileListCache: fileListCache,
      );
      final recommendationService = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
      );

      await recommendationService.resetRecommendations();

      // 刷新UI中的推荐卡片
      await QuickAccessSection.refreshRecommendations();

      // 重新加载选择信息
      await _loadRecommendationSelectionInfo();

      if (mounted) {
        Navigator.of(context).pop(); // 关闭加载对话框

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 推荐已重置'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      logger.e('重置推荐失败: $e');

      if (mounted) {
        Navigator.of(context).pop(); // 关闭加载对话框

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 重置失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes} 分钟前';
      }
      return '${diff.inHours} 小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    } else {
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    }
  }

  /// 系统回收站诊断
  Widget _buildSystemTrashDiagnosticsTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.recycling),
      title: const Text('系统回收站诊断'),
      subtitle: const Text('检查系统回收站扫描状态和抑制期设置'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await SystemTrashDiagnostics.show(context);
      },
    );
  }
}
