import 'package:easyfile/analytics/analytics_helper.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/data_sources/data_source_factory.dart';
import 'package:easyfile/core/data_sources/file_list_data_source.dart';
import 'package:easyfile/core/data_sources/media_store_data_source.dart';
import 'package:easyfile/core/data_sources/recommend_config_mapper.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/core/models/recommend_page_config.dart';
import 'package:easyfile/core/services/app_file_list_cache.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/mediastore_cache_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/thumbnail_pre_generation_service.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/recommendation_card.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/mixins/edit_mode_mixin.dart';
import 'package:easyfile/ui/mixins/pop_scope_handler_mixin.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/services/batch_operations_service.dart';
import 'package:easyfile/ui/services/single_file_operations_service.dart';
import 'package:easyfile/ui/widgets/edit_mode_widgets.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/ui/widgets/file_search_bar.dart';
import 'package:easyfile/ui/widgets/file_toolbar.dart';
import 'package:easyfile/ui/widgets/selection_bottom_bar.dart';
import 'package:easyfile/ui/widgets/single_file_operations_sheet.dart';
import 'package:easyfile/ui/widgets/unified_view_config.dart';
import 'package:easyfile/utils/file_comparator_util.dart';
import 'package:easyfile/utils/file_grouping_util.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 推荐聚合页面
///
/// 职责：
/// - 接收 RecommendPageConfig 配置
/// - 根据配置构建页面结构（AppBar、Header、文件列表）
/// - 不包含任何具体业务判断
///
/// 使用示例：
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (context) => RecommendAggregatePage(
///       config: wechatConfig,  // 配置驱动
///       dataSourceFactory: factory,
///       viewModel: viewModel,
///       presenter: presenter,
///     ),
///   ),
/// );
/// ```
class RecommendAggregatePage extends StatefulWidget {
  /// 页面配置
  final RecommendPageConfig config;

  /// 数据源工厂
  final DataSourceFactory dataSourceFactory;

  /// 文件ViewModel
  final FileViewModel viewModel;

  /// 文件Presenter
  final FilePresenter presenter;

  const RecommendAggregatePage({
    super.key,
    required this.config,
    required this.dataSourceFactory,
    required this.viewModel,
    required this.presenter,
  });

  @override
  State<RecommendAggregatePage> createState() => _RecommendAggregatePageState();
}

class _RecommendAggregatePageState extends State<RecommendAggregatePage>
    with SingleTickerProviderStateMixin, EditModeMixin, PopScopeHandlerMixin, WidgetsBindingObserver {
  /// Tab 控制器（仅 application 模式使用）
  TabController? _tabController;

  /// 当前文件列表（全部文件，未过滤）
  List<FileItem> _allFiles = [];

  /// 显示的文件列表（经过Tab过滤）
  List<FileItem> _files = [];

  /// 有效的Tabs（过滤掉没有文件的Tab）
  List<TabConfig>? _visibleTabs;

  /// 加载状态
  bool _isLoading = true;

  /// 搜索状态
  bool _isSearchMode = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// 数据源实例
  late FileListDataSource _dataSource;

  /// 选择控制器（EditModeMixin必需）
  final SelectionController _selectionController = SelectionController();

  @override
  SelectionController get selectionController => _selectionController;

  /// 单文件操作服务
  late final SingleFileOperationsService _singleFileOperationsService;

  /// 批量操作服务
  late final BatchOperationsService _batchOperationsService;

  /// 标记页面是否首次加载
  bool _isFirstLoad = true;

  /// 标记是否已预生成缩略图（应用模式Tab切换用）
  bool _hasPregenerated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDataSource();
    _initServices();
    _loadFilesAndInitTabs();

    // 监听PageSettingsService变化
    PageSettingsService().addListener(_onPageSettingsChanged);

    // 监听ViewModel变化，实现缓存增量更新
    widget.viewModel.addListener(_onViewModelChanged);

    // 埋点：推荐卡片浏览
    AnalyticsHelper.logHomeRecommendView(widget.config.type.toString(), 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    logger.i(
        'RecommendAggregatePage: didChangeDependencies called - mounted: $mounted, _isFirstLoad: $_isFirstLoad, mode: ${widget.config.mode}');

    // 所有加载场景（包括首次）都触发刷新检查
    if (mounted) {
      // 检查缓存是否被清除
      _checkAndReloadIfCacheCleared();

      // content模式和application模式：智能后台刷新（检查是否有新文件）
      if (widget.config.mode == RecommendMode.content || widget.config.mode == RecommendMode.application) {
        // 延迟执行，避免阻塞首次渲染
        if (_isFirstLoad) {
          // 首次加载：延迟500ms后刷新
          Future.delayed(Duration(milliseconds: 500), () {
            if (mounted) {
              logger.i('RecommendAggregatePage: ✅ 首次加载后触发后台刷新检查');
              _smartBackgroundRefresh();
            }
          });
        } else {
          // 页面重新显示：立即刷新
          logger.i('RecommendAggregatePage: ✅ 页面重新显示，触发后台刷新');
          _smartBackgroundRefresh();
        }
      }
    }
    _isFirstLoad = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    logger.i('RecommendAggregatePage: didChangeAppLifecycleState called - state: $state, mode: ${widget.config.mode}');

    // 应用从后台恢复时触发刷新
    if (state == AppLifecycleState.resumed && mounted) {
      logger.i('RecommendAggregatePage: ✅ 应用从后台恢复，触发后台刷新');

      // content模式和application模式：智能后台刷新
      if (widget.config.mode == RecommendMode.content || widget.config.mode == RecommendMode.application) {
        _smartBackgroundRefresh();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PageSettingsService().removeListener(_onPageSettingsChanged);
    widget.viewModel.removeListener(_onViewModelChanged);
    _tabController?.dispose();
    super.dispose();
  }

  @override
  void handlePopInvoked(bool didPop, dynamic result) {
    // 页面返回前的处理
    if (!didPop && _dataUpdated) {
      // 手动pop并传递结果
      Navigator.of(context).pop(_dataUpdated);
      return;
    }
    super.handlePopInvoked(didPop, result);
  }

  @override
  bool canPopPage() {
    // 如果有数据更新，需要自定义pop行为来传递结果
    // 返回false让handlePopInvoked处理
    if (_dataUpdated) {
      return false;
    }
    return super.canPopPage();
  }

  /// 获取当前Tab对应的PageId
  PageId _getPageIdForCurrentTab() {
    // content模式：根据内容类型返回对应的PageId
    if (widget.config.mode == RecommendMode.content) {
      switch (widget.config.type) {
        case RecommendationType.memories:
          return PageId.recommendContentMemories;
        case RecommendationType.videos:
          return PageId.recommendContentVideos;
        case RecommendationType.recordings:
          return PageId.recommendContentRecordings;
        default:
          return widget.config.pageId;
      }
    }

    // 非application模式：直接使用配置的pageId
    if (widget.config.mode != RecommendMode.application ||
        _tabController == null ||
        _visibleTabs == null ||
        _visibleTabs!.isEmpty) {
      return widget.config.pageId;
    }

    // application模式：根据当前Tab的title返回对应的PageId
    final currentTab = _visibleTabs![_tabController!.index];
    switch (currentTab.title) {
      case '全部':
        return PageId.recommendApplicationAll;
      case '图片':
        return PageId.recommendApplicationImages;
      case '视频':
        return PageId.recommendApplicationVideos;
      case '文档':
        return PageId.recommendApplicationDocuments;
      case '音频':
        return PageId.recommendApplicationAudios;
      default:
        return PageId.recommendApplication; // 其他Tab使用默认值
    }
  }

  /// PageSettingsService变化回调
  void _onPageSettingsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// ViewModel变化回调 - 增量更新缓存
  void _onViewModelChanged() async {
    if (!mounted) return;

    // 处理 content 模式（时光记忆/生活剪影/声音记录）
    if (widget.config.mode == RecommendMode.content) {
      await _handleContentModeChanges();
      return;
    }

    // 处理应用模式（微信/QQ等）
    if (widget.config.mode != RecommendMode.application) return;

    // 获取appKey
    final appKey = _getAppKeyFromConfig();
    if (appKey == null) return;

    // 获取scanner实例
    final scanner = widget.dataSourceFactory.scanner;
    if (scanner == null) return;

    logger.d('RecommendAggregatePage: ViewModel changed callback triggered for $appKey');

    // 处理文件删除
    final deletedPath = widget.viewModel.lastDeletedFilePath;
    if (deletedPath != null) {
      logger.d('RecommendAggregatePage: Processing file deletion: $deletedPath');

      // 更新缓存
      await scanner.updateCacheForDeletedFile(appKey, deletedPath);

      // 更新UI
      if (mounted) {
        setState(() {
          _allFiles.removeWhere((f) => f.path == deletedPath);
          _files = _filterFilesByTab(_allFiles);
        });
      }
      return;
    }

    // 处理文件更新（重命名/移动）
    final oldPath = widget.viewModel.lastUpdatedOldPath;
    final newFile = widget.viewModel.lastUpdatedNewFile;
    if (oldPath != null && newFile != null) {
      logger.d('RecommendAggregatePage: Processing file update: $oldPath -> ${newFile.path}');

      // 更新缓存
      await scanner.updateCacheForUpdatedFile(appKey, oldPath, newFile);

      // 更新UI
      if (mounted) {
        setState(() {
          final index = _allFiles.indexWhere((f) => f.path == oldPath);
          if (index != -1) {
            _allFiles[index] = newFile;
            _files = _filterFilesByTab(_allFiles);
          }
        });
      }
      return;
    }

    // 处理文件添加
    final addedFile = widget.viewModel.lastAddedFile;
    if (addedFile != null && _shouldShowAddedFile(addedFile)) {
      logger.d('RecommendAggregatePage: Processing file addition: ${addedFile.path}');

      // 更新缓存
      await scanner.updateCacheForAddedFile(appKey, addedFile);

      // 更新UI
      if (mounted) {
        setState(() {
          if (!_allFiles.any((f) => f.path == addedFile.path)) {
            _allFiles.add(addedFile);
            _files = _filterFilesByTab(_allFiles);
          }
        });
      }
    }
  }

  /// 处理 content 模式的文件变化
  Future<void> _handleContentModeChanges() async {
    // 只处理删除操作（添加/更新由外部应用完成，需要重新扫描）
    final deletedPath = widget.viewModel.lastDeletedFilePath;
    if (deletedPath == null) return;

    logger.d('Content模式 - 处理文件删除: $deletedPath');

    // 确定MediaStore类型
    final mediaStoreType = _getMediaStoreType();
    if (mediaStoreType == null) return;

    // 从MediaStore缓存中移除文件
    final cacheService = MediaStoreCacheService();
    await cacheService.initialize();
    await cacheService.removeFileFromCache(mediaStoreType, deletedPath);

    // 更新UI
    if (mounted) {
      setState(() {
        _allFiles.removeWhere((f) => f.path == deletedPath);
        _files = _allFiles; // content模式无Tab过滤
      });
    }

    logger.i('✅ Content模式 - 文件删除已同步到缓存和UI');
  }

  /// 获取当前配置对应的MediaStore类型
  MediaStoreType? _getMediaStoreType() {
    switch (widget.config.type) {
      case RecommendationType.memories:
        return MediaStoreType.cameraPhotos;
      case RecommendationType.videos:
        return MediaStoreType.cameraVideos;
      case RecommendationType.recordings:
        return MediaStoreType.recordings;
      default:
        return null;
    }
  }

  /// 从配置获取appKey
  String? _getAppKeyFromConfig() {
    switch (widget.config.type) {
      case RecommendationType.wechat:
        return 'wechat';
      case RecommendationType.qq:
        return 'qq';
      case RecommendationType.telegram:
        return 'telegram';
      case RecommendationType.wps:
        return 'wps';
      default:
        return null;
    }
  }

  /// 判断添加的文件是否应该显示在当前页面
  bool _shouldShowAddedFile(FileItem file) {
    if (file.isDirectory) return false;

    // 如果有Tab，检查文件是否属于当前Tab
    if (widget.config.mode == RecommendMode.application &&
        _tabController != null &&
        _visibleTabs != null &&
        _visibleTabs!.isNotEmpty) {
      final currentTab = _visibleTabs![_tabController!.index];

      // 全部Tab：所有文件都显示
      if (currentTab.fileTypes == null) {
        return true;
      }

      // 特定类型Tab：检查扩展名
      final ext = FileUtils.getExtension(file.name);
      return currentTab.fileTypes!.contains(ext);
    }

    return true;
  }

  /// 初始化服务
  void _initServices() {
    // 初始化单文件操作服务
    _singleFileOperationsService = SingleFileOperationsService(
      context: context,
      viewModel: widget.viewModel,
      presenter: widget.presenter,
      onRefresh: () => _loadFiles(),
      onUIUpdate: () {
        if (mounted) setState(() {});
      },
    );

    // 初始化批量操作服务
    _batchOperationsService = BatchOperationsService(
      viewModel: widget.viewModel,
      presenter: widget.presenter,
      onRefresh: () async {
        if (mounted) await _loadFiles();
      },
      onExitSelectionMode: () {
        if (mounted) {
          setState(() {
            _selectionController.clear();
          });
        }
      },
    );
  }

  /// 加载文件并初始化Tabs（仅首次调用）
  Future<void> _loadFilesAndInitTabs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 获取查询参数（首次加载时不需要考虑Tab）
      final params = RecommendConfigDataSourceMapper.getDefaultQueryParams(
        widget.config.type,
      );

      logger.d('RecommendAggregatePage - 查询参数: $params');

      // ⚡ 快速路径：应用模式下，scanApp会自动使用内存缓存
      // 不需要单独检查文件数量，直接调用scanApp(forceRefresh: false)
      // 如果有缓存，scanApp会立即返回缓存结果；没有缓存才执行扫描
      logger.d('📋 开始加载文件列表 (config.mode=${widget.config.mode})');

      // 查询文件
      final files = await _dataSource.queryFiles(params);

      if (mounted) {
        // 根据文件内容过滤出visible tabs
        if (widget.config.mode == RecommendMode.application && widget.config.tabs != null) {
          final visibleTabs = <TabConfig>[];

          for (final tab in widget.config.tabs!) {
            if (_hasFilesForTab(tab, files)) {
              visibleTabs.add(tab);
            }
          }

          _visibleTabs = visibleTabs.isNotEmpty ? visibleTabs : widget.config.tabs;

          // 初始化TabController
          if (_visibleTabs!.isNotEmpty) {
            _tabController = TabController(
              length: _visibleTabs!.length,
              vsync: this,
            );
            _tabController!.addListener(_onTabChanged);

            // 添加Tab切换监听，处理视频Tab的预生成
            _tabController!.addListener(() {
              if (_shouldPreGenerateThumbnails() && !_hasPregenerated) {
                _preGenerateVideoThumbnailsAsync(_files);
                _hasPregenerated = true;
              }
            });
          }

          logger.d('初始化可见Tabs: ${_visibleTabs!.length} 个 (原${widget.config.tabs!.length}个)');
        }

        setState(() {
          _allFiles = files;
          _files = _filterFilesByTab(files);
          _isLoading = false;
        });
      }

      logger.i('RecommendAggregatePage - 加载完成: ${_allFiles.length} 个文件，显示 ${_files.length} 个');

      // ⚡ 视频缩略图预生成（应用模式/content模式视频列表）
      if (_shouldPreGenerateThumbnails()) {
        _preGenerateVideoThumbnailsAsync(_files);
        _hasPregenerated = true;
      }

      // content模式：首次加载后立即触发后台刷新（检查是否有新文件）
      if (widget.config.mode == RecommendMode.content && !_isBackgroundRefreshing) {
        logger.d('Content模式 - 首次加载后触发后台刷新');
        _smartBackgroundRefresh();
      }
    } catch (e) {
      logger.e('RecommendAggregatePage - 加载失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 智能后台刷新（content模式专用）
  ///
  /// 策略：
  /// - 页面进入/返回时触发
  /// - 不阻塞UI，后台静默刷新
  /// - 发现新文件时自动更新UI
  /// - 并发保护：同时只执行一次刷新
  ///
  /// 场景优化：
  /// - 用户删除文件后从回收站恢复 → 立即刷新能看到
  /// - 系统相机拍照后进入 → 能看到最新照片
  /// - MediaStore 系统层面有缓存，性能影响微乎其微
  Future<void> _smartBackgroundRefresh() async {
    // 并发保护：避免重复刷新
    if (_isBackgroundRefreshing) {
      logger.d('RecommendAggregatePage: 后台刷新进行中，跳过');
      return;
    }

    _isBackgroundRefreshing = true;

    final appKey = _getAppKeyFromConfig();
    logger.i('RecommendAggregatePage: 🔄 启动智能后台刷新... (appKey: $appKey, mode: ${widget.config.mode})');

    try {
      // 获取正确的查询参数（包含必需的 appKey）
      final params = RecommendConfigDataSourceMapper.getDefaultQueryParams(widget.config.type);
      params['forceRefresh'] = true;

      // 后台扫描（不阻塞UI）
      logger.d('RecommendAggregatePage: 调用 queryFiles with params: $params');
      final newFiles = await _dataSource.queryFiles(params);

      logger.i('RecommendAggregatePage: 扫描完成，获得 ${newFiles.length} 个文件');

      if (!mounted) return;

      // 比较文件列表，判断是否有变化
      final oldCount = _allFiles.length;
      final newCount = newFiles.length;

      // 方法1：数量不同，肯定有变化
      if (newCount != oldCount) {
        logger.i('✨ 发现文件变化: $oldCount → $newCount');

        // 更新数据
        setState(() {
          _allFiles = newFiles;
          _files = widget.config.mode == RecommendMode.application ? _filterFilesByTab(_allFiles) : _allFiles;
        });

        // 提示用户
        if (mounted) {
          final diff = newCount - oldCount;
          final message = diff > 0 ? '发现 $diff 个新文件' : '已移除 ${-diff} 个文件';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // 方法2：数量相同，但可能文件内容不同（如删除1个+恢复1个）
        // 比较文件路径集合
        final oldPaths = _allFiles.map((f) => f.path).toSet();
        final newPaths = newFiles.map((f) => f.path).toSet();

        logger.d('比较文件路径集合: 缓存${oldPaths.length}个, 扫描${newPaths.length}个');

        // 找出差异文件
        final addedPaths = newPaths.difference(oldPaths);
        final removedPaths = oldPaths.difference(newPaths);

        if (addedPaths.isNotEmpty || removedPaths.isNotEmpty) {
          // 有文件路径不同，说明有文件被替换
          logger.i('✨ 发现文件内容变化（数量相同但文件不同）');
          logger.i('  新增文件: ${addedPaths.length}个');
          if (addedPaths.isNotEmpty && addedPaths.length <= 5) {
            for (final path in addedPaths) {
              logger.d('    + $path');
            }
          }
          logger.i('  移除文件: ${removedPaths.length}个');
          if (removedPaths.isNotEmpty && removedPaths.length <= 5) {
            for (final path in removedPaths) {
              logger.d('    - $path');
            }
          }

          // 更新数据
          setState(() {
            _allFiles = newFiles;
            _files = widget.config.mode == RecommendMode.application ? _filterFilesByTab(_allFiles) : _allFiles;
          });

          // 提示用户
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('文件列表已更新'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          logger.d('后台刷新完成，无新变化');
        }
      }
    } catch (e) {
      logger.e('后台刷新失败: $e');
    } finally {
      _isBackgroundRefreshing = false;
    }
  }

  /// 检查缓存是否被清除，如果被清除则重新加载
  Future<void> _checkAndReloadIfCacheCleared() async {
    // 只对应用模式（微信、QQ等）进行检查
    if (widget.config.mode != RecommendMode.application) {
      return;
    }

    final appKey = _getAppKeyFromConfig();
    if (appKey == null) return;

    try {
      // 检查SharedPreferences缓存
      final cache = await locator.getAsync<AppFileListCache>();
      final cachedFiles = await cache.getFileList(appKey);

      // 如果有文件列表但缓存为空，说明缓存被清除了
      final shouldReload = _allFiles.isNotEmpty && cachedFiles == null;

      if (shouldReload) {
        logger.i('检测到缓存已清除，强制重新扫描: $appKey');
        // 使用 forceRefresh: true 强制重新扫描，跳过内存缓存
        await _loadFiles(forceRefresh: true);
      }
    } catch (e) {
      logger.e('检查缓存状态失败: $e');
    }
  }

  /// 检查Tab是否有文件
  bool _hasFilesForTab(TabConfig tab, List<FileItem> files) {
    // 全部Tab：只要有文件就显示
    if (tab.fileTypes == null) {
      return files.isNotEmpty;
    }

    // 具体类型Tab：检查是否有该类型的文件
    if (tab.fileTypes!.isNotEmpty) {
      return files.any((file) {
        final ext = FileUtils.getExtension(file.name);
        return tab.fileTypes!.contains(ext);
      });
    }

    // 其他Tab：检查是否有不在已知类型中的文件
    final knownTypes = <String>{};
    for (final t in widget.config.tabs!) {
      if (t.fileTypes != null && t.fileTypes!.isNotEmpty) {
        knownTypes.addAll(t.fileTypes!);
      }
    }

    return files.any((file) {
      final ext = FileUtils.getExtension(file.name);
      return !knownTypes.contains(ext);
    });
  }

  /// 初始化数据源
  void _initDataSource() {
    final strategy = RecommendConfigDataSourceMapper.getQueryStrategy(
      widget.config.type,
    );

    _dataSource = widget.dataSourceFactory.create(strategy);
    logger.d('RecommendAggregatePage - 数据源: $strategy');
  }

  /// 加载文件（刷新时使用）
  // 标记数据是否已更新（用于返回时通知主页刷新）
  bool _dataUpdated = false;

  /// 是否正在后台刷新
  bool _isBackgroundRefreshing = false;

  Future<void> _loadFiles({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
    });

    // 如果是强制刷新，标记数据可能已更新
    if (forceRefresh) {
      _dataUpdated = true;
    }

    try {
      // 获取查询参数
      // ⚡ 修复：刷新时始终获取所有文件，而不是只获取当前Tab的文件
      // 避免刷新后切换Tab时其他Tab没有数据的问题
      Map<String, dynamic> params = RecommendConfigDataSourceMapper.getDefaultQueryParams(
        widget.config.type,
      );

      // 添加强制刷新标志（用于缓存控制）
      if (forceRefresh) {
        params['forceRefresh'] = true;
      }

      logger.d('RecommendAggregatePage - 查询参数: $params${forceRefresh ? ' (强制刷新)' : ''}');

      // 查询文件（会优先使用缓存）
      final files = await _dataSource.queryFiles(params);

      if (mounted) {
        setState(() {
          _allFiles = files;
          _files = _filterFilesByTab(files);
          _isLoading = false;
        });
      }

      logger.i('RecommendAggregatePage - 加载完成: ${_allFiles.length} 个文件，显示 ${_files.length} 个');

      // ⚡ 视频缩略图预生成（应用模式/content模式视频列表）
      if (_shouldPreGenerateThumbnails() && !_hasPregenerated) {
        _preGenerateVideoThumbnailsAsync(_files);
        _hasPregenerated = true;
      }

      // 后台刷新策略
      if (!forceRefresh && files.isNotEmpty && !_isBackgroundRefreshing) {
        if (widget.config.mode == RecommendMode.application) {
          // 应用模式：使用原有的后台刷新
          _startBackgroundRefresh(params);
        } else if (widget.config.mode == RecommendMode.content) {
          // content模式：首次加载后立即后台刷新
          logger.d('Content模式 - 首次加载后触发后台刷新');
          _smartBackgroundRefresh();
        }
      }
    } catch (e) {
      logger.e('RecommendAggregatePage - 加载失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 后台静默刷新数据
  void _startBackgroundRefresh(Map<String, dynamic> params) {
    if (_isBackgroundRefreshing) return;

    _isBackgroundRefreshing = true;
    logger.d('RecommendAggregatePage - 🔄 启动后台刷新');

    // 异步执行，不阻塞UI
    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        // 强制刷新以获取最新数据
        final refreshParams = Map<String, dynamic>.from(params);
        refreshParams['forceRefresh'] = true;

        final files = await _dataSource.queryFiles(refreshParams);

        if (mounted && files.isNotEmpty) {
          // 静默更新数据（如果数据有变化）
          if (files.length != _allFiles.length) {
            logger.i('RecommendAggregatePage - 🔄 后台刷新完成: ${_allFiles.length} -> ${files.length} 文件');
            setState(() {
              _allFiles = files;
              _files = _filterFilesByTab(files);
            });
          } else {
            logger.d('RecommendAggregatePage - 🔄 后台刷新完成: 数据无变化');
          }
        }
      } catch (e) {
        logger.e('RecommendAggregatePage - 🔄 后台刷新失败: $e');
      } finally {
        _isBackgroundRefreshing = false;
      }
    });
  }

  /// 根据当前Tab过滤文件
  List<FileItem> _filterFilesByTab(List<FileItem> files) {
    if (widget.config.mode != RecommendMode.application ||
        _tabController == null ||
        _visibleTabs == null ||
        _visibleTabs!.isEmpty) {
      return files;
    }

    final currentTab = _visibleTabs![_tabController!.index];

    // 全部Tab：返回所有文件
    if (currentTab.fileTypes == null) {
      logger.d('Tab "${currentTab.title}": 显示所有文件');
      return files;
    }

    // 具体类型Tab：按扩展名过滤
    if (currentTab.fileTypes!.isNotEmpty) {
      final filtered = files.where((file) {
        final ext = FileUtils.getExtension(file.name);
        return currentTab.fileTypes!.contains(ext);
      }).toList();
      logger.d('Tab "${currentTab.title}": 过滤后 ${filtered.length} 个文件');
      return filtered;
    }

    // 其他Tab：排除已知类型
    final knownTypes = <String>{};
    for (final tab in _visibleTabs!) {
      if (tab.fileTypes != null && tab.fileTypes!.isNotEmpty) {
        knownTypes.addAll(tab.fileTypes!);
      }
    }

    final filtered = files.where((file) {
      final ext = FileUtils.getExtension(file.name);
      return !knownTypes.contains(ext);
    }).toList();
    logger.d('Tab "${currentTab.title}": 其他类型 ${filtered.length} 个文件（排除${knownTypes.length}种已知类型）');
    return filtered;
  }

  /// Tab 切换回调
  void _onTabChanged() {
    setState(() {
      _files = _filterFilesByTab(_allFiles);
      // 切换Tab时清除选择状态
      _selectionController.clear();
    });
  }

  /// 文件点击回调
  void _onFileTap(FileItem file) {
    // 编辑模式：切换选中状态
    if (isEditMode) {
      setState(() {
        _selectionController.toggle(file.path);
      });
      return;
    }

    // 添加到最近访问
    widget.presenter.addToRecentFiles(file);

    // 打开预览
    _previewFile(file);
  }

  /// 预览文件
  Future<void> _previewFile(FileItem file) async {
    logger.d('Previewing file: ${file.path}');

    // 图片/视频/音频：传递文件列表支持滑动切换
    final isMediaFile =
        FileUtils.isImageFile(file.name) || FileUtils.isVideoFile(file.name) || FileUtils.isAudioFile(file.name);

    final fileList = isMediaFile ? _files : null;
    final initialIndex = fileList?.indexWhere((f) => f.path == file.path) ?? 0;

    final needsRefresh = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => FilePreviewPage(
          file: file,
          fileList: fileList,
          initialIndex: initialIndex >= 0 ? initialIndex : 0,
          viewModel: widget.viewModel,
          presenter: widget.presenter,
        ),
      ),
    );

    // 从预览返回后，检查并恢复视频缩略图预生成
    if (_shouldPreGenerateThumbnails()) {
      final service = ThumbnailPreGenerationService();
      // 如果预生成已停止（isGenerating=false），重新启动
      if (!service.isGenerating) {
        logger.i('[RecommendAggregatePage] 预览返回后重新启动预生成');
        _preGenerateVideoThumbnailsAsync(_files);
      } else {
        logger.d('[RecommendAggregatePage] 预览返回，预生成仍在进行中');
      }
    }

    // 如果文件被修改，刷新列表
    if (needsRefresh == true) {
      await _loadFiles();
    }
  }

  /// 长按处理
  void _onFileLongPress(FileItem file) {
    // 编辑模式下禁用长按
    if (isEditMode) return;

    // 显示单文件操作菜单
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SingleFileOperationsSheet(
        file: file,
        service: _singleFileOperationsService,
      ),
    );
  }

  /// 判断当前页面是否需要预生成视频缩略图
  bool _shouldPreGenerateThumbnails() {
    // 1. 应用模式 - 视频Tab
    if (widget.config.mode == RecommendMode.application &&
        _tabController != null &&
        _visibleTabs != null &&
        _visibleTabs!.isNotEmpty) {
      final currentTab = _visibleTabs![_tabController!.index];
      if (currentTab.title == '视频') {
        logger.d('[PreGeneration] 应用模式 - 视频Tab，需要预生成');
        return true;
      }
    }

    // 2. Content模式 - 生活剪影（相机视频）
    if (widget.config.mode == RecommendMode.content && widget.config.type == RecommendationType.videos) {
      logger.d('[PreGeneration] Content模式 - 生活剪影，需要预生成');
      return true;
    }

    return false;
  }

  /// 异步后台预生成视频缩略图（不阻塞UI）
  void _preGenerateVideoThumbnailsAsync(List<FileItem> files) {
    // 过滤出视频文件
    final videoFiles = files.where((f) => !f.isDirectory && AppConfig.instance.fileTypes.isVideoFile(f.name)).toList();

    if (videoFiles.isEmpty) {
      logger.d('[PreGeneration] 没有视频文件，跳过预生成');
      return;
    }

    logger.i('[RecommendAggregatePage] 启动后台预生成 ${videoFiles.length} 个视频缩略图');

    final service = ThumbnailPreGenerationService();

    // 后台执行，不等待完成
    service.preGenerateThumbnails(
      videoFiles,
      onProgress: (current, total) {
        // 可选：记录进度日志
        if (current % 10 == 0 || current == total) {
          logger.i('[RecommendAggregatePage] 后台预生成进度: $current/$total');
        }
      },
      onComplete: () {
        logger.i('[RecommendAggregatePage] 后台预生成完成');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 检测横屏模式
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return wrapWithPopScope(
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              // AppBar（横屏时使用SliverAppBar支持自动隐藏）
              isLandscape
                  ? SliverAppBar(
                      floating: true, // 向上滑动时立即显示
                      snap: true, // 显示/隐藏时有吸附效果
                      pinned: false, // 不固定在顶部
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context, _dataUpdated),
                      ),
                      title: Text(
                        widget.config.subtitle != null
                            ? '${widget.config.title} · ${widget.config.subtitle}'
                            : widget.config.title,
                        style: const TextStyle(fontSize: 16),
                      ),
                      centerTitle: false,
                      titleSpacing: 0,
                      toolbarHeight: 48, // 横屏时压缩AppBar高度
                      backgroundColor: widget.config.themeColor,
                      foregroundColor: Colors.white,
                      systemOverlayStyle: SystemUiOverlayStyle.light, // 状态栏使用浅色图标（白色）
                    )
                  : SliverAppBar(
                      pinned: true, // 竖屏时固定在顶部
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context, _dataUpdated),
                      ),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.config.title),
                          if (widget.config.subtitle != null)
                            Text(
                              widget.config.subtitle!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                        ],
                      ),
                      centerTitle: false,
                      titleSpacing: 0,
                      backgroundColor: widget.config.themeColor,
                      foregroundColor: Colors.white,
                    ),

              // Header（横屏时隐藏以节省空间）
              if (widget.config.headerType != HeaderType.none && !isLandscape)
                SliverToBoxAdapter(child: _buildHeader()),

              // Tab Bar（仅 application 模式，吸顶显示）
              if (widget.config.mode == RecommendMode.application && _tabController != null)
                SliverPersistentHeader(
                  pinned: true, // 吸顶
                  delegate: _StickyHeaderDelegate(
                    child: _buildTabBar(),
                    // 横屏时高度 = Tab高度 + 状态栏高度
                    height: isLandscape ? 44 + MediaQuery.of(context).padding.top : 56,
                  ),
                ),

              // 工具栏（吸顶显示）
              SliverPersistentHeader(
                pinned: true, // 吸顶
                delegate: _StickyHeaderDelegate(
                  child: _buildToolbar(),
                  // content模式（时光记忆、生活剪影、声音记录）和cleanupRecommend模式（大文件）在横屏时需要增加状态栏高度
                  height: isLandscape
                      ? (widget.config.mode == RecommendMode.content ||
                              widget.config.mode == RecommendMode.cleanupRecommend
                          ? 40 + MediaQuery.of(context).padding.top
                          : 40)
                      : 48,
                ),
              ),

              // 搜索框（条件显示，吸顶）
              if (_isSearchMode)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyHeaderDelegate(
                    child: FileSearchBar(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onSearch: (query) => setState(() => _searchQuery = query),
                      onChanged: (query) => setState(() => _searchQuery = query),
                      onClose: () => setState(() {
                        _isSearchMode = false;
                        _searchQuery = '';
                        _searchController.clear();
                      }),
                    ),
                    height: 56,
                  ),
                ),
            ];
          },
          body: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        '正在扫描文件，请稍候...',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : _buildFileListForNestedScroll(),
        ),
        bottomNavigationBar: isEditMode ? _buildSelectionBottomBar() : null,
      ),
    );
  }

  /// 构建 Header
  Widget _buildHeader() {
    switch (widget.config.headerType) {
      case HeaderType.applicationSummary:
        return _ApplicationSummaryHeader(
          files: _files,
          themeColor: widget.config.themeColor,
        );

      case HeaderType.emotion:
        return _EmotionHeader(
          config: widget.config,
          filesCount: _files.length,
        );

      case HeaderType.storageSummary:
        return _StorageSummaryHeader(
          files: _files,
          themeColor: widget.config.themeColor,
        );

      case HeaderType.none:
        return const SizedBox.shrink();
    }
  }

  /// 构建 Tab Bar
  Widget _buildTabBar() {
    if (_visibleTabs == null || _visibleTabs!.isEmpty) {
      return const SizedBox.shrink();
    }

    // 检测横屏模式
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    // 横屏时添加顶部安全区域，避免与系统状态栏重合
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: isLandscape ? EdgeInsets.only(top: MediaQuery.of(context).padding.top) : EdgeInsets.zero,
      child: TabBar(
        controller: _tabController,
        isScrollable: true, // 允许滚动以显示更多Tab
        tabAlignment: TabAlignment.start, // Tab靠左显示
        tabs: _visibleTabs!.map((tab) {
          return Tab(
            text: tab.title,
            icon: tab.icon != null ? Icon(tab.icon, size: isLandscape ? 18 : 22) : null,
            height: isLandscape ? 44 : 56, // 横屏时压缩高度（44避免溢出）
            iconMargin: EdgeInsets.only(bottom: isLandscape ? 0 : 2), // 横屏去掉底部边距
          );
        }).toList(),
        labelColor: widget.config.themeColor ?? Theme.of(context).primaryColor,
        unselectedLabelColor: Colors.grey,
        indicatorColor: widget.config.themeColor ?? Theme.of(context).primaryColor,
        labelStyle: TextStyle(fontSize: isLandscape ? 12 : 13), // 横屏时更小的文字
        unselectedLabelStyle: TextStyle(fontSize: isLandscape ? 12 : 13),
      ),
    );
  }

  /// 构建工具栏
  Widget _buildToolbar() {
    final theme = Theme.of(context);
    // 检测横屏模式
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    // content模式（时光记忆、生活剪影、声音记录）和cleanupRecommend模式（大文件）在横屏时需要增加顶部安全区域
    final needsTopPadding =
        (widget.config.mode == RecommendMode.content || widget.config.mode == RecommendMode.cleanupRecommend) &&
            isLandscape;
    final topPadding = needsTopPadding ? MediaQuery.of(context).padding.top : 0.0;

    return Container(
      height: isLandscape ? 40 : 48, // 横屏时压缩高度
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 1),
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5), width: 0.5),
        ),
      ),
      padding: EdgeInsets.only(
        left: isLandscape ? 6 : 8,
        right: isLandscape ? 6 : 8,
        top: topPadding, // 横屏时在content模式下增加顶部安全区域
      ),
      child: Row(
        children: [
          // 编辑模式：全选按钮（只在编辑模式且有文件时显示）
          if (isEditMode && _filteredFiles.isNotEmpty)
            SelectAllButton(
              selectedCount: _selectionController.selected.length,
              totalCount: _filteredFiles.length,
              onPressed: () {
                setState(() {
                  if (_selectionController.selected.length == _filteredFiles.length) {
                    _selectionController.clear();
                  } else {
                    _selectionController.selectAll(
                      _filteredFiles.map((f) => f.path).toList(),
                    );
                  }
                });
              },
              iconSize: 22,
            ),

          const Spacer(),

          // 工具按钮区
          FileToolbar(
            pageId: _getPageIdForCurrentTab(),
            showBackButton: false,
            showSearchButton: true,
            onSearchPressed: _toggleSearch,
            isSearchMode: _isSearchMode,
            showSortButton: true,
            onSortPressed: _showSortOptions,
            showGroupButton: true,
            onGroupToggle: () => setState(() {}),
            showViewModeToggle: true,
            iconSize: 20,
          ),

          // 编辑/完成按钮
          EditModeToolbarButton(
            isEditMode: isEditMode,
            onEnterEditMode: enterEditMode,
            onExitEditMode: exitEditMode,
          ),
        ],
      ),
    );
  }

  /// 切换搜索模式
  void _toggleSearch() {
    setState(() {
      _isSearchMode = !_isSearchMode;
      if (!_isSearchMode) {
        _searchQuery = '';
        _searchController.clear();
      } else {
        // 进入搜索模式时，聚焦输入框
        Future.delayed(const Duration(milliseconds: 100), () {
          _searchFocusNode.requestFocus();
        });
      }
    });
  }

  /// 显示排序选项
  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final pageId = _getPageIdForCurrentTab();
        final settings = PageSettingsService().getPageSettings(pageId);

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '排序方式',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildSortOption(
                    context: context,
                    title: '修改时间',
                    sortType: SortType.modifiedTime,
                    currentSortType: settings.sortType,
                    currentAscending: settings.sortAscending,
                    onTap: (ascending) {
                      PageSettingsService().setSortType(pageId, SortType.modifiedTime);
                      PageSettingsService().setSortAscending(pageId, ascending ?? false);
                      setState(() {});
                      Navigator.pop(context); // 关闭菜单
                    },
                  ),
                  _buildSortOption(
                    context: context,
                    title: '文件名',
                    sortType: SortType.name,
                    currentSortType: settings.sortType,
                    currentAscending: settings.sortAscending,
                    onTap: (ascending) {
                      PageSettingsService().setSortType(pageId, SortType.name);
                      PageSettingsService().setSortAscending(pageId, ascending ?? false);
                      setState(() {});
                      Navigator.pop(context); // 关闭菜单
                    },
                  ),
                  _buildSortOption(
                    context: context,
                    title: '文件大小',
                    sortType: SortType.size,
                    currentSortType: settings.sortType,
                    currentAscending: settings.sortAscending,
                    onTap: (ascending) {
                      PageSettingsService().setSortType(pageId, SortType.size);
                      PageSettingsService().setSortAscending(pageId, ascending ?? false);
                      setState(() {});
                      Navigator.pop(context); // 关闭菜单
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 构建排序选项
  Widget _buildSortOption({
    required BuildContext context,
    required String title,
    required SortType sortType,
    SortType? currentSortType,
    bool? currentAscending,
    required Function(bool? ascending) onTap,
  }) {
    final isSelected = currentSortType == sortType;

    return ListTile(
      title: Text(title),
      trailing: isSelected
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  currentAscending == true ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 18,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.check, color: Colors.blue),
              ],
            )
          : null,
      onTap: () {
        if (isSelected) {
          // 切换升序/降序
          onTap(!(currentAscending ?? false));
        } else {
          // 选择新的排序方式，默认降序
          onTap(false);
        }
      },
    );
  }

  /// 过滤后的文件列表（支持搜索）
  List<FileItem> get _filteredFiles {
    var result = _files;

    if (_searchQuery.isNotEmpty) {
      result = result.where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    // 应用排序
    final pageId = _getPageIdForCurrentTab();
    final settings = PageSettingsService().getPageSettings(pageId);
    if (settings.sortType != null) {
      result = FileComparatorUtil.sortFiles(
        result,
        settings.sortType!,
        ascending: settings.sortAscending ?? false,
      );
    }

    return result;
  }

  /// 分组后的文件列表
  Map<String, List<FileItem>> get _groupedFiles {
    final pageId = _getPageIdForCurrentTab();
    final isGroupEnabled = PageSettingsService().getGroupEnabled(pageId);

    if (!isGroupEnabled) {
      return {'': _filteredFiles};
    }

    return FileGroupingUtil.groupByModifiedDate(_filteredFiles);
  }

  /// 判断是否使用网格视图
  bool get _isGridView {
    final pageId = _getPageIdForCurrentTab();
    return PageSettingsService().getViewMode(pageId) == ViewMode.grid;
  }

  /// 构建文件列表

  /// 构建用于NestedScrollView的文件列表
  Widget _buildFileListForNestedScroll() {
    final files = _filteredFiles;
    if (files.isEmpty) {
      return Center(
        child: Text(_isSearchMode ? '无匹配结果' : '暂无文件'),
      );
    }

    final isGridView = _isGridView;
    final pageId = _getPageIdForCurrentTab();
    final isGroupEnabled = PageSettingsService().getGroupEnabled(pageId);

    // 判断当前Tab是否为纯图片/视频Tab（所有文件类型相同）
    bool isPureImageOrVideoTab = false;
    if (widget.config.mode == RecommendMode.application &&
        _tabController != null &&
        _visibleTabs != null &&
        _visibleTabs!.isNotEmpty) {
      final currentTab = _visibleTabs![_tabController!.index];
      isPureImageOrVideoTab = currentTab.title == '图片' || currentTab.title == '视频';
    } else if (widget.config.mode == RecommendMode.content) {
      isPureImageOrVideoTab =
          widget.config.type == RecommendationType.memories || widget.config.type == RecommendationType.videos;
    }

    // ⚡ 性能优化：纯图片/视频Tab使用全局config，混合Tab使用viewConfigBuilder
    UnifiedViewConfig? config;
    UnifiedViewConfig? Function(FileItem)? viewConfigBuilder;

    if (isGridView && isPureImageOrVideoTab) {
      // 纯图片/视频Tab：所有文件配置相同，使用全局config（避免每个item都调用函数）
      final showFileInfo = PageSettingsService().getGridShowFileInfo(pageId);
      final useCompactMode = !showFileInfo;
      config = UnifiedViewConfig.fromContext(context, compactMode: useCompactMode);
      logger.d('⚡ 使用全局config (compactMode: $useCompactMode) - 纯图片/视频Tab');
    } else if (isGridView) {
      // 混合Tab（如下载Tab）：文件类型不同，使用viewConfigBuilder
      final showFileInfo = PageSettingsService().getGridShowFileInfo(pageId);
      viewConfigBuilder = (file) {
        if (!file.isDirectory) {
          final fileTypes = AppConfig.instance.fileTypes;
          final isImage = fileTypes.isImageFile(file.name);
          final isVideo = fileTypes.isVideoFile(file.name);
          if (isImage || isVideo) {
            final useCompactMode = !showFileInfo;
            return UnifiedViewConfig.fromContext(context, compactMode: useCompactMode);
          }
        }
        return UnifiedViewConfig.fromContext(context, compactMode: false);
      };
    }

    // 使用Builder确保正确获取PrimaryScrollController
    return Builder(
      builder: (context) {
        // 如果启用分组，使用groups参数
        if (isGroupEnabled) {
          final groupedFiles = _groupedFiles;
          final fileGroups = groupedFiles.entries.map((entry) {
            final dateLabel = entry.key;
            final groupFiles = entry.value;
            return FileGroup(
              key: dateLabel,
              title: dateLabel.isNotEmpty ? '$dateLabel（${groupFiles.length}个文件）' : '',
              items: groupFiles,
              isCollapsible: false,
            );
          }).toList();

          return FileCollectionView(
            groups: fileGroups,
            gridMode: isGridView,
            config: config,
            padding: isGridView ? const EdgeInsets.all(8) : const EdgeInsets.symmetric(vertical: 0),
            // 优化预构建范围：图片Tab/时光记忆3500px，视频Tab/生活剪影2000px，混合Tab1000px，列表600px
            cacheExtent: isGridView ? _getCacheExtent() : 600.0,
            selectionController: _selectionController,
            showCheckbox: isEditMode,
            showFavoriteButton: true,
            isFavorite: (path) => widget.viewModel.isFavoriteFile(path),
            onFavoriteToggle: (file) async {
              return await widget.presenter.toggleFavoriteFile(file);
            },
            useUnifiedGridItem: true,
            viewConfigBuilder: viewConfigBuilder,
            onTap: _onFileTap,
            onLongPress: _onFileLongPress,
            onRefresh: () async {
              await _loadFiles(forceRefresh: true);
            },
          );
        }

        return FileCollectionView(
          items: files,
          gridMode: isGridView,
          config: config,
          padding: isGridView ? const EdgeInsets.all(8) : const EdgeInsets.symmetric(vertical: 0),
          // 优化预构建范围：图片Tab/时光记忆3500px，视频Tab/生活剪影2000px，混合Tab1000px，列表600px
          cacheExtent: isGridView ? _getCacheExtent() : 600.0,
          selectionController: _selectionController,
          showCheckbox: isEditMode,
          showFavoriteButton: true,
          isFavorite: (path) => widget.viewModel.isFavoriteFile(path),
          onFavoriteToggle: (file) async {
            return await widget.presenter.toggleFavoriteFile(file);
          },
          useUnifiedGridItem: true,
          viewConfigBuilder: viewConfigBuilder,
          onTap: _onFileTap,
          onLongPress: _onFileLongPress,
          onRefresh: () async {
            await _loadFiles(forceRefresh: true);
          },
        );
      },
    );
  }

  /// 获取智能预构建范围
  ///
  /// 根据当前Tab类型返回最优的cacheExtent值：
  /// - 图片Tab/时光记忆：3500px（图片解码快，预构建更多）
  /// - 视频Tab/生活剪影：2000px（视频解码慢，适度预构建）
  /// - 其他混合Tab：1000px（默认值）
  double _getCacheExtent() {
    // 应用模式：根据当前Tab判断
    if (widget.config.mode == RecommendMode.application &&
        _tabController != null &&
        _visibleTabs != null &&
        _visibleTabs!.isNotEmpty) {
      final currentTab = _visibleTabs![_tabController!.index];
      if (currentTab.title == '图片') {
        return 3500.0; // 图片Tab：大幅提升预构建范围
      } else if (currentTab.title == '视频') {
        return 2000.0; // 视频Tab：保持适度预构建
      }
    }

    // 内容模式：根据推荐类型判断
    if (widget.config.mode == RecommendMode.content) {
      if (widget.config.type == RecommendationType.memories) {
        return 3500.0; // 时光记忆（照片）：大幅提升预构建范围
      } else if (widget.config.type == RecommendationType.videos) {
        return 2000.0; // 生活剪影（视频）：保持适度预构建
      }
    }

    // 其他情况：使用默认值
    return 1000.0;
  }

  /// 构建批量操作底部栏
  Widget _buildSelectionBottomBar() {
    return SelectionBottomBar(
      selectedPaths: _selectionController.selected,
      isAllFavorite: _batchOperationsService.isAllSelectedFavorite(
        _selectionController.selected,
      ),
      onCopy: () {
        if (!mounted) return;
        _batchOperationsService.batchCopy(
          context,
          _selectionController.selected,
          '/storage/emulated/0',
        );
      },
      onRename: () {
        if (!mounted) return;
        _batchOperationsService.batchRename(
          context,
          _selectionController.selected,
        );
      },
      onShare: () {
        if (!mounted) return;
        _batchOperationsService.batchShare(
          context,
          _selectionController.selected,
        );
      },
      onMove: () {
        if (!mounted) return;
        _batchOperationsService.batchMove(
          context,
          _selectionController.selected,
          '/storage/emulated/0',
          shouldRefresh: false,
        );
      },
      onToggleFavorite: () {
        if (!mounted) return;
        _batchOperationsService.batchToggleFavorite(
          context,
          _selectionController.selected,
        );
      },
      onDelete: () {
        if (!mounted) return;
        _batchOperationsService.batchDelete(
          context,
          _selectionController.selected,
        );
      },
    );
  }
}

