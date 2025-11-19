import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/file_toolbar.dart';
import 'package:easyfile/ui/widgets/file_search_bar.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/ui/widgets/selection_bottom_bar.dart';
import 'package:easyfile/ui/services/batch_operations_service.dart';
import 'package:easyfile/utils/android_test_file_creator.dart';

class StoragePage extends StatefulWidget {
  final FilePresenter presenter;
  final FileViewModel viewModel;

  const StoragePage({
    super.key,
    required this.presenter,
    required this.viewModel,
  });

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  String _searchQuery = '';
  bool _isSearchMode = false;
  bool _searchInSubfolders = false; // 是否在子文件夹中搜索

  // 批量操作相关状态（SelectionController 内部管理 isSelectionMode 状态）
  Set<String> _selectedItems = {}; // 存储选中的文件/文件夹路径
  late final SelectionController _selectionController;

  // 搜索控制器
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// 获取排序后的文件列表
  List<FileItem> _getSortedFiles(List<FileItem> files) {
    final result = List<FileItem>.from(files);
    final sortType = PageSettingsService().getSortType(PageId.storage);
    final comparator = _getComparatorForSortType(sortType);
    result.sort(comparator);
    return result;
  }

  /// 根据排序类型获取比较器
  Comparator<FileItem> _getComparatorForSortType(SortType sortType) {
    switch (sortType) {
      case SortType.name:
        return (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case SortType.modifiedTime:
        return (a, b) => b.modified.compareTo(a.modified);
      case SortType.size:
        return (a, b) => b.size.compareTo(a.size);
      case SortType.fileType:
        return (a, b) {
          // 获取文件扩展名
          String getExt(String name) {
            final lastDot = name.lastIndexOf('.');
            if (lastDot == -1 || lastDot == name.length - 1) return '';
            return name.substring(lastDot + 1).toLowerCase();
          }

          final extA = getExt(a.name);
          final extB = getExt(b.name);

          // 没有扩展名的排在后面
          if (extA.isEmpty && extB.isNotEmpty) return 1;
          if (extA.isNotEmpty && extB.isEmpty) return -1;

          // 按扩展名排序
          final extCompare = extA.compareTo(extB);
          if (extCompare != 0) return extCompare;

          // 扩展名相同时按名称排序
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        };
    }
  }

  /// 获取日期分组后的文件
  Map<String, List<FileItem>> _groupFilesByDate(List<FileItem> files) {
    final Map<String, List<FileItem>> groups = {
      '今天': [],
      '昨天': [],
      '本周': [],
      '本月': [],
      '更早': [],
    };

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeekStart = today.subtract(Duration(days: now.weekday - 1));
    final thisMonthStart = DateTime(now.year, now.month, 1);

    for (final file in files) {
      final fileDate = DateTime(
        file.modified.year,
        file.modified.month,
        file.modified.day,
      );

      if (fileDate.isAtSameMomentAs(today)) {
        groups['今天']!.add(file);
      } else if (fileDate.isAtSameMomentAs(yesterday)) {
        groups['昨天']!.add(file);
      } else if (fileDate.isAfter(thisWeekStart) ||
          fileDate.isAtSameMomentAs(thisWeekStart)) {
        groups['本周']!.add(file);
      } else if (fileDate.isAfter(thisMonthStart) ||
          fileDate.isAtSameMomentAs(thisMonthStart)) {
        groups['本月']!.add(file);
      } else {
        groups['更早']!.add(file);
      }
    }

    // 移除空分组
    groups.removeWhere((key, value) => value.isEmpty);
    return groups;
  }

  /// 显示排序选项菜单
  void _showSortOptions() {
    final currentSortType = PageSettingsService().getSortType(PageId.storage);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('按名称排序'),
                trailing: currentSortType == SortType.name
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  PageSettingsService()
                      .setSortType(PageId.storage, SortType.name);
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('按修改时间排序'),
                trailing: currentSortType == SortType.modifiedTime
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  PageSettingsService()
                      .setSortType(PageId.storage, SortType.modifiedTime);
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('按文件大小排序'),
                trailing: currentSortType == SortType.size
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  PageSettingsService()
                      .setSortType(PageId.storage, SortType.size);
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.category),
                title: const Text('按文件类型排序'),
                trailing: currentSortType == SortType.fileType
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  PageSettingsService()
                      .setSortType(PageId.storage, SortType.fileType);
                  setState(() {}); // 刷新列表
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<FileItem> get _filteredFiles {
    if (_searchQuery.isEmpty) return _getSortedFiles(_files);

    // 如果启用子文件夹搜索
    if (_searchInSubfolders) {
      return _searchFilesRecursively(_currentPath, _searchQuery);
    }

    // 仅在当前文件夹搜索
    final filtered = _files
        .where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
    return _getSortedFiles(filtered);
  }

  bool _isLoading = true;
  List<FileItem> _files = [];
  String _currentPath = '';
  String _rootPath = ''; // 存储根路径

  // 判断是否可以返回上级目录
  bool _canNavigateUp(String currentPath) {
    if (Platform.isWindows) {
      // Windows根目录如C:\
      final root = Platform.environment['USERPROFILE'] ?? 'C:\\';
      return currentPath != root;
    } else if (Platform.isAndroid) {
      return currentPath != '/storage/emulated/0';
    } else {
      return currentPath != Directory.current.path;
    }
  }

  // 返回上级目录
  void _navigateUp() {
    final parent = Directory(_currentPath).parent.path;
    _loadFilesInPath(parent);
    setState(() {
      _currentPath = parent;
    });
  }

  // 递归搜索文件
  List<FileItem> _searchFilesRecursively(String path, String query) {
    final List<FileItem> results = [];
    final searchLower = query.toLowerCase();

    try {
      final directory = Directory(path);
      if (!directory.existsSync()) return results;

      final entities = directory.listSync();

      for (var entity in entities) {
        try {
          // 跳过隐藏文件
          final name = entity.path.split(Platform.pathSeparator).last;
          if (name.startsWith('.')) continue;

          if (entity is Directory) {
            // 递归搜索子文件夹
            results.addAll(_searchFilesRecursively(entity.path, query));
          } else if (entity is File) {
            // 检查文件名是否匹配
            if (name.toLowerCase().contains(searchLower)) {
              results.add(FileItem.fromEntity(entity));
            }
          }
        } catch (e) {
          // 忽略无权访问的文件/文件夹
          continue;
        }
      }
    } catch (e) {
      logger.e('Recursive search error: $e');
    }

    return results;
  }

  // 获取当前文件夹名称
  String _getCurrentFolderName() {
    if (_currentPath.isEmpty) return '存储空间';
    if (_currentPath == _rootPath) {
      if (Platform.isAndroid) return '内部存储';
      if (Platform.isWindows) return '用户目录';
      return '根目录';
    }
    return _currentPath.split(Platform.pathSeparator).last;
  }

  // 获取简化的路径面包屑（用于副标题显示）
  String _getSimplifiedBreadcrumb() {
    if (_currentPath.isEmpty || _currentPath == _rootPath) {
      return '根目录';
    }

    final parts = _currentPath
        .split(Platform.pathSeparator)
        .where((p) => p.isNotEmpty)
        .toList();
    final rootParts = _rootPath
        .split(Platform.pathSeparator)
        .where((p) => p.isNotEmpty)
        .toList();

    // 移除根路径部分
    final relativeParts = parts.sublist(rootParts.length);

    if (relativeParts.isEmpty) return '根目录';
    if (relativeParts.length == 1) return '根目录 > ${relativeParts[0]}';

    // 多层时只显示"..."，节省空间给统计信息
    return '...';
  }

  // 获取统计信息文本
  String _getStatisticsText() {
    // 使用原始文件列表而非过滤后的列表
    final folderCount = _files.where((f) => f.isDirectory).length;
    final fileCount = _files.where((f) => !f.isDirectory).length;
    final totalCount = _files.length;

    if (totalCount == 0) return '空文件夹';

    // 如果在搜索模式，显示搜索结果数量
    if (_isSearchMode && _searchQuery.isNotEmpty) {
      final filteredCount = _filteredFiles.length;
      return '找到$filteredCount个 / 共$totalCount个项目';
    }

    return '$totalCount个项目 ($folderCount个文件夹, $fileCount个文件)';
  }

  // 构建面包屑导航菜单
  void _showBreadcrumbMenu(BuildContext context) {
    if (_currentPath == _rootPath) return;

    final separator = Platform.pathSeparator;
    final parts =
        _currentPath.split(separator).where((p) => p.isNotEmpty).toList();
    final rootParts =
        _rootPath.split(separator).where((p) => p.isNotEmpty).toList();

    // 如果在根目录，不显示菜单
    if (parts.length <= rootParts.length) return;

    final relativeParts = parts.sublist(rootParts.length);
    if (relativeParts.isEmpty) return;

    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(16, 80, 16, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      // 使用MenuStyle减小垂直间距
      menuPadding: EdgeInsets.zero,
      items: [
        PopupMenuItem(
          value: _rootPath,
          height: 36, // 进一步减小高度
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          child: const SizedBox(
            height: 36,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('根目录', style: TextStyle(fontSize: 14)),
            ),
          ),
        ),
        ...List.generate(relativeParts.length, (index) {
          // 重建路径
          String path;
          if (Platform.isWindows) {
            // Windows: 保留盘符
            final driveLetter = parts[0];
            final pathComponents = [
              ...parts.sublist(1, rootParts.length),
              ...relativeParts.sublist(0, index + 1),
            ];
            path = '$driveLetter$separator${pathComponents.join(separator)}';
          } else {
            // Unix-like: 前缀斜杠
            final pathComponents = [
              ...rootParts,
              ...relativeParts.sublist(0, index + 1),
            ];
            path = separator + pathComponents.join(separator);
          }

          return PopupMenuItem(
            value: path,
            height: 36, // 减小高度
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            child: SizedBox(
              height: 36,
              child: Padding(
                padding: EdgeInsets.only(left: (index + 1) * 12.0),
                child: Row(
                  children: [
                    const Icon(Icons.folder, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        relativeParts[index],
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    ).then((selectedPath) {
      if (selectedPath != null && selectedPath != _currentPath) {
        if (!mounted) return;
        _loadFilesInPath(selectedPath);
        setState(() {
          _currentPath = selectedPath;
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _selectionController = SelectionController();
    // 监听SelectionController变化并同步到_selectedItems
    _selectionController.selectedNotifier.addListener(_onSelectionChanged);
    _loadStorageFiles();
  }

  void _onSelectionChanged() {
    setState(() {
      _selectedItems = _selectionController.selected;
      // SelectionController 自动管理 isSelectionMode 状态
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _selectionController.dispose();
    super.dispose();
  }

  Future<void> _loadStorageFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 获取根存储路径
      String rootPath;
      if (Platform.isAndroid) {
        rootPath = '/storage/emulated/0';
      } else if (Platform.isWindows) {
        rootPath = Platform.environment['USERPROFILE'] ?? 'C:\\';
      } else {
        rootPath = Directory.current.path;
      }

      _currentPath = rootPath;
      _rootPath = rootPath; // 保存根路径

      final directory = Directory(rootPath);
      if (directory.existsSync()) {
        final entities = directory
            .listSync()
            .where(
              (entity) => !entity.path
                  .split(Platform.pathSeparator)
                  .last
                  .startsWith('.'),
            )
            .toList();

        final files = entities.map((e) => FileItem.fromEntity(e)).toList();

        // 使用页面级排序设置
        final sortType = PageSettingsService().getSortType(PageId.storage);
        final comparator = _getComparatorForSortType(sortType);
        files.sort(comparator);

        setState(() {
          _files = files;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      logger.e('Failed to load storage files: $e');
      setState(() {
        _isLoading = false;
      });
      final messenger = ScaffoldMessenger.of(context);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('加载失败: $e')));
    }
  }

  void _onFileTap(FileItem file) {
    // 多选模式下，点击切换选中状态
    if (_selectionController.isSelectionMode) {
      if (_selectedItems.contains(file.path)) {
        _selectionController.deselect(file.path);
      } else {
        _selectionController.select(file.path);
      }
      return;
    }

    if (file.isDirectory) {
      // 在当前页面刷新并显示该文件夹内容
      _currentPath = file.path;
      _loadFilesInPath(file.path);
    } else {
      // 跳转到文件预览页
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => FilePreviewPage(file: file)),
      );
    }
  }

  // 新增：加载指定路径下的文件
  Future<void> _loadFilesInPath(String path) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final directory = Directory(path);
      if (directory.existsSync()) {
        final entities = directory
            .listSync()
            .where(
              (entity) => !entity.path
                  .split(Platform.pathSeparator)
                  .last
                  .startsWith('.'),
            )
            .toList();
        final files = entities.map((e) => FileItem.fromEntity(e)).toList();
        // 使用页面级排序设置
        final sortType = PageSettingsService().getSortType(PageId.storage);
        final comparator = _getComparatorForSortType(sortType);
        files.sort(comparator);
        setState(() {
          _files = files;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      logger.e('Failed to load files in path: $e');
      setState(() {
        _isLoading = false;
      });
      final messenger = ScaffoldMessenger.of(context);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('加载失败: $e')));
    }
  }

  /// 构建文件列表/网格视图（使用FileCollectionView）
  Widget _buildFileView() {
    final isGridView =
        PageSettingsService().getViewMode(PageId.storage) == ViewMode.grid;
    final isGroupEnabled =
        PageSettingsService().getGroupEnabled(PageId.storage);

    // 根据是否启用分组来决定显示方式
    if (isGroupEnabled) {
      final groupMap = _groupFilesByDate(_filteredFiles);
      final groups = groupMap.entries.map((entry) {
        final count = entry.value.length;
        return FileGroup(
          key: entry.key,
          title: '${entry.key}（$count个文件）',
          items: entry.value,
        );
      }).toList();

      return FileCollectionView(
        groups: groups,
        gridMode: isGridView,
        padding: isGridView
            ? const EdgeInsets.all(8)
            : const EdgeInsets.symmetric(vertical: 0),
        selectionController: _selectionController,
        showFullPath: _isSearchMode && _searchInSubfolders,
        showFavoriteButton: true,
        isFavorite: (path) => widget.viewModel.isFavoriteFile(path),
        onFavoriteToggle: (file) async {
          return await widget.presenter.toggleFavoriteFile(file);
        },
        useUnifiedGridItem: true,
        onTap: (file) => _onFileTap(file),
        // onLongPress 移除，由 FileCollectionView 内部处理
      );
    }

    return FileCollectionView(
      items: _filteredFiles,
      gridMode: isGridView,
      padding: isGridView
          ? const EdgeInsets.all(8)
          : const EdgeInsets.symmetric(vertical: 0),
      selectionController: _selectionController,
      // 列表模式显示选项
      showFullPath: _isSearchMode && _searchInSubfolders,
      showFavoriteButton: true,
      isFavorite: (path) => widget.viewModel.isFavoriteFile(path),
      onFavoriteToggle: (file) async {
        return await widget.presenter.toggleFavoriteFile(file);
      },
      useUnifiedGridItem: true,
      onTap: (file) => _onFileTap(file),
      // onLongPress 移除，由 FileCollectionView 内部处理
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _selectionController.isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _selectionController.clear();
                  });
                },
                tooltip: '取消',
              )
            : IconButton(
                icon: const Icon(Icons.home),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: '返回主页',
                padding: const EdgeInsets.all(4),
                visualDensity: VisualDensity.compact,
                iconSize: 22,
              ),
        leadingWidth: 48,
        titleSpacing: 4,
        title: _selectionController.isSelectionMode
            ? Text('已选中 ${_selectedItems.length} 项')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 主标题：当前文件夹名称
                  Text(
                    _getCurrentFolderName(),
                    style: const TextStyle(fontSize: 18),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // 副标题：路径 + 统计信息
                  if (!_isLoading)
                    InkWell(
                      onTap: () => _showBreadcrumbMenu(context),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${_getSimplifiedBreadcrumb()} · ${_getStatisticsText()}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
        actions: _selectionController.isSelectionMode
            ? [
                // 全选按钮
                IconButton(
                  icon: Icon(
                    _selectedItems.length == _filteredFiles.length
                        ? Icons.deselect
                        : Icons.select_all,
                  ),
                  onPressed: () {
                    if (_selectedItems.length == _filteredFiles.length) {
                      _selectionController.clear();
                    } else {
                      _selectionController.selectAll(
                        _filteredFiles.map((f) => f.path).toList(),
                      );
                    }
                  },
                  tooltip: _selectedItems.length == _filteredFiles.length
                      ? '取消全选'
                      : '全选',
                ),
              ]
            : [
                // 测试按钮（仅Android）
                if (Platform.isAndroid)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.science, size: 20),
                    tooltip: '测试工具',
                    onSelected: (value) async {
                      if (value == 'create') {
                        await _createTestFiles();
                      } else if (value == 'cleanup') {
                        await _cleanupTestFiles();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'create',
                        child: Row(
                          children: [
                            Icon(Icons.create_new_folder, size: 18),
                            SizedBox(width: 8),
                            Text('创建测试文件'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'cleanup',
                        child: Row(
                          children: [
                            Icon(Icons.delete_sweep, size: 18),
                            SizedBox(width: 8),
                            Text('清理测试文件'),
                          ],
                        ),
                      ),
                    ],
                  ),
                // 使用Row来控制按钮间距
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 使用统一的FileToolbar组件
                      FileToolbar(
                        pageId: PageId.storage,
                        showBackButton: _canNavigateUp(_currentPath),
                        onBackPressed: _navigateUp,
                        showSearchButton: true,
                        onSearchPressed: () {
                          setState(() {
                            _isSearchMode = !_isSearchMode;
                            if (!_isSearchMode) _searchQuery = '';
                          });
                        },
                        isSearchMode: _isSearchMode,
                        showSortButton: true,
                        onSortPressed: _showSortOptions,
                        showGroupButton: true,
                        onGroupToggle: () => setState(() {}),
                        iconSize: 22,
                      ),
                    ],
                  ),
                ),
              ],
      ),
      body: Consumer<PageSettingsService>(
        builder: (context, pageSettingsService, _) {
          return _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // 搜索栏（使用统一的FileSearchBar组件）
                    if (_isSearchMode)
                      FileSearchBar(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        hintText: '搜索文件...',
                        onSearch: (query) async {
                          if (query.isNotEmpty) {
                            setState(() {
                              _searchQuery = query;
                            });
                          }
                        },
                        onClose: () {
                          setState(() {
                            _searchQuery = '';
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

                    // 搜索范围选择器
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: _isSearchMode && _searchQuery.isNotEmpty ? 48 : 0,
                      child: _isSearchMode && _searchQuery.isNotEmpty
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              child: Row(
                                children: [
                                  Text(
                                    '搜索范围:',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(
                                        context,
                                      )
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text(
                                      '当前文件夹',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    selected: !_searchInSubfolders,
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _searchInSubfolders = false;
                                        });
                                      }
                                    },
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text(
                                      '包含子文件夹',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    selected: _searchInSubfolders,
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _searchInSubfolders = true;
                                        });
                                      }
                                    },
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const Spacer(),
                                  // 显示搜索结果数量
                                  if (_searchQuery.isNotEmpty)
                                    Text(
                                      '找到 ${_filteredFiles.length} 个结果',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : null,
                    ),

                    // 文件列表区域（占据剩余空间）
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadStorageFiles,
                        child: _buildFileView(),
                      ),
                    ),
                  ],
                );
        },
      ),
      // 批量操作底部工具栏
      bottomNavigationBar: _selectionController.isSelectionMode ? _buildSelectionBottomBar() : null,
    );
  }

  /// 构建批量选择底部工具栏
  Widget _buildSelectionBottomBar() {
    final batchService = _getBatchOperationsService();
    return SelectionBottomBar(
      selectedPaths: _selectedItems,
      isAllFavorite: batchService.isAllSelectedFavorite(_selectedItems),
      onCopy: () => batchService.batchCopy(_selectedItems, _currentPath),
      onRename: () => batchService.batchRename(_selectedItems),
      onShare: () => batchService.batchShare(_selectedItems),
      onMove: () => batchService.batchMove(_selectedItems, _currentPath),
      onToggleFavorite: () => batchService.batchToggleFavorite(_selectedItems),
      onDelete: () => batchService.batchDelete(_selectedItems),
    );
  }

  /// 获取批量操作服务实例
  BatchOperationsService _getBatchOperationsService() {
    return BatchOperationsService(
      context: context,
      viewModel: widget.viewModel,
      presenter: widget.presenter,
      onRefresh: () async {
        await _loadFilesInPath(_currentPath);
      },
      onExitSelectionMode: () {
        setState(() {
          _selectionController.clear();
        });
      },
    );
  }

  /// 创建测试文件
  Future<void> _createTestFiles() async {
    // 显示加载对话框
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在创建测试文件...'),
          ],
        ),
      ),
    );

    try {
      await AndroidTestFileCreator.createTestStructure();

      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭加载对话框

      // 刷新文件列表
      await _loadStorageFiles();

      // 显示成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 测试文件创建成功！'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭加载对话框

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ 创建失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 清理测试文件
  Future<void> _cleanupTestFiles() async {
    // 显示确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除所有测试文件吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在清理测试文件...'),
          ],
        ),
      ),
    );

    try {
      await AndroidTestFileCreator.cleanupTestFiles();

      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭加载对话框

      // 刷新文件列表
      await _loadStorageFiles();

      // 显示成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 测试文件已清理！'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭加载对话框

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ 清理失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
