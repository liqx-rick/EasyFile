import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/archive_preview_cache_manager.dart';
import 'package:easyfile/core/services/extraction_record_service.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/ui/services/single_file_operations_service.dart';
import 'package:easyfile/ui/widgets/single_file_operations_sheet.dart';
import 'package:easyfile/ui/widgets/selection_bottom_bar.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/ui/widgets/unified_view_config.dart';
import 'package:easyfile/ui/widgets/archive_list_item.dart';
import 'package:easyfile/ui/widgets/file_search_bar.dart';
import 'package:easyfile/ui/widgets/file_toolbar.dart';
import 'package:easyfile/ui/mixins/category_like_page_mixin.dart';
import 'package:easyfile/ui/mixins/edit_mode_mixin.dart';
import 'package:easyfile/ui/mixins/batch_operations_mixin.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/ui/pages/archive_viewer_page.dart';
import 'package:easyfile/ui/pages/extraction_records_page.dart';

/// 压缩包管理页面
///
/// 扫描并展示设备上所有压缩包文件
/// 支持：
/// - 搜索（按名称）
/// - 格式筛选（全部/ZIP/RAR/7Z/其他）
/// - 排序（名称/大小/时间）
/// - 编辑模式（多选）
/// - 批量删除
/// - 单文件操作（删除、分享等）
class ArchiveManagementPage extends StatefulWidget {
  const ArchiveManagementPage({super.key});

  @override
  State<ArchiveManagementPage> createState() => _ArchiveManagementPageState();
}

