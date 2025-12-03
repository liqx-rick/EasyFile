import 'package:flutter/material.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/app_info.dart';
import 'package:easyfile/core/services/app_management_service.dart';
import 'package:easyfile/core/services/usage_stats_permission_service.dart';
import 'package:easyfile/core/services/system_intent_service.dart';

/// 应用管理页面
///
/// 展示所有已安装应用的存储占用情况
/// 支持双入口：
/// - 从存储管理页面进入（isFromStorageManagement=true）
/// - 从Ta b导航进入（isFromStorageManagement=false）
class AppManagementPage extends StatefulWidget {
  final bool isFromStorageManagement;

  const AppManagementPage({
    super.key,
    this.isFromStorageManagement = false,
  });

  @override
  State<AppManagementPage> createState() => _AppManagementPageState();
}

class _AppManagementPageState extends State<AppManagementPage>
    with WidgetsBindingObserver {
  final _appService = locator<AppManagementService>();
  final _permissionService = locator<UsageStatsPermissionService>();
  final _intentService = locator<SystemIntentService>();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();

  List<EasyFileAppInfo> _apps = [];
  List<EasyFileAppInfo> _filteredApps = [];
  bool _isLoading = false;
  bool _isRefreshing = false; // 区分首次加载和刷新
  bool _hasPermission = false;
  int _loadCurrent = 0;
  int _loadTotal = 0;
  String _searchQuery = '';

  // 排序选项
  SortOption _sortOption = SortOption.size;
  bool _sortAscending = false; // false=降序, true=升序

  // 筛选选项
  bool _showSystemApps = false;
  final double _minSizeMB = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
    _loadApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 当应用从后台返回前台时，快速刷新检测卸载
    if (state == AppLifecycleState.resumed) {
      logger.i('App resumed, checking for uninstalled apps');
      _refreshApps();
    }
  }

  /// 检查权限
  Future<void> _checkPermission() async {
    final hasPermission = await _permissionService.isGranted();
    setState(() {
      _hasPermission = hasPermission;
    });
  }

  /// 请求权限
  Future<void> _requestPermission() async {
    // 跳转到设置页面
    await _permissionService.request();

    // 等待用户操作完成后返回
    await Future.delayed(const Duration(milliseconds: 500));

    // 重新检查权限状态
    await _checkPermission();

    // 如果已授权，清除缓存并重新加载
    if (_hasPermission) {
      await _refreshApps();
    }
  }

  /// 快速刷新（下拉刷新）
  ///
  /// 检测已卸载的应用并从列表中移除，同时更新使用统计，不重新查询存储信息
  Future<void> _refreshApps() async {
    // 使用 microtask 立即更新 UI
    await Future.microtask(() {
      if (mounted) {
        setState(() {
          _isRefreshing = true;
        });
      }
    });

    try {
      // 1. 重新检查权限状态
      await _checkPermission();

      // 2. 快速检测已卸载的应用并移除
      if (_apps.isNotEmpty) {
        final updatedApps = await _appService.quickRefresh(
          _apps,
          includeSystemApps: _showSystemApps,
        );

        setState(() {
          _apps = updatedApps;
          _applyFilters();
        });
      }

      // 3. 显示提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已刷新应用列表'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logger.e('Error refreshing apps: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刷新失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  /// 完全刷新（点击刷新按钮）
  ///
  /// 清除所有缓存并重新查询所有应用的存储信息，显示完整扫描进度
  Future<void> _forceRefreshApps() async {
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('完全刷新'),
        content: const Text(
          '将清除所有缓存并重新查询所有应用的存储信息。\n\n'
          '这可能需要10-20秒时间。\n\n'
          '确定要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 立即显示加载状态
    setState(() {
      _isLoading = true;
      _loadCurrent = 0;
      _loadTotal = 0;
    });

    try {
      // 1. 重新检查权限状态
      await _checkPermission();

      // 2. 清除所有缓存
      await _appService.refreshCache();

      // 3. 重新加载所有应用（会显示完整的扫描进度）
      await _loadApps();

      // 4. 显示提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已清除缓存并刷新'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logger.e('Error force refreshing apps: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刷新失败: $e')),
        );
      }
    }
  }

  /// 加载应用列表（首次进入或完全刷新时调用）
  ///
  /// 获取所有已安装应用并加载存储信息（优先使用缓存）
  Future<void> _loadApps() async {
    // 如果还未设置加载状态，则设置
    if (!_isLoading) {
      setState(() {
        _isLoading = true;
        _loadCurrent = 0;
        _loadTotal = 0;
      });
    }

    try {
      // 1. 获取已安装应用列表（带图标）
      var apps = await _appService.getInstalledApps(
        includeSystemApps: _showSystemApps,
        withIcons: true,
      );

      setState(() {
        _loadTotal = apps.length;
      });

      // 2. 加载存储信息（如有缓存则使用缓存，否则查询）
      apps = await _appService.loadAppsWithStorage(
        apps,
        onProgress: (current, total) {
          setState(() {
            _loadCurrent = current;
            _loadTotal = total;
          });
        },
      );

      setState(() {
        _apps = apps;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      logger.e('Error loading apps: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载应用失败: $e')),
        );
      }
    }
  }

  /// 应用筛选和排序
  Future<void> _applyFilters() async {
    var filtered = _apps;

    // 搜索过滤
    if (_searchQuery.isNotEmpty) {
      filtered = await _appService.searchApps(filtered, _searchQuery);
    }

    // 大小过滤
    if (_minSizeMB > 0) {
      filtered = _appService.filterByMinSize(
          filtered, (_minSizeMB * 1024 * 1024).toInt());
    }

    // 排序
    switch (_sortOption) {
      case SortOption.size:
        filtered = _appService.sortBySize(filtered);
        break;
      case SortOption.name:
        filtered = _appService.sortByName(filtered);
        break;
      case SortOption.lastUsed:
        filtered = _sortByLastUsed(filtered);
        break;
    }

    // 应用排序方向
    if (_sortAscending) {
      filtered = filtered.reversed.toList();
    }

    setState(() {
      _filteredApps = filtered;
    });
  }

  /// 构建权限请求卡片
  Widget _buildPermissionCard() {
    if (_hasPermission) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange[700]),
                const SizedBox(width: 8),
                const Text(
                  '权限提示',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '为了获取更准确的应用存储信息，需要授予「查看应用使用情况」权限。\n\n'
              '不授权也可以使用，但部分数据可能不准确。',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _requestPermission,
                icon: const Icon(Icons.security),
                label: const Text('授予权限'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建统计卡片
  Widget _buildStatsCard() {
    if (_apps.isEmpty) return const SizedBox.shrink();

    final stats = _appService.getStatistics(_apps);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              '应用数量',
              '${stats.totalCount}',
              Icons.apps,
            ),
            _buildStatItem(
              '总占用',
              _formatSize(stats.totalSize),
              Icons.storage,
            ),
            _buildStatItem(
              '缓存总量',
              _formatSize(stats.totalCache),
              Icons.cached,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.blue),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  /// 构建搜索栏
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: SizedBox(
        height: 48,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          decoration: InputDecoration(
            hintText: '搜索应用...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _searchFocusNode.unfocus(); // 取消焦点
                      setState(() {
                        _searchQuery = '';
                        _applyFilters();
                      });
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[100],
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
              _applyFilters();
            });
          },
        ),
      ),
    );
  }

  /// 构建筛选和排序栏
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: SizedBox(
        height: 50,
        child: Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 5,
            children: [
              // 排序选项 - 添加方向指示
              _buildSortChip(
                label: '按大小',
                option: SortOption.size,
              ),
              _buildSortChip(
                label: '按名称',
                option: SortOption.name,
              ),
              _buildSortChip(
                label: '按使用',
                option: SortOption.lastUsed,
              ),
              // 筛选选项
              FilterChip(
                label: const Text('显示系统应用', style: TextStyle(fontSize: 13)),
                selected: _showSystemApps,
                showCheckmark: false, // 隐藏勾选图标
                labelPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (selected) {
                  setState(() {
                    _showSystemApps = selected;
                    _loadApps(); // 重新加载
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建排序按钮（带方向指示）
  Widget _buildSortChip({
    required String label,
    required SortOption option,
  }) {
    final isSelected = _sortOption == option;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          if (isSelected) ...[
            const SizedBox(width: 3),
            Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
            ),
          ],
        ],
      ),
      selected: isSelected,
      showCheckmark: false, // 隐藏勾选图标
      labelPadding:
          const EdgeInsets.symmetric(horizontal: 5, vertical: 0), // 增加内边距
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6), // 增加外边距
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, // 收缩点击区域
      onSelected: (selected) {
        setState(() {
          if (_sortOption == option) {
            // 如果已经选中，切换方向
            _sortAscending = !_sortAscending;
          } else {
            // 切换到新的排序方式，默认降序
            _sortOption = option;
            _sortAscending = false;
          }
          _applyFilters();
        });

        // 在下一帧滚动到顶部（确保列表已经更新）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      },
    );
  }

  /// 构建应用列表
  Widget _buildAppListSliver() {
    // 如果正在刷新，不显示加载指示器（RefreshIndicator已经有了）
    if (_isLoading && !_isRefreshing) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                '加载中... $_loadCurrent/$_loadTotal',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredApps.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.apps, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isNotEmpty ? '未找到匹配的应用' : '暂无应用',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    // 使用 SliverList 实现懒加载
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildAppItem(_filteredApps[index]),
        childCount: _filteredApps.length,
      ),
    );
  }

  /// 构建单个应用项
  Widget _buildAppItem(EasyFileAppInfo app) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: app.icon != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                app.icon!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(Icons.android, size: 40, color: Colors.grey[400]);
                },
              ),
            )
          : Icon(Icons.android, size: 40, color: Colors.grey[400]),
      title: Text(
        app.name,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：包名 + 使用时间 + 详情按钮
          Row(
            children: [
              Expanded(
                child: Text(
                  app.packageName,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (app.usageStats != null) ...[
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    // 添加调试输出（显示lastTimeUsed和lastUpdateTime）
                    final stats = app.usageStats!;
                    final deviceBaseline = _appService.deviceBaselineTime;
                    final description = stats.getLastUsedDescription(
                      deviceBaselineTime:
                          app.isSystemApp ? deviceBaseline : null,
                    );

                    debugPrint('[UI显示] ${app.name}: '
                        'lastTimeUsed=${stats.lastTimeUsed}, '
                        'lastUpdateTime=${stats.lastUpdateTime}, '
                        'effective=${stats.effectiveLastTime}, '
                        'isSystem=${app.isSystemApp}, '
                        'baseline=$deviceBaseline, '
                        'description=$description');

                    if (stats.effectiveLastTime != null) {
                      // 根据时间距离决定颜色
                      final days = stats.daysSinceLastTime ?? 0;
                      Color timeColor;

                      if (days <= 7) {
                        // 7天内：蓝色（活跃）
                        timeColor = Colors.blue[600]!;
                      } else if (days <= 30) {
                        // 8-30天：根据数据来源选择深浅蓝
                        timeColor = stats.lastTimeUsed != null
                            ? Colors.blue[600]!
                            : Colors.blue[400]!;
                      } else if (days <= 180) {
                        // 1-6个月：浅蓝色
                        timeColor = Colors.blue[400]!;
                      } else if (days <= 365) {
                        // 6-12个月：橙色
                        timeColor = Colors.orange[600]!;
                      } else {
                        // 12个月以上：红色
                        timeColor = Colors.red[600]!;
                      }

                      return Text(
                        description,
                        style: TextStyle(
                          fontSize: 11,
                          color: timeColor,
                          fontWeight: stats.isActive
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      );
                    } else {
                      return Text(
                        '从未使用',
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      );
                    }
                  },
                ),
              ],
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _openAppSettings(app.packageName),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child:
                      Icon(Icons.settings, size: 16, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          // 第二行：存储信息
          if (app.storageInfo != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Flexible(
                  child: Text(
                    '总占用 ${_formatSize(app.storageInfo!.totalSize)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (app.storageInfo!.cacheSize > 0) ...[
                  const SizedBox(width: 12),
                  Text(
                    '缓存 ${_formatSize(app.storageInfo!.cacheSize)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 打开应用设置页面
  Future<void> _openAppSettings(String packageName) async {
    try {
      final success = await _intentService.openAppSettings(packageName);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('打开应用设置失败')),
        );
      }
    } catch (e) {
      logger.e('Error opening app settings: $e');
    }
  }

  /// 格式化文件大小
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 按最近使用时间排序
  List<EasyFileAppInfo> _sortByLastUsed(List<EasyFileAppInfo> apps) {
    return apps.toList()
      ..sort((a, b) {
        final aTime = a.usageStats?.effectiveLastTime;
        final bTime = b.usageStats?.effectiveLastTime;

        // 有时间记录的排前面
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;

        // 最近使用/更新的排前面
        return bTime.compareTo(aTime);
      });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 点击页面其他地方时取消搜索框焦点
        _searchFocusNode.unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('应用管理'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '完全刷新',
              onPressed: _isLoading ? null : _forceRefreshApps,
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshApps,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // 权限卡片和统计卡片（可滚动）
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildPermissionCard(),
                    _buildStatsCard(),
                  ],
                ),
              ),

              // 搜索框和排序栏（固定在顶部）
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyHeaderDelegate(
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSearchBar(),
                        _buildFilterBar(),
                      ],
                    ),
                  ),
                ),
              ),

              // 应用列表
              _buildAppListSliver(),
            ],
          ),
        ),
      ),
    );
  }
}

// 自定义 SliverPersistentHeaderDelegate 用于固定搜索和排序栏
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyHeaderDelegate({required this.child});

  @override
  double get minExtent => 114; // 最小高度（搜索框 48 + 排序栏 50 + padding）

  @override
  double get maxExtent => 114; // 最大高度

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}

enum SortOption {
  size,
  name,
  lastUsed,
}
