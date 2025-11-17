import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/view_mode_service.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/category_group_service.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/file_toolbar.dart';
import 'package:easyfile/ui/widgets/file_search_bar.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/ui/widgets/image_thumbnail.dart';
import 'package:easyfile/ui/widgets/real_video_thumbnail.dart';
import 'package:easyfile/ui/widgets/audio_cover_widget.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';
import 'package:easyfile/ui/widgets/enhanced_delete_dialog.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';

/// 文档文件类型枚举
enum DocumentFileType {
  all('全部', ''),
  pdf('PDF', 'PDF'),
  word('Word', 'DOC, DOCX'),
  excel('Excel', 'XLS, XLSX, CSV'),
  ppt('PPT', 'PPT, PPTX'),
  text('TXT', 'TXT, MD, LOG'),
  other('其他', '');

  final String label;
  final String extensions;
  const DocumentFileType(this.label, this.extensions);

  IconData get icon {
    switch (this) {
      case DocumentFileType.text:
        return Icons.description;
      case DocumentFileType.word:
        return Icons.article;
      case DocumentFileType.excel:
        return Icons.table_chart;
      case DocumentFileType.ppt:
        return Icons.slideshow;
      case DocumentFileType.pdf:
        return Icons.picture_as_pdf;
      case DocumentFileType.other:
        return Icons.insert_drive_file;
      default:
        return Icons.folder_open;
    }
  }

  bool matches(String filename) {
    if (this == DocumentFileType.all) return true;
    final ext = filename.split('.').last.toUpperCase();
    switch (this) {
      case DocumentFileType.text:
        return ['TXT', 'MD', 'LOG', 'RTF'].contains(ext);
      case DocumentFileType.word:
        return ['DOC', 'DOCX'].contains(ext);
      case DocumentFileType.excel:
        return ['XLS', 'XLSX', 'CSV'].contains(ext);
      case DocumentFileType.ppt:
        return ['PPT', 'PPTX'].contains(ext);
      case DocumentFileType.pdf:
        return ext == 'PDF';
      case DocumentFileType.other:
        // 其他：不属于上述任何类型的文档
        return ![
          'TXT',
          'MD',
          'LOG',
          'RTF',
          'DOC',
          'DOCX',
          'XLS',
          'XLSX',
          'CSV',
          'PPT',
          'PPTX',
          'PDF',
        ].contains(ext);
      default:
        return false;
    }
  }
}

/// 下载文件类型枚举
enum DownloadFileType {
  all('全部', ''),
  installer('APK', 'APK, EXE, MSI'),
  archive('压缩包', 'ZIP, RAR, 7Z'),
  document('文档', 'PDF, DOC, XLS'),
  image('图片', 'JPG, PNG, GIF'),
  media('视频', 'MP3, MP4, AVI'),
  other('其他', '');

  final String label;
  final String extensions;
  const DownloadFileType(this.label, this.extensions);

  IconData get icon {
    switch (this) {
      case DownloadFileType.installer:
        return Icons.install_desktop;
      case DownloadFileType.archive:
        return Icons.folder_zip;
      case DownloadFileType.document:
        return Icons.description;
      case DownloadFileType.image:
        return Icons.image;
      case DownloadFileType.media:
        return Icons.play_circle_outline;
      case DownloadFileType.other:
        return Icons.insert_drive_file;
      default:
        return Icons.folder_open;
    }
  }

  bool matches(String filename) {
    if (this == DownloadFileType.all) return true;
    final ext = filename.split('.').last.toUpperCase();
    switch (this) {
      case DownloadFileType.installer:
        return ['APK', 'EXE', 'MSI', 'DMG', 'DEB', 'RPM'].contains(ext);
      case DownloadFileType.archive:
        return ['ZIP', 'RAR', '7Z', 'TAR', 'GZ', 'BZ2', 'XZ'].contains(ext);
      case DownloadFileType.document:
        return [
          'PDF',
          'DOC',
          'DOCX',
          'XLS',
          'XLSX',
          'PPT',
          'PPTX',
          'TXT',
          'MD',
        ].contains(ext);
      case DownloadFileType.image:
        return [
          'JPG',
          'JPEG',
          'PNG',
          'GIF',
          'BMP',
          'WEBP',
          'SVG',
        ].contains(ext);
      case DownloadFileType.media:
        return [
          'MP3',
          'MP4',
          'AVI',
          'MKV',
          'MOV',
          'WMV',
          'FLV',
          'WAV',
          'FLAC',
        ].contains(ext);
      case DownloadFileType.other:
        // 其他：不属于上述任何类型
        final allKnownExts = [
          'APK',
          'EXE',
          'MSI',
          'DMG',
          'DEB',
          'RPM',
          'ZIP',
          'RAR',
          '7Z',
          'TAR',
          'GZ',
          'BZ2',
          'XZ',
          'PDF',
          'DOC',
          'DOCX',
          'XLS',
          'XLSX',
          'PPT',
          'PPTX',
          'TXT',
          'MD',
          'JPG',
          'JPEG',
          'PNG',
          'GIF',
          'BMP',
          'WEBP',
          'SVG',
          'MP3',
          'MP4',
          'AVI',
          'MKV',
          'MOV',
          'WMV',
          'FLV',
          'WAV',
          'FLAC',
        ];
        return !allKnownExts.contains(ext);
      default:
        return false;
    }
  }
}

