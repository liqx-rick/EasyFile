import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/file_item_tile.dart';
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

  // 视图模式
  bool _isGridView = false;

  // 搜索
  bool _isSearchMode = false;
  String _searchQuery = '';

  // 分组相关
  bool _groupByDate = false;

  // 文件类型筛选
  DocumentFileType _documentTypeFilter = DocumentFileType.all;
  DownloadFileType _downloadTypeFilter = DownloadFileType.all;

  // 批量操作相关
  bool _isSelectionMode = false;
  Set<String> _selectedFiles = {}; // 使用Set存储选中文件的路径

  // 计算选中文件的总大小
  int get _selectedTotalSize {
    int total = 0;
    for (final path in _selectedFiles) {
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
    categoryInfo = CategoryInfo.getInfoByType(widget.categoryType)!;
    _loadViewPreference();
    _loadGroupPreference();
    _loadFileTypeFilter();
    _loadCategoryFiles();
  }

  /// 加载视图偏好
  Future<void> _loadViewPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'category_view_${widget.categoryType.name}';
      final savedView = prefs.getBool(key);

      setState(() {
        // 如果有保存的偏好就用保存的，否则根据分类类型自动选择
        if (savedView != null) {
          _isGridView = savedView;
        } else {
          _isGridView = _getDefaultViewMode();
        }
      });
    } catch (e) {
      logger.e('Failed to load view preference: $e');
      // 出错时使用默认视图
      setState(() {
        _isGridView = _getDefaultViewMode();
      });
    }
  }

  /// 加载分组偏好
  Future<void> _loadGroupPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'category_group_by_date_${widget.categoryType.name}';
      final savedGroup = prefs.getBool(key) ?? false;

      setState(() {
        _groupByDate = savedGroup;
      });
    } catch (e) {
      logger.e('Failed to load group preference: $e');
    }
  }

  /// 保存视图偏好
  Future<void> _saveViewPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'category_view_${widget.categoryType.name}';
      await prefs.setBool(key, _isGridView);
    } catch (e) {
      logger.e('Failed to save view preference: $e');
    }
  }

  /// 保存分组偏好
  Future<void> _saveGroupPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'category_group_by_date_${widget.categoryType.name}';
      await prefs.setBool(key, _groupByDate);
    } catch (e) {
      logger.e('Failed to save group preference: $e');
    }
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

  /// 获取默认视图模式（图片和视频默认网格，其他默认列表）
  bool _getDefaultViewMode() {
    return widget.categoryType == CategoryType.images ||
        widget.categoryType == CategoryType.video;
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
      child: Scaffold(
        appBar: AppBar(
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = false;
                      _selectedFiles.clear();
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
              ? Text('已选择 ${_selectedFiles.length} 项')
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
                            _selectedFiles.length == _filteredFiles.length
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 22,
                          ),
                          onPressed: () {
                            setState(() {
                              if (_selectedFiles.length ==
                                  _filteredFiles.length) {
                                _selectedFiles.clear();
                              } else {
                                _selectedFiles = _filteredFiles
                                    .map((f) => f.path)
                                    .toSet();
                              }
                            });
                          },
                          tooltip:
                              _selectedFiles.length == _filteredFiles.length
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
                        // 正常模式下的操作按钮
                        // 搜索按钮
                        IconButton(
                          icon: const Icon(Icons.search, size: 22),
                          onPressed: () {
                            setState(() {
                              _isSearchMode = !_isSearchMode;
                              if (!_isSearchMode) _searchQuery = '';
                            });
                          },
                          tooltip: '搜索',
                          padding: EdgeInsets.zero,
                          visualDensity: const VisualDensity(
                            horizontal: -4,
                            vertical: -4,
                          ),
                        ),
                        // 视图切换按钮
                        IconButton(
                          icon: Icon(
                            _isGridView ? Icons.view_list : Icons.grid_view,
                            size: 22,
                          ),
                          onPressed: () {
                            setState(() {
                              _isGridView = !_isGridView;
                            });
                            _saveViewPreference();
                          },
                          tooltip: _isGridView ? '列表视图' : '网格视图',
                          padding: EdgeInsets.zero,
                          visualDensity: const VisualDensity(
                            horizontal: -4,
                            vertical: -4,
                          ),
                        ),
                      ],
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // 搜索框
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: _isSearchMode ? 56 : 0,
              child: _isSearchMode
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: '搜索${categoryInfo.name}...',
                          hintStyle: const TextStyle(fontSize: 14),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Theme.of(context).primaryColor,
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () {
                              setState(() {
                                _searchQuery = '';
                                _isSearchMode = false;
                              });
                            },
                            tooltip: '关闭搜索',
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                        style: const TextStyle(fontSize: 14),
                        onChanged: (query) {
                          setState(() {
                            _searchQuery = query;
                          });
                        },
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // 主体内容
            Expanded(child: _buildBody()),
          ],
        ),
        // 批量操作底部工具栏
        bottomNavigationBar: _isSelectionMode
            ? _buildSelectionBottomBar()
            : null,
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
              const SizedBox(width: 8),
              // 分组切换按钮（仅在列表模式下显示）
              if (!_isGridView && !_isSearchMode)
                InkWell(
                  onTap: () {
                    setState(() {
                      _groupByDate = !_groupByDate;
                    });
                    _saveGroupPreference();
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _groupByDate ? Icons.view_list : Icons.view_agenda,
                      size: 18,
                      color: categoryInfo.iconColor,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              // 排序按钮
              InkWell(
                onTap: _showSortOptions,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.sort,
                    size: 18,
                    color: categoryInfo.iconColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 刷新按钮
              InkWell(
                onTap: () => _loadCategoryFiles(forceRefresh: true),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.refresh,
                    size: 18,
                    color: categoryInfo.iconColor,
                  ),
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

        // 文件列表或网格
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadCategoryFiles(forceRefresh: true),
            child: _isGridView ? _buildGridView() : _buildListView(),
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
                '${_selectedFiles.length} 个文件 · ${_formatSize(_selectedTotalSize)}',
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
            if (_selectedFiles.length == 1)
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
            if (_selectedFiles.length == 1)
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
              onPressed: _selectedFiles.isEmpty ? null : _batchShare,
              tooltip: '分享',
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
            // 移动按钮
            IconButton(
              icon: const Icon(Icons.drive_file_move),
              onPressed: _selectedFiles.isEmpty ? null : _batchMove,
              tooltip: '移动',
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
            // 删除按钮
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selectedFiles.isEmpty ? null : _batchDelete,
              tooltip: '删除',
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
          ],
        ),
      ),
    );
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
    if (_selectedFiles.isEmpty) return;

    try {
      // 调用presenter批量分享
      final filePaths = _selectedFiles.toList();
      final success = await widget.presenter.batchShareFiles(filePaths);

      if (mounted) {
        if (success) {
          // 分享成功后退出多选模式
          setState(() {
            _isSelectionMode = false;
            _selectedFiles.clear();
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('分享失败，请检查是否有有效的文件'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 批量移动
  void _batchMove() async {
    if (_selectedFiles.isEmpty) return;

    // 使用第一个选中文件的父目录作为初始路径
    String initialPath = widget.viewModel.currentPath;
    if (initialPath.isEmpty && _selectedFiles.isNotEmpty) {
      final firstFile = _selectedFiles.first;
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

    try {
      // 调用presenter批量移动
      final filePaths = _selectedFiles.toList();
      final results = await widget.presenter.batchMoveFiles(
        filePaths,
        destinationPath,
      );

      if (mounted) {
        Navigator.pop(context); // 关闭进度对话框

        // 统计成功和失败的数量
        final successCount = results.values.where((v) => v).length;
        final failCount = results.length - successCount;

        // 刷新文件列表
        await _loadCategoryFiles(forceRefresh: true);

        // 退出多选模式
        setState(() {
          _isSelectionMode = false;
          _selectedFiles.clear();
        });

        // 显示结果提示
        if (failCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('成功移动 $successCount 个文件'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('成功移动 $successCount 个文件，失败 $failCount 个'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 关闭进度对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移动失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 批量删除
  void _batchDelete() async {
    if (_selectedFiles.isEmpty) return;

    // 使用增强的删除确认对话框
    final confirmed = await EnhancedDeleteDialog.showBatchDeleteConfirmation(
      context: context,
      paths: _selectedFiles.toList(),
      fileCount: _selectedFiles.length,
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

    try {
      // 调用presenter批量删除
      final filePaths = _selectedFiles.toList();
      final results = await widget.presenter.batchDeleteFiles(filePaths);

      if (mounted) {
        Navigator.pop(context); // 关闭进度对话框

        // 统计成功和失败的数量
        final successCount = results.values.where((v) => v).length;
        final failCount = results.length - successCount;

        // 刷新文件列表
        await _loadCategoryFiles(forceRefresh: true);

        // 退出多选模式
        setState(() {
          _isSelectionMode = false;
          _selectedFiles.clear();
        });

        // 显示结果提示
        if (failCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('成功删除 $successCount 个文件'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('成功删除 $successCount 个文件，失败 $failCount 个'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 关闭进度对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 复制文件（单个文件）
  void _copyFile() async {
    if (_selectedFiles.length != 1) return;

    final filePath = _selectedFiles.first;
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

    try {
      // 调用presenter复制文件
      final targetPath = path.join(destinationPath, path.basename(filePath));
      final success = await widget.presenter.copyFile(file, targetPath);

      if (mounted) {
        Navigator.pop(context); // 关闭进度对话框

        if (success) {
          // 刷新文件列表
          await _loadCategoryFiles(forceRefresh: true);

          // 退出多选模式
          setState(() {
            _isSelectionMode = false;
            _selectedFiles.clear();
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('复制成功'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('复制失败'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 关闭进度对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('复制失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 重命名文件（单个文件）
  void _renameFile() async {
    if (_selectedFiles.length != 1) return;

    final filePath = _selectedFiles.first;
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

    try {
      // 调用presenter重命名文件
      final newFileName = newName.trim() + extension;
      final success = await widget.presenter.renameFile(file, newFileName);

      if (mounted) {
        Navigator.pop(context); // 关闭进度对话框

        if (success) {
          // 刷新文件列表
          await _loadCategoryFiles(forceRefresh: true);

          // 退出多选模式
          setState(() {
            _isSelectionMode = false;
            _selectedFiles.clear();
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('重命名成功'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('重命名失败'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 关闭进度对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重命名失败：$e'), backgroundColor: Colors.red),
        );
      }
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

  /// 构建列表视图
  Widget _buildListView() {
    // 如果启用分组，显示分组列表
    if (_groupByDate) {
      return _buildGroupedListView();
    }

    // 否则显示普通列表
    return ListView.builder(
      itemCount: _filteredFiles.length,
      itemBuilder: (context, index) {
        final file = _filteredFiles[index];
        final isSelected = _selectedFiles.contains(file.path);

        return InkWell(
          onTap: () {
            if (_isSelectionMode) {
              // 多选模式下，点击切换选中状态
              setState(() {
                if (isSelected) {
                  _selectedFiles.remove(file.path);
                } else {
                  _selectedFiles.add(file.path);
                }
              });
            } else {
              // 正常模式下，点击预览文件
              _previewFile(file);
            }
          },
          onLongPress: () {
            // 长按进入多选模式并选中当前文件
            if (!_isSelectionMode) {
              setState(() {
                _isSelectionMode = true;
                _selectedFiles.add(file.path);
              });
            }
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 文件列表项（不显示收藏按钮）
              Expanded(
                child: FileItemTile(
                  file: file,
                  showFullPath: true,
                  isFavorite: false, // 收藏按钮外置，这里不显示
                  onFavoriteToggle: null, // 收藏按钮外置
                  onTap: null, // 由外层InkWell处理
                  onLongPress: null, // 由外层InkWell处理
                ),
              ),
              // 收藏按钮（始终显示）
              IconButton(
                icon: Icon(
                  widget.viewModel.isFavoriteFile(file.path)
                      ? Icons.star
                      : Icons.star_border,
                  color: widget.viewModel.isFavoriteFile(file.path)
                      ? Colors.amber
                      : Colors.grey,
                  size: 20,
                ),
                onPressed: () async {
                  final isFavorite = await widget.presenter.toggleFavoriteFile(
                    file,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isFavorite ? '已添加到收藏' : '已取消收藏'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                },
                tooltip: widget.viewModel.isFavoriteFile(file.path)
                    ? '取消收藏'
                    : '收藏',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              // 多选模式下显示复选框（在文件行末尾）
              if (_isSelectionMode)
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedFiles.add(file.path);
                        } else {
                          _selectedFiles.remove(file.path);
                        }
                      });
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: -4,
                      vertical: -4,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 构建按日期分组的列表视图
  Widget _buildGroupedListView() {
    final groups = _groupedFiles;
    final groupKeys = ['今天', '昨天', '本周', '本月', '更早'];
    final existingGroups = groupKeys
        .where((key) => groups.containsKey(key))
        .toList();

    return ListView.builder(
      itemCount: existingGroups
          .map((key) => groups[key]!.length + 1)
          .fold<int>(0, (a, b) => a + b),
      itemBuilder: (context, index) {
        // 计算当前索引属于哪个分组
        int currentIndex = index;
        for (final groupKey in existingGroups) {
          final groupFiles = groups[groupKey]!;
          final groupItemCount = groupFiles.length + 1; // +1 for header

          if (currentIndex == 0) {
            // 分组标题
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
              child: Row(
                children: [
                  Text(
                    groupKey,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${groupFiles.length} 个文件',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          } else if (currentIndex < groupItemCount) {
            // 分组中的文件项
            final file = groupFiles[currentIndex - 1];
            final isSelected = _selectedFiles.contains(file.path);

            return InkWell(
              onTap: () {
                if (_isSelectionMode) {
                  // 多选模式下，点击切换选中状态
                  setState(() {
                    if (isSelected) {
                      _selectedFiles.remove(file.path);
                    } else {
                      _selectedFiles.add(file.path);
                    }
                  });
                } else {
                  // 正常模式下，点击预览文件
                  _previewFile(file);
                }
              },
              onLongPress: () {
                // 长按进入多选模式并选中当前文件
                if (!_isSelectionMode) {
                  setState(() {
                    _isSelectionMode = true;
                    _selectedFiles.add(file.path);
                  });
                }
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 文件列表项（不显示收藏按钮）
                  Expanded(
                    child: FileItemTile(
                      file: file,
                      showFullPath: true,
                      isFavorite: false, // 收藏按钮外置，这里不显示
                      onFavoriteToggle: null, // 收藏按钮外置
                      onTap: null, // 由外层InkWell处理
                      onLongPress: null, // 由外层InkWell处理
                    ),
                  ),
                  // 收藏按钮（始终显示）
                  IconButton(
                    icon: Icon(
                      widget.viewModel.isFavoriteFile(file.path)
                          ? Icons.star
                          : Icons.star_border,
                      color: widget.viewModel.isFavoriteFile(file.path)
                          ? Colors.amber
                          : Colors.grey,
                      size: 20,
                    ),
                    onPressed: () async {
                      final isFavorite = await widget.presenter
                          .toggleFavoriteFile(file);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(isFavorite ? '已添加到收藏' : '已取消收藏'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    tooltip: widget.viewModel.isFavoriteFile(file.path)
                        ? '取消收藏'
                        : '收藏',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  // 多选模式下显示复选框（在文件行末尾）
                  if (_isSelectionMode)
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedFiles.add(file.path);
                            } else {
                              _selectedFiles.remove(file.path);
                            }
                          });
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: const VisualDensity(
                          horizontal: -4,
                          vertical: -4,
                        ),
                      ),
                    ),
                ],
              ),
            );
          } else {
            currentIndex -= groupItemCount;
          }
        }

        return const SizedBox.shrink();
      },
    );
  }

  /// 构建网格视图
  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85, // 调整为接近正方形，同时保证内容显示完整
      ),
      itemCount: _filteredFiles.length,
      itemBuilder: (context, index) {
        final file = _filteredFiles[index];
        return _buildGridItem(file);
      },
    );
  }

  /// 构建网格项
  Widget _buildGridItem(FileItem file) {
    final isImage = FileUtils.isImageFile(file.name);
    final isVideo = FileUtils.isVideoFile(file.name);
    final isAudio = FileUtils.isAudioFile(file.name);
    final isDocument = FileUtils.isDocumentFile(file.name);
    final isFavorite = widget.viewModel.isFavoriteFile(file.path);
    final isSelected = _selectedFiles.contains(file.path);

    return InkWell(
      onTap: () {
        if (_isSelectionMode) {
          // 多选模式下，点击切换选中状态
          setState(() {
            if (isSelected) {
              _selectedFiles.remove(file.path);
            } else {
              _selectedFiles.add(file.path);
            }
          });
        } else {
          // 正常模式下，点击预览文件
          _previewFile(file);
        }
      },
      onLongPress: () {
        // 长按进入多选模式并选中当前文件
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            _selectedFiles.add(file.path);
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
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            // 主内容区域
            Padding(
              padding: const EdgeInsets.only(
                top: 28,
                left: 4,
                right: 4,
                bottom: 4,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 缩略图或图标
                  Expanded(
                    child: Center(
                      child: isImage
                          ? ImageThumbnail(imagePath: file.path, size: 80)
                          : isVideo
                          ? RealVideoThumbnail(videoPath: file.path, size: 80)
                          : isAudio
                          ? AudioCoverWidget(audioPath: file.path, size: 64)
                          : isDocument
                          ? DocumentIconWidget(fileName: file.name, size: 64)
                          : Icon(
                              Icons.insert_drive_file,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 文件名
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      file.name,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 文件大小
                  Text(
                    FileUtils.formatFileSize(file.size),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            // 多选模式下在左上角显示复选框
            if (_isSelectionMode)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Transform.scale(
                    scale: 0.9,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selectedFiles.add(file.path);
                          } else {
                            _selectedFiles.remove(file.path);
                          }
                        });
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                    ),
                  ),
                ),
              ),
            // 收藏按钮始终在右上角（多选模式下也显示）
            Positioned(
              top: 4,
              right: 4,
              child: InkWell(
                onTap: () async {
                  final newIsFavorite = await widget.presenter
                      .toggleFavoriteFile(file);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(newIsFavorite ? '已添加到收藏' : '已取消收藏'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    size: 18,
                    color: isFavorite ? Colors.amber : Colors.grey,
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
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sort_by_alpha),
              title: const Text('按名称排序'),
              onTap: () {
                Navigator.pop(context);
                _sortFiles((a, b) => a.name.compareTo(b.name));
              },
            ),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('按修改时间排序'),
              onTap: () {
                Navigator.pop(context);
                _sortFiles((a, b) => b.modified.compareTo(a.modified));
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('按文件大小排序'),
              onTap: () {
                Navigator.pop(context);
                _sortFiles((a, b) => b.size.compareTo(a.size));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 排序文件
  void _sortFiles(int Function(FileItem, FileItem) compare) {
    setState(() {
      _files.sort(compare);
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
