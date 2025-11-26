import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/category_file_cache_service.dart';
import 'package:easyfile/core/services/file_display_settings_service.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/file_toolbar.dart';
import 'package:easyfile/ui/widgets/file_search_bar.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/ui/widgets/selection_bottom_bar.dart';
import 'package:easyfile/ui/widgets/unified_view_config.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/ui/services/batch_operations_service.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/utils/file_grouping_util.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/utils/file_comparator_util.dart';

/// 文件类型筛选接口
abstract class FileTypeFilter {
  String get label;
  bool matches(String filename);
  bool get isAll;
}

/// 文档文件类型枚举
enum DocumentFileType implements FileTypeFilter {
  all('全部', ''),
  pdf('PDF', 'PDF'),
  word('Word', 'DOC, DOCX'),
  excel('Excel', 'XLS, XLSX, CSV'),
  ppt('PPT', 'PPT, PPTX'),
  text('TXT', 'TXT, MD, LOG'),
  other('其他', '');

  @override
  final String label;
  final String extensions;
  const DocumentFileType(this.label, this.extensions);

  @override
  bool get isAll => this == DocumentFileType.all;

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

  @override
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
enum DownloadFileType implements FileTypeFilter {
  all('全部', ''),
  installer('APK', 'APK, EXE, MSI'),
  archive('压缩包', 'ZIP, RAR, 7Z'),
  document('文档', 'PDF, DOC, XLS'),
  image('图片', 'JPG, PNG, GIF'),
  media('视频', 'MP3, MP4, AVI'),
  other('其他', '');

  @override
  final String label;
  final String extensions;
  const DownloadFileType(this.label, this.extensions);

  @override
  bool get isAll => this == DownloadFileType.all;

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

  @override
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
  bool _isRefreshing = false; // 后台刷新状态（不影响列表显示）
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

  // 批量操作相关（SelectionController 内部管理 isSelectionMode 状态）
  final SelectionController _selectionController = SelectionController();

  // 文件显示设置
  bool _showFullPath = false;