class _ArchiveManagementPageState extends State<ArchiveManagementPage>
    with
        CategoryLikePageMixin<ArchiveManagementPage>,
        EditModeMixin<ArchiveManagementPage>,
        BatchOperationsMixin<ArchiveManagementPage>,
        SingleTickerProviderStateMixin {
  // TabController
  late final TabController _tabController;
  
  // 解压记录服务
  final ExtractionRecordService _recordService = ExtractionRecordService();
  int _recordCount = 0;
  
  // 已解压压缩包标记（用于显示角标）
  Set<String> _extractedArchives = {};
  static const String _extractedArchivesKey = 'extracted_archives';
  
  // 数据源和依赖
  late final FilePresenter _presenter;
  late final FileViewModel _viewModel;

  // 加载状态
  bool _isScanning = true;
  String _errorMessage = '';

  // 搜索
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchMode = false;

  // 排序
  String _sortBy = 'time'; // name, size, time
  bool _sortAscending = false; // 默认降序（最新的在前）

  // SelectionController（来自 EditModeMixin）
  final SelectionController _selectionController = SelectionController();

  @override
  SelectionController get selectionController => _selectionController;

  // BatchOperationsMixin 需要的 getter
  @override
  FilePresenter get presenter => _presenter;

  @override
  FileViewModel get viewModel => _viewModel;

  @override
  Future<void> refreshData() => _scanArchives();

  @override
  String get searchQuery => _searchController.text;

  @override
  bool filterFile(FileItem file) {
    // 显示所有压缩包，不区分格式
    return true;
  }

  @override
  void initState() {
    super.initState();

    // 初始化Tab控制器
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        // 切换到记录Tab时更新记录数
        _loadRecordCount();
      }
      setState(() {});
    });

    // 加载已解压标记
    _loadExtractedArchives();

    // 初始化依赖
    _presenter = locator<FilePresenter>();
    _viewModel = locator<FileViewModel>();

    // 初始化搜索控制器
    _searchController = TextEditingController();
    _searchController.addListener(() {
      setState(() {
        // searchQuery getter 会自动返回新的查询文本
        // filteredFiles 属性会自动重新计算
      });
    });

    // 初始化选择控制器
    _selectionController.selectedNotifier.addListener(() {
      setState(() {});
    });

    // 加载解压记录数量
    _loadRecordCount();

    // 加载排序偏好
    _loadSortPreferences();

    // 加载记录数
    _loadRecordCount();

    // 异步静默清理过期缓存（不阻塞UI）
    Future.microtask(() {
      ArchivePreviewCacheManager.clearExpiredCache();
    });

    // 加载压缩包列表
    _scanArchives();
  }

  /// 加载已解压压缩包标记
  Future<void> _loadExtractedArchives() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> paths = prefs.getStringList(_extractedArchivesKey) ?? [];
      setState(() {
        _extractedArchives = Set.from(paths);
      });
    } catch (e) {
      debugPrint('加载已解压标记失败: $e');
    }
  }

  /// 保存已解压压缩包标记
  Future<void> _saveExtractedArchives() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_extractedArchivesKey, _extractedArchives.toList());
    } catch (e) {
      debugPrint('保存已解压标记失败: $e');
    }
  }

  /// 加载记录数量
  Future<void> _loadRecordCount() async {
    final count = await _recordService.getRecordCount();
    if (mounted) {
      setState(() {
        _recordCount = count;
      });
    }
  }

  /// 加载排序偏好
  Future<void> _loadSortPreferences() async {
    try {
      final pageId = PageId.archiveManagement;
      final sortType = PageSettingsService().getSortType(pageId);
      final ascending = PageSettingsService().getSortAscending(pageId);

      setState(() {
        _sortBy = sortType.name.toLowerCase();
        _sortAscending = ascending;
      });

      logger.d(
          'Loaded archive page preferences: $sortType, ascending=$ascending');
    } catch (e) {
      logger.w('Failed to load sort preferences: $e');
      // 使用默认值
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _selectionController.selectedNotifier.removeListener(() {});
    _selectionController.dispose();
    super.dispose();
  }

  /// 扫描压缩包列表
  Future<void> _scanArchives() async {
    setState(() {
      _isScanning = true;
      _errorMessage = '';
    });

    try {
      // 直接使用 presenter 的分类扫描能力（复用现有逻辑）
      allFiles = await _presenter.scanFilesByCategory(CategoryType.archive);

      // 应用排序
      _applySorting();

      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    } catch (e) {
      logger.e('扫描压缩包失败: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
          _errorMessage = '扫描失败: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e')),
        );
      }
    }
  }

  /// 应用排序
  void _applySorting() {
    setState(() {
      // 使用 Mixin 提供的排序方法，在 allFiles 上应用排序
      final sortType = _getSortType();
      applySorting(allFiles, sortType, ascending: _sortAscending);

      // 保存排序偏好到 PageSettingsService
      final pageId = PageId.archiveManagement;
      PageSettingsService().setSortType(pageId, sortType);
      if (_sortAscending) {
        PageSettingsService().setSortAscending(pageId, true);
      } else {
        PageSettingsService().toggleSortDirection(pageId);
      }
    });
  }

  SortType _getSortType() {
    switch (_sortBy) {
      case 'name':
        return SortType.name;
      case 'size':
        return SortType.size;
      case 'time':
        return SortType.modifiedTime;
      default:
        return SortType.name;
    }
  }

  void _changeSortBy(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = sortBy;
        _sortAscending = true;
      }
      _applySorting();
    });
  }

  /// 显示排序菜单
  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                _sortBy == 'name'
                    ? (_sortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward)
                    : Icons.sort_by_alpha,
              ),
              title: const Text('按名称'),
              onTap: () {
                Navigator.pop(context);
                _changeSortBy('name');
              },
            ),
            ListTile(
              leading: Icon(
                _sortBy == 'size'
                    ? (_sortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward)
                    : Icons.data_usage,
              ),
              title: const Text('按大小'),
              onTap: () {
                Navigator.pop(context);
                _changeSortBy('size');
              },
            ),
            ListTile(
              leading: Icon(
                _sortBy == 'time'
                    ? (_sortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward)
                    : Icons.access_time,
              ),
              title: const Text('按时间'),
              onTap: () {
                Navigator.pop(context);
                _changeSortBy('time');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: _tabController.index == 0, // 只有在压缩包Tab时才能直接返回
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // 如果在解压记录Tab，切换回压缩包Tab
        if (_tabController.index == 1) {
          setState(() {
            _tabController.index = 0;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('压缩包管理', style: TextStyle(fontSize: 18)),
            if (!_isScanning && _tabController.index == 0)
              Text(
                '${filteredFiles.length} 个文件',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: _tabController.index == 0
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 使用 FileToolbar 统一工具栏
                      FileToolbar(
                        pageId: PageId.archiveManagement,
                        showBackButton: false,
                        showSearchButton: true,
                        onSearchPressed: () {
                          setState(() {
                            _isSearchMode = !_isSearchMode;
                            if (!_isSearchMode) {
                              _searchController.clear();
                            }
                          });
                        },
                        isSearchMode: _isSearchMode,
                        showSortButton: true,
                        onSortPressed: _showSortOptions,
                        showGroupButton: false,
                        showViewModeToggle: false,
                        iconSize: 22,
                      ),
                      // 编辑模式按钮
                      if (isEditMode)
                        IconButton(
                          icon: const Icon(Icons.close, size: 24, weight: 700),
                          color: theme.colorScheme.primary,
                          onPressed: exitEditMode,
                          tooltip: '退出编辑',
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: enterEditMode,
                          tooltip: '编辑',
                        ),
                    ],
                  ),
                ),
              ]
            : null,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('压缩包'),
                  if (!_isScanning)
                    Text(' (${filteredFiles.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('解压记录'),
                  if (_recordCount > 0) Text(' ($_recordCount)'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: 压缩包列表
          _buildArchiveListTab(theme),
          // Tab 2: 解压记录
          ExtractionRecordsPage(),
        ],
      ),
      ),
    );
  }

  Widget _buildArchiveListTab(ThemeData theme) {
    return Scaffold(
      body: Column(
        children: [
          // 搜索框（使用 FileSearchBar 组件）
          if (_isSearchMode)
            FileSearchBar(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: '搜索压缩包...',
              onSearch: (query) async {
                // 搜索逻辑已在 controller 的 listener 中处理
              },
              onClose: () {
                setState(() {
                  _searchController.clear();
                  _isSearchMode = false;
                });
              },
              onChanged: (query) {
                setState(() {
                  // 触发重新过滤
                });
              },
            ),
          // 列表
          Expanded(
            child: _buildBody(theme),
          ),
        ],
      ),
      bottomNavigationBar: isEditMode ? _buildSelectionBottomBar(theme) : null,
    );
  }

  /// 构建批量选择操作工具栏
  Widget _buildSelectionBottomBar(ThemeData theme) {
    final batchService = createBatchService(); // 使用 Mixin 提供的统一方法

    // 使用存储根目录作为移动/复制的起始路径
    const storagePath = '/storage/emulated/0';

    return SelectionBottomBar(
      selectedPaths: _selectionController.selected,
      isAllFavorite: false, // 压缩包不支持收藏
      onCopy: () {
        if (!mounted) return;
        batchService.batchCopy(
          context,
          _selectionController.selected,
          storagePath,
        );
      },
      onRename: () {
        if (!mounted) return;
        batchService.batchRename(context, _selectionController.selected);
      },
      onShare: () {
        if (!mounted) return;
        batchService.batchShare(context, _selectionController.selected);
      },
      onMove: () {
        if (!mounted) return;
        batchService.batchMove(
          context,
          _selectionController.selected,
          storagePath,
          shouldRefresh: true,
        );
      },
      onToggleFavorite: null, // 压缩包不支持收藏
      onDelete: () {
        if (!mounted) return;
        batchService.batchDelete(context, _selectionController.selected);
      },
    );
  }

  /// 构建格式筛选 chips
  /// 构建主体内容
  Widget _buildBody(ThemeData theme) {
    if (_isScanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '正在扫描压缩包...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (filteredFiles.isEmpty) {
      return _buildEmptyState(theme);
    }

    // 使用 FileCollectionView
    return FileCollectionView(
      items: filteredFiles,
      gridMode: false, // 压缩包管理页总是列表模式
      config: UnifiedViewConfig.fromContext(context),
      selectionController: _selectionController,
      showCheckbox: isEditMode, // 编辑模式下显示复选框
      // 使用自定义的压缩包列表项组件
      itemBuilder: (file) {
        final isSelected = _selectionController.contains(file.path);
        final hasExtracted = _extractedArchives.contains(file.path);
        return ArchiveListItem(
          file: file,
          isSelected: isSelected,
          hasExtracted: hasExtracted,
          showCheckbox: isEditMode,
          showExtractButton: !isEditMode, // 编辑模式下隐藏解压按钮
          onTap: () {
            if (isEditMode) {
              // 编辑模式：点击切换选中状态
              _selectionController.toggle(file.path);
            } else {
              // 正常模式：打开压缩包内容查看器
              _viewArchiveContents(file);
            }
          },
          onLongPress: () {
            // 编辑模式下禁用长按（避免与选择操作冲突）
            if (isEditMode) return;
            // 长按：显示单文件操作菜单（与 CategoryFilePage 保持一致）
            _showOperationsMenu(file);
          },
          onExtract: () {
            // 解压按钮回调
            _extractArchive(file);
          },
        );
      },
      onTap: (file) {
        if (isEditMode) {
          // 编辑模式：点击切换选中状态
          _selectionController.toggle(file.path);
        } else {
          // 正常模式：打开压缩包内容查看器
          _viewArchiveContents(file);
        }
      },
      onLongPress: (file) {
        // 编辑模式下禁用长按（避免与选择操作冲突）
        if (isEditMode) return;

        // 长按：显示单文件操作菜单（与 CategoryFilePage 保持一致）
        _showOperationsMenu(file);
      },
      padding: const EdgeInsets.symmetric(vertical: 0),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_zip_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '未找到压缩包',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '支持 ZIP、RAR、7Z、TAR、GZ 等格式',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 查看压缩包内容
  void _viewArchiveContents(FileItem archive) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ArchiveViewerPage(archiveFile: archive),
      ),
    );
  }

  /// 解压压缩包
  void _extractArchive(FileItem archive) {
    // 标记为已解压（点击开始解压按钮时立即标记）
    setState(() {
      _extractedArchives.add(archive.path);
    });
    _saveExtractedArchives();

    final service = SingleFileOperationsService(
      context: context,
      viewModel: _viewModel,
      presenter: _presenter,
      onRefresh: _scanArchives,
    );
    service.extractArchive(archive);
  }

  /// 显示操作菜单
  void _showOperationsMenu(FileItem archive) {
    final service = SingleFileOperationsService(
      context: context,
      viewModel: _viewModel,
      presenter: _presenter,
      onRefresh: _scanArchives,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SingleFileOperationsSheet(
        file: archive,
        service: service,
      ),
    );
  }
}
