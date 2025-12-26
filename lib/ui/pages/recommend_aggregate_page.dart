import 'package:flutter/material.dart';
import 'package:easyfile/core/models/recommend_page_config.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/file_change_listener_service.dart';
import 'package:easyfile/core/services/app_statistics_cache.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/data_sources/data_sources.dart';
import 'package:easyfile/core/data_sources/recommend_config_mapper.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/data/models/recommendation_card.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/mixins/edit_mode_mixin.dart';
import 'package:easyfile/ui/mixins/pop_scope_handler_mixin.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/ui/widgets/file_toolbar.dart';
import 'package:easyfile/ui/widgets/file_search_bar.dart';
import 'package:easyfile/ui/widgets/unified_view_config.dart';
import 'package:easyfile/ui/services/single_file_operations_service.dart';
import 'package:easyfile/ui/services/batch_operations_service.dart';
import 'package:easyfile/ui/widgets/single_file_operations_sheet.dart';
import 'package:easyfile/ui/widgets/selection_bottom_bar.dart';
import 'package:easyfile/ui/widgets/edit_mode_widgets.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/utils/file_grouping_util.dart';
import 'package:easyfile/utils/file_comparator_util.dart';

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
    Key? key,
    required this.config,
    required this.dataSourceFactory,
    required this.viewModel,
    required this.presenter,
  }) : super(key: key);

  @override
  State<RecommendAggregatePage> createState() => _RecommendAggregatePageState();
}

