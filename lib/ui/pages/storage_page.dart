import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easyfile/core/services/view_mode_service.dart';
import 'package:easyfile/core/services/search_history_service.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/file_toolbar.dart';
import 'package:easyfile/ui/widgets/file_search_bar.dart';
import 'package:easyfile/ui/widgets/folder_picker_dialog.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/utils/path_security.dart';
import 'package:easyfile/ui/widgets/image_thumbnail.dart';
import 'package:easyfile/ui/widgets/real_video_thumbnail.dart';
import 'package:easyfile/ui/widgets/audio_cover_widget.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';
import 'package:easyfile/ui/widgets/enhanced_delete_dialog.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';

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

  // 批量操作相关状态
  bool _isSelectionMode = false;
  Set<String> _selectedItems = {}; // 存储选中的文件/文件夹路径
  late final SelectionController _selectionController;

  // 搜索控制器
  final TextEditingController _searchController = TextEditingController();

  List<FileItem> get _filteredFiles {
    if (_searchQuery.isEmpty) return _files;

    // 如果启用子文件夹搜索
    if (_searchInSubfolders) {
      return _searchFilesRecursively(_currentPath, _searchQuery);
    }

    // 仅在当前文件夹搜索
    return _files
        .where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
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
    final parts = _currentPath
        .split(separator)
        .where((p) => p.isNotEmpty)
        .toList();
    final rootParts = _rootPath
        .split(separator)
        .where((p) => p.isNotEmpty)
        .toList();

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
      // 如果选择为空，退出选择模式
      if (_selectedItems.isEmpty && _isSelectionMode) {
        _isSelectionMode = false;
      }
    });
  }



  @override
  void dispose() {
    _searchController.dispose();
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

        // 按类型排序：文件夹在前，文件在后
        files.sort((a, b) {
          if (a.isDirectory && !b.isDirectory) return -1;
          if (!a.isDirectory && b.isDirectory) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

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
    if (_isSelectionMode) {
      setState(() {
        if (_selectedItems.contains(file.path)) {
          _selectedItems.remove(file.path);
          // 如果取消选择后没有选中项，退出多选模式
          if (_selectedItems.isEmpty) {
            _isSelectionMode = false;
          }
        } else {
          _selectedItems.add(file.path);
        }
      });
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
        files.sort((a, b) {
          if (a.isDirectory && !b.isDirectory) return -1;
          if (!a.isDirectory && b.isDirectory) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
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
    final viewModeService = ViewModeService();
    return FileCollectionView(
      items: _filteredFiles,
      gridMode: viewModeService.isGridView,
      padding: viewModeService.isGridView
          ? const EdgeInsets.all(8)
          : const EdgeInsets.symmetric(vertical: 0),
      selectionController: _isSelectionMode ? _selectionController : null,
      // 列表模式显示选项
      showFullPath: _isSearchMode && _searchInSubfolders,
      showFavoriteButton: true,
      isFavorite: (path) => widget.viewModel.isFavoriteFile(path),
      onFavoriteToggle: (file) async {
        return await widget.presenter.toggleFavoriteFile(file);
      },
      // 网格模式使用自定义构建器
      itemBuilder: viewModeService.isGridView ? (file) {
        final isSelected = _selectionController.contains(file.path);
        return _buildGridItem(file, isSelected);
      } : null, // 列表模式使用默认实现
      onTap: (file) => _onFileTap(file),
      onLongPress: (file) {
        // 长按进入多选模式并选中当前项
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            _selectedItems.add(file.path);
          });
        }
      },
    );
  }

  /// 构建网格项（用于网格视图）
  Widget _buildGridItem(FileItem file, bool isSelected) {
    final isImage = !file.isDirectory && FileUtils.isImageFile(file.name);
    final isVideo = !file.isDirectory && FileUtils.isVideoFile(file.name);
    final isAudio = !file.isDirectory && FileUtils.isAudioFile(file.name);
    final isDocument = !file.isDirectory && FileUtils.isDocumentFile(file.name);
    final isFavorite = widget.viewModel.isFavoriteFile(file.path);

    return InkWell(
      onTap: () => _onFileTap(file),
      onLongPress: () {
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            _selectionController.select(file.path);
            _selectedItems.add(file.path);
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: 2,  // 固定宽度，避免选中时溢出
          ),
        ),
        child: Stack(
        children: [
          // 主内容区域 - 图标在上，文件名和大小在下
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 文件图标或缩略图
                  if (isImage)
                    ImageThumbnail(imagePath: file.path, size: 64)
                  else if (isVideo)
                    RealVideoThumbnail(videoPath: file.path, size: 64)
                  else if (isAudio)
                    AudioCoverWidget(audioPath: file.path, size: 64)
                  else if (isDocument)
                    DocumentIconWidget(fileName: file.name, size: 64)
                  else
                    Icon(
                      file.isDirectory ? Icons.folder : _getFileIcon(file),
                      size: 48,
                      color: file.isDirectory ? Colors.amber : Colors.blue,
                    ),
                  const SizedBox(height: 8),
                  // 文件名
                  Text(
                    file.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  // 文件大小
                  if (!file.isDirectory)
                    Text(
                      FileUtils.formatFileSize(file.size),
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
          // 收藏按钮（右上角）- 所有文件都显示
          if (!file.isDirectory)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                width: 26,
                height: 26,
                child: Transform.scale(
                  scale: 0.75,  // 与复选框使用相同的缩放比例
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final isFavoriteNew = await widget.presenter
                            .toggleFavoriteFile(file);
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(isFavoriteNew ? '已添加到收藏' : '已取消收藏'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          isFavorite ? Icons.star : Icons.star_border,
                          color: isFavorite ? Colors.amber : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // 多选模式下的Checkbox（右下角）
          if (_isSelectionMode)
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                width: 26,
                height: 26,
                child: Transform.scale(
                  scale: 0.75,  // 缩放到18px，与收藏按钮大小一致
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (bool? value) {
                      if (value == true) {
                        _selectionController.select(file.path);
                      } else {
                        _selectionController.deselect(file.path);
                      }
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  }

  /// 获取文件图标
  IconData _getFileIcon(FileItem file) {
    final ext = file.name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.audio_file;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.archive;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
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
        title: _isSelectionMode
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
                                ).colorScheme.onSurface.withOpacity(0.6),
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
        actions: _isSelectionMode
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
                // 使用Row来控制按钮间距
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 使用统一的FileToolbar组件
                      FileToolbar(
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
                        iconSize: 22,
                      ),
                    ],
                  ),
                ),
              ],
      ),
      body: Consumer<ViewModeService>(
          builder: (context, viewModeService, _) {
            return _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      // 搜索栏（使用统一的FileSearchBar组件）
                      if (_isSearchMode)
                        FileSearchBar(
                          controller: _searchController,
                          hintText: '搜索文件...',
                          onSearch: (query) async {
                            if (query.isNotEmpty) {
                              await SearchHistoryService().addSearch(query);
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
                                        ).colorScheme.onSurface.withOpacity(0.7),
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
      bottomNavigationBar: _isSelectionMode ? _buildSelectionBottomBar() : null,
    );
  }

  /// 构建批量选择底部工具栏
  Widget _buildSelectionBottomBar() {
    // 统计选中的文件和文件夹数量
    int fileCount = 0;
    int folderCount = 0;
    int totalSize = 0;

    for (final path in _selectedItems) {
      final entity = FileSystemEntity.typeSync(path);
      if (entity == FileSystemEntityType.directory) {
        folderCount++;
      } else if (entity == FileSystemEntityType.file) {
        fileCount++;
        try {
          totalSize += File(path).lengthSync();
        } catch (e) {
          logger.w('Failed to get file size: $path');
        }
      }
    }

    // 判断是否只选中了文件（可以分享）
    final hasOnlyFiles = folderCount == 0 && fileCount > 0;
    // 判断是否只选中了一个项（可以重命名）
    final isSingleSelection = _selectedItems.length == 1;

    return BottomAppBar(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // 显示选中信息
            Expanded(
              child: Text(
                _buildSelectionInfo(fileCount, folderCount, totalSize),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 操作按钮
            // 复制按钮（单个文件/文件夹）
            if (isSingleSelection)
              IconButton(
                icon: const Icon(Icons.copy),
                padding: EdgeInsets.zero,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
                onPressed: _batchCopy,
                tooltip: '复制',
              ),
            // 重命名按钮（单个文件/文件夹）
            if (isSingleSelection)
              IconButton(
                icon: const Icon(Icons.edit),
                padding: EdgeInsets.zero,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
                onPressed: _batchRename,
                tooltip: '重命名',
              ),
            // 分享按钮（只有文件可以分享）
            if (hasOnlyFiles)
              IconButton(
                icon: const Icon(Icons.share),
                padding: EdgeInsets.zero,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
                onPressed: _batchShare,
                tooltip: '分享',
              ),
            // 移动按钮
            IconButton(
              icon: const Icon(Icons.drive_file_move),
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              onPressed: _selectedItems.isEmpty ? null : _batchMove,
              tooltip: '移动',
            ),
            // 批量收藏/取消收藏按钮（只有文件可以收藏）
            if (hasOnlyFiles)
              IconButton(
                icon: Icon(_isAllSelectedFavorite() ? Icons.star : Icons.star_border),
                onPressed: _batchToggleFavorite,
                tooltip: _isAllSelectedFavorite() ? '取消收藏' : '添加收藏',
                color: _isAllSelectedFavorite() ? Colors.amber : null,
                padding: EdgeInsets.zero,
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              ),
            // 删除按钮
            IconButton(
              icon: const Icon(Icons.delete),
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              onPressed: _selectedItems.isEmpty ? null : _batchDelete,
              tooltip: '删除',
            ),
          ],
        ),
      ),
    );
  }

  /// 构建选中信息文本
  String _buildSelectionInfo(int fileCount, int folderCount, int totalSize) {
    final parts = <String>[];
    if (fileCount > 0) parts.add('$fileCount 个文件');
    if (folderCount > 0) parts.add('$folderCount 个文件夹');
    final info = parts.join('，');
    if (totalSize > 0) {
      return '$info · ${FileUtils.formatFileSize(totalSize)}';
    }
    return info;
  }

  /// 检查选中的文件是否全部已收藏
  bool _isAllSelectedFavorite() {
    if (_selectedItems.isEmpty) return false;
    return _selectedItems.every((path) => widget.viewModel.isFavoriteFile(path));
  }

  /// 批量添加/取消收藏
  void _batchToggleFavorite() async {
    if (_selectedItems.isEmpty) return;

    final allFavorite = _isAllSelectedFavorite();
    final action = allFavorite ? '取消收藏' : '添加到收藏';
    
    int successCount = 0;
    int failCount = 0;

    for (final path in _selectedItems) {
      // 只处理文件，跳过文件夹
      final entity = FileSystemEntity.typeSync(path);
      if (entity != FileSystemEntityType.file) continue;

      try {
        final file = FileItem(
          name: path.split(Platform.pathSeparator).last,
          path: path,
          size: File(path).lengthSync(),
          modified: File(path).lastModifiedSync(),
          isDirectory: false,
        );

        if (allFavorite) {
          // 全部已收藏，则取消收藏
          await widget.presenter.toggleFavoriteFile(file);
          successCount++;
        } else {
          // 有未收藏的，则添加收藏
          final isFav = widget.viewModel.isFavoriteFile(path);
          if (!isFav) {
            await widget.presenter.toggleFavoriteFile(file);
            successCount++;
          }
        }
      } catch (e) {
        logger.e('Failed to toggle favorite: $path, error: $e');
        failCount++;
      }
    }

    if (mounted) {
      final message = failCount > 0
          ? '$action完成：成功 $successCount 个，失败 $failCount 个'
          : '已${action} $successCount 个文件';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 批量删除
  void _batchDelete() async {
    if (_selectedItems.isEmpty) return;

    // 🔒 安全检查：验证所有选中项是否允许删除
    for (final path in _selectedItems) {
      final riskLevel = PathSecurity.getPathRiskLevel(path);

      if (riskLevel == PathRiskLevel.forbidden ||
          riskLevel == PathRiskLevel.danger) {
        final fileName = path.split(Platform.pathSeparator).last;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🛑 禁止删除'),
            content: Text(
              '选中的文件包含受保护的系统目录 "$fileName"！\n\n'
              '删除系统目录会导致：\n'
              '• 系统功能损坏\n'
              '• 应用无法运行\n'
              '• 数据永久丢失\n\n'
              '为保护您的设备，此操作已被阻止。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
        logger.w('Delete blocked by UI: $path (Risk: ${riskLevel.name})');
        return;
      }

      // 检查是否为系统关键文件夹
      final fileName = path.split(Platform.pathSeparator).last;
      if (PathSecurity.isSystemFolderName(fileName)) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🔒 禁止删除'),
            content: Text(
              '"$fileName" 是系统重要文件夹！\n\n'
              '删除此文件夹会导致系统功能异常。\n\n'
              '为保护您的设备，此操作已被阻止。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
        logger.w('Delete blocked: "$fileName" is a system folder');
        return;
      }
    }

    // 统计文件和文件夹数量
    int fileCount = 0;
    int folderCount = 0;
    for (final path in _selectedItems) {
      final entity = FileSystemEntity.typeSync(path);
      if (entity == FileSystemEntityType.directory) {
        folderCount++;
      } else if (entity == FileSystemEntityType.file) {
        fileCount++;
      }
    }

    // 使用增强的删除确认对话框
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final confirmed = await EnhancedDeleteDialog.showBatchDeleteConfirmation(
      context: context,
      paths: _selectedItems.toList(),
      fileCount: fileCount,
      folderCount: folderCount,
    );

    if (!confirmed || !mounted) return;

    // 显示进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在删除...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      int successCount = 0;
      int failCount = 0;

      for (final path in _selectedItems) {
        try {
          // 🔒 记录操作日志
          final riskLevel = PathSecurity.getPathRiskLevel(path);
          PathSecurity.logOperation(
            operation: 'DELETE (UI)',
            path: path,
            riskLevel: riskLevel,
            allowed: true,
          );

          final entity = FileSystemEntity.typeSync(path);
          if (entity == FileSystemEntityType.directory) {
            await Directory(path).delete(recursive: true);
          } else if (entity == FileSystemEntityType.file) {
            await File(path).delete();
          }
          successCount++;
        } catch (e) {
          logger.e('Failed to delete: $path, error: $e');
          failCount++;
        }
      }

      if (!mounted) return;
      navigator.pop(); // 关闭进度对话框

      // 刷新文件列表
      await _loadFilesInPath(_currentPath);

      // 退出多选模式
      setState(() {
        _isSelectionMode = false;
        _selectedItems.clear();
      });

      // 显示结果提示
      if (failCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功删除 $successCount 项'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功删除 $successCount 项，失败 $failCount 项'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      navigator.pop(); // 关闭进度对话框
      messenger.showSnackBar(
        SnackBar(content: Text('删除失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 批量移动
  void _batchMove() async {
    if (_selectedItems.isEmpty) return;

    // 🔒 安全检查：验证所有选中项是否允许移动
    for (final path in _selectedItems) {
      final riskLevel = PathSecurity.getPathRiskLevel(path);

      if (riskLevel == PathRiskLevel.forbidden ||
          riskLevel == PathRiskLevel.danger) {
        final fileName = path.split(Platform.pathSeparator).last;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('无法移动 "$fileName"：这是受保护的系统目录'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        logger.w('Move blocked by UI: $path (Risk: ${riskLevel.name})');
        return;
      }

      // 检查是否为系统关键文件夹
      final fileName = path.split(Platform.pathSeparator).last;
      if (PathSecurity.isSystemFolderName(fileName)) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🔒 禁止移动'),
            content: Text(
              '"$fileName" 是系统重要文件夹！\n\n'
              '移动此文件夹会导致系统功能异常。\n\n'
              '为保护您的设备，此操作已被阻止。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
        logger.w('Move blocked: "$fileName" is a system folder');
        return;
      }
    }

    // 显示文件夹选择对话框
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final destinationPath = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(currentPath: _currentPath),
    );

    if (destinationPath == null || !mounted) return;

    // 🔒 验证目标路径安全性
    final targetRiskLevel = PathSecurity.getPathRiskLevel(destinationPath);
    if (targetRiskLevel == PathRiskLevel.forbidden ||
        targetRiskLevel == PathRiskLevel.danger) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('目标位置不安全，无法移动文件'),
          backgroundColor: Colors.red,
        ),
      );
      logger.w('Move blocked: target path $destinationPath is protected');
      return;
    }

    // 检查是否要移动到子目录（会造成循环）
    for (final path in _selectedItems) {
      if (FileSystemEntity.typeSync(path) == FileSystemEntityType.directory) {
        if (destinationPath.startsWith(path + Platform.pathSeparator) ||
            destinationPath == path) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('不能将文件夹移动到自己的子目录中'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }

    // 显示进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在移动...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      int successCount = 0;
      int failCount = 0;

      for (final path in _selectedItems) {
        try {
          final entity = FileSystemEntity.typeSync(path);
          final baseName = path.split(Platform.pathSeparator).last;
          final targetPath =
              '$destinationPath${Platform.pathSeparator}$baseName';

          // 🔒 记录操作日志
          final riskLevel = PathSecurity.getPathRiskLevel(path);
          PathSecurity.logOperation(
            operation: 'MOVE (UI)',
            path: '$path -> $targetPath',
            riskLevel: riskLevel,
            allowed: true,
          );

          if (entity == FileSystemEntityType.directory) {
            await Directory(path).rename(targetPath);
          } else if (entity == FileSystemEntityType.file) {
            await File(path).rename(targetPath);
          }
          successCount++;
        } catch (e) {
          logger.e('Failed to move: $path, error: $e');
          failCount++;
        }
      }

      if (!mounted) return;
      navigator.pop();
      await _loadFilesInPath(_currentPath);
      setState(() {
        _isSelectionMode = false;
        _selectedItems.clear();
      });

      if (failCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功移动 $successCount 项'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功移动 $successCount 项，失败 $failCount 项'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('移动失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 批量复制
  void _batchCopy() async {
    if (_selectedItems.length != 1) return;

    final sourcePath = _selectedItems.first;

    // 显示文件夹选择对话框
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final destinationPath = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(currentPath: _currentPath),
    );

    if (destinationPath == null || !mounted) return;

    // 显示进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在复制...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final entity = FileSystemEntity.typeSync(sourcePath);
      final baseName = sourcePath.split(Platform.pathSeparator).last;
      final targetPath = '$destinationPath${Platform.pathSeparator}$baseName';

      if (entity == FileSystemEntityType.directory) {
        // 递归复制文件夹
        await _copyDirectory(Directory(sourcePath), Directory(targetPath));
      } else if (entity == FileSystemEntityType.file) {
        await File(sourcePath).copy(targetPath);
      }

      if (!mounted) return;
      navigator.pop(context);
      await _loadFilesInPath(_currentPath);
      setState(() {
        _isSelectionMode = false;
        _selectedItems.clear();
      });

      messenger.showSnackBar(
        const SnackBar(content: Text('复制成功'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('复制失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 递归复制文件夹
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }

    await for (final entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDirectory = Directory(
          '${destination.path}${Platform.pathSeparator}${entity.path.split(Platform.pathSeparator).last}',
        );
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy(
          '${destination.path}${Platform.pathSeparator}${entity.path.split(Platform.pathSeparator).last}',
        );
      }
    }
  }

  /// 批量重命名
  void _batchRename() async {
    if (_selectedItems.length != 1) return;

    final sourcePath = _selectedItems.first;
    final entity = FileSystemEntity.typeSync(sourcePath);
    final currentName = sourcePath.split(Platform.pathSeparator).last;
    final isDirectory = entity == FileSystemEntityType.directory;

    // 🔒 安全检查：验证是否允许重命名
    final riskLevel = PathSecurity.getPathRiskLevel(sourcePath);

    // 禁止重命名系统关键目录
    if (riskLevel == PathRiskLevel.forbidden ||
        riskLevel == PathRiskLevel.danger) {
      final messenger = ScaffoldMessenger.of(context);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            PathSecurity.getOperationDeniedMessage(sourcePath, '重命名'),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      logger.w('Rename blocked by UI: $sourcePath (Risk: ${riskLevel.name})');
      return;
    }

    // 检查是否为系统关键文件夹名称
    if (PathSecurity.isSystemFolderName(currentName)) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🔒 禁止重命名'),
          content: Text(
            '"$currentName" 是系统重要文件夹！\n\n'
            '重命名此文件夹会导致：\n'
            '• 系统功能异常\n'
            '• 应用无法访问文件\n'
            '• 媒体库损坏\n\n'
            '为保护您的设备，此操作已被阻止。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
      logger.w('Rename blocked: "$currentName" is a system folder');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // 显示重命名对话框
    final TextEditingController controller = TextEditingController(
      text: currentName,
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isDirectory ? '重命名文件夹' : '重命名文件'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '新名称',
            hintText: '请输入新名称',
          ),
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
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (newName == null || newName.trim().isEmpty || !mounted) return;
    if (newName == currentName) return;

    // 显示进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在重命名...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final parentPath = sourcePath.substring(
        0,
        sourcePath.lastIndexOf(Platform.pathSeparator),
      );
      final targetPath =
          '$parentPath${Platform.pathSeparator}${newName.trim()}';

      // 🔒 验证目标路径安全性
      final targetRiskLevel = PathSecurity.getPathRiskLevel(targetPath);
      if (targetRiskLevel == PathRiskLevel.forbidden ||
          targetRiskLevel == PathRiskLevel.danger) {
        final messenger = ScaffoldMessenger.of(context);
        if (!mounted) return;
        Navigator.pop(context); // 关闭进度对话框
        messenger.showSnackBar(
          const SnackBar(
            content: Text('重命名失败：目标路径不安全'),
            backgroundColor: Colors.red,
          ),
        );
        logger.w('Rename blocked: target path $targetPath is protected');
        return;
      }

      // 🔒 记录操作日志
      PathSecurity.logOperation(
        operation: 'RENAME (UI)',
        path: '$sourcePath -> $targetPath',
        riskLevel: riskLevel,
        allowed: true,
      );

      if (entity == FileSystemEntityType.directory) {
        await Directory(sourcePath).rename(targetPath);
      } else if (entity == FileSystemEntityType.file) {
        await File(sourcePath).rename(targetPath);
      }

      if (!mounted) return;
      navigator.pop();
      await _loadFilesInPath(_currentPath);
      setState(() {
        _isSelectionMode = false;
        _selectedItems.clear();
      });

      messenger.showSnackBar(
        const SnackBar(content: Text('重命名成功'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('重命名失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 批量分享
  void _batchShare() async {
    if (_selectedItems.isEmpty) return;

    // 只分享文件，过滤掉文件夹
    final filePaths = _selectedItems.where((path) {
      return FileSystemEntity.typeSync(path) == FileSystemEntityType.file;
    }).toList();

    if (filePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请选择至少一个文件进行分享'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Capture messenger before awaiting presenter
      final messenger = ScaffoldMessenger.of(context);

      // 使用presenter批量分享
      final success = await widget.presenter.batchShareFiles(filePaths);

      if (!mounted) return;
      if (success) {
        // 分享成功后退出多选模式
        setState(() {
          _isSelectionMode = false;
          _selectedItems.clear();
        });
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('分享失败，请检查是否有有效的文件'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      logger.e('Failed to share files: $e');
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(content: Text('分享失败：$e'), backgroundColor: Colors.red),
      );
    }
  }
}
