import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
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
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/ui/widgets/unified_view_config.dart';
import 'package:easyfile/ui/widgets/selection_bottom_bar.dart';
import 'package:easyfile/ui/widgets/folder_navigation_bar.dart';
import 'package:easyfile/ui/services/batch_operations_service.dart';
import 'package:easyfile/utils/file_grouping_util.dart';
import 'package:easyfile/utils/file_comparator_util.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/core/services/file_display_settings_service.dart';

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

  // 编辑模式状态
  bool _isEditMode = false;

  // 批量操作相关状态（SelectionController 内部管理 isSelectionMode 状态）
  Set<String> _selectedItems = {}; // 存储选中的文件/文件夹路径
  late final SelectionController _selectionController;

  // 搜索控制器
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // 缓存的设置值，用于检测变化
  bool? _cachedShowHidden;
  bool? _cachedShowSystem;

  /// 获取排序后的文件列表
  List<FileItem> _getSortedFiles(List<FileItem> files) {
    final sortType = PageSettingsService().getSortType(PageId.storage);
    return FileComparatorUtil.sortFiles(files, sortType);
  }

  /// 获取日期分组后的文件
  Map<String, List<FileItem>> _groupFilesByDate(List<FileItem> files) {
    return FileGroupingUtil.groupByModifiedDate(files);
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

  /// 进入编辑模式
  void _enterEditMode() {
    setState(() {
      _isEditMode = true;
    });
  }

  /// 退出编辑模式
  void _exitEditMode() {
    setState(() {
      _isEditMode = false;
      // 退出编辑模式时，清除所有选中项
      _selectionController.clear();
    });
  }

  /// 显示新建文件夹对话框
  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '文件夹名称',
            hintText: '请输入文件夹名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              Navigator.pop(context, value);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _createFolder(result);
    }
  }

  /// 创建文件夹
  Future<void> _createFolder(String name) async {
    try {
      // 验证文件夹名称
      if (name.contains('/') || name.contains('\\')) {
        _showMessage('文件夹名称不能包含 / 或 \\');
        return;
      }

      final newPath = path.join(_currentPath, name);
      final dir = Directory(newPath);

      if (await dir.exists()) {
        _showMessage('文件夹已存在');
        return;
      }

      await dir.create(recursive: true);
      _showMessage('创建成功');
      
      // 刷新文件列表
      _loadFilesInPath(_currentPath);
    } catch (e) {
      logger.e('Failed to create folder: $e');
      _showMessage('创建失败: $e');
    }
  }

  /// 显示提示消息
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 获取全选复选框的状态（三态）
  bool? _getSelectAllCheckboxValue() {
    final totalCount = _filteredFiles.length;
    final selectedCount = _selectedItems.length;
    
    if (selectedCount == 0) {
      return false;  // 未选中任何项 → 空心框
    } else if (selectedCount == totalCount && totalCount > 0) {
      return true;   // 全部选中 → 勾选框
    } else {
      return null;   // 部分选中 → 横线框（indeterminate）
    }
  }

  /// 处理全选/取消全选
  void _handleSelectAll() {
    if (_selectedItems.length == _filteredFiles.length) {
      // 取消全选：清空选择，但保持在编辑模式和选择模式
      // 直接调用 clear() 会退出选择模式，所以我们手动清空选择集
      setState(() {
        _selectionController.selectedNotifier.value = {};
        // 确保选择模式保持激活状态（编辑模式下必须保持选择模式）
        if (!_selectionController.isSelectionMode) {
          _selectionController.selectionModeNotifier.value = true;
        }
      });
    } else {
      _selectionController.selectAll(
        _filteredFiles.map((f) => f.path).toList(),
      );
    }
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

      List<FileSystemEntity> entities;
      try {
        entities = directory.listSync();
      } catch (e) {
        // 捕获权限拒绝错误，跳过该目录
        if (e.toString().contains('Permission denied') ||
            e.toString().contains('errno = 13')) {
          logger.w('Permission denied for directory: $path');
          return results;
        }
        rethrow;
      }

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
    // 监听ViewModel变化，当文件列表更新时同步本地状态
    widget.viewModel.addListener(_onViewModelChanged);
    _loadStorageFiles();
  }

  /// ViewModel变化回调 - 同步文件列表
  void _onViewModelChanged() {
    if (mounted) {
      final oldPath = widget.viewModel.lastUpdatedOldPath;
      final newFile = widget.viewModel.lastUpdatedNewFile;

      if (oldPath != null && newFile != null) {
        setState(() {
          // 在本地列表中找到旧路径的文件并替换
          final index = _files.indexWhere((f) => f.path == oldPath);
          if (index != -1) {
            _files[index] = newFile;
            logger
                .d('Updated file in storage page: $oldPath -> ${newFile.path}');
          }
        });
      }
    }
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
    widget.viewModel.removeListener(_onViewModelChanged);
    super.dispose();
  }

  /// 检查设置是否变化，如果变化则刷新列表
  ///
  /// 此方法在每次 build 时调用，用于检测文件显示设置的变化。
  /// 如果用户在设置页面修改了"显示隐藏文件"或"显示系统文件"选项，
  /// 返回存储页面时会自动刷新文件列表。
  void _checkAndRefreshIfSettingsChanged() {
    final displaySettings = FileDisplaySettingsService();

    // 异步检查设置
    displaySettings.getShowHiddenFiles().then((showHidden) {
      displaySettings.getShowSystemFiles().then((showSystem) {
        // 检查设置是否变化
        if (_cachedShowHidden != null && _cachedShowSystem != null) {
          if (_cachedShowHidden != showHidden ||
              _cachedShowSystem != showSystem) {
            // 设置已变化，更新缓存并刷新
            _cachedShowHidden = showHidden;
            _cachedShowSystem = showSystem;
            logger.i('Display settings changed, refreshing storage page');

            // 刷新当前视图
            if (_currentPath.isNotEmpty && _currentPath != _rootPath) {
              _loadFilesInPath(_currentPath);
            } else {
              _loadStorageFiles();
            }
          }
        } else {
          // 首次加载，缓存当前设置
          _cachedShowHidden = showHidden;
          _cachedShowSystem = showSystem;
        }
      });
    });
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
        // 获取显示设置
        final displaySettings = FileDisplaySettingsService();
        final showHidden = await displaySettings.getShowHiddenFiles();
        final showSystem = await displaySettings.getShowSystemFiles();

        // 更新缓存
        _cachedShowHidden = showHidden;
        _cachedShowSystem = showSystem;

        List<FileSystemEntity> entities;
        try {
          entities = directory.listSync().where((entity) {
            final fileName = entity.path.split(Platform.pathSeparator).last;

            // 过滤隐藏文件
            if (!showHidden &&
                FileDisplaySettingsService.isHiddenFile(fileName)) {
              return false;
            }

            // 过滤系统文件夹和文件
            if (!showSystem) {
              if (FileSystemEntity.isDirectorySync(entity.path)) {
                if (FileDisplaySettingsService.isSystemFolder(fileName)) {
                  return false;
                }
              } else {
                if (FileDisplaySettingsService.isSystemFile(fileName)) {
                  return false;
                }
              }
            }

            return true;
          }).toList();
        } catch (e) {
          // 捕获权限拒绝错误（如 Android/data 目录）
          if (e.toString().contains('Permission denied') ||
              e.toString().contains('errno = 13')) {
            logger.w('Permission denied for directory: $rootPath');
            // 返回空列表，不显示错误 SnackBar
            entities = [];
          } else {
            // 其他错误继续抛出
            rethrow;
          }
        }

        final files = entities.map((e) => FileItem.fromEntity(e)).toList();

        // 使用页面级排序设置
        final sortType = PageSettingsService().getSortType(PageId.storage);
        FileComparatorUtil.sortFilesInPlace(files, sortType);

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
    // 编辑模式下，点击文件/文件夹自动进入选择模式并选中
    if (_isEditMode && !_selectionController.isSelectionMode) {
      _selectionController.select(file.path);
      return;
    }
    
    // 选择模式下，点击切换选中状态
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

  // 新增：加载指定路径下的文件
  Future<void> _loadFilesInPath(String path) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final directory = Directory(path);
      if (directory.existsSync()) {
        // 获取显示设置
        final displaySettings = FileDisplaySettingsService();
        final showHidden = await displaySettings.getShowHiddenFiles();
        final showSystem = await displaySettings.getShowSystemFiles();

        // 更新缓存
        _cachedShowHidden = showHidden;
        _cachedShowSystem = showSystem;

        List<FileSystemEntity> entities;
        try {
          entities = directory.listSync().where((entity) {
            final fileName = entity.path.split(Platform.pathSeparator).last;

            // 过滤隐藏文件
            if (!showHidden &&
                FileDisplaySettingsService.isHiddenFile(fileName)) {
              return false;
            }

            // 过滤系统文件夹和文件
            if (!showSystem) {
              if (FileSystemEntity.isDirectorySync(entity.path)) {
                if (FileDisplaySettingsService.isSystemFolder(fileName)) {
                  return false;
                }
              } else {
                if (FileDisplaySettingsService.isSystemFile(fileName)) {
                  return false;
                }
              }
            }

            return true;
          }).toList();
        } catch (e) {
          // 捕获权限拒绝错误（如 Android/data 目录）
          if (e.toString().contains('Permission denied') ||
              e.toString().contains('errno = 13')) {
            logger.w('Permission denied for directory: $path');
            // 返回空列表，不显示错误 SnackBar
            entities = [];
          } else {
            // 其他错误继续抛出
            rethrow;
          }
        }
        final files = entities.map((e) => FileItem.fromEntity(e)).toList();
        // 使用页面级排序设置
        final sortType = PageSettingsService().getSortType(PageId.storage);
        FileComparatorUtil.sortFilesInPlace(files, sortType);
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
    // 检查是否是受保护的目录且为空
    final isProtectedDir = _currentPath.contains('/Android/data') ||
        _currentPath.contains('/Android/obb') ||
        _currentPath.contains('/Android/media');

    if (_files.isEmpty && isProtectedDir && !_isSearchMode) {
      // 显示受保护目录的友好提示
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 20),
              Text(
                '无法访问此目录',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[200]!, width: 2),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 48,
                      color: Colors.orange[700],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '此目录受 Android 系统保护，无法访问',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.orange[900],
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Android 11+ 系统限制了对某些系统目录的直接访问',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[800],
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: _navigateUp,
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回上级'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isGridView =
        PageSettingsService().getViewMode(PageId.storage) == ViewMode.grid;
    final isGroupEnabled =
        PageSettingsService().getGroupEnabled(PageId.storage);

    // 获取视图配置：对图片/视频文件应用简洁模式
    UnifiedViewConfig? Function(FileItem)? viewConfigBuilder;
    if (isGridView) {
      viewConfigBuilder = (file) {
        final shouldUseCompactMode = !file.isDirectory &&
            (file.category == FileCategory.image ||
                file.category == FileCategory.video);
        if (shouldUseCompactMode) {
          final showFileInfo = PageSettingsService().getGridShowFileInfo(PageId.storage);
          return UnifiedViewConfig.fromContext(context, compactMode: !showFileInfo);
        }
        return null;
      };
    }

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
        showFullPath: false, // 搜索模式下不显示路径文本
        showFavoriteButton: true,
        isFavorite: (path) => widget.viewModel.isFavoriteFile(path),
        onFavoriteToggle: (file) async {
          return await widget.presenter.toggleFavoriteFile(file);
        },
        useUnifiedGridItem: true,
        viewConfigBuilder: viewConfigBuilder,
        onTap: (file) => _onFileTap(file),
        onLongPress: _selectionController.isSelectionMode
            ? (file) {
                // 仅对文件显示详情面板，文件夹保持默认行为
                if (!file.isDirectory) {
                  _showFileDetailsBottomSheet(file);
                }
              }
            : null,
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
      showFullPath: false, // 搜索模式下不显示路径文本
      showFavoriteButton: true,
      isFavorite: (path) => widget.viewModel.isFavoriteFile(path),
      onFavoriteToggle: (file) async {
        return await widget.presenter.toggleFavoriteFile(file);
      },
      useUnifiedGridItem: true,
      viewConfigBuilder: viewConfigBuilder,
      onTap: (file) => _onFileTap(file),
      onLongPress: _selectionController.isSelectionMode
          ? (file) {
              // 仅对文件显示详情面板，文件夹保持默认行为
              if (!file.isDirectory) {
                _showFileDetailsBottomSheet(file);
              }
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 检查设置是否变化，如果变化则重新加载
    _checkAndRefreshIfSettingsChanged();

    return WillPopScope(
      onWillPop: () async {
        // 优先级1: 退出批量选择模式
        if (_selectionController.isSelectionMode) {
          setState(() {
            _selectionController.clear();
          });
          return false;
        }

        // 优先级2: 退出编辑模式
        if (_isEditMode) {
          _exitEditMode();
          return false;
        }

        // 优先级3: 退出搜索模式
        if (_isSearchMode) {
          setState(() {
            _searchQuery = '';
            _searchController.clear();
            _isSearchMode = false;
          });
          return false;
        }

        // 优先级4: 子文件夹返回上级
        if (_canNavigateUp(_currentPath)) {
          _navigateUp();
          return false;
        }

        // 优先级5: 其他情况允许系统默认行为（返回主页）
        return true;
      },
      child: Scaffold(
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
              : _isEditMode
                  ? Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.edit,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.home),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: '返回主页',
                      padding: const EdgeInsets.all(4),
                      visualDensity: VisualDensity.compact,
                      iconSize: 22,
                    ),
          automaticallyImplyLeading: false,  // 禁用自动 leading
          leadingWidth: 48,
          titleSpacing: 4,
          title: Column(
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
                                  )
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.6),
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
                  // 全选复选框（三态支持）
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: _handleSelectAll,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _getSelectAllCheckboxValue(),
                              tristate: true,
                              onChanged: (_) => _handleSelectAll(),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '全选',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ]
              : [
                  // 使用Row来控制按钮间距
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 使用统一的FileToolbar组件
                        FileToolbar(
                          pageId: PageId.storage,
                          showBackButton: false, // 移除工具栏返回按钮，使用底部导航栏代替
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
                        // 右侧最后按钮：编辑模式显示完成按钮，正常模式显示编辑按钮
                        IconButton(
                          icon: Icon(_isEditMode ? Icons.close : Icons.edit_outlined),
                          onPressed: _isEditMode ? _exitEditMode : _enterEditMode,
                          tooltip: _isEditMode ? '完成' : '编辑',
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
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

                      // 编辑模式工具栏（Material You 风格）
                      if (_isEditMode)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: FilledButton.icon(
                            onPressed: _showCreateFolderDialog,
                            icon: const Icon(Icons.create_new_folder),
                            label: const Text('新建文件夹'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),

                      // 搜索范围选择器
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height:
                            _isSearchMode && _searchQuery.isNotEmpty ? 48 : 0,
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
                        child: Column(
                          children: [
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: _loadStorageFiles,
                                child: _buildFileView(),
                              ),
                            ),

                            // 底部文件夹导航栏（子文件夹中显示）
                            if (!_selectionController.isSelectionMode &&
                                !_isSearchMode &&
                                _canNavigateUp(_currentPath))
                              FolderNavigationBar(
                                currentPath: _currentPath,
                                onBackPressed: _navigateUp,
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
          },
        ),
        // 批量操作底部工具栏
        bottomNavigationBar: _selectionController.isSelectionMode
            ? _buildSelectionBottomBar()
            : null,
      ),
    );
  }

  /// 构建批量选择底部工具栏
  Widget _buildSelectionBottomBar() {
    final batchService = _getBatchOperationsService();
    return SelectionBottomBar(
      selectedPaths: _selectedItems,
      isAllFavorite: batchService.isAllSelectedFavorite(_selectedItems),
      onCopy: () {
        if (!mounted) return;
        batchService.batchCopy(context, _selectedItems, _currentPath);
      },
      onRename: () {
        if (!mounted) return;
        batchService.batchRename(context, _selectedItems);
      },
      onShare: () {
        if (!mounted) return;
        batchService.batchShare(context, _selectedItems);
      },
      onMove: () {
        if (!mounted) return;
        batchService.batchMove(context, _selectedItems, _currentPath);
      },
      onToggleFavorite: () {
        if (!mounted) return;
        batchService.batchToggleFavorite(context, _selectedItems);
      },
      onDelete: () {
        if (!mounted) return;
        batchService.batchDelete(context, _selectedItems);
      },
    );
  }

  /// 获取批量操作服务实例
  ///
  /// 注意：服务不再存储BuildContext，context需要在调用方法时传入
  BatchOperationsService _getBatchOperationsService() {
    return BatchOperationsService(
      viewModel: widget.viewModel,
      presenter: widget.presenter,
      onRefresh: () async {
        if (!mounted) return;
        await _loadFilesInPath(_currentPath);
      },
      onExitSelectionMode: () {
        if (!mounted) return;
        setState(() {
          _selectionController.clear();
        });
      },
    );
  }

  /// 显示文件详情底部面板
  void _showFileDetailsBottomSheet(FileItem file) {
    final colorScheme = Theme.of(context).colorScheme;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  '文件详情',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // 文件名
            _buildDetailRow(
              '文件名',
              file.name,
              colorScheme,
              isSelectable: true,
            ),
            const SizedBox(height: 16),
            
            // 完整路径
            _buildDetailRow(
              '完整路径',
              file.path,
              colorScheme,
              isSelectable: true,
            ),
            const SizedBox(height: 16),
            
            // 文件大小
            _buildDetailRow(
              '文件大小',
              _formatFileSize(file.size),
              colorScheme,
            ),
            const SizedBox(height: 16),
            
            // 修改时间
            _buildDetailRow(
              '修改时间',
              '${file.modified.year}-${file.modified.month.toString().padLeft(2, '0')}-${file.modified.day.toString().padLeft(2, '0')} '
              '${file.modified.hour.toString().padLeft(2, '0')}:${file.modified.minute.toString().padLeft(2, '0')}',
              colorScheme,
            ),
            const SizedBox(height: 24),
            
            // 关闭按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建详情行
  Widget _buildDetailRow(
    String label,
    String value,
    ColorScheme colorScheme, {
    bool isSelectable = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label：',
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: isSelectable
              ? SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface,
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface,
                  ),
                ),
        ),
      ],
    );
  }

  /// 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
