import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/file_toolbar.dart';
import 'package:easyfile/ui/widgets/file_search_bar.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/ui/widgets/unified_view_config.dart';
import 'package:easyfile/ui/widgets/selection_bottom_bar.dart';
import 'package:easyfile/ui/widgets/folder_navigation_bar.dart';
import 'package:easyfile/ui/services/batch_operations_service.dart';
import 'package:easyfile/utils/file_comparator_util.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/core/services/file_display_settings_service.dart';
import 'package:easyfile/ui/mixins/edit_mode_mixin.dart';
import 'package:easyfile/ui/mixins/create_folder_mixin.dart';
import 'package:easyfile/ui/widgets/edit_mode_hint_bar.dart';
import 'package:easyfile/ui/services/single_file_operations_service.dart';
import 'package:easyfile/ui/widgets/single_file_operations_sheet.dart';

/// 解压文件浏览页面
///
/// 专门用于浏览解压后的文件夹内容
/// 特性：
/// - 自定义 AppBar 标题（显示压缩包名称）
/// - 移除排序和分组功能（默认按名称升序）
/// - 保留搜索、网格切换、编辑功能
/// - 返回逻辑：返回到解压记录页面
class ExtractedFilesBrowserPage extends StatefulWidget {
  final String archiveName; // 压缩包名称（用于显示标题）
  final String extractedPath; // 解压后的文件夹路径
  final FilePresenter presenter;
  final FileViewModel viewModel;

  const ExtractedFilesBrowserPage({
    super.key,
    required this.archiveName,
    required this.extractedPath,
    required this.presenter,
    required this.viewModel,
  });

  @override
  State<ExtractedFilesBrowserPage> createState() =>
      _ExtractedFilesBrowserPageState();
}