/// 分类聚合视图页面
///
/// 显示特定类型的所有文件（如图片、音乐等）
class CategoryFilePage extends StatefulWidget {
  final CategoryType categoryType;
  final FilePresenter presenter;
  final FileViewModel viewModel;

  const CategoryFilePage({
    super.key,
    required this.categoryType,
    required this.presenter,
    required this.viewModel,
  });

  @override
  State<CategoryFilePage> createState() => _CategoryFilePageState();
}

class _CategoryFilePageState extends State<CategoryFilePage> {
  late CategoryInfo categoryInfo;
  bool _isLoading = true;
  List<FileItem> _files = [];
  String _errorMessage = '';
  String _loadingProgress = '';

  // 搜索
  bool _isSearchMode = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // 文件类型筛选
  DocumentFileType _documentTypeFilter = DocumentFileType.all;
  DownloadFileType _downloadTypeFilter = DownloadFileType.all;

  // 批量操作相关
  bool _isSelectionMode = false;
  final SelectionController _selectionController = SelectionController();

  // 计算选中文件的总大小
  int get _selectedTotalSize {
    int total = 0;
    for (final path in _selectionController.selected) {
      final file = _files.firstWhere(
        (f) => f.path == path,
        orElse: () => _files.first,
      );
      total += file.size;
    }
    return total;
  }

