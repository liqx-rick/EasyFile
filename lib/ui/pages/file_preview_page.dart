import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';

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

  @override
  void initState() {
    super.initState();
    _loadFileContent();
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

  bool _isTextFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return [
      'txt', 'md', 'json', 'xml', 'html', 'css', 'js', 'ts',
      'dart', 'java', 'py', 'cpp', 'c', 'h', 'cs', 'php',
      'yaml', 'yml', 'ini', 'conf', 'log', 'csv'
    ].contains(ext);
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

  String _getFileTypeDisplay() {
    if (_isImageFile(widget.file.name)) return '图片';
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
                  : _buildTextPreview(),
    );
  }

  void _showFileInfo(BuildContext context) {
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
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}