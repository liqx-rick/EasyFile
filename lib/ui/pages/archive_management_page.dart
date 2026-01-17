import 'package:flutter/material.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/data/models/extraction_record.dart';
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
import 'package:easyfile/ui/widgets/edit_mode_widgets.dart';
import 'package:easyfile/ui/mixins/category_like_page_mixin.dart';
import 'package:easyfile/ui/mixins/edit_mode_mixin.dart';
import 'package:easyfile/ui/mixins/batch_operations_mixin.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/ui/pages/archive_viewer_page.dart';
import 'package:easyfile/ui/pages/extracted_files_browser_page.dart';

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
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver {
  // TabController
  late final TabController _tabController;
  
  // 解压记录服务
  final ExtractionRecordService _recordService = ExtractionRecordService();
  int _recordCount = 0;
  
  // 解压记录列表数据
  List<ExtractionRecord> _extractionRecords = [];
  Map<String, bool> _recordFolderExistsMap = {};
  bool _isLoadingRecords = true;
  
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

  // 单文件操作服务（修复问题1、2、3）- 延迟创建以便访问context
  SingleFileOperationsService? _singleFileOperationsService;
  
  SingleFileOperationsService get singleFileOperationsService {
    _singleFileOperationsService ??= SingleFileOperationsService(
      context: context,
      viewModel: _viewModel,
      presenter: _presenter,
      onRefresh: _forceRefreshAfterOperation, // 修复问题2、3：使用强制刷新
      onUIUpdate: () {
        // 轻量级UI刷新（不重新加载数据，只更新UI状态）
        if (mounted) {
          setState(() {});
        }
      },
    );
    return _singleFileOperationsService!;
  }
  
  /// 操作完成后强制刷新（修复问题2、3）
  Future<void> _forceRefreshAfterOperation() async {
    // 延迟一点确保文件系统操作完成
    await Future.delayed(const Duration(milliseconds: 100));
    // 清除可能的缓存
    _singleFileOperationsService = null;
    // 重新扫描
    await _scanArchives();
  }

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

  /// 处理ViewModel更新（修复问题2、3、删除实时刷新：实时更新文件信息）
  void _handleViewModelUpdate() {
    if (!mounted) return;

    // 处理文件删除
    final deletedPath = _viewModel.lastDeletedFilePath;
    if (deletedPath != null) {
      logger.d('ArchiveManagementPage: Processing file deletion: $deletedPath');
      setState(() {
        final initialLength = allFiles.length;
        allFiles.removeWhere((f) => f.path == deletedPath);
        final removed = initialLength - allFiles.length;
        if (removed > 0) {
          logger.i('Removed $removed file(s) from archive list. Remaining: ${allFiles.length}');
          // 同时从选择列表中移除（如果在编辑模式下）
          if (isEditMode && _selectionController.contains(deletedPath)) {
            _selectionController.deselect(deletedPath);
          }
          // 从已解压标记中移除
          _extractedArchives.remove(deletedPath);
          _saveExtractedArchives();
        }
      });
      return;
    }

    // 处理文件更新（重命名、移动、复制等）
    final updatedFile = _viewModel.lastUpdatedNewFile;
    if (updatedFile != null) {
      final oldPath = _viewModel.lastUpdatedOldPath;
      logger.d('ArchiveManagementPage: Processing file update');
      logger.d('  Old path: $oldPath');
      logger.d('  New path: ${updatedFile.path}');

      setState(() {
        if (oldPath != null) {
          // 重命名或移动：更新现有文件
          final index = allFiles.indexWhere((f) => f.path == oldPath);
          if (index != -1) {
            allFiles[index] = updatedFile;
            logger.d('Updated file at index $index: ${allFiles[index].path}');
          } else {
            logger.w('File not found for update: $oldPath');
          }
        }
      });
      return;
    }

    // 处理文件添加（复制操作）
    final addedFile = _viewModel.lastAddedFile;
    if (addedFile != null && FileUtils.isArchiveFile(addedFile.name)) {
      logger.d('ArchiveManagementPage: Processing file addition: ${addedFile.path}');
      setState(() {
        // 检查是否已存在（避免重复添加）
        if (!allFiles.any((f) => f.path == addedFile.path)) {
          allFiles.add(addedFile);
          // 重新排序
          _applySorting();
          logger.i('Added file to archive list. Total: ${allFiles.length}');
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();

    // 初始化Tab控制器
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        // 切换到记录Tab时更新记录数和列表
        _loadRecordCount();
        _loadExtractionRecords();
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

    // 监听ViewModel变化（修复问题2、3：实时更新文件信息）
    _viewModel.addListener(_handleViewModelUpdate);

    // 监听应用生命周期（应用恢复时刷新列表）
    WidgetsBinding.instance.addObserver(this);

    // 加载解压记录数量
    _loadRecordCount();

    // 加载排序偏好
    _loadSortPreferences();

    // 加载解压记录列表
    _loadExtractionRecords();

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

  /// 删除所有解压记录
  Future<void> _deleteAllExtractionRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空所有记录'),
        content: const Text('确定要清空所有解压记录吗？\n（不会删除解压后的文件）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _recordService.deleteAllRecords();
      await _loadRecordCount();
      await _loadExtractionRecords();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清空所有记录')),
        );
      }
    }
  }

  /// 加载解压记录列表
  Future<void> _loadExtractionRecords() async {
    setState(() => _isLoadingRecords = true);

    final records = await _recordService.getAllRecords();
    
    // 批量检查文件夹是否存在
    final paths = records.map((r) => r.targetPath).toList();
    final existsMap = await _recordService.batchCheckFoldersExist(paths);

    if (mounted) {
      setState(() {
        _extractionRecords = records;
        _recordFolderExistsMap = existsMap;
        _isLoadingRecords = false;
      });
    }
  }

  /// 删除单条解压记录
  Future<void> _deleteExtractionRecord(ExtractionRecord record) async {
    await _recordService.deleteRecord(record.id);
    await _loadRecordCount();
    await _loadExtractionRecords();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除记录')),
      );
    }
  }

  /// 查看解压文件
  Future<void> _viewExtractedFiles(ExtractionRecord record) async {
    // 导航到解压文件浏览页面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExtractedFilesBrowserPage(
          archiveName: record.archiveName,
          extractedPath: record.targetPath,
          presenter: _presenter,
          viewModel: _viewModel,
        ),
      ),
    );
  }

  /// 格式化路径显示
  String _formatRecordPathDisplay(String path) {
    if (path == '/storage/emulated/0') {
      return '内部存储';
    }
    if (path.startsWith('/storage/emulated/0/')) {
      final relativePath = path.substring('/storage/emulated/0/'.length);
      return '内部存储$relativePath';
    }
    return path;
  }

  /// 格式化日期时间
  String _formatRecordDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
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
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _selectionController.selectedNotifier.removeListener(() {});
    _selectionController.dispose();
    _viewModel.removeListener(_handleViewModelUpdate);
    super.dispose();
  }

  /// 应用生命周期状态变化回调
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      // 应用从后台恢复到前台，刷新压缩包列表
      logger.d('App resumed, refreshing archive list');
      _scanArchives();
    }
  }

  /// 扫描压缩包列表
  Future<void> _scanArchives() async {
    setState(() {
      _isScanning = true;
      _errorMessage = '';
    });

    try {
      // 保存当前最近添加的文件（避免被扫描结果覆盖）
      final recentlyAddedFile = _viewModel.lastAddedFile;
      
      // 直接使用 presenter 的分类扫描能力（复用现有逻辑）
      final scannedFiles = await _presenter.scanFilesByCategory(CategoryType.archive);
      
      // 修复MediaStore返回不完整数据的问题
      await _fixIncompleteFileMetadata(scannedFiles);
      
      // 如果有最近添加的文件，确保它在列表中（修复批量复制后显示错误的问题）
      if (recentlyAddedFile != null && 
          FileUtils.isArchiveFile(recentlyAddedFile.name)) {
        logger.d('Preserving recently added file: ${recentlyAddedFile.path}');
        
        // 如果扫描结果中不包含这个文件，或者包含但数据不完整，使用 ViewModel 中的版本
        final existingIndex = scannedFiles.indexWhere((f) => f.path == recentlyAddedFile.path);
        if (existingIndex == -1) {
          // 文件不在扫描结果中，添加它
          logger.i('Adding recently added file to scan results: ${recentlyAddedFile.name}');
          scannedFiles.add(recentlyAddedFile);
        } else {
          // 文件在扫描结果中，但检查数据是否完整
          final scannedFile = scannedFiles[existingIndex];
          if (scannedFile.size == 0 || scannedFile.modified.year == 1970) {
            // 扫描结果数据不完整，使用 ViewModel 中的正确数据
            logger.w('Scan result has incomplete data for ${recentlyAddedFile.name}');
            logger.i('Replacing with correct data: size=${recentlyAddedFile.size}, date=${recentlyAddedFile.modified}');
            scannedFiles[existingIndex] = recentlyAddedFile;
          }
        }
      }
      
      allFiles = scannedFiles;

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

  /// 修复MediaStore返回的不完整文件元数据
  /// 
  /// MediaStore可能返回size=0或date=1970的文件（缓存问题），
  /// 通过File.stat()重新获取正确的元数据
  Future<void> _fixIncompleteFileMetadata(List<FileItem> files) async {
    int fixedCount = 0;
    
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      
      // 检查是否有不完整的元数据
      if (file.size == 0 || file.modified.year == 1970) {
        try {
          final ioFile = File(file.path);
          if (await ioFile.exists()) {
            final stat = await ioFile.stat();
            
            // 只在数据确实有问题时才修复
            if ((file.size == 0 && stat.size > 0) || 
                (file.modified.year == 1970 && stat.modified.year > 1970)) {
              logger.w('Fixing incomplete metadata for: ${file.name}');
              logger.d('  Old: size=${file.size}, modified=${file.modified}');
              logger.d('  New: size=${stat.size}, modified=${stat.modified}');
              
              // 创建新的FileItem替换旧的
              files[i] = FileItem(
                name: file.name,
                path: file.path,
                size: stat.size,
                modified: stat.modified,
                isDirectory: file.isDirectory,
              );
              fixedCount++;
            }
          }
        } catch (e) {
          logger.e('Failed to fix metadata for ${file.name}: $e');
        }
      }
    }
    
    if (fixedCount > 0) {
      logger.i('Fixed $fixedCount file(s) with incomplete metadata');
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

    // 修复问题6：手动处理返回键
    return PopScope(
      canPop: !isEditMode && !_isSearchMode && _tabController.index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        
        // 优先级1: Tab切换
        if (_tabController.index == 1) {
          setState(() {
            _tabController.index = 0;
          });
          return;
        }
        
        // 优先级2: 退出搜索模式
        if (_isSearchMode) {
          setState(() {
            _isSearchMode = false;
            _searchController.clear();
          });
          return;
        }
        
        // 优先级3: 退出编辑模式
        if (isEditMode) {
          exitEditMode();
          return;
        }
      },
      child: Scaffold(
        appBar: AppBar(
        leading: isEditMode && _tabController.index == 0
            ? SelectAllButton(
                selectedCount: _selectionController.selected.length,
                totalCount: filteredFiles.length,
                onPressed: () {
                  setState(() {
                    if (_selectionController.selected.length == filteredFiles.length) {
                      _selectionController.clear();
                    } else {
                      _selectionController.selectAll(
                        filteredFiles.map((f) => f.path).toList(),
                      );
                    }
                  });
                },
              )
            : null,
        title: const Text('压缩包管理', style: TextStyle(fontSize: 18)),
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
            : _tabController.index == 1 && _recordCount > 0
                ? [
                    IconButton(
                      icon: const Icon(Icons.delete_sweep),
                      tooltip: '清空所有记录',
                      onPressed: _deleteAllExtractionRecords,
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
          _buildRecordsTab(theme),
        ],
      ),
      ),
    );
  }

  Widget _buildArchiveListTab(ThemeData theme) {
    final body = Column(
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
    );
    
    // 如果在编辑模式，包装底部导航栏
    if (isEditMode) {
      return Column(
        children: [
          Expanded(child: body),
          _buildSelectionBottomBar(theme),
        ],
      );
    }
    
    return body;
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
          showCheckbox: isEditMode, // 修复问题1：编辑模式显示checkbox
          checkboxPosition: CheckboxPosition.trailing,
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
        if (!isEditMode) {
          // 长按进入编辑模式并选中（修复问题5相关）
          enterEditMode();
          _selectionController.select(file.path);
        }
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

    singleFileOperationsService.extractArchive(archive);
  }

  /// 显示操作菜单（修复问题1、2、3 - 使用复用的service）
  void _showOperationsMenu(FileItem archive) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SingleFileOperationsSheet(
        file: archive,
        service: singleFileOperationsService,
      ),
    );
  }

  /// 构建解压记录Tab
  Widget _buildRecordsTab(ThemeData theme) {
    return _isLoadingRecords
        ? const Center(child: CircularProgressIndicator())
        : _extractionRecords.isEmpty
            ? _buildRecordsEmptyState(theme)
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _extractionRecords.length,
                separatorBuilder: (context, index) => const Divider(height: 32),
                itemBuilder: (context, index) {
                  final record = _extractionRecords[index];
                  final folderExists = _recordFolderExistsMap[record.targetPath] ?? false;
                  return _buildRecordItem(
                    record,
                    folderExists,
                    theme,
                  );
                },
              );
  }

  /// 构建解压记录空状态
  Widget _buildRecordsEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无解压记录',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '解压压缩包后会显示在这里',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单条解压记录项
  Widget _buildRecordItem(
    ExtractionRecord record,
    bool folderExists,
    ThemeData theme,
  ) {
    final colorScheme = theme.colorScheme;
    final isDeleted = !folderExists;
    final textColor = isDeleted
        ? colorScheme.onSurfaceVariant.withOpacity(0.5)
        : colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 压缩包名称
        Row(
          children: [
            Icon(
              Icons.folder_zip,
              color: isDeleted ? Colors.grey[400] : Colors.amber[700],
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                record.archiveName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // 解压文件夹信息
        Row(
          children: [
            const SizedBox(width: 28),
            Icon(
              Icons.folder,
              color: isDeleted ? Colors.grey[400] : colorScheme.primary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      record.folderName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${record.fileCount}个文件)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (isDeleted) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.warning_amber,
                      size: 16,
                      color: Colors.orange[700],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '已删除',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange[700],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 位置和时间
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(
            _formatRecordPathDisplay(record.targetPath),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(
            _formatRecordDateTime(record.extractedAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 操作按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (folderExists)
              TextButton.icon(
                onPressed: () => _viewExtractedFiles(record),
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('查看文件'),
              ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => _deleteExtractionRecord(record),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除'),
            ),
          ],
        ),
      ],
    );
  }
}
