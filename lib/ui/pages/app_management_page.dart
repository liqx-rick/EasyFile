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
class AppManagementPage extends StatefulWidget {
  const AppManagementPage({
    super.key,
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
  bool _isScanning = false; // 是否正在扫描（从 native 获取应用列表）
  bool _hasPermission = false;
  bool _hadPermissionBefore = false; // 记录之前的权限状态，用于检测权限变化
  int _loadCurrent = 0;
  int _loadTotal = 0;
  String _searchQuery = '';
  bool _showSearchBar = false; // 控制搜索栏显示
  bool _showRefreshBanner = false; // 显示刷新状态栏
  String _refreshMessage = ''; // 刷新状态消息

  // 排序选项
  SortOption _sortOption = SortOption.size;
  bool _sortAscending = false; // false=降序, true=升序

  // 筛选选项
  bool _showSystemApps = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission().then((_) {
      _hadPermissionBefore = _hasPermission; // 初始化权限状态记录
    });
    _loadAndRefreshApps(); // 先加载缓存，再后台刷新
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

    // 当应用从后台返回前台时，检测权限变化或快速刷新
    if (state == AppLifecycleState.resumed) {
      logger.i('App resumed, checking permission and apps');

      // 异步检查权限状态和缓存状态
      _checkPermission().then((_) async {
        // 如果权限状态从无到有，执行完整扫描（不显示顶部状态栏，使用中间加载指示器）
        if (!_hadPermissionBefore && _hasPermission) {
          logger
              .i('Permission state changed: granted, reloading with full scan');
          _loadApps(); // 不传showBanner参数，默认false，显示中间的加载状态
        } else {
          // 检查缓存是否存在，决定使用增量刷新还是完全刷新
          final (_, hasCache) = await _appService.quickLoadApps(
            includeSystemApps: _showSystemApps,
            withIcons: false, // 仅检测缓存存在性，不加载数据
          );

          if (!hasCache) {
            // 缓存被清空（可能用户刚清理了缓存），执行完全刷新
            logger.i('Cache cleared, performing full refresh');
            _refreshAppsWithBanner(incremental: false);
          } else {
            // 缓存存在，只做增量刷新（检测卸载+更新统计）
            logger.d('Cache exists, performing incremental refresh');
            _refreshAppsWithBanner(incremental: true);
          }
        }

        // 更新权限状态记录
        _hadPermissionBefore = _hasPermission;
      });
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

    // 如果已授权，执行完整扫描（显示存储占用和缓存总量）
    if (_hasPermission) {
      logger.i('Permission granted, starting full scan with storage info');
      await _loadApps();
    }
  }

  /// 加载并刷新应用（进入页面时调用）
  ///
  /// 先快速显示缓存内容，然后使用增量刷新提升性能
  void _loadAndRefreshApps() {
    // 1. 快速检查缓存是否存在（不加载数据，仅检测）
    _appService
        .quickLoadApps(
      includeSystemApps: _showSystemApps,
      withIcons: false, // 仅检测缓存，不加载图标，避免无缓存时的重复扫描
    )
        .then((result) async {
      final (apps, isFromCache) = result;

      if (isFromCache && apps.isNotEmpty && mounted) {
        // 2a. 有缓存：先加载缓存（需要图标）
        final (cachedApps, _) = await _appService.quickLoadApps(
          includeSystemApps: _showSystemApps,
          withIcons: true, // 加载完整缓存（含图标）
        );

        if (mounted) {
          setState(() {
            _apps = cachedApps;
            _applyFilters();
          });
          logger.i(
              'Loaded ${cachedApps.length} apps from cache, starting incremental refresh');

          // 然后增量刷新
          _refreshAppsWithBanner(incremental: true);
        }
      } else {
        // 2b. 无缓存：使用完整加载（显示中间的加载状态，不显示顶部状态栏）
        logger.i('No cache found, starting full load with progress');
        if (mounted) {
          setState(() {
            _showRefreshBanner = false; // 确保不显示顶部状态栏
          });
          _loadApps();
        }
      }
    }).catchError((e) {
      logger.e('Error loading apps from cache: $e');
      // 加载失败也使用完整加载
      if (mounted) {
        setState(() {
          _showRefreshBanner = false; // 确保不显示顶部状态栏
        });
        _loadApps();
      }
    });
  }

  /// 显示刷新状态栏并执行刷新
  ///
  /// [incremental] true=增量刷新（仅检测变化），false=完全扫描（重新加载所有数据）
  Future<void> _refreshAppsWithBanner({bool incremental = false}) async {
    setState(() {
      _showRefreshBanner = true;
      _refreshMessage = incremental ? '检查应用更新...' : '应用刷新中...';
    });

    try {
      // 延迟开始刷新，确保banner先显示
      await Future.delayed(const Duration(milliseconds: 50));
      await _refreshApps(incremental: incremental);
    } finally {
      // 刷新完成后立即隐藏状态栏
      if (mounted) {
        setState(() {
          _showRefreshBanner = false;
        });
      }
    }
  }

  /// 刷新应用列表
  ///
  /// [incremental] true=增量刷新（快速），false=完全扫描（慢但准确）
  ///
  /// 增量刷新：仅检测卸载应用+更新使用统计，保留图标和存储信息缓存
  /// 完全扫描：重新获取所有应用和存储信息
  Future<void> _refreshApps({bool incremental = false}) async {
    try {
      // 1. 重新检查权限状态
      await _checkPermission();

      List<EasyFileAppInfo> appsWithStorage;

      if (incremental && _apps.isNotEmpty) {
        // 增量刷新：使用 quickRefresh（仅检测变化，保留缓存）
        logger.i('Starting incremental refresh...');
        appsWithStorage = await _appService.quickRefresh(
          _apps,
          includeSystemApps: _showSystemApps,
        );
        logger
            .i('Incremental refresh completed: ${appsWithStorage.length} apps');
      } else {
        // 完全扫描：重新获取所有应用和存储信息
        logger.i('Starting full refresh...');

        // 2. 直接从 native 获取最新应用列表（跳过缓存）
        final apps = await _appService.getInstalledApps(
          includeSystemApps: _showSystemApps,
          withIcons: true,
        );

        // 设置扫描状态和总数
        if (mounted) {
          setState(() {
            _isScanning = true;
            _loadCurrent = 0;
            _loadTotal = apps.length;
          });
        }

        // 3. 加载存储信息（带进度显示）
        appsWithStorage = await _appService.loadAppsWithStorage(
          apps,
          onProgress: (current, total) {
            if (mounted) {
              setState(() {
                _loadCurrent = current;
                _loadTotal = total;
              });
            }
          },
          includeSystemApps: _showSystemApps,
        );

        // 清除扫描状态
        if (mounted) {
          setState(() {
            _isScanning = false;
          });
        }

        logger.i('Full refresh completed: ${appsWithStorage.length} apps');
      }

      // 4. 保存到缓存（覆盖旧缓存）
      await _appService.saveAppListToCache(
        appsWithStorage,
        includeSystemApps: _showSystemApps,
      );

      // 5. 更新UI
      if (mounted) {
        setState(() {
          _apps = appsWithStorage;
          _applyFilters();
        });
      }
    } catch (e) {
      logger.e('Error refreshing apps: $e');
    }
  }

  /// 加载应用列表（完整扫描，带进度显示）
  ///
  /// ⚠️ 使用场景：
  /// - 权限刚授予时（_requestPermission）
  /// - 系统应用筛选切换时
  ///
  /// 进入页面时的缓存加载由 _loadAndRefreshApps() 处理
  ///
  /// [showBanner] 是否显示刷新状态栏（权限变化时使用）
  Future<void> _loadApps({bool showBanner = false}) async {
    // 显示状态栏（如果需要）
    if (showBanner && mounted) {
      setState(() {
        _showRefreshBanner = true;
        _refreshMessage = '应用刷新中...';
      });
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // 设置加载状态
    if (!_isLoading) {
      setState(() {
        _isLoading = true;
        _isScanning = true; // 立即显示扫描状态
        _loadCurrent = 0;
        _loadTotal = 0; // 总数在获取应用列表后更新
      });
    }

    try {
      // 1. 优先从缓存加载应用列表（包括图标和存储信息）
      final (apps, isFromCache) = await _appService.quickLoadApps(
        includeSystemApps: _showSystemApps,
        withIcons: true,
      );

      logger.i('Loaded ${apps.length} apps (fromCache: $isFromCache)');

      List<EasyFileAppInfo> appsWithStorage;

      if (isFromCache) {
        // 从缓存加载：直接使用，不重新查询存储信息
        appsWithStorage = apps;

        // 验证并更新baseline（只针对用户应用）
        if (!_showSystemApps) {
          await _appService.validateAndUpdateBaseline(apps);
        }

        // 清除扫描状态（无需显示进度）
        if (mounted) {
          setState(() {
            _isScanning = false;
            _isLoading = false;
          });
        }
      } else {
        // 从 native 加载：需要查询存储信息
        if (mounted) {
          setState(() {
            _loadTotal = apps.length;
          });
        }

        // 加载存储信息（带进度显示）
        appsWithStorage = await _appService.loadAppsWithStorage(
          apps,
          onProgress: (current, total) {
            if (mounted) {
              setState(() {
                _loadCurrent = current;
                _loadTotal = total;
              });
            }
          },
          includeSystemApps: _showSystemApps,
        );

        // 保存到缓存
        await _appService.saveAppListToCache(
          appsWithStorage,
          includeSystemApps: _showSystemApps,
        );

        // 清除扫描状态
        if (mounted) {
          setState(() {
            _isScanning = false;
            _isLoading = false;
          });
        }
      }

      // 更新UI
      if (mounted) {
        setState(() {
          _apps = appsWithStorage;
          _applyFilters();
        });
      }
    } catch (e) {
      logger.e('Error loading apps: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isScanning = false;
        });
      }
    } finally {
      // 隐藏状态栏（如果显示了）
      if (showBanner && mounted) {
        setState(() {
          _showRefreshBanner = false;
        });
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
            suffixIcon: IconButton(
              icon: Icon(
                _searchQuery.isNotEmpty ? Icons.clear : Icons.close,
                size: 20,
              ),
              onPressed: _searchQuery.isNotEmpty
                  ? () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _applyFilters();
                      });
                    }
                  : () {
                      // 关闭搜索栏
                      setState(() {
                        _showSearchBar = false;
                        _searchController.clear();
                        _searchQuery = '';
                        _searchFocusNode.unfocus();
                        _applyFilters();
                      });
                    },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: _searchQuery.isNotEmpty ? '清除' : '关闭',
            ),
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
                onSelected: _isLoading
                    ? null
                    : (selected) async {
                        // 加载时禁用
                        logger.i(
                            '🔄 系统应用切换: $selected, 当前baseline=${_appService.deviceBaselineTime}');

                        // 如果要显示系统应用，确保baseline已经存在
                        if (selected &&
                            _appService.deviceBaselineTime == null) {
                          logger.w('⚠️ Baseline未加载，先加载用户应用以计算baseline');
                          // 先加载用户应用以计算baseline（baseline在加载用户应用时自动计算并保存）
                          logger.i('📥 [第1次加载] 加载用户应用以计算baseline...');
                          await _loadApps(); // 此时 _showSystemApps 还是 false，加载用户应用
                          logger.i(
                              '✓ Baseline已计算并保存: ${_appService.deviceBaselineTime}');

                          // 计算完baseline后，切换到系统应用
                          logger.i('📥 [第2次加载] 切换到系统应用，使用已计算的baseline');
                          if (mounted) {
                            setState(() {
                              _showSystemApps = true;
                            });
                            await _loadApps();
                            logger.i('✓ 切换完成，当前显示${_apps.length}个应用');
                          }
                          return;
                        }

                        // 切换显示范围并重新加载（使用已保存的baseline）
                        logger.i(
                            '📥 [切换加载] 切换到${selected ? "系统应用" : "用户应用"}，使用已有baseline');
                        setState(() {
                          _showSystemApps = selected;
                        });
                        await _loadApps();
                        logger.i('✓ 切换完成，当前显示${_apps.length}个应用');
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
    // 如果正在加载，显示加载指示器
    if (_isLoading) {
      // 根据是否正在扫描显示不同文案
      final loadingText = _isScanning
          ? (_loadTotal > 0 ? '扫描中... $_loadCurrent/$_loadTotal' : '扫描中...')
          : (_loadTotal > 0 ? '加载中... $_loadCurrent/$_loadTotal' : '加载中...');

      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                loadingText,
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
                    final stats = app.usageStats!;
                    final deviceBaseline = _appService.deviceBaselineTime;

                    // 统一传递基准时间，让 getLastUsedDescription 内部判断如何显示
                    final description = stats.getLastUsedDescription(
                      deviceBaselineTime: deviceBaseline,
                    );

                    debugPrint('[UI显示] ${app.name}: '
                        'lastTimeUsed=${stats.lastTimeUsed}, '
                        'lastUpdateTime=${stats.lastUpdateTime}, '
                        'effective=${stats.effectiveLastTime}, '
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
              icon: const Icon(Icons.search),
              tooltip: '搜索应用',
              onPressed: () {
                setState(() {
                  _showSearchBar = true;
                  // 显示搜索栏时自动聚焦
                  Future.delayed(const Duration(milliseconds: 100), () {
                    _searchFocusNode.requestFocus();
                  });
                });
              },
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () =>
              _refreshAppsWithBanner(incremental: false), // 下拉刷新使用完全扫描
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // 权限卡片和统计卡片（可滚动）
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildPermissionCard(),
                    // 刷新状态栏
                    if (_showRefreshBanner)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.blue[700]!),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _refreshMessage,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    _buildStatsCard(),
                  ],
                ),
              ),

              // 搜索框和排序栏（固定在顶部）
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyHeaderDelegate(
                  height: _showSearchBar
                      ? 114
                      : 58, // 动态高度：搜索栏(48+8) + 排序栏(50+8) = 114；仅排序栏(50+8) = 58
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_showSearchBar) _buildSearchBar(),
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
  final double height;

  _StickyHeaderDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) {
    return child != oldDelegate.child || height != oldDelegate.height;
  }
}

enum SortOption {
  size,
  name,
  lastUsed,
}
