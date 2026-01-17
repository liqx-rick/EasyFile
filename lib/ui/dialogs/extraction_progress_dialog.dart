import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/services/archive_service.dart' as archive_svc;
import 'package:easyfile/core/services/extraction_record_service.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:provider/provider.dart';
import 'package:easyfile/ui/pages/extracted_files_browser_page.dart';
import 'package:easyfile/ui/widgets/password_input_dialog.dart';

/// 解压进度对话框
///
/// 显示解压进度并在完成后提供查看文件的选项
class ExtractionProgressDialog extends StatefulWidget {
  final FileItem archiveFile;
  final String targetBaseDir;
  final String folderName;
  final bool autoRename;

  const ExtractionProgressDialog({
    super.key,
    required this.archiveFile,
    required this.targetBaseDir,
    required this.folderName,
    required this.autoRename,
  });

  @override
  State<ExtractionProgressDialog> createState() =>
      _ExtractionProgressDialogState();
}

class _ExtractionProgressDialogState extends State<ExtractionProgressDialog> {
  final archive_svc.ArchiveService _archiveService =
      archive_svc.ArchiveService();
  final ExtractionRecordService _recordService = ExtractionRecordService();

  bool _isExtracting = true;
  double _progress = 0.0;
  archive_svc.ExtractResult? _result;
  String _statusMessage = '准备解压...';

  /// 获取根目录显示名称
  String _getRootDisplayName(String path) {
    if (path == '/storage/emulated/0' ||
        path.startsWith('/storage/emulated/0/')) {
      return '内部存储';
    }
    return '根目录';
  }

  /// 格式化路径显示（只显示相对路径）
  String _formatPathDisplay(String path) {
    if (path == '/storage/emulated/0') {
      return '/';
    }
    if (path.startsWith('/storage/emulated/0/')) {
      return path.substring('/storage/emulated/0'.length);
    }
    return path;
  }

  @override
  void initState() {
    super.initState();
    _startExtraction();
  }

  /// 开始解压
  Future<void> _startExtraction() async {
    String? password;
    int attempts = 0;
    const maxAttempts = 3;
    bool needRetry = true;

    while (attempts < maxAttempts && needRetry) {
      setState(() {
        _isExtracting = true;
        _progress = 0.0;
        _statusMessage = '正在解压...';
      });

      try {
        final result = await _archiveService.extractTo(
          archivePath: widget.archiveFile.path,
          targetDir: widget.targetBaseDir,
          folderName: widget.folderName,
          autoRename: widget.autoRename,
          password: password,
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _progress = progress;
                _statusMessage = '正在解压... ${(progress * 100).toInt()}%';
              });
            }
          },
        );

        if (mounted) {
          setState(() {
            _isExtracting = false;
            _result = result;
            _statusMessage = result.success ? '解压完成！' : '解压失败';
          });

          // 解压成功后保存记录
          if (result.success && result.targetPath.isNotEmpty) {
            await _recordService.addRecord(
              archivePath: widget.archiveFile.path,
              targetPath: result.targetPath,
              fileCount: result.extractedFiles ?? 0,
            );
            needRetry = false;
          } else {
            // 检查是否需要密码
            if (_needsPassword(result.errorMessage)) {
              attempts++;

              // 显示密码输入对话框
              password = await showDialog<String>(
                context: context,
                barrierDismissible: false,
                builder: (context) => PasswordInputDialog(
                  remainingAttempts: maxAttempts - attempts,
                ),
              );

              // 用户取消
              if (password == null) {
                needRetry = false;
              }
            } else {
              // 非密码错误，不重试
              needRetry = false;
            }
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isExtracting = false;
            _result = archive_svc.ExtractResult.failure(
              errorMessage: e.toString(),
            );
            _statusMessage = '解压失败';
          });
        }
        needRetry = false;
      }
    }
  }

  /// 检查错误消息是否表示需要密码
  bool _needsPassword(String? errorMessage) {
    if (errorMessage == null) return false;
    final lowerError = errorMessage.toLowerCase();
    return lowerError.contains('password') ||
        lowerError.contains('encrypted') ||
        lowerError.contains('密码');
  }

  /// 查看解压后的文件
  Future<void> _viewExtractedFiles() async {
    if (_result == null || !_result!.success) return;

    final presenter = locator<FilePresenter>();
    final viewModel = context.read<FileViewModel>();

    // 关闭对话框
    Navigator.pop(context);

    // 导航到解压文件浏览页面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExtractedFilesBrowserPage(
          archiveName: widget.archiveFile.name,
          extractedPath: _result!.targetPath,
          presenter: presenter,
          viewModel: viewModel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: _isExtracting
          ? const Text('正在解压')
          : (_result?.success == true
              ? Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green[600],
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    const Text('解压成功'),
                  ],
                )
              : const Text('解压失败')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isExtracting) ...[
            // 文件信息
            Row(
              children: [
                Icon(
                  Icons.folder_zip,
                  color: Colors.amber[700],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.archiveFile.name,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 进度条
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: colorScheme.surfaceContainerHighest,
              minHeight: 8,
            ),
            const SizedBox(height: 12),
            Text(
              _statusMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ] else if (_result != null) ...[
            // 结果显示
            if (_result!.success) ...[
              // 成功 - 文件流向
              Row(
                children: [
                  Icon(
                    Icons.folder_zip,
                    color: Colors.amber[700],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.archiveFile.name,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 位置 - 灰色背景
              Text(
                '位置（${_getRootDisplayName(_result!.targetPath)}）：',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatPathDisplay(_result!.targetPath),
                  style: theme.textTheme.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 部分失败提示
              if (!_result!.success &&
                  _result!.extractedFiles != null &&
                  _result!.extractedFiles! > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.orange[300]!,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        color: Colors.orange[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '部分文件解压失败',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.orange[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ] else ...[
              // 失败
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error,
                    color: Colors.red[600],
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _result!.errorMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
      actions: [
        if (_isExtracting)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('后台运行'),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          if (_result?.success == true)
            FilledButton.icon(
              onPressed: _viewExtractedFiles,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('查看文件'),
            ),
        ],
      ],
    );
  }
}