// ============================================================================
// Header 组件
// ============================================================================

/// 应用汇总 Header
class _ApplicationSummaryHeader extends StatelessWidget {
  final List<FileItem> files;
  final Color? themeColor;

  const _ApplicationSummaryHeader({
    required this.files,
    this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    final totalSize = files.fold<int>(0, (sum, file) => sum + file.size);

    return Container(
      padding: const EdgeInsets.all(16),
      color: themeColor?.withValues(alpha: 0.1) ?? Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            icon: Icons.file_copy,
            label: '文件数量',
            value: '${files.length}',
          ),
          _buildStatItem(
            icon: Icons.storage,
            label: '占用空间',
            value: _formatSize(totalSize),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, size: 32, color: themeColor),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
  }
}

/// 情感化 Header
class _EmotionHeader extends StatelessWidget {
  final RecommendPageConfig config;
  final int filesCount;

  const _EmotionHeader({
    required this.config,
    required this.filesCount,
  });

  @override
  Widget build(BuildContext context) {
    final emotionText = _getEmotionText();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            config.themeColor?.withValues(alpha: 0.3) ?? Colors.purple.withValues(alpha: 0.3),
            config.themeColor?.withValues(alpha: 0.1) ?? Colors.purple.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            emotionText,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '共找到 $filesCount 个回忆',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  String _getEmotionText() {
    // TODO: 根据推荐类型返回不同的情感化文案
    switch (config.type) {
      case RecommendationType.memories:
        return '这些照片，记录了你的珍贵回忆\n时光流转，美好永存 📷';
      case RecommendationType.videos:
        return '生活的精彩片段\n都在这些视频里 🎬';
      case RecommendationType.recordings:
        return '声音，承载着记忆\n每一段录音都值得回味 🎤';
      default:
        return '发现这些文件\n可能对你有用 📁';
    }
  }
}

/// 存储汇总 Header
class _StorageSummaryHeader extends StatelessWidget {
  final List<FileItem> files;
  final Color? themeColor;

  const _StorageSummaryHeader({
    required this.files,
    this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    final totalSize = files.fold<int>(0, (sum, file) => sum + file.size);
    final largestFile = files.isEmpty ? null : files.reduce((a, b) => a.size > b.size ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.orange.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                '占用空间：${_formatSize(totalSize)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (largestFile != null) ...[
            const SizedBox(height: 8),
            Text(
              '最大文件：${largestFile.name} (${_formatSize(largestFile.size)})',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
    }
  }
}

/// 吸顶Header的Delegate
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _StickyHeaderDelegate({
    required this.child,
    required this.height,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}
