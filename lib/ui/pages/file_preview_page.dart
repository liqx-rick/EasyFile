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
  // 滑动切换相关状态
  late PageController _pageController;
  late int _currentIndex;
  bool _showPageIndicator = true; // 是否显示页码指示器
  double _pageIndicatorOpacity = 1.0; // 页码指示器透明度

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? 0;
    _pageController = PageController(initialPage: _currentIndex);

    // 如果有多个文件，3秒后淡出页码指示器
    if (widget.fileList != null && widget.fileList!.length > 1) {
      _scheduleIndicatorFadeOut();
    }
  }

  /// 计划页码指示器淡出动画
  /// 3秒后开始淡出，300毫秒完成动画后隐藏组件
  void _scheduleIndicatorFadeOut() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _pageIndicatorOpacity = 0.0;
        });
        // 完全隐藏（为了性能）
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              _showPageIndicator = false;
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有文件列表或只有一个文件，使用单文件预览模式
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
            itemCount: widget.fileList!.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
                _showPageIndicator = true;
                _pageIndicatorOpacity = 1.0;
              });

              // 重新计划淡出
              _scheduleIndicatorFadeOut();
            },
            itemBuilder: (context, index) {
              return _FilePreviewItem(
                file: widget.fileList![index],
                key: ValueKey(widget.fileList![index].path),
              );
            },
          ),

          // 页码指示器 - 改进的视觉效果
          if (_showPageIndicator && widget.fileList!.length > 1)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _pageIndicatorOpacity,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          FileUtils.isImageFile(
                                  widget.fileList![_currentIndex].name)
                              ? Icons.image
                              : Icons.videocam,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_currentIndex + 1} / ${widget.fileList!.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
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
    if (FileUtils.isImageFile(file.name)) return '图片';
    if (FileUtils.isVideoFile(file.name)) return '视频';
    if (FileUtils.isAudioFile(file.name)) return '音频';
    if (FileUtils.isPdfFile(file.name)) return 'PDF文档';
    if (FileUtils.isDocumentFile(file.name)) return '文档';
    if (FileUtils.isTextFile(file.name)) return '文本';
    return '未知类型';
  }

  /// 显示指定文件的信息
  void _showFileInfoForFile(BuildContext context, FileItem file) async {
    // 对于音视频文件，显示详细信息
    if (FileUtils.isVideoFile(file.name) || FileUtils.isAudioFile(file.name)) {
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
      final info = FileUtils.isVideoFile(file.name)
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
                    isVideo: FileUtils.isVideoFile(file.name),
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
  // 只为图片和文本文件保持状态，视频不保持（避免内存问题）
  bool get wantKeepAlive =>
      FileUtils.isImageFile(widget.file.name) ||
      FileUtils.isTextFile(widget.file.name) ||
      FileUtils.isPdfFile(widget.file.name);

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
      if (FileUtils.isTextFile(widget.file.name)) {
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