class _ExtractedFilesBrowserPageState extends State<ExtractedFilesBrowserPage>
    with EditModeMixin, CreateFolderMixin {
  String _searchQuery = '';
  bool _isSearchMode = false;

  // 批量操作相关状态
  late final SelectionController _selectionController;

  // EditModeMixin 接口实现
  @override
  SelectionController get selectionController => _selectionController;

  // 搜索控制器
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // 缓存的设置值
  bool? _cachedShowHidden;
  bool? _cachedShowSystem;

  /// 获取排序后的文件列表（固定按名称升序）
  List<FileItem> _getSortedFiles(List<FileItem> files) {
    return FileComparatorUtil.sortFiles(
      files,
      SortType.name,
      ascending: true, // 固定升序
    );
  }

  List<FileItem> get _filteredFiles {
    if (_searchQuery.isEmpty) return _getSortedFiles(_files);

    // 仅在当前文件夹搜索
    final filtered = _files
        .where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
    return _getSortedFiles(filtered);
  }

  // CreateFolderMixin 接口实现
  @override
  String getCurrentPath() => _currentPath;

  @override
  Future<void> onFolderCreated() async {
    await _loadFilesInPath(_currentPath);
    _showMessage('文件夹创建成功');
    exitEditMode();
  }

  /// 显示提示消息
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool _isLoading = true;
  List<FileItem> _files = [];
  String _currentPath = '';
  String _rootPath = ''; // 存储根路径

  /// ViewModel变化回调 - 同步文件列表
  void _onViewModelChanged() {
    if (!mounted) return;

    // 处理文件删除
    final deletedPath = widget.viewModel.lastDeletedFilePath;
    if (deletedPath != null) {
      setState(() {
        final initialLength = _files.length;
        _files.removeWhere((f) => f.path == deletedPath);
        final removed = initialLength - _files.length;
        if (removed > 0) {
          logger.d(
              'Extracted files page: Removed $removed file(s). Remaining: ${_files.length}');
        }
      });
      return;
    }

    // 处理文件更新（重命名/移动）
    final oldPath = widget.viewModel.lastUpdatedOldPath;
    final newFile = widget.viewModel.lastUpdatedNewFile;

    if (oldPath != null && newFile != null) {
      setState(() {
        // 检查文件是否在当前列表中
        final index = _files.indexWhere((f) => f.path == oldPath);
        if (index != -1) {
          // 判断文件是移动到其他目录还是在当前目录重命名
          final newFileDir = path.dirname(newFile.path);

          if (newFileDir == _currentPath) {
            // 在当前目录内重命名/移动 → 更新路径
            _files[index] = newFile;
            logger
                .d('Updated file in extracted files page: $oldPath -> ${newFile.path}');
          } else {
            // 移动到其他目录 → 从列表中移除
            _files.removeAt(index);
            logger.d(
                'File moved to different directory, removed from list: $oldPath');
          }
        }
      });
      return;
    }

    // 处理文件添加（复制/恢复操作）
    final addedFile = widget.viewModel.lastAddedFile;
    if (addedFile != null) {
      // 只添加到当前目录的文件
      final addedFileDir = path.dirname(addedFile.path);
      if (addedFileDir == _currentPath) {
        setState(() {
          // 检查是否已存在
          if (!_files.any((f) => f.path == addedFile.path)) {
            _files.add(addedFile);
            // 重新排序（固定按名称升序）
            FileComparatorUtil.sortFilesInPlace(_files, SortType.name,
                ascending: true);
            logger.d(
                'Extracted files page: Added file ${addedFile.path}. Total: ${_files.length}');
          }
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();

    _selectionController = SelectionController();
    _selectionController.selectedNotifier.addListener(() {
      setState(() {});
    });

    // 监听ViewModel变化，当文件列表更新时同步本地状态
    widget.viewModel.addListener(_onViewModelChanged);

    // 初始化根路径和当前路径
    _rootPath = widget.extractedPath;
    _currentPath = widget.extractedPath;

    // 加载文件列表
    _loadFilesInPath(_currentPath);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _selectionController.selectedNotifier.removeListener(() {});
    _selectionController.dispose();
    widget.viewModel.removeListener(_onViewModelChanged);
    super.dispose();
  }

  /// 加载指定路径下的文件
  Future<void> _loadFilesInPath(String path) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final directory = Directory(path);
      if (directory.existsSync()) {
        // 获取显示设置
        final showHidden =
            await FileDisplaySettingsService().getShowHiddenFiles();
        final showSystem =
            await FileDisplaySettingsService().getShowSystemFiles();

        // 检测设置变化
        final settingsChanged =
            _cachedShowHidden != showHidden || _cachedShowSystem != showSystem;

        if (settingsChanged) {
          logger.d(
              'File display settings changed: showHidden=$showHidden, showSystem=$showSystem');
          _cachedShowHidden = showHidden;
          _cachedShowSystem = showSystem;
        }

        // 获取文件列表
        final entities = directory.listSync();
        final fileItems = <FileItem>[];

        for (final entity in entities) {
          try {
            final name = entity.path.split('/').last;

            // 过滤隐藏文件
            if (!showHidden && name.startsWith('.')) continue;

            // 过滤系统文件
            if (!showSystem && _isSystemFile(name)) continue;

            fileItems.add(FileItem.fromEntity(entity));
          } catch (e) {
            logger.w('Error processing file ${entity.path}: $e');
          }
        }

        setState(() {
          _files = fileItems;
          _currentPath = path;
          _isLoading = false;
        });
      }
    } catch (e) {
      logger.e('Error loading files from $path: $e');
      setState(() {
        _isLoading = false;
      });
      _showMessage('加载文件失败: $e');
    }
  }

  /// 判断是否是系统文件
  bool _isSystemFile(String name) {
    const systemFiles = [
      'Android',
      'DCIM',
      'LOST.DIR',
      'system',
      'lost+found',
    ];
    return systemFiles.contains(name);
  }

  /// 检查是否可以返回上级目录
  bool _canNavigateUp(String currentPath) {
    return currentPath != _rootPath && currentPath.isNotEmpty;
  }

  /// 返回上级目录
  void _navigateUp() {
    if (_canNavigateUp(_currentPath)) {
      final parentPath = Directory(_currentPath).parent.path;
      // 确保不会超出根目录
      if (parentPath.startsWith(_rootPath)) {
        _loadFilesInPath(parentPath);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !isEditMode && !_isSearchMode && !_canNavigateUp(_currentPath),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // 优先级1: 退出编辑模式
        if (isEditMode) {
          exitEditMode();
          return;
        }

        // 优先级2: 退出搜索模式
        if (_isSearchMode) {
          setState(() {
            _searchQuery = '';
            _searchController.clear();
            _isSearchMode = false;
          });
          return;
        }

        // 优先级3: 返回上级目录
        if (_canNavigateUp(_currentPath)) {
          _navigateUp();
          return;
        }

        // 最终: 返回上一个页面
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.archiveName} - 解压文件',
                style: const TextStyle(fontSize: 18),
              ),
              if (!_isLoading)
                Text(
                  '${_filteredFiles.length} 个文件',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 使用 FileToolbar（隐藏排序和分组按钮）
                  FileToolbar(
                    pageId: PageId.storage,
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
                    showSortButton: false, // 隐藏排序
                    showGroupButton: false, // 隐藏分组
                    showViewModeToggle: false, // 隐藏网格切换
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
          ],
        ),
        body: Column(
          children: [
            // 搜索框
            if (_isSearchMode)
              FileSearchBar(
                controller: _searchController,
                focusNode: _searchFocusNode,
                hintText: '搜索文件...',
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
                    _searchQuery = query;
                  });
                },
              ),
            // 编辑模式提示条
            if (isEditMode)
              const EditModeHintBar(),
            // 文件列表
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: _buildBody(theme),
                  ),
                  // 底部导航栏（如果不在根目录）
                  if (_currentPath != _rootPath)
                    FolderNavigationBar(
                      currentPath: _currentPath,
                      onBackPressed: _navigateUp,
                    ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar:
            isEditMode ? _buildSelectionBottomBar(theme) : null,
      ),
    );
  }

  /// 构建批量选择操作工具栏
  Widget _buildSelectionBottomBar(ThemeData theme) {
    final batchService = BatchOperationsService(
      presenter: widget.presenter,
      viewModel: widget.viewModel,
      onRefresh: () async {
        await _loadFilesInPath(_currentPath);
      },
      onExitSelectionMode: exitEditMode,
    );

    return SelectionBottomBar(
      selectedPaths: _selectionController.selected,
      isAllFavorite: batchService.isAllSelectedFavorite(_selectionController.selected),
      onCopy: () {
        if (!mounted) return;
        batchService.batchCopy(
          context,
          _selectionController.selected,
          _currentPath,
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
          _currentPath,
          shouldRefresh: true,
        );
      },
      onToggleFavorite: () async {
        if (!mounted) return;
        await batchService.batchToggleFavorite(context, _selectionController.selected);
        // 刷新列表以显示收藏状态
        if (mounted) {
          await _loadFilesInPath(_currentPath);
        }
      },
      onDelete: () {
        if (!mounted) return;
        batchService.batchDelete(context, _selectionController.selected);
      },
    );
  }

  /// 构建主体内容
  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '加载中...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_filteredFiles.isEmpty) {
      return _buildEmptyState(theme);
    }

    // 获取当前视图模式
    final gridMode = PageSettingsService().getViewMode(PageId.storage) ==
        ViewMode.grid;

    return FileCollectionView(
      items: _filteredFiles,
      gridMode: gridMode,
      config: UnifiedViewConfig.fromContext(context),
      selectionController: _selectionController,
      showCheckbox: isEditMode,
      showFavoriteButton: true,
      isFavorite: (path) => widget.viewModel.isFavoriteFile(path),
      onFavoriteToggle: (file) async {
        return await widget.presenter.toggleFavoriteFile(file);
      },
      onTap: (file) {
        if (isEditMode) {
          _selectionController.toggle(file.path);
        } else {
          _openFile(file);
        }
      },
      onLongPress: (file) {
        if (isEditMode) return;
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
            Icons.folder_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? '此文件夹为空' : '未找到匹配的文件',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 打开文件或文件夹
  void _openFile(FileItem file) {
    if (file.isDirectory) {
      // 进入子文件夹
      _loadFilesInPath(file.path);
    } else {
      // 添加到最近访问记录
      widget.presenter.addToRecentFiles(file);
      
      // 对于图片/视频/音频文件，支持左右滑动浏览相邻文件
      if (FileUtils.isImageFile(file.name) ||
          FileUtils.isVideoFile(file.name) ||
          FileUtils.isAudioFile(file.name)) {
        // 根据当前文件类型只筛选同类型文件
        final mediaFiles = _files.where((f) {
          if (f.isDirectory) return false;
          if (FileUtils.isImageFile(file.name)) {
            return FileUtils.isImageFile(f.name);
          } else if (FileUtils.isVideoFile(file.name)) {
            return FileUtils.isVideoFile(f.name);
          } else if (FileUtils.isAudioFile(file.name)) {
            return FileUtils.isAudioFile(f.name);
          }
          return false;
        }).toList();

        final initialIndex = mediaFiles.indexWhere((f) => f.path == file.path);

        Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) => FilePreviewPage(
              file: file,
              fileList: mediaFiles,
              initialIndex: initialIndex >= 0 ? initialIndex : 0,
              viewModel: widget.viewModel,
              presenter: widget.presenter,
            ),
          ),
        );
      } else {
        // 其他文件类型使用单文件模式
        Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) => FilePreviewPage(
              file: file,
              viewModel: widget.viewModel,
              presenter: widget.presenter,
            ),
          ),
        );
      }
    }
  }

  /// 显示单文件操作菜单
  void _showOperationsMenu(FileItem file) {
    final service = SingleFileOperationsService(
      context: context,
      viewModel: widget.viewModel,
      presenter: widget.presenter,
      onRefresh: () async {
        await _loadFilesInPath(_currentPath);
      },
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SingleFileOperationsSheet(
        file: file,
        service: service,
      ),
    );
  }
}
