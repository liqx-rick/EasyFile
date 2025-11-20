import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/utils/media_info_extractor.dart';
import 'package:easyfile/ui/widgets/video_player_widget.dart';
import 'package:easyfile/ui/widgets/audio_player_widget.dart';
import 'package:easyfile/ui/widgets/detailed_media_info_view.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:open_file/open_file.dart';
import 'package:pdfx/pdfx.dart';

class FilePreviewPage extends StatefulWidget {
  final FileItem file;
  final List<FileItem>? fileList; // 可选：用于滑动切换
  final int? initialIndex; // 可选：初始索引

  const FilePreviewPage({
    super.key,
    required this.file,
    this.fileList,
    this.initialIndex,
  });

  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  // 滑动切换相关
  late PageController _pageController;
  late int _currentIndex;
  bool _showPageIndicator = true;

  // 预加载管理
  final Map<int, bool> _preloadedIndexes = {};
  static const int _preloadDistance = 2; // 前后各预加载2页
  static const int _cleanupDistance = 3; // 清理距离超过3页的缓存
  int _lastCleanupIndex = -1; // 上次清理时的索引，用于渐进式清理

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? 0;
    _pageController = PageController(initialPage: _currentIndex);

    // 3秒后隐藏页码指示器
    if (widget.fileList != null && widget.fileList!.length > 1) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showPageIndicator = false;
          });
        }
      });

      // 初始化时预加载当前页和相邻页
      _preloadAdjacentPages(_currentIndex);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 预加载相邻页面
  void _preloadAdjacentPages(int centerIndex) {
    if (widget.fileList == null || widget.fileList!.isEmpty) return;

    logger.d('Starting preload for center index: $centerIndex');
    final indicesToPreload = <int>[];

    // 向前预加载（前2页）
    for (int i = 1; i <= _preloadDistance; i++) {
      final prevIndex = centerIndex - i;
      if (prevIndex >= 0) {
        // 检查是否已预加载且成功
        if (_preloadedIndexes[prevIndex] != true) {
          indicesToPreload.add(prevIndex);
          logger.d('Will preload previous page at index $prevIndex');
        } else {
          logger.d('Page $prevIndex already preloaded, skipping');
        }
      }
    }

    // 向后预加载（后2页）
    for (int i = 1; i <= _preloadDistance; i++) {
      final nextIndex = centerIndex + i;
      if (nextIndex < widget.fileList!.length) {
        // 检查是否已预加载且成功
        if (_preloadedIndexes[nextIndex] != true) {
          indicesToPreload.add(nextIndex);
          logger.d('Will preload next page at index $nextIndex');
        } else {
          logger.d('Page $nextIndex already preloaded, skipping');
        }
      }
    }

    logger.d(
        'Total pages to preload: ${indicesToPreload.length}, indices: $indicesToPreload');

    // 异步预加载（避免阻塞UI）
    for (final index in indicesToPreload) {
      _preloadFileAtIndex(index);
    }

    // 清理远离的页面缓存
    _cleanupDistantPages(centerIndex);
  }

  /// 预加载指定索引的文件
  Future<void> _preloadFileAtIndex(int index) async {
    if (_preloadedIndexes[index] == true) {
      logger.d('Index $index already preloaded, skipping');
      return;
    }

    logger.d('Starting preload for index $index');
    _preloadedIndexes[index] = true;
    final file = widget.fileList![index];

    try {
      if (_isImageFile(file.name)) {
        // 预加载图片到Flutter缓存
        final imageFile = File(file.path);
        if (await imageFile.exists()) {
          if (!mounted) return;
          await precacheImage(
            FileImage(imageFile),
            context,
          );
          logger.d(
              '✓ Successfully preloaded IMAGE at index $index: ${file.name}');
        } else {
          logger.w('Image file does not exist at index $index: ${file.path}');
          _preloadedIndexes[index] = false;
        }
      } else if (_isVideoFile(file.name)) {
        // 视频缩略图已由RealVideoThumbnail组件自动缓存
        logger.d(
            '✓ VIDEO at index $index will be loaded on demand: ${file.name}');
      } else if (_isAudioFile(file.name)) {
        logger.d(
            '✓ AUDIO at index $index will be loaded on demand: ${file.name}');
      } else {
        logger.d(
            '✓ FILE at index $index (${file.name}) will be loaded on demand');
      }
      // PDF和文本文件按需加载，不预加载
    } catch (e) {
      logger.e('✗ Failed to preload file at index $index: $e');
      _preloadedIndexes[index] = false;
    }
  }

  /// 清理距离当前页面较远的缓存（渐进式清理策略）
  void _cleanupDistantPages(int currentIndex) {
    // 只在索引变化时执行清理
    if (_lastCleanupIndex == currentIndex) return;

    final direction = currentIndex > _lastCleanupIndex ? 1 : -1; // 1=向右滑，-1=向左滑
    _lastCleanupIndex = currentIndex;

    final keysToRemove = <int>[];

    // 查找需要清理的页面（距离超过cleanupDistance）
    _preloadedIndexes.forEach((index, _) {
      if ((index - currentIndex).abs() > _cleanupDistance) {
        keysToRemove.add(index);
      }
    });

    if (keysToRemove.isNotEmpty) {
      // 按照滑动方向，优先清理最远的页面
      keysToRemove.sort((a, b) {
        final distA = (a - currentIndex).abs();
        final distB = (b - currentIndex).abs();
        return distB.compareTo(distA); // 从远到近排序
      });

      logger.d(
          '🧹 Cleanup triggered at index $currentIndex (direction: ${direction > 0 ? "→" : "←"}), will clean ${keysToRemove.length} pages: $keysToRemove');
    }

    for (final key in keysToRemove) {
      _preloadedIndexes.remove(key);

      // 清理缓存并记录日志
      if (key < widget.fileList!.length) {
        final file = widget.fileList![key];
        if (_isImageFile(file.name)) {
          final imageFile = File(file.path);
          imageCache.evict(FileImage(imageFile));
          logger.d('🗑 Cleaned up IMAGE cache for page $key: ${file.name}');
        } else if (_isVideoFile(file.name)) {
          logger.d(
              '🗑 Cleaned up VIDEO preload record for page $key: ${file.name}');
        } else if (_isAudioFile(file.name)) {
          logger.d(
              '🗑 Cleaned up AUDIO preload record for page $key: ${file.name}');
        } else {
          logger.d('🗑 Cleaned up preload record for page $key: ${file.name}');
        }
      }
    }
  }

  // 辅助方法：判断文件类型
  bool _isImageFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'bmp',
      'webp',
      'svg',
      'ico',
      'tiff',
      'tif',
      'heic',
      'heif'
    ].contains(ext);
  }

  bool _isVideoFile(String fileName) {
    return FileUtils.isVideoFile(fileName);
  }

  bool _isAudioFile(String fileName) {
    return FileUtils.isAudioFile(fileName);
  }

  bool _isTextFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return [
      'txt',
      'md',
      'json',
      'xml',
      'html',
      'css',
      'js',
      'ts',
      'dart',
      'java',
      'py',
      'cpp',
      'c',
      'h',
      'cs',
      'php',
      'yaml',
      'yml',
      'ini',
      'conf',
      'log',
      'csv',
    ].contains(ext);
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有文件列表或只有一个文件，使用原来的单文件模式
    if (widget.fileList == null || widget.fileList!.length <= 1) {
      return _buildSingleFilePreview(context, widget.file);
    }

    // 多文件模式：使用 PageView 支持滑动切换
    return _buildPageViewPreview(context);
  }

  /// 构建支持滑动切换的预览页面
  Widget _buildPageViewPreview(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileList![_currentIndex].name,
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              _getFileTypeDisplayForFile(widget.fileList![_currentIndex]),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showFileInfoForFile(
              context,
              widget.fileList![_currentIndex],
            ),
            tooltip: '文件信息',
          ),
        ],
      ),
      body: Stack(
        children: [
          // PageView 支持滑动切换
          PageView.builder(
            controller: _pageController,
            physics: const BouncingScrollPhysics(), // 启用回弹效果
            itemCount: widget.fileList!.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
                _showPageIndicator = true;
              });

              // 预加载相邻页面
              _preloadAdjacentPages(index);

              // 3秒后隐藏页码
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) {
                  setState(() {
                    _showPageIndicator = false;
                  });
                }
              });
            },
            itemBuilder: (context, index) {
              return _FilePreviewItem(
                file: widget.fileList![index],
                key: ValueKey(widget.fileList![index].path),
              );
            },
          ),

          // 页码指示器
          if (_showPageIndicator && widget.fileList!.length > 1)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _showPageIndicator ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.fileList!.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建单文件预览页面（保持原有逻辑）
  Widget _buildSingleFilePreview(BuildContext context, FileItem file) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(file.name, style: const TextStyle(fontSize: 16)),
            Text(
              _getFileTypeDisplayForFile(file),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showFileInfoForFile(context, file),
            tooltip: '文件信息',
          ),
        ],
      ),
      body: _FilePreviewItem(file: file),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  /// 获取指定文件的类型显示
  String _getFileTypeDisplayForFile(FileItem file) {
    if (_isImageFile(file.name)) return '图片';
    if (_isVideoFile(file.name)) return '视频';
    if (_isAudioFile(file.name)) return '音频';
    if (FileUtils.isPdfFile(file.name)) return 'PDF文档';
    if (FileUtils.isDocumentFile(file.name)) return '文档';
    if (_isTextFile(file.name)) return '文本';
    return '未知类型';
  }

  /// 显示指定文件的信息
  void _showFileInfoForFile(BuildContext context, FileItem file) async {
    // 对于音视频文件，显示详细信息
    if (_isVideoFile(file.name) || _isAudioFile(file.name)) {
      _showDetailedMediaInfoForFile(context, file);
      return;
    }

    // 普通文件显示基本信息
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('文件信息'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInfoRow('文件名', file.name),
            _buildInfoRow('路径', file.path),
            _buildInfoRow(
                '大小', FileSizeFormatter.formatBytesWithSpace(file.size)),
            _buildInfoRow('修改时间', _formatDateTime(file.modified)),
            _buildInfoRow('类型', _getFileTypeDisplayForFile(file)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 显示指定文件的详细媒体信息
  void _showDetailedMediaInfoForFile(
      BuildContext context, FileItem file) async {
    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在加载详细信息...'),
              ],
            ),
          ),
        ),
      ),
    );

    final navigator = Navigator.of(context);

    try {
      final extractor = MediaInfoExtractor();
      final info = _isVideoFile(file.name)
          ? await extractor.extractVideoInfo(file.path)
          : await extractor.extractAudioInfo(file.path);

      if (!mounted) return;
      navigator.pop(); // 关闭加载对话框

      // 显示详细信息
      showDialog(
        context: this.context,
        builder: (context) => Dialog(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
            child: Column(
              children: [
                AppBar(
                  title: const Text('详细信息'),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                Expanded(
                  child: DetailedMediaInfoView(
                    info: info,
                    isVideo: _isVideoFile(file.name),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      navigator.pop(); // 关闭加载对话框
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载详细信息失败: $e')),
      );
    }
  }
}

/// 单个文件预览项组件（用于 PageView）
class _FilePreviewItem extends StatefulWidget {
  final FileItem file;

  const _FilePreviewItem({super.key, required this.file});

  @override
  State<_FilePreviewItem> createState() => __FilePreviewItemState();
}

class __FilePreviewItemState extends State<_FilePreviewItem>
    with AutomaticKeepAliveClientMixin {
  String? _fileContent;
  bool _isLoading = true;
  String? _error;
  PdfController? _pdfController;

  @override
  bool get wantKeepAlive => true; // 保持状态，避免重复加载

  @override
  void initState() {
    super.initState();
    _loadFileContent();
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _loadFileContent() async {
    try {
      logger.d('Loading file content for: ${widget.file.path}');

      // 图片、视频、音频不需要预加载
      if (FileUtils.isImageFile(widget.file.name) ||
          FileUtils.isVideoFile(widget.file.name) ||
          FileUtils.isAudioFile(widget.file.name)) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // PDF 文件
      if (FileUtils.isPdfFile(widget.file.name)) {
        await _loadPdfDocument();
        return;
      }

      // 文档文件
      if (FileUtils.isDocumentFile(widget.file.name)) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 文本文件
      if (_isTextFile(widget.file.name)) {
        final file = File(widget.file.path);
        final content = await file.readAsString();
        setState(() {
          _fileContent = content;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = '不支持预览此文件类型';
          _isLoading = false;
        });
      }
    } catch (e) {
      logger.e('Error loading file content: $e');
      setState(() {
        _error = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPdfDocument() async {
    try {
      final pdfDoc = await PdfDocument.openFile(widget.file.path);
      _pdfController = PdfController(document: Future.value(pdfDoc));
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      logger.e('Error loading PDF: $e');
      setState(() {
        _error = 'PDF加载失败: $e';
        _isLoading = false;
      });
    }
  }

  bool _isTextFile(String filename) {
    return filename.toLowerCase().endsWith('.txt') ||
        filename.toLowerCase().endsWith('.log') ||
        filename.toLowerCase().endsWith('.md') ||
        filename.toLowerCase().endsWith('.json') ||
        filename.toLowerCase().endsWith('.xml');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用，因为使用了 AutomaticKeepAliveClientMixin

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadFileContent();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 根据文件类型显示不同预览
    if (FileUtils.isImageFile(widget.file.name)) {
      return _buildImagePreview();
    } else if (FileUtils.isVideoFile(widget.file.name)) {
      return _buildVideoPreview();
    } else if (FileUtils.isAudioFile(widget.file.name)) {
      return _buildAudioPreview();
    } else if (FileUtils.isPdfFile(widget.file.name)) {
      return _buildPdfViewer();
    } else if (FileUtils.isDocumentFile(widget.file.name)) {
      return _buildDocumentInfo();
    } else {
      return _buildTextPreview();
    }
  }

  Widget _buildImagePreview() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: Image.file(
          File(widget.file.path),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('图片加载失败'),
                  Text('$error', style: const TextStyle(fontSize: 12)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideoPreview() {
    return Center(
      child: VideoPlayerWidget(videoPath: widget.file.path),
    );
  }

  Widget _buildAudioPreview() {
    return Center(
      child: AudioPlayerWidget(
        audioPath: widget.file.path,
        fileName: widget.file.name,
      ),
    );
  }

  Widget _buildPdfViewer() {
    if (_pdfController == null) {
      return const Center(child: Text('PDF加载失败'));
    }

    return PdfView(controller: _pdfController!);
  }

  Widget _buildDocumentInfo() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DocumentIconWidget(fileName: widget.file.name, size: 80),
          const SizedBox(height: 24),
          Text(
            widget.file.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            FileSizeFormatter.formatBytesWithSpace(widget.file.size),
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await OpenFile.open(widget.file.path);
              if (result.type != ResultType.done) {
                logger.w('Failed to open file: ${result.message}');
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('使用外部应用打开'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextPreview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        _fileContent ?? '',
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    );
  }
}
