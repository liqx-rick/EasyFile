import 'package:easyfile/analytics/analytics_helper.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/file_type_detector_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 文件类型识别器页面
///
/// 功能：
/// - 选择单个或多个文件
/// - 识别文件真实类型（通过文件头）
/// - 显示文件详细信息
/// - 支持复制类型信息
class FileTypeDetectorPage extends StatefulWidget {
  const FileTypeDetectorPage({super.key});

  @override
  State<FileTypeDetectorPage> createState() => _FileTypeDetectorPageState();
}

class _FileTypeDetectorPageState extends State<FileTypeDetectorPage> {
  final FileTypeDetectorService _detectorService = FileTypeDetectorService();

  // 识别结果列表
  List<FileTypeResult> _results = [];

  // UI 状态
  bool _isDetecting = false;

  @override
  void initState() {
    super.initState();
    // 埋点：进入文件类型识别器页面
    AnalyticsHelper.logFileTypeDetectorEnter();
  }

  /// 选择文件
  Future<void> _pickFiles() async {
    try {
      logger.d('打开文件选择器...');

      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) {
        logger.d('用户取消选择文件');
        return;
      }

      logger.d('用户选择了 ${result.files.length} 个文件');

      setState(() {
        _results = [];
        _isDetecting = true;
      });

      // 识别所有文件
      final results = <FileTypeResult>[];
      for (final file in result.files) {
        if (file.path != null) {
          try {
            final fileResult = await _detectorService.detectFileType(file.path!);
            results.add(fileResult);
          } catch (e) {
            logger.e('识别文件失败: ${file.name}, 错误: $e');
          }
        }
      }

      setState(() {
        _results = results;
        _isDetecting = false;
      });

      // 埋点：识别完成
      AnalyticsHelper.logFileTypeDetectFinish(
        fileCount: results.length,
      );

      if (results.isNotEmpty) {
        _showSnackBar('已识别 ${results.length} 个文件');
      }
    } catch (e, stackTrace) {
      logger.e('选择文件失败: $e\nStackTrace: $stackTrace');
      setState(() {
        _isDetecting = false;
      });
      _showSnackBar('选择文件失败: $e');
    }
  }

  /// 复制到剪贴板
  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('$label 已复制到剪贴板');
  }

  /// 显示提示消息
  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('文件类型识别器'),
        actions: [
          if (_results.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () {
                setState(() {
                  _results = [];
                });
              },
              tooltip: '清空列表',
            ),
        ],
      ),
      body: Column(
        children: [
          // 选择文件按钮
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildSelectFilesButton(theme),
          ),

          // 结果列表
          Expanded(
            child: _buildResultsList(theme),
          ),
        ],
      ),
    );
  }

  /// 构建选择文件按钮
  Widget _buildSelectFilesButton(ThemeData theme) {
    return ElevatedButton.icon(
      onPressed: _isDetecting ? null : _pickFiles,
      icon: const Icon(Icons.file_open, size: 28),
      label: Text(
        _results.isEmpty ? '选择文件' : '添加更多文件',
        style: const TextStyle(fontSize: 18),
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        minimumSize: const Size(double.infinity, 0),
      ),
    );
  }

  /// 构建结果列表
  Widget _buildResultsList(ThemeData theme) {
    if (_isDetecting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在识别文件类型...'),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return _buildEmptyState(theme);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        return _buildFileCard(_results[index], theme);
      },
    );
  }

  /// 构建空状态
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Card(
        color: Colors.blue.shade50,
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search,
                size: 64,
                color: Colors.blue.shade700,
              ),
              const SizedBox(height: 16),
              Text(
                '使用说明',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(height: 12),
              const Text('1. 点击"选择文件"按钮'),
              const SizedBox(height: 6),
              const Text('2. 选择一个或多个文件'),
              const SizedBox(height: 6),
              const Text('3. 查看文件的真实类型'),
              const SizedBox(height: 6),
              const Text('4. 点击复制按钮可复制信息'),
              const SizedBox(height: 16),
              Text(
                '💡 通过读取文件头识别真实类型',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建文件卡片
  Widget _buildFileCard(FileTypeResult result, ThemeData theme) {
    // 根据是否匹配选择颜色
    final cardColor = result.isExtensionMatch ? null : Colors.orange.shade50;
    final iconColor = result.isExtensionMatch ? Colors.green : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文件名和图标
            Row(
              children: [
                Icon(
                  _getFileIcon(result.detectedType),
                  color: iconColor,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.fileName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.formattedSize,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // 详细信息
            _buildInfoRow(
              icon: Icons.extension,
              label: '扩展名',
              value: result.extension.isEmpty ? '无' : '.${result.extension}',
              onCopy: result.extension.isNotEmpty ? () => _copyToClipboard(result.extension, '扩展名') : null,
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.verified,
              label: '真实类型',
              value: result.detectedType,
              onCopy: () => _copyToClipboard(result.detectedType, '文件类型'),
              valueColor: iconColor,
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.info,
              label: 'MIME 类型',
              value: result.mimeType,
              onCopy: () => _copyToClipboard(result.mimeType, 'MIME 类型'),
            ),

            // 匹配状态提示
            if (!result.isExtensionMatch) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '扩展名与真实类型不匹配',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建信息行
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onCopy,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
              color: valueColor,
            ),
          ),
        ),
        if (onCopy != null)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: onCopy,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: '复制',
          ),
      ],
    );
  }

  /// 获取文件图标
  IconData _getFileIcon(String detectedType) {
    final type = detectedType.toLowerCase();

    if (type.contains('image') ||
        type.contains('png') ||
        type.contains('jpeg') ||
        type.contains('jpg') ||
        type.contains('gif') ||
        type.contains('bmp') ||
        type.contains('webp')) {
      return Icons.image;
    }
    if (type.contains('video') || type.contains('mp4') || type.contains('avi') || type.contains('mkv')) {
      return Icons.movie;
    }
    if (type.contains('audio') ||
        type.contains('mp3') ||
        type.contains('wav') ||
        type.contains('ogg') ||
        type.contains('flac')) {
      return Icons.audio_file;
    }
    if (type.contains('pdf')) {
      return Icons.picture_as_pdf;
    }
    if (type.contains('doc') || type.contains('xls') || type.contains('ppt')) {
      return Icons.description;
    }
    if (type.contains('archive') ||
        type.contains('zip') ||
        type.contains('rar') ||
        type.contains('7z') ||
        type.contains('gzip')) {
      return Icons.folder_zip;
    }
    if (type.contains('text') || type.contains('txt')) {
      return Icons.text_snippet;
    }
    if (type.contains('executable') || type.contains('exe') || type.contains('apk')) {
      return Icons.settings_applications;
    }

    return Icons.insert_drive_file;
  }
}
