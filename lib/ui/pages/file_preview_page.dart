import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/utils/media_info_extractor.dart';
import 'package:easyfile/ui/widgets/video_player_widget.dart';
import 'package:easyfile/ui/widgets/audio_player_widget.dart';
import 'package:easyfile/ui/widgets/media_info_bar.dart';
import 'package:easyfile/ui/widgets/detailed_media_info_view.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';
import 'package:open_file/open_file.dart';
import 'package:pdfx/pdfx.dart';

class FilePreviewPage extends StatefulWidget {
  final FileItem file;

  const FilePreviewPage({
    super.key,
    required this.file,
  });

  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  String? _fileContent;
  bool _isLoading = true;
  String? _error;
  PdfController? _pdfController;
  int _totalPages = 0;

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

      if (_isImageFile(widget.file.name)) {
        logger.d('File is an image, no content loading needed');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      if (_isVideoFile(widget.file.name)) {
        logger.d('File is a video, no content loading needed');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      if (_isAudioFile(widget.file.name)) {
        logger.d('File is an audio, no content loading needed');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 对于文档文件，处理逻辑
      if (FileUtils.isDocumentFile(widget.file.name)) {
        // PDF 直接在应用内预览
        if (FileUtils.isPdfFile(widget.file.name)) {
          logger.d('File is a PDF, loading PDF viewer');
          await _loadPdfDocument();
        } else {
          logger.d('File is an Office document, showing info page');
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      if (_isTextFile(widget.file.name)) {
        logger.d('Loading text file content');
        final file = File(widget.file.path);
        final content = await file.readAsString();
        logger.d('Text file loaded, length: ${content.length}');

        setState(() {
          _fileContent = content;
          _isLoading = false;
        });
      } else {
        logger.w('Unsupported file type: ${widget.file.name}');
        setState(() {
          _error = '不支持预览此文件类型';
          _isLoading = false;
        });
      }
    } catch (e) {
      logger.e('Error loading file content: $e');
      setState(() {
        _error = '加载文件失败: $e';
        _isLoading = false;
      });
    }
  }

  bool _isImageFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
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
      'csv'
    ].contains(ext);
  }

  /// 加载 PDF 文档
  Future<void> _loadPdfDocument() async {
    try {
      setState(() {
        _pdfController = PdfController(
          document: PdfDocument.openFile(widget.file.path),
        );
        _isLoading = false;
      });

      final document = await PdfDocument.openFile(widget.file.path);
      setState(() {
        _totalPages = document.pagesCount;
      });

      logger.i('PDF loaded: $_totalPages pages');
    } catch (e) {
      logger.e('Error loading PDF: $e');
      setState(() {
        _error = '加载 PDF 失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 用外部应用打开文件（PDF备用打开方式）
  Future<void> _openWithExternalApp() async {
    // 复用应用选择器功能
    await _openWithAppChooser();
  }

  Widget _buildImagePreview() {
    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.file(
          File(widget.file.path),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            logger.e('Error loading image: $error');
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 48, color: Colors.red),
                  SizedBox(height: 16),
                  Text('无法加载图片'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideoPreview() {
    return Column(
      children: [
        MediaInfoBar(
          filePath: widget.file.path,
          fileName: widget.file.name,
          fileSize: widget.file.size,
          isVideo: true,
        ),
        Expanded(
          child: VideoPlayerWidget(videoPath: widget.file.path),
        ),
      ],
    );
  }

  Widget _buildAudioPreview() {
    return Column(
      children: [
        MediaInfoBar(
          filePath: widget.file.path,
          fileName: widget.file.name,
          fileSize: widget.file.size,
          isVideo: false,
        ),
        Expanded(
          child: AudioPlayerWidget(
            audioPath: widget.file.path,
            fileName: widget.file.name,
          ),
        ),
      ],
    );
  }

  Widget _buildTextPreview() {
    if (_fileContent == null) {
      return const Center(
        child: Text('无内容'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: SelectableText(
          _fileContent!,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  /// 构建 PDF 查看器
  Widget _buildPdfViewer() {
    if (_pdfController == null) {
      return const Center(
        child: Text('PDF 加载失败'),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(
              bottom: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  _pdfController!.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                tooltip: '上一页',
              ),
              Expanded(
                child: PdfPageNumber(
                  controller: _pdfController!,
                  builder: (context, loadingState, page, pagesCount) {
                    return Center(
                      child: Text(
                        '$page / $pagesCount',
                        style: const TextStyle(fontSize: 16),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  _pdfController!.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                tooltip: '下一页',
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: _openWithExternalApp,
                tooltip: '用其他应用打开',
              ),
            ],
          ),
        ),
        Expanded(
          child: PdfView(
            controller: _pdfController!,
            scrollDirection: Axis.vertical,
            builders: PdfViewBuilders<DefaultBuilderOptions>(
              options: const DefaultBuilderOptions(),
              documentLoaderBuilder: (_) => const Center(
                child: CircularProgressIndicator(),
              ),
              pageLoaderBuilder: (_) => const Center(
                child: CircularProgressIndicator(),
              ),
              errorBuilder: (_, error) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('加载失败: $error'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建 Office 文档信息页面
  Widget _buildDocumentInfo() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            DocumentIconWidget(
              fileName: widget.file.name,
              size: 128,
            ),
            const SizedBox(height: 24),
            
            Text(
              widget.file.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            
            Text(
              '${_formatFileSize(widget.file.size)} · ${_getDocumentTypeLabel()}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            
            const SizedBox(height: 32),
            
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _openWithAppChooser,
                icon: const Icon(Icons.open_in_new),
                label: const Text('选择应用打开'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // 文件信息卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '文件信息',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(),
                    _buildInfoRowWithIcon(Icons.folder_outlined, '路径', 
                        _truncatePath(widget.file.path)),
                    const SizedBox(height: 12),
                    _buildInfoRowWithIcon(Icons.calendar_today, '修改时间', 
                        _formatDateTime(widget.file.modified)),
                    const SizedBox(height: 12),
                    _buildInfoRowWithIcon(Icons.storage, '大小', 
                        _formatFileSize(widget.file.size)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建带图标的信息行
  Widget _buildInfoRowWithIcon(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 截断路径显示
  String _truncatePath(String path) {
    if (path.length <= 50) return path;
    return '...${path.substring(path.length - 47)}';
  }

  /// 获取文档类型标签
  String _getDocumentTypeLabel() {
    if (FileUtils.isWordFile(widget.file.name)) {
      return 'Word 文档';
    } else if (FileUtils.isExcelFile(widget.file.name)) {
      return 'Excel 表格';
    } else if (FileUtils.isPowerPointFile(widget.file.name)) {
      return 'PowerPoint 演示文稿';
    }
    return '文档';
  }

  /// 用应用选择器打开文件
  Future<void> _openWithAppChooser() async {
    try {
      logger.i('Opening file with app chooser: ${widget.file.path}');
      
      // 获取 MIME 类型
      String? mimeType = _getMimeType(widget.file.name);
      
      final result = await OpenFile.open(
        widget.file.path,
        type: mimeType,
      );
      
      if (mounted) {
        String message;
        switch (result.type) {
          case ResultType.done:
            message = '已打开文件';
            break;
          case ResultType.noAppToOpen:
            message = '未找到可以打开此文件的应用';
            break;
          case ResultType.fileNotFound:
            message = '文件不存在';
            break;
          case ResultType.permissionDenied:
            message = '没有权限打开此文件';
            break;
          default:
            message = '打开文件失败: ${result.message}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logger.e('Error opening file with app chooser: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打开文件失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 获取 MIME 类型
  String? _getMimeType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'pdf':
        return 'application/pdf';
      default:
        return null;
    }
  }

  String _getFileTypeDisplay() {
    if (_isImageFile(widget.file.name)) return '图片';
    if (_isVideoFile(widget.file.name)) return '视频';
    if (_isAudioFile(widget.file.name)) return '音频';
    if (FileUtils.isPdfFile(widget.file.name)) return 'PDF';
    if (FileUtils.isDocumentFile(widget.file.name)) return '文档';
    if (_isTextFile(widget.file.name)) return '文本';
    return '文件';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.file.name,
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              _getFileTypeDisplay(),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showFileInfo(context),
            tooltip: '文件信息',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
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
                )
              : _isImageFile(widget.file.name)
                  ? _buildImagePreview()
                  : _isVideoFile(widget.file.name)
                      ? _buildVideoPreview()
                      : _isAudioFile(widget.file.name)
                          ? _buildAudioPreview()
                          : FileUtils.isPdfFile(widget.file.name)
                              ? _buildPdfViewer()
                              : FileUtils.isDocumentFile(widget.file.name)
                                  ? _buildDocumentInfo()
                                  : _buildTextPreview(),
    );
  }

  void _showFileInfo(BuildContext context) async {
    // 对于音视频文件，显示详细信息
    if (_isVideoFile(widget.file.name) || _isAudioFile(widget.file.name)) {
      _showDetailedMediaInfo(context);
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
            _buildInfoRow('文件名', widget.file.name),
            _buildInfoRow('路径', widget.file.path),
            _buildInfoRow('大小', _formatFileSize(widget.file.size)),
            _buildInfoRow('修改时间', _formatDateTime(widget.file.modified)),
            _buildInfoRow('类型', _getFileTypeDisplay()),
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

  void _showDetailedMediaInfo(BuildContext context) async {
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

    try {
      final extractor = MediaInfoExtractor();
      final info = _isVideoFile(widget.file.name)
          ? await extractor.extractVideoInfo(widget.file.path)
          : await extractor.extractAudioInfo(widget.file.path);

      if (context.mounted) {
        Navigator.of(context).pop(); // 关闭加载对话框

        // 显示详细信息
        showDialog(
          context: context,
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
                      isVideo: _isVideoFile(widget.file.name),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      logger.e('Error loading detailed media info: $e');
      if (context.mounted) {
        Navigator.of(context).pop(); // 关闭加载对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载详细信息失败: $e')),
        );
      }
    }
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
          Expanded(
            child: SelectableText(value),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}