class _RecommendAggregatePageState extends State<RecommendAggregatePage>
    with SingleTickerProviderStateMixin, EditModeMixin, PopScopeHandlerMixin {
  
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
  
  /// 文件变化监听服务
  FileChangeListenerService? _fileChangeListener;
  
  @override
  void initState() {
    super.initState();
    _initDataSource();
    _initServices();
    _loadFilesAndInitTabs();
    _initFileChangeListener();
    
    // 监听PageSettingsService变化
    PageSettingsService().addListener(_onPageSettingsChanged);
  }
  
  @override
  void dispose() {
    PageSettingsService().removeListener(_onPageSettingsChanged);
    _fileChangeListener?.stopListening();
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
  
  /// 初始化文件变化监听
  Future<void> _initFileChangeListener() async {
    try {
      // 创建统计缓存实例
      final statisticsCache = AppStatisticsCache();
      
      _fileChangeListener = FileChangeListenerService(
        statisticsCache: statisticsCache,
        onCacheCleared: () async {
          // 缓存清除后自动刷新文件列表
          logger.i('🔄 文件变化 -> 自动刷新应用文件列表');
          if (mounted) {
            // 延迟10秒后刷新，给用户足够的时间看到新文件
            await Future.delayed(const Duration(seconds: 10));
            if (mounted) {
              _loadFiles(forceRefresh: true);
            }
          }
        },
      );
      await _fileChangeListener!.startListening();
      
      logger.i('✓ 应用文件列表页: 文件监听已启动');
    } catch (e) {
      logger.e('启动文件监听失败: $e');
    }
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
      
      // ⚡ 快速路径：先从缓存读取文件数量（如果是应用模式）
      if (widget.config.mode == RecommendMode.application) {
        final appKey = params['appKey'] as String?;
        if (appKey != null) {
          // 尝试从缓存快速获取文件数量
          final cachedCount = await widget.dataSourceFactory.scanner?.getFileCountFast(appKey: appKey);
          if (cachedCount != null && cachedCount > 0) {
            logger.d('RecommendAggregatePage - 缓存命中: $appKey = $cachedCount 文件');
            // 立即更新UI显示缓存的数量（使用空列表占位）
            if (mounted) {
              setState(() {
                _allFiles = List.generate(cachedCount, (i) => FileItem(
                  name: '',
                  path: '',
                  isDirectory: false,
                  size: 0,
                  modified: DateTime.now(),
                ));
                _files = _allFiles;
              });
            }
          }
        }
      }
      
      // 查询文件
      final files = await _dataSource.queryFiles(params);
      
      if (mounted) {
        // 根据文件内容过滤出visible tabs
        if (widget.config.mode == RecommendMode.application && 
            widget.config.tabs != null) {
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
    } catch (e) {
      logger.e('RecommendAggregatePage - 加载失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
        final ext = file.name.split('.').last.toLowerCase();
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
      final ext = file.name.split('.').last.toLowerCase();
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
      Map<String, dynamic> params;
      
      if (widget.config.mode == RecommendMode.application && 
          _tabController != null) {
        // 应用模式：根据当前 Tab 获取参数
        final currentTab = _visibleTabs![_tabController!.index];
        params = RecommendConfigDataSourceMapper.getTabQueryParams(
          widget.config.type,
          fileTypes: currentTab.fileTypes,
        );
      } else {
        // 内容/清理模式：使用默认参数
        params = RecommendConfigDataSourceMapper.getDefaultQueryParams(
          widget.config.type,
        );
      }
      
      // 添加强制刷新标志（用于缓存控制）
      if (forceRefresh) {
        params['forceRefresh'] = true;
      }
      
      logger.d('RecommendAggregatePage - 查询参数: $params${forceRefresh ? ' (强制刷新)' : ''}');
      
      // 查询文件
      final files = await _dataSource.queryFiles(params);
      
      if (mounted) {
        setState(() {
          _allFiles = files;
          _files = _filterFilesByTab(files);
          _isLoading = false;
        });
      }
      
      logger.i('RecommendAggregatePage - 加载完成: ${_allFiles.length} 个文件，显示 ${_files.length} 个');
    } catch (e) {
      logger.e('RecommendAggregatePage - 加载失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
        final ext = file.name.split('.').last.toLowerCase();
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
      final ext = file.name.split('.').last.toLowerCase();
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
    final isMediaFile = FileUtils.isImageFile(file.name) ||
        FileUtils.isVideoFile(file.name) ||
        FileUtils.isAudioFile(file.name);
    
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
  
  @override
  Widget build(BuildContext context) {
    return wrapWithPopScope(
      child: Scaffold(
        appBar: _buildAppBar(),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              // Header（根据配置选择）
              if (widget.config.headerType != HeaderType.none)
                SliverToBoxAdapter(child: _buildHeader()),
              
              // Tab Bar（仅 application 模式，吸顶显示）
              if (widget.config.mode == RecommendMode.application && _tabController != null)
                SliverPersistentHeader(
                  pinned: true, // 吸顶
                  delegate: _StickyHeaderDelegate(
                    child: _buildTabBar(),
                    height: 56,
                  ),
                ),
              
              // 工具栏（吸顶显示）
              SliverPersistentHeader(
                pinned: true, // 吸顶
                delegate: _StickyHeaderDelegate(
                  child: _buildToolbar(),
                  height: 48,
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
              ? const Center(child: CircularProgressIndicator())
              : _buildFileListForNestedScroll(),
        ),
        bottomNavigationBar: isEditMode
            ? _buildSelectionBottomBar()
            : null,
      ),
    );
  }
  
  /// 构建 AppBar
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          // 返回时传递数据更新标志
          Navigator.pop(context, _dataUpdated);
        },
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
      backgroundColor: widget.config.themeColor,
      foregroundColor: Colors.white, // 确保文字在深色背景下清晰可见
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
    
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: TabBar(
        controller: _tabController,
        isScrollable: true, // 允许滚动以显示更多Tab
        tabAlignment: TabAlignment.start, // Tab靠左显示
        tabs: _visibleTabs!.map((tab) {
          return Tab(
            text: tab.title,
            icon: tab.icon != null ? Icon(tab.icon, size: 22) : null, // Icon尺寸22
            height: 56, // 减少Tab高度，避免遮挡
            iconMargin: const EdgeInsets.only(bottom: 2), // 减小icon和文字的间距
          );
        }).toList(),
        labelColor: widget.config.themeColor ?? Theme.of(context).primaryColor,
        unselectedLabelColor: Colors.grey,
        indicatorColor: widget.config.themeColor ?? Theme.of(context).primaryColor,
        labelStyle: const TextStyle(fontSize: 13), // 略微减小文字大小
        unselectedLabelStyle: const TextStyle(fontSize: 13),
      ),
    );
  }
  
  /// 构建工具栏
  Widget _buildToolbar() {
    final theme = Theme.of(context);
    
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 1),
          top: BorderSide(color: theme.dividerColor.withOpacity(0.5), width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
      result = result.where((f) => 
        f.name.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
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
    
    // 为图片/视频构建视图配置（简洁模式支持）
    UnifiedViewConfig? Function(FileItem)? viewConfigBuilder;
    if (isGridView) {
      viewConfigBuilder = (file) {
        final shouldUseCompactMode = !file.isDirectory &&
            (file.category == FileCategory.image ||
                file.category == FileCategory.video);
        if (shouldUseCompactMode) {
          final showFileInfo =
              PageSettingsService().getGridShowFileInfo(pageId);
          return UnifiedViewConfig.fromContext(context,
              compactMode: !showFileInfo);
        }
        return null;
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
            padding: isGridView
                ? const EdgeInsets.all(8)
                : const EdgeInsets.symmetric(vertical: 0),
            cacheExtent: isGridView ? 1000.0 : 600.0,
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
          padding: isGridView
              ? const EdgeInsets.all(8)
              : const EdgeInsets.symmetric(vertical: 0),
          cacheExtent: isGridView ? 1000.0 : 600.0,
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
      color: themeColor?.withOpacity(0.1) ?? Colors.grey[100],
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
            config.themeColor?.withOpacity(0.3) ?? Colors.purple.withOpacity(0.3),
            config.themeColor?.withOpacity(0.1) ?? Colors.purple.withOpacity(0.1),
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
    final largestFile = files.isEmpty 
        ? null 
        : files.reduce((a, b) => a.size > b.size ? a : b);
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.orange.withOpacity(0.1),
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