  // 过滤后的文件列表（按搜索和文件类型筛选）
  List<FileItem> get _filteredFiles {
    var result = _files;

    // 按文件类型筛选
    if (widget.categoryType == CategoryType.documents &&
        _documentTypeFilter != DocumentFileType.all) {
      result =
          result.where((f) => _documentTypeFilter.matches(f.name)).toList();
    } else if (widget.categoryType == CategoryType.downloads &&
        _downloadTypeFilter != DownloadFileType.all) {
      result =
          result.where((f) => _downloadTypeFilter.matches(f.name)).toList();
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
    return FileGroupingUtil.groupByModifiedDate(_filteredFiles);
  }

  @override
  void initState() {
    super.initState();
    // 监听SelectionController变化并同步状态
    _selectionController.selectedNotifier.addListener(_onSelectionChanged);
    // 监听PageSettingsService变化，当设置改变时重新排序
    PageSettingsService().addListener(_onPageSettingsChanged);
    // 监听ViewModel变化，当文件列表更新时同步本地状态
    widget.viewModel.addListener(_onViewModelChanged);

    // 加载显示设置
    _loadDisplaySettings();
    categoryInfo = CategoryInfo.getInfoByType(widget.categoryType)!;
    _loadFileTypeFilter();
    _loadCategoryFiles();
  }

  /// 加载显示设置
  Future<void> _loadDisplaySettings() async {
    final displaySettings = FileDisplaySettingsService();
    final showFullPath = await displaySettings.getShowFullPath();
    if (mounted) {
      setState(() {
        _showFullPath = showFullPath;
      });
    }
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
            logger.d(
                'Updated file in category page: $oldPath -> ${newFile.path}');
          }
        });
      }
    }
  }

  /// 页面设置改变回调
  void _onPageSettingsChanged() {
    // 使用postFrameCallback避免在build期间调用setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _files.isNotEmpty) {
        _applySorting();
      }
    });
  }

  /// 选择状态改变回调
  void _onSelectionChanged() {
    setState(() {
      // SelectionController内部已经管理了选择状态，这里只需要触发界面更新
      // 不再需要手动管理 _isSelectionMode
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _selectionController.selectedNotifier.removeListener(_onSelectionChanged);
    _selectionController.dispose();
    PageSettingsService().removeListener(_onPageSettingsChanged);
    widget.viewModel.removeListener(_onViewModelChanged);
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

  /// 根据分类类型获取PageId
  PageId _getPageIdForCategory() {
    switch (widget.categoryType) {
      case CategoryType.images:
        return PageId.categoryImages;
      case CategoryType.documents:
        return PageId.categoryDocuments;
      case CategoryType.music:
        return PageId.categoryMusic;
      case CategoryType.video:
        return PageId.categoryVideo;
      case CategoryType.downloads:
        return PageId.categoryDownloads;
    }
  }

  /// 获取当前页面是否为网格视图
  bool get _isGridView {
    final pageId = _getPageIdForCategory();
    return PageSettingsService().getViewMode(pageId) == ViewMode.grid;
  }

  /// 获取当前页面是否启用分组
  bool get _isGroupEnabled {
    final pageId = _getPageIdForCategory();
    return PageSettingsService().getGroupEnabled(pageId);
  }

  /// 获取统一视图配置（包含简洁模式设置）
  UnifiedViewConfig _getViewConfig(BuildContext context) {
    final pageId = _getPageIdForCategory();
    // 仅图片和视频分类使用简洁模式设置
    final shouldUseCompactMode = (widget.categoryType == CategoryType.images ||
            widget.categoryType == CategoryType.video) &&
        _isGridView;

    if (shouldUseCompactMode) {
      // 从设置服务获取是否显示文件信息
      final showFileInfo = PageSettingsService().getGridShowFileInfo(pageId);
      return UnifiedViewConfig.fromContext(context, compactMode: !showFileInfo);
    }

    return UnifiedViewConfig.fromContext(context);
  }

  /// 将CategoryType转换为FileCategory枚举
  FileCategory _getCategoryEnumFromType(CategoryType type) {
    switch (type) {
      case CategoryType.images:
        return FileCategory.image;
      case CategoryType.video:
        return FileCategory.video;
      case CategoryType.music:
        return FileCategory.audio;
      case CategoryType.documents:
        return FileCategory.document;
      case CategoryType.downloads:
        return FileCategory.other; // downloads没有直接对应，使用other
    }
  }

  /// 加载分类文件
  Future<void> _loadCategoryFiles({bool forceRefresh = false}) async {
    // Step 0: 优先检查综合扫描的缓存统计
    if (!forceRefresh) {
      final cacheService = CategoryFileCacheService();
      final hasCacheStats = await cacheService.hasCache();

      if (hasCacheStats) {
        // 有综合扫描的缓存统计，显示提示信息
        final categoryCount = await cacheService.getCategoryCount(
          _getCategoryEnumFromType(widget.categoryType),
        );

        if (categoryCount != null && categoryCount > 0) {
          logger.i(
            'Found comprehensive scan cache: $categoryCount files for ${categoryInfo.name}',
          );

          // 在UI上显示友好提示
          if (mounted) {
            setState(() {
              _loadingProgress =
                  '已发现 $categoryCount 个${categoryInfo.name}，正在加载...';
            });
          }
        }
      }
    }

    // 如果是强制刷新，跳过缓存
    if (!forceRefresh) {
      // Step 1: 尝试加载缓存
      final cached = await _loadFromCache();
      if (cached.isNotEmpty) {
        // 应用页面级排序
        final pageId = _getPageIdForCategory();
        final sortType = PageSettingsService().getSortType(pageId);
        FileComparatorUtil.sortFilesInPlace(cached, sortType);

        setState(() {
          _files = cached;
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
      // 强制刷新：后台刷新，保持列表可见
      await _clearCache();
      setState(() {
        _isRefreshing = true;
        _errorMessage = '';
        _loadingProgress = '正在为您刷新页面列表，请稍等...';
      });
    }

    // Step 2: 后台扫描最新数据
    try {
      logger.i('Loading files for category: ${categoryInfo.name}');

      // 显示扫描进度
      if (_isLoading || _isRefreshing) {
        setState(() {
          _loadingProgress = _isRefreshing
              ? '正在为您刷新页面列表，请稍等...'
              : '正在扫描${categoryInfo.name}文件...';
        });
      }

      final files = await widget.presenter.scanFilesByCategory(
        widget.categoryType,
      );

      // Step 3: 更新UI和缓存
      // 应用页面级排序
      final pageId = _getPageIdForCategory();
      final sortType = PageSettingsService().getSortType(pageId);
      FileComparatorUtil.sortFilesInPlace(files, sortType);

      // 计算总大小
      int totalSize = 0;
      for (final file in files) {
        if (!file.isDirectory) {
          totalSize += file.size;
        }
      }
      final sizeStr = FileSizeFormatter.formatBytes(totalSize);

      setState(() {
        _files = files;
        _isLoading = false;
        _isRefreshing = false;
        _loadingProgress =
            '找到 ${files.length} 个${categoryInfo.name}文件    $sizeStr';
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
        _isRefreshing = false;
        _loadingProgress = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 每次构建时检查并更新显示设置
    _loadDisplaySettings();

    return ChangeNotifierProvider<FileViewModel>.value(
      value: widget.viewModel,
      child: Consumer<PageSettingsService>(
        builder: (context, pageSettingsService, _) {
          return PopScope(
            canPop: !_selectionController.isSelectionMode,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              // 如果在选择模式下，退出选择模式
              if (_selectionController.isSelectionMode) {
                setState(() {
                  _selectionController.clear();
                });
              }
            },
            child: Scaffold(
              appBar: AppBar(
                leading: _selectionController.isSelectionMode
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 22),
                        onPressed: () {
                          setState(() {
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
                title: _selectionController.isSelectionMode
                    ? Text('已选择 ${_selectionController.count} 项')
                    : Builder(
                        builder: (context) {
                          final isDark =
                              Theme.of(context).brightness == Brightness.dark;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? categoryInfo.iconColor.withValues(
                                          alpha: 0.2) // 深色模式：20%主题色透明度
                                      : categoryInfo
                                          .backgroundColor, // 浅色模式：原背景色
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  categoryInfo.icon,
                                  size: 20,
                                  color: isDark
                                      ? categoryInfo
                                          .backgroundColor // 深色模式：使用原背景色（更浅）
                                      : categoryInfo.iconColor, // 浅色模式：原图标色
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(categoryInfo.name),
                            ],
                          );
                        },
                      ),
                titleSpacing: 0,
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _selectionController.isSelectionMode
                          ? [
                              // 多选模式下的操作按钮
                              // 全选/取消全选按钮
                              IconButton(
                                icon: Icon(
                                  _selectionController.count ==
                                          _filteredFiles.length
                                      ? Icons.deselect
                                      : Icons.select_all,
                                ),
                                onPressed: () {
                                  if (_selectionController.count ==
                                      _filteredFiles.length) {
                                    // 取消全选
                                    _selectionController.clear();
                                  } else {
                                    // 全选 - 直接使用selectAll方法
                                    _selectionController.selectAll(
                                      _filteredFiles
                                          .map((f) => f.path)
                                          .toList(),
                                    );
                                  }
                                },
                                tooltip: _selectionController.count ==
                                        _filteredFiles.length
                                    ? '取消全选'
                                    : '全选',
                              ),
                            ]
                          : [
                              // 正常模式下的操作按钮（使用统一的FileToolbar组件）
                              FileToolbar(
                                pageId: _getPageIdForCategory(),
                                showBackButton: false, // 类别页不需要返回按钮
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
              bottomNavigationBar: _selectionController.isSelectionMode
                  ? _buildSelectionBottomBar()
                  : null,
            ),
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
        // 统计信息栏（刷新时显示提示，完成后显示统计）
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: categoryInfo.backgroundColor.withValues(alpha: 0.3),
          child: Row(
            children: [
              // 刷新时显示加载指示器
              if (_isRefreshing) ...[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(categoryInfo.iconColor),
                  ),
                ),
              ] else
                Icon(categoryInfo.icon,
                    size: 16, color: categoryInfo.iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isRefreshing
                          ? _loadingProgress
                          : (_isSearchMode && _searchQuery.isNotEmpty
                              ? '找到 ${_filteredFiles.length} 个匹配文件（共${_files.length}个）'
                              : _loadingProgress.isNotEmpty
                                  ? _loadingProgress
                                  : '找到 ${_files.length} 个${categoryInfo.name}文件    ${_formatTotalSize()}'),
                      style: TextStyle(
                        color: categoryInfo.iconColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
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
          child: GestureDetector(
            // 左右滑动切换文件类型Tab（文档和下载分类）
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) return;

              final velocity = details.primaryVelocity!;
              final isSwipeRight = velocity > 500; // 右滑
              final isSwipeLeft = velocity < -500; // 左滑

              // 搜索模式下禁用手势
              if (_isSearchMode) return;

              // 文档分类：切换文档类型Tab
              if (widget.categoryType == CategoryType.documents) {
                final availableTypes = _getAvailableDocumentTypes();
                if (availableTypes.length <= 1) return;

                final currentIndex =
                    availableTypes.indexOf(_documentTypeFilter);
                if (currentIndex == -1) return;

                if (isSwipeLeft && currentIndex < availableTypes.length - 1) {
                  // 左滑切换到下一个类型
                  setState(() {
                    _documentTypeFilter = availableTypes[currentIndex + 1];
                  });
                  _saveFileTypeFilter();
                } else if (isSwipeRight && currentIndex > 0) {
                  // 右滑切换到上一个类型
                  setState(() {
                    _documentTypeFilter = availableTypes[currentIndex - 1];
                  });
                  _saveFileTypeFilter();
                }
              }
              // 下载分类：切换下载类型Tab
              else if (widget.categoryType == CategoryType.downloads) {
                final availableTypes = _getAvailableDownloadTypes();
                if (availableTypes.length <= 1) return;

                final currentIndex =
                    availableTypes.indexOf(_downloadTypeFilter);
                if (currentIndex == -1) return;

                if (isSwipeLeft && currentIndex < availableTypes.length - 1) {
                  // 左滑切换到下一个类型
                  setState(() {
                    _downloadTypeFilter = availableTypes[currentIndex + 1];
                  });
                  _saveFileTypeFilter();
                } else if (isSwipeRight && currentIndex > 0) {
                  // 右滑切换到上一个类型
                  setState(() {
                    _downloadTypeFilter = availableTypes[currentIndex - 1];
                  });
                  _saveFileTypeFilter();
                }
              }
            },
            child: RefreshIndicator(
              onRefresh: () => _loadCategoryFiles(forceRefresh: true),
              // 启用分组时（无论列表还是网格模式）都使用分组视图
              child: _isGroupEnabled
                  ? _buildGroupedView()
                  : FileCollectionView(
                      items: _filteredFiles,
                      gridMode: _isGridView,
                      config: _getViewConfig(context),
                      padding: _isGridView
                          ? const EdgeInsets.all(8)
                          : const EdgeInsets.symmetric(vertical: 0),
                      // 增加预构建范围以改善滚动体验
                      cacheExtent: _isGridView ? 1000.0 : 600.0,
                      selectionController: _selectionController,
                      // 列表模式显示选项
                      showFullPath:
                          !_isGridView && _showFullPath, // 只在列表模式下显示路径
                      showFavoriteButton: true,
                      isFavorite: (path) =>
                          widget.viewModel.isFavoriteFile(path),
                      onFavoriteToggle: (file) async {
                        return await widget.presenter.toggleFavoriteFile(file);
                      },
                      useUnifiedGridItem: true,
                      onTap: (file) {
                        if (!_selectionController.isSelectionMode) {
                          // 添加到最近访问记录
                          widget.presenter.addToRecentFiles(file);
                          _previewFile(file);
                        }
                      },
                      // onLongPress 不再需要，FileCollectionView 内部处理
                    ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建批量操作底部工具栏
  Widget _buildSelectionBottomBar() {
    final batchService = _getBatchOperationsService();
    // 使用存储根目录作为移动/复制的起始路径
    final storagePath = '/storage/emulated/0';
    return SelectionBottomBar(
      selectedPaths: _selectionController.selected,
      isAllFavorite:
          batchService.isAllSelectedFavorite(_selectionController.selected),
      onCopy: () =>
          batchService.batchCopy(_selectionController.selected, storagePath),
      onRename: () => batchService.batchRename(_selectionController.selected),
      onShare: () => batchService.batchShare(_selectionController.selected),
      onMove: () =>
          batchService.batchMove(_selectionController.selected, storagePath),
      onToggleFavorite: () =>
          batchService.batchToggleFavorite(_selectionController.selected),
      onDelete: () => batchService.batchDelete(_selectionController.selected),
    );
  }

  /// 获取批量操作服务实例
  BatchOperationsService _getBatchOperationsService() {
    return BatchOperationsService(
      context: context,
      viewModel: widget.viewModel,
      presenter: widget.presenter,
      onRefresh: () async {
        await _loadCategoryFiles(forceRefresh: true);
      },
      onExitSelectionMode: () {
        setState(() {
          _selectionController.clear();
        });
      },
    );
  }

  /// 获取可用的文档类型列表（过滤掉没有文件的类型）
  List<DocumentFileType> _getAvailableDocumentTypes() {
    final typeCounts = <DocumentFileType, int>{};
    for (final type in DocumentFileType.values) {
      final count = _files.where((file) => type.matches(file.name)).length;
      typeCounts[type] = count;
    }

    return DocumentFileType.values
        .where((type) => type.isAll || (typeCounts[type] ?? 0) > 0)
        .toList();
  }

  /// 获取可用的下载类型列表（过滤掉没有文件的类型）
  List<DownloadFileType> _getAvailableDownloadTypes() {
    final typeCounts = <DownloadFileType, int>{};
    for (final type in DownloadFileType.values) {
      final count = _files.where((file) => type.matches(file.name)).length;
      typeCounts[type] = count;
    }

    return DownloadFileType.values
        .where((type) => type.isAll || (typeCounts[type] ?? 0) > 0)
        .toList();
  }

  /// 构建文件类型筛选标签
  Widget _buildFileTypeChips() {
    if (widget.categoryType == CategoryType.documents) {
      return _buildGenericTypeChips<DocumentFileType>(
        types: DocumentFileType.values,
        currentFilter: _documentTypeFilter,
        onFilterChanged: (type) {
          setState(() {
            _documentTypeFilter = type;
          });
          _saveFileTypeFilter();
        },
      );
    } else if (widget.categoryType == CategoryType.downloads) {
      return _buildGenericTypeChips<DownloadFileType>(
        types: DownloadFileType.values,
        currentFilter: _downloadTypeFilter,
        onFilterChanged: (type) {
          setState(() {
            _downloadTypeFilter = type;
          });
          _saveFileTypeFilter();
        },
      );
    }
    return const SizedBox.shrink();
  }

  /// 通用的文件类型筛选标签构建方法
  Widget _buildGenericTypeChips<T extends FileTypeFilter>({
    required List<T> types,
    required T currentFilter,
    required ValueChanged<T> onFilterChanged,
  }) {
    // 计算每个类型的文件数量
    final typeCounts = <T, int>{};
    for (final type in types) {
      final count = _files.where((file) => type.matches(file.name)).length;
      typeCounts[type] = count;
    }

    // 过滤掉没有文件的类型（除了"全部"）
    final availableTypes = types
        .where((type) => type.isAll || (typeCounts[type] ?? 0) > 0)
        .toList();

    // 如果只有"全部"一个选项，则不显示筛选栏
    if (availableTypes.length <= 1) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: availableTypes.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final type = availableTypes[index];
          final isSelected = currentFilter == type;

          return FilterChip(
            label: Text(type.label, style: const TextStyle(fontSize: 14)),
            selected: isSelected,
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            labelPadding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            selectedColor: categoryInfo.iconColor.withValues(alpha: 0.2),
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
                onFilterChanged(type);
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
    final groupKeys = FileGroupingUtil.dateGroupKeys;

    // 构建 FileGroup 列表
    final fileGroups =
        groupKeys.where((key) => groups.containsKey(key)).map((key) {
      return FileGroup(
        key: key,
        title: '$key（${groups[key]!.length}个文件）',
        items: groups[key]!,
        isCollapsible: false, // 不使用折叠功能，保持与原来一致
      );
    }).toList();

    return FileCollectionView(
      groups: fileGroups,
      gridMode: _isGridView,
      config: _getViewConfig(context),
      padding: _isGridView
          ? const EdgeInsets.symmetric(vertical: 4)
          : const EdgeInsets.symmetric(vertical: 0),
      // 增加预构建范围以改善滚动体验
      cacheExtent: _isGridView ? 1000.0 : 600.0,
      selectionController: _selectionController,
      // 显示选项
      showFullPath: !_isGridView && _showFullPath, // 只在列表模式下显示路径
      showFavoriteButton: true,
      isFavorite: (path) => widget.viewModel.isFavoriteFile(path),
      onFavoriteToggle: (file) async {
        return await widget.presenter.toggleFavoriteFile(file);
      },
      useUnifiedGridItem: true,
      onTap: (file) {
        if (!_selectionController.isSelectionMode) {
          // 添加到最近访问记录
          widget.presenter.addToRecentFiles(file);
          _previewFile(file);
        }
      },
      // onLongPress 不再需要，FileCollectionView 内部处理
    );
  }

  /// 格式化总大小
  String _formatTotalSize() {
    return FileSizeFormatter.formatTotalSize(
      _files.map((file) => file.size).toList(),
    );
  }

  /// 显示排序选项
  void _showSortOptions() {
    final pageId = _getPageIdForCategory();
    final currentSortType = PageSettingsService().getSortType(pageId);
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
                  PageSettingsService().setSortType(pageId, SortType.name);
                  _applySorting();
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
                      .setSortType(pageId, SortType.modifiedTime);
                  _applySorting();
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
                  PageSettingsService().setSortType(pageId, SortType.size);
                  _applySorting();
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
                  PageSettingsService().setSortType(pageId, SortType.fileType);
                  _applySorting();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 应用排序
  void _applySorting() {
    setState(() {
      final pageId = _getPageIdForCategory();
      final sortType = PageSettingsService().getSortType(pageId);
      FileComparatorUtil.sortFilesInPlace(_files, sortType);
    });
  }

  /// 预览文件
  void _previewFile(FileItem file) async {
    logger.d('Previewing file: ${file.path}');

    // 对于图片、视频和音频，传递文件列表以支持滑动切换
    if (widget.categoryType == CategoryType.images ||
        widget.categoryType == CategoryType.video ||
        widget.categoryType == CategoryType.music) {
      // 图片、视频、音乐分类：传递所有文件
      final fileList = _filteredFiles;
      final initialIndex = fileList.indexWhere((f) => f.path == file.path);

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

      // 如果文件被修改（复制、移动、重命名），刷新列表
      if (needsRefresh == true) {
        logger.d('File modified in preview, refreshing category list');
        await _loadCategoryFiles(forceRefresh: true);
      }
    } else if (widget.categoryType == CategoryType.downloads &&
        (FileUtils.isImageFile(file.name) ||
            FileUtils.isVideoFile(file.name) ||
            FileUtils.isAudioFile(file.name))) {
      // 下载分类：根据当前文件类型只过滤同类型文件
      final mediaFiles = _filteredFiles.where((f) {
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

      final needsRefresh = await Navigator.of(context).push<bool>(
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

      // 如果文件被修改，刷新列表
      if (needsRefresh == true) {
        logger.d('File modified in preview, refreshing category list');
        await _loadCategoryFiles(forceRefresh: true);
      }
    } else {
      // 其他类型保持单文件模式
      final needsRefresh = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => FilePreviewPage(
            file: file,
            viewModel: widget.viewModel,
            presenter: widget.presenter,
          ),
        ),
      );

      // 如果文件被修改，刷新列表
      if (needsRefresh == true) {
        logger.d('File modified in preview, refreshing category list');
        await _loadCategoryFiles(forceRefresh: true);
      }
    }
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