  // 过滤后的文件列表（按搜索和文件类型筛选）
  List<FileItem> get _filteredFiles {
    var result = _files;

    // 按文件类型筛选
    if (widget.categoryType == CategoryType.documents &&
        _documentTypeFilter != DocumentFileType.all) {
      result = result
          .where((f) => _documentTypeFilter.matches(f.name))
          .toList();
    } else if (widget.categoryType == CategoryType.downloads &&
        _downloadTypeFilter != DownloadFileType.all) {
      result = result
          .where((f) => _downloadTypeFilter.matches(f.name))
          .toList();
    }

    // 按搜索关键词筛选
    if (_searchQuery.isNotEmpty) {
      result = result
          .where(
            (f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }

    return result;
  }

  // 按日期分组的文件列表
  Map<String, List<FileItem>> get _groupedFiles {
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

    for (final file in _filteredFiles) {
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

  @override
  void initState() {
    super.initState();
    // 监听SelectionController变化并同步状态
    _selectionController.selectedNotifier.addListener(_onSelectionChanged);
    categoryInfo = CategoryInfo.getInfoByType(widget.categoryType)!;
    _loadFileTypeFilter();
    _loadCategoryFiles();
  }

  /// 选择状态改变回调
  void _onSelectionChanged() {
    setState(() {
      // SelectionController内部已经管理了选择状态，这里只需要触发界面更新
      // 如果选择为空，退出选择模式
      if (_selectionController.selected.isEmpty && _isSelectionMode) {
        _isSelectionMode = false;
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _selectionController.selectedNotifier.removeListener(_onSelectionChanged);
    _selectionController.dispose();
    super.dispose();
  }



  /// 加载文件类型筛选偏好
  Future<void> _loadFileTypeFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (widget.categoryType == CategoryType.documents) {
        final key = 'category_file_type_filter_documents';
        final savedIndex = prefs.getInt(key) ?? 0;
        setState(() {
          _documentTypeFilter = DocumentFileType.values[savedIndex];
        });
      } else if (widget.categoryType == CategoryType.downloads) {
        final key = 'category_file_type_filter_downloads';
        final savedIndex = prefs.getInt(key) ?? 0;
        setState(() {
          _downloadTypeFilter = DownloadFileType.values[savedIndex];
        });
      }
    } catch (e) {
      logger.e('Failed to load file type filter: $e');
    }
  }

  /// 保存文件类型筛选偏好
  Future<void> _saveFileTypeFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (widget.categoryType == CategoryType.documents) {
        final key = 'category_file_type_filter_documents';
        await prefs.setInt(key, _documentTypeFilter.index);
      } else if (widget.categoryType == CategoryType.downloads) {
        final key = 'category_file_type_filter_downloads';
        await prefs.setInt(key, _downloadTypeFilter.index);
      }
    } catch (e) {
      logger.e('Failed to save file type filter: $e');
    }
  }

  /// 从缓存加载文件列表
  Future<List<FileItem>> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'category_cache_${widget.categoryType.name}';
      final cacheJson = prefs.getString(key);

      if (cacheJson == null) {
        logger.d('No cache found for ${widget.categoryType.name}');
        return [];
      }

      final cacheData = json.decode(cacheJson) as Map<String, dynamic>;
      final timestamp = cacheData['timestamp'] as int;
      final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;

      // 缓存有效期：24小时（86400000毫秒）
      if (cacheAge > 86400000) {
        logger.d('Cache expired for ${widget.categoryType.name}');
        return [];
      }

      final filesData = cacheData['files'] as List<dynamic>;
      final files = filesData.map((fileJson) {
        final map = fileJson as Map<String, dynamic>;
        return FileItem(
          name: map['name'] as String,
          path: map['path'] as String,
          isDirectory: false, // 分类文件都是文件，不是目录
          size: map['size'] as int,
          modified: DateTime.fromMillisecondsSinceEpoch(map['modified'] as int),
        );
      }).toList();

      logger.i(
        'Loaded ${files.length} files from cache for ${widget.categoryType.name}',
      );
      return files;
    } catch (e) {
      logger.e('Failed to load cache: $e');
      return [];
    }
  }

  /// 保存文件列表到缓存
  Future<void> _saveToCache(List<FileItem> files) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'category_cache_${widget.categoryType.name}';

      final cacheData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'categoryType': widget.categoryType.name,
        'files': files
            .map(
              (file) => {
                'name': file.name,
                'path': file.path,
                'size': file.size,
                'modified': file.modified.millisecondsSinceEpoch,
              },
            )
            .toList(),
      };

      await prefs.setString(key, json.encode(cacheData));
      logger.i('Cached ${files.length} files for ${widget.categoryType.name}');
    } catch (e) {
      logger.e('Failed to save cache: $e');
    }
  }

  /// 清除缓存
  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'category_cache_${widget.categoryType.name}';
      await prefs.remove(key);
      logger.i('Cleared cache for ${widget.categoryType.name}');
    } catch (e) {
      logger.e('Failed to clear cache: $e');
    }
  }

  /// 加载分类文件
  Future<void> _loadCategoryFiles({bool forceRefresh = false}) async {
    // 如果是强制刷新，跳过缓存
    if (!forceRefresh) {
      // Step 1: 尝试加载缓存
      final cached = await _loadFromCache();
      if (cached.isNotEmpty) {
        setState(() {
          _files = cached;
          // 应用全局排序设置
          _files.sort(CategorySortService().getComparator());
          _isLoading = false;
          _errorMessage = '';
        });
        logger.i('Showing cached data, starting background refresh...');
      } else {
        setState(() {
          _isLoading = true;
          _errorMessage = '';
          _loadingProgress = '开始扫描...';
        });
      }
    } else {
      // 强制刷新：清除缓存并显示加载状态
      await _clearCache();
      setState(() {
        _isLoading = true;
        _errorMessage = '';
        _loadingProgress = '开始扫描...';
      });
    }

    // Step 2: 后台扫描最新数据
    try {
      logger.i('Loading files for category: ${categoryInfo.name}');

      // 显示扫描进度
      if (_isLoading) {
        setState(() {
          _loadingProgress = '正在扫描${categoryInfo.name}文件...';
        });
      }

      final files = await widget.presenter.scanFilesByCategory(
        widget.categoryType,
      );

      // Step 3: 更新UI和缓存
      setState(() {
        _files = files;
        // 应用全局排序设置
        _files.sort(CategorySortService().getComparator());
        _isLoading = false;
        _loadingProgress = '';
      });

      // 保存到缓存
      await _saveToCache(files);

      logger.i(
        'Loaded ${files.length} files for category ${categoryInfo.name}',
      );
    } catch (e) {
      logger.e('Error loading category files: $e');
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
        _loadingProgress = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FileViewModel>.value(
      value: widget.viewModel,
      child: Consumer2<ViewModeService, CategoryGroupService>(
        builder: (context, viewModeService, groupService, _) {
          return Scaffold(
        appBar: AppBar(
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = false;
                      _selectionController.clear();
                    });
                  },
                  tooltip: '退出多选',
                )
              : IconButton(
                  icon: const Icon(Icons.home),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '返回主页',
                ),
          title: _isSelectionMode
              ? Text('已选择 ${_selectionController.count} 项')
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: categoryInfo.backgroundColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        categoryInfo.icon,
                        size: 20,
                        color: categoryInfo.iconColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(categoryInfo.name),
                  ],
                ),
          titleSpacing: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _isSelectionMode
                    ? [
                        // 多选模式下的操作按钮
                        // 全选/取消全选按钮
                        IconButton(
                          icon: Icon(
                            _selectionController.count == _filteredFiles.length
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 22,
                          ),
                          onPressed: () {
                            setState(() {
                              if (_selectionController.count ==
                                  _filteredFiles.length) {
                                _selectionController.clear();
                              } else {
                                _selectionController.clear();
                                for (final file in _filteredFiles) {
                                  _selectionController.select(file.path);
                                }
                              }
                            });
                          },
                          tooltip:
                              _selectionController.count == _filteredFiles.length
                              ? '取消全选'
                              : '全选',
                          padding: EdgeInsets.zero,
                          visualDensity: const VisualDensity(
                            horizontal: -4,
                            vertical: -4,
                          ),
                        ),
                      ]
                    : [
                        // 正常模式下的操作按钮（使用统一的FileToolbar组件）
                        FileToolbar(
                          showBackButton: false,  // 类别页不需要返回按钮
                          showSearchButton: true,
                          onSearchPressed: () {
                            setState(() {
                              _isSearchMode = !_isSearchMode;
                              if (!_isSearchMode) _searchQuery = '';
                            });
                          },
                          isSearchMode: _isSearchMode,
                          extraActions: [
                            // 排序按钮
                            IconButton(
                              icon: const Icon(Icons.sort, size: 22),
                              onPressed: _showSortOptions,
                              tooltip: '排序',
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                            ),
                            // 分组切换按钮
                            IconButton(
                              icon: Icon(
                                CategoryGroupService().isGroupEnabled ? Icons.view_list : Icons.view_agenda,
                                size: 22,
                              ),
                              onPressed: () {
                                CategoryGroupService().toggleGroup();
                                setState(() {}); // 触发界面刷新
                              },
                              tooltip: CategoryGroupService().isGroupEnabled ? '取消分组' : '按日期分组',
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                            ),
                          ],
                          iconSize: 22,
                        ),
                      ],
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // 搜索框（使用统一的FileSearchBar组件）
            if (_isSearchMode)
              FileSearchBar(
                controller: _searchController,
                focusNode: _searchFocusNode,
                hintText: '搜索${categoryInfo.name}...',
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

            // 主体内容
            Expanded(child: _buildBody()),
          ],
        ),
        // 批量操作底部工具栏
        bottomNavigationBar: _isSelectionMode
            ? _buildSelectionBottomBar()
            : null,
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_loadingProgress.isEmpty ? '正在扫描文件...' : _loadingProgress),
            if (_files.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '已找到 ${_files.length} 个文件',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadCategoryFiles,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_files.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadCategoryFiles,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(categoryInfo.icon, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '没有找到${categoryInfo.name}文件',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '支持的格式: ${categoryInfo.extensions.take(5).join(', ')}${categoryInfo.extensions.length > 5 ? ' 等' : ''}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '下拉刷新',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        // 统计信息栏
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: categoryInfo.backgroundColor.withOpacity(0.3),
          child: Row(
            children: [
              Icon(categoryInfo.icon, size: 16, color: categoryInfo.iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isSearchMode && _searchQuery.isNotEmpty
                          ? '找到 ${_filteredFiles.length} 个匹配文件（共${_files.length}个）'
                          : '找到 ${_files.length} 个${categoryInfo.name}文件',
                      style: TextStyle(
                        color: categoryInfo.iconColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              // 文件大小
              Text(
                _formatTotalSize(),
                style: TextStyle(color: categoryInfo.iconColor, fontSize: 12),
              ),
            ],
          ),
        ),

        // 文件类型筛选标签（仅文档和下载分类显示，搜索模式下隐藏）
        if (!_isSearchMode &&
            (widget.categoryType == CategoryType.documents ||
                widget.categoryType == CategoryType.downloads))
          _buildFileTypeChips(),

        // 文件列表或网格（已迁移到 FileCollectionView）
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadCategoryFiles(forceRefresh: true),
            // 启用分组时（无论列表还是网格模式）都使用分组视图
            child: CategoryGroupService().isGroupEnabled
                ? _buildGroupedView()
                : FileCollectionView(
                    items: _filteredFiles,
                    gridMode: ViewModeService().isGridView,
                    padding: ViewModeService().isGridView
                        ? const EdgeInsets.all(8)
                        : const EdgeInsets.symmetric(vertical: 0),
                    selectionController: _isSelectionMode ? _selectionController : null,
                    // 列表模式显示选项
                    showFullPath: _isSearchMode,  // 只在搜索模式下显示完整路径
                    showFavoriteButton: true,
                    isFavorite: (path) => widget.viewModel.isFavoriteFile(path),
                    onFavoriteToggle: (file) async {
                      return await widget.presenter.toggleFavoriteFile(file);
                    },
                    // 网格模式使用自定义构建器
                    itemBuilder: ViewModeService().isGridView ? (file) {
                      final isSelected = _selectionController.contains(file.path);
                      return _buildGridItem(file, isSelected);
                    } : null, // 列表模式使用默认实现
                    onTap: (file) {
                      if (!_isSelectionMode) {
                        _previewFile(file);
                      }
                    },
                    onLongPress: (file) {
                      if (!_isSelectionMode) {
                        setState(() {
                          _isSelectionMode = true;
                        });
                      }
                    },
                  ),
          ),
        ),
      ],
    );
  }

  /// 构建批量操作底部工具栏
  Widget _buildSelectionBottomBar() {
    return BottomAppBar(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // 显示选中信息
            Expanded(
              child: Text(
                '${_selectionController.count} 个文件 · ${_formatSize(_selectedTotalSize)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 操作按钮 - 紧凑排列
            // 复制按钮（仅单个文件时显示）
            if (_selectionController.count == 1)
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: _copyFile,
                tooltip: '复制',
                padding: EdgeInsets.zero,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
              ),
            // 重命名按钮（仅单个文件时显示）
            if (_selectionController.count == 1)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: _renameFile,
                tooltip: '重命名',
                padding: EdgeInsets.zero,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
              ),
            // 分享按钮
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _selectionController.selected.isEmpty ? null : _batchShare,
              tooltip: '分享',
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
            // 移动按钮
            IconButton(
              icon: const Icon(Icons.drive_file_move),
              onPressed: _selectionController.selected.isEmpty ? null : _batchMove,
              tooltip: '移动',
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
            // 批量收藏/取消收藏按钮
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
              onPressed: _selectionController.selected.isEmpty ? null : _batchDelete,
              tooltip: '删除',
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
          ],
        ),
      ),
    );
  }

  /// 检查选中的文件是否全部已收藏
  bool _isAllSelectedFavorite() {
    if (_selectionController.selected.isEmpty) return false;
    return _selectionController.selected.every((path) => widget.viewModel.isFavoriteFile(path));
  }

  /// 批量添加/取消收藏
  void _batchToggleFavorite() async {
    if (_selectionController.selected.isEmpty) return;

    final allFavorite = _isAllSelectedFavorite();
    final action = allFavorite ? '取消收藏' : '添加到收藏';
    
    int successCount = 0;
    int failCount = 0;

    for (final path in _selectionController.selected) {
      try {
        final file = _filteredFiles.firstWhere((f) => f.path == path);

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

  /// 格式化文件大小
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 批量分享
  void _batchShare() async {
    if (_selectionController.selected.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      // 调用presenter批量分享
      final filePaths = _selectionController.selected.toList();
      final success = await widget.presenter.batchShareFiles(filePaths);

      if (!mounted) return;
      if (success) {
        // 分享成功后退出多选模式
        setState(() {
          _isSelectionMode = false;
          _selectionController.clear();
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
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('分享失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 批量移动
  void _batchMove() async {
    if (_selectionController.selected.isEmpty) return;

    // 使用第一个选中文件的父目录作为初始路径
    String initialPath = widget.viewModel.currentPath;
    if (initialPath.isEmpty && _selectionController.selected.isNotEmpty) {
      final firstFile = _selectionController.selected.first;
      initialPath = path.dirname(firstFile);
    }

    // 显示文件夹选择对话框
    final destinationPath = await showDialog<String>(
      context: context,
      builder: (context) => _FolderPickerDialog(currentPath: initialPath),
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
                  Text('正在移动...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 预先捕获 UI 对象，避免跨 async gap 使用 BuildContext
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      // 调用presenter批量移动
      final filePaths = _selectionController.selected.toList();
      final results = await widget.presenter.batchMoveFiles(
        filePaths,
        destinationPath,
      );

      if (!mounted) return;
      navigator.pop(); // 关闭进度对话框

      // 统计成功和失败的数量
      final successCount = results.values.where((v) => v).length;
      final failCount = results.length - successCount;

      // 刷新文件列表
      await _loadCategoryFiles(forceRefresh: true);

      if (!mounted) return;

      // 退出多选模式
      setState(() {
        _isSelectionMode = false;
        _selectionController.clear();
      });

      // 显示结果提示
      if (failCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功移动 $successCount 个文件'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功移动 $successCount 个文件，失败 $failCount 个'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      navigator.pop(); // 关闭进度对话框
      messenger.showSnackBar(
        SnackBar(content: Text('移动失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 批量删除
  void _batchDelete() async {
    if (_selectionController.selected.isEmpty) return;

    // 使用增强的删除确认对话框
    final confirmed = await EnhancedDeleteDialog.showBatchDeleteConfirmation(
      context: context,
      paths: _selectionController.selected.toList(),
      fileCount: _selectionController.count,
      folderCount: 0, // 分类文件页面只处理文件，不包含文件夹
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

    // 预先捕获 UI 对象，避免跨 async gap 使用 BuildContext
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      // 调用presenter批量删除
      final filePaths = _selectionController.selected.toList();
      final results = await widget.presenter.batchDeleteFiles(filePaths);

      if (!mounted) return;
      navigator.pop(); // 关闭进度对话框

      // 统计成功和失败的数量
      final successCount = results.values.where((v) => v).length;
      final failCount = results.length - successCount;

      // 刷新文件列表
      await _loadCategoryFiles(forceRefresh: true);

      if (!mounted) return;

      // 退出多选模式
      setState(() {
        _isSelectionMode = false;
        _selectionController.clear();
      });

      // 显示结果提示
      if (failCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功删除 $successCount 个文件'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功删除 $successCount 个文件，失败 $failCount 个'),
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

  /// 复制文件（单个文件）
  void _copyFile() async {
    if (_selectionController.count != 1) return;

    final filePath = _selectionController.selected.first;
    final file = _files.firstWhere((f) => f.path == filePath);

    // 显示文件夹选择对话框
    final destinationPath = await showDialog<String>(
      context: context,
      builder: (context) =>
          _FolderPickerDialog(currentPath: path.dirname(filePath)),
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

    // 预先捕获 UI 对象，避免跨 async gap 使用 BuildContext
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      // 调用presenter复制文件
      final targetPath = path.join(destinationPath, path.basename(filePath));
      final success = await widget.presenter.copyFile(file, targetPath);

      if (!mounted) return;
      navigator.pop(); // 关闭进度对话框

      if (success) {
        // 刷新文件列表
        await _loadCategoryFiles(forceRefresh: true);

        // 退出多选模式
        setState(() {
          _isSelectionMode = false;
          _selectionController.clear();
        });

        messenger.showSnackBar(
          const SnackBar(
            content: Text('复制成功'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('复制失败'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      navigator.pop(); // 关闭进度对话框
      messenger.showSnackBar(
        SnackBar(content: Text('复制失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 重命名文件（单个文件）
  void _renameFile() async {
    if (_selectionController.count != 1) return;

    final filePath = _selectionController.selected.first;
    final file = _files.firstWhere((f) => f.path == filePath);
    final currentName = path.basenameWithoutExtension(filePath);
    final extension = path.extension(filePath);

    // 显示重命名对话框
    final TextEditingController controller = TextEditingController(
      text: currentName,
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '新文件名',
            hintText: '请输入新文件名',
            suffix: Text(extension, style: TextStyle(color: Colors.grey[600])),
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

    // 检查输入并防止无效调用
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    if (newName == currentName) return; // 名称没有改变

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

    // 预先捕获 UI 对象，避免跨 async gap 使用 BuildContext
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      // 调用presenter重命名文件
      final newFileName = newName.trim() + extension;
      final success = await widget.presenter.renameFile(file, newFileName);

      if (!mounted) return;
      navigator.pop(); // 关闭进度对话框

      if (success) {
        // 刷新文件列表
        await _loadCategoryFiles(forceRefresh: true);

        // 退出多选模式
        setState(() {
          _isSelectionMode = false;
          _selectionController.clear();
        });

        messenger.showSnackBar(
          const SnackBar(
            content: Text('重命名成功'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('重命名失败'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      navigator.pop(); // 关闭进度对话框
      messenger.showSnackBar(
        SnackBar(content: Text('重命名失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 构建文件类型筛选标签
  Widget _buildFileTypeChips() {
    if (widget.categoryType == CategoryType.documents) {
      return _buildDocumentTypeChips();
    } else if (widget.categoryType == CategoryType.downloads) {
      return _buildDownloadTypeChips();
    }
    return const SizedBox.shrink();
  }

  /// 构建文档类型筛选标签
  Widget _buildDocumentTypeChips() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.3),
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: DocumentFileType.values.length,
        separatorBuilder: (context, index) => const SizedBox(width: 2),
        itemBuilder: (context, index) {
          final type = DocumentFileType.values[index];
          final isSelected = _documentTypeFilter == type;

          return FilterChip(
            label: Text(type.label, style: const TextStyle(fontSize: 14)),
            selected: isSelected,
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            labelPadding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            selectedColor: categoryInfo.iconColor.withOpacity(0.2),
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            side: BorderSide(
              color: isSelected
                  ? categoryInfo.iconColor
                  : Theme.of(context).dividerColor,
              width: isSelected ? 1.5 : 1,
            ),
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _documentTypeFilter = type;
                });
                _saveFileTypeFilter();
              }
            },
          );
        },
      ),
    );
  }

  /// 构建下载类型筛选标签
  Widget _buildDownloadTypeChips() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.3),
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: DownloadFileType.values.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final type = DownloadFileType.values[index];
          final isSelected = _downloadTypeFilter == type;

          return FilterChip(
            label: Text(type.label, style: const TextStyle(fontSize: 14)),
            selected: isSelected,
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            labelPadding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            selectedColor: categoryInfo.iconColor.withOpacity(0.2),
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            side: BorderSide(
              color: isSelected
                  ? categoryInfo.iconColor
                  : Theme.of(context).dividerColor,
              width: isSelected ? 1.5 : 1,
            ),
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _downloadTypeFilter = type;
                });
                _saveFileTypeFilter();
              }
            },
          );
        },
      ),
    );
  }

  // 已迁移为 FileCollectionView 试点，旧的列表构建函数已移除。

  /// 构建按日期分组的视图
  Widget _buildGroupedView() {
    final groups = _groupedFiles;
    final groupKeys = ['今天', '昨天', '本周', '本月', '更早'];
    
    // 构建 FileGroup 列表
    final fileGroups = groupKeys
        .where((key) => groups.containsKey(key))
        .map((key) {
          return FileGroup(
            key: key,
            title: '$key（${groups[key]!.length} 个文件）',
            items: groups[key]!,
            isCollapsible: false, // 不使用折叠功能，保持与原来一致
          );
        })
        .toList();

    return FileCollectionView(
      groups: fileGroups,
      gridMode: ViewModeService().isGridView,
      padding: ViewModeService().isGridView
          ? const EdgeInsets.symmetric(vertical: 4)
          : const EdgeInsets.symmetric(vertical: 0),
      selectionController: _isSelectionMode ? _selectionController : null,
      // 显示选项
      showFullPath: _isSearchMode,  // 只在搜索模式下显示完整路径
      showFavoriteButton: true,
      isFavorite: (path) => widget.viewModel.isFavoriteFile(path),
      onFavoriteToggle: (file) async {
        return await widget.presenter.toggleFavoriteFile(file);
      },
      // 网格模式使用自定义构建器
      itemBuilder: ViewModeService().isGridView ? (file) {
        final isSelected = _selectionController.contains(file.path);
        return _buildGridItem(file, isSelected);
      } : null, // 列表模式使用默认实现
      onTap: (file) {
        if (!_isSelectionMode) {
          _previewFile(file);
        }
      },
      onLongPress: (file) {
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
          });
        }
      },
    );
  }

  /// 构建网格项（简化版本，由 FileCollectionView 处理选中和点击）
  /// 构建网格项（与主页保持一致）
  Widget _buildGridItem(FileItem file, bool isSelected) {
    final isImage = !file.isDirectory && FileUtils.isImageFile(file.name);
    final isVideo = !file.isDirectory && FileUtils.isVideoFile(file.name);
    final isAudio = !file.isDirectory && FileUtils.isAudioFile(file.name);
    final isDocument = !file.isDirectory && FileUtils.isDocumentFile(file.name);
    final isFavorite = widget.viewModel.isFavoriteFile(file.path);

    return InkWell(
      key: ValueKey('${file.path}_$_isSelectionMode'),  // 添加key确保状态变化时重建
      onTap: () {
        if (_isSelectionMode) {
          _selectionController.toggle(file.path);
        } else {
          _previewFile(file);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            _selectionController.select(file.path);
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
                        Icons.insert_drive_file,
                        size: 48,
                        color: Colors.grey[400],
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
            // 收藏按钮（右上角）- 非文件夹才显示
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
                          final isFavoriteNew = await widget.presenter.toggleFavoriteFile(file);
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

  /// 格式化总大小
  String _formatTotalSize() {
    final totalSize = _files.fold<int>(0, (sum, file) => sum + file.size);
    if (totalSize < 1024) {
      return '${totalSize}B';
    } else if (totalSize < 1024 * 1024) {
      return '${(totalSize / 1024).toStringAsFixed(1)}KB';
    } else if (totalSize < 1024 * 1024 * 1024) {
      return '${(totalSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    } else {
      return '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
  }

  /// 显示排序选项
  void _showSortOptions() {
    final sortService = CategorySortService();
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sort_by_alpha),
              title: const Text('按名称排序'),
              trailing: sortService.sortType == SortType.name
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                Navigator.pop(context);
                sortService.setSortType(SortType.name);
                _applySorting();
              },
            ),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('按修改时间排序'),
              trailing: sortService.sortType == SortType.modifiedTime
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                Navigator.pop(context);
                sortService.setSortType(SortType.modifiedTime);
                _applySorting();
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('按文件大小排序'),
              trailing: sortService.sortType == SortType.size
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                Navigator.pop(context);
                sortService.setSortType(SortType.size);
                _applySorting();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 应用排序
  void _applySorting() {
    setState(() {
      _files.sort(CategorySortService().getComparator());
    });
  }

  /// 预览文件
  void _previewFile(FileItem file) {
    logger.d('Previewing file: ${file.path}');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => FilePreviewPage(file: file)),
    );
  }
}

/// 文件夹选择器对话框
class _FolderPickerDialog extends StatefulWidget {
  final String currentPath;

  const _FolderPickerDialog({required this.currentPath});

  @override
  State<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<_FolderPickerDialog> {
  late String _currentPath;
  List<Directory> _folders = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.currentPath.isNotEmpty
        ? widget.currentPath
        : (Platform.isWindows
              ? Platform.environment['USERPROFILE'] ?? 'C:\\'
              : Platform.environment['HOME'] ?? '/');
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);

    try {
      final directory = Directory(_currentPath);
      if (!directory.existsSync()) {
        throw Exception('目录不存在');
      }

      final entities = directory
          .listSync()
          .whereType<Directory>()
          .where((dir) => !path.basename(dir.path).startsWith('.'))
          .toList();

      entities.sort(
        (a, b) => path.basename(a.path).compareTo(path.basename(b.path)),
      );

      setState(() {
        _folders = entities;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载文件夹失败：$e')));
      }
    }
  }

  void _navigateToFolder(String folderPath) {
    setState(() => _currentPath = folderPath);
    _loadFolders();
  }

  void _navigateUp() {
    final parentPath = path.dirname(_currentPath);
    if (parentPath != _currentPath &&
        parentPath.isNotEmpty &&
        parentPath != '.' &&
        !(Platform.isWindows && parentPath.endsWith(':'))) {
      _navigateToFolder(parentPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 标题和当前路径
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '选择目标文件夹',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentPath,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),

            // 返回上级按钮
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('返回上级目录'),
              onTap: _navigateUp,
              dense: true,
            ),

            const Divider(),

            // 文件夹列表
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _folders.isEmpty
                  ? const Center(child: Text('此目录下没有文件夹'))
                  : ListView.builder(
                      itemCount: _folders.length,
                      itemBuilder: (context, index) {
                        final folder = _folders[index];
                        final folderName = path.basename(folder.path);

                        return ListTile(
                          leading: const Icon(
                            Icons.folder,
                            color: Colors.amber,
                          ),
                          title: Text(folderName),
                          onTap: () => _navigateToFolder(folder.path),
                          dense: true,
                        );
                      },
                    ),
            ),

            const Divider(),

            // 底部按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _currentPath),
                  child: const Text('移动到此处'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
