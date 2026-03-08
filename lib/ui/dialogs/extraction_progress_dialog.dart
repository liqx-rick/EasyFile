import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/extraction_completion_info.dart';
import 'package:easyfile/core/services/archive_service.dart' as archive_svc;
import 'package:easyfile/core/services/extraction_notification_manager.dart';
import 'package:easyfile/core/services/extraction_record_service.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/pages/extracted_files_browser_page.dart';
import 'package:easyfile/ui/widgets/password_input_dialog.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  /// 检查是否为 RAR 或 ZIP 格式
  bool get _isRarOrZip {
    final lowerPath = archiveFile.path.toLowerCase();
    return lowerPath.endsWith('.rar') || lowerPath.endsWith('.zip');
  }

  @override
  State<ExtractionProgressDialog> createState() => _ExtractionProgressDialogState();
}

class _ExtractionProgressDialogState extends State<ExtractionProgressDialog> {
  final archive_svc.ArchiveService _archiveService = archive_svc.ArchiveService();
  final ExtractionRecordService _recordService = ExtractionRecordService();

  // 使用 getter 获取单例，确保和 ArchiveViewerPage 使用同一个实例
  ExtractionNotificationManager get _notificationManager => ExtractionNotificationManager();

  bool _isExtracting = true;
  bool _isStopped = false;
  archive_svc.ExtractResult? _result;
  String _statusMessage = '准备解压...';

  /// 获取根目录显示名称
  String _getRootDisplayName(String path) {
    if (path == '/storage/emulated/0' || path.startsWith('/storage/emulated/0/')) {
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

  /// 停止解压操作
  void _stopExtraction() {
    final lowerPath = widget.archiveFile.path.toLowerCase();
    final isRarOrZip = lowerPath.endsWith('.rar') || lowerPath.endsWith('.zip');

    if (!isRarOrZip) {
      // libarchive格式：真正停止解压进程
      final success = _archiveService.stopExtraction();
      if (success) {
        logger.i('已发送停止信号给 libarchive');
      }
    } else {
      // RAR/ZIP格式：只关闭进度显示（解压继续在后台）
      logger.i('RAR/ZIP格式：关闭进度对话框，解压将继续在后台完成');
    }

    // 统一更新UI为停止状态
    if (mounted) {
      setState(() {
        _isExtracting = false;
        _isStopped = true;
        _statusMessage = '已停止解压';
        // 为 RAR/ZIP 创建一个部分成功的结果对象
        if (isRarOrZip && _result == null) {
          _result = archive_svc.ExtractResult(
            success: false,
            errorMessage: 'Operation cancelled by user',
            targetPath: '${widget.targetBaseDir}/${widget.folderName}',
            totalFiles: 0,
            extractedFiles: 0,
          );
        }
      });
    }
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
      if (mounted) {
        setState(() {
          _isExtracting = true;
          _statusMessage = '正在解压，请稍候...';
        });
      }

      try {
        // 使用后台 Isolate 解压（避免UI卡顿，且支持停止操作）
        final result = await _archiveService.extractToInBackground(
          archivePath: widget.archiveFile.path,
          targetDir: widget.targetBaseDir,
          folderName: widget.folderName,
          autoRename: widget.autoRename,
          password: password,
        );

        // 检查是否被用户停止（错误消息包含 "cancelled"）
        final wasStopped = result.errorMessage.toLowerCase().contains('cancelled');

        if (wasStopped) {
          // 停止：添加记录，不发送通知
          if (result.targetPath.isNotEmpty && mounted) {
            await _recordService.addRecord(
              archivePath: widget.archiveFile.path,
              targetPath: result.targetPath,
              fileCount: result.extractedFiles ?? 0,
            );
          }

          if (mounted) {
            setState(() {
              _isExtracting = false;
              _isStopped = true;
              _result = result;
              _statusMessage = '解压已停止';
            });
          }
          needRetry = false;
          return; // 提前退出
        }

        // 解压成功后保存记录（即使对话框已关闭也要保存）
        if (result.success && result.targetPath.isNotEmpty) {
          await _recordService.addRecord(
            archivePath: widget.archiveFile.path,
            targetPath: result.targetPath,
            fileCount: result.extractedFiles ?? 0,
          );

          // 只有在对话框已关闭（后台完成）时才添加通知
          // 如果用户还在看对话框，说明没有后台运行，不需要通知
          if (!mounted) {
            _notificationManager.addCompletion(
              ExtractionCompletionInfo(
                id: ExtractionCompletionInfo.generateId(),
                archiveName: widget.archiveFile.name,
                archivePath: widget.archiveFile.path,
                extractPath: result.targetPath,
                fileCount: result.extractedFiles ?? 0,
                completedAt: DateTime.now(),
                isSuccess: true,
              ),
            );
          }

          needRetry = false;
        }

        if (mounted) {
          setState(() {
            _isExtracting = false;
            _result = result;
            _statusMessage = result.success ? '解压完成！' : '解压失败';
          });

          // 检查是否需要密码
          debugPrint('[密码检测] 解压结果: success=${result.success}, errorMessage=${result.errorMessage}');
          final needsPwd = _needsPassword(result.errorMessage);
          debugPrint('[密码检测] 是否需要密码: $needsPwd');

          if (!result.success && needsPwd) {
            attempts++;
            debugPrint('[密码检测] 检测到需要密码，尝试次数: $attempts/$maxAttempts');

            // 显示密码输入对话框
            password = await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (context) => PasswordInputDialog(remainingAttempts: maxAttempts - attempts),
            );

            debugPrint('[密码对话框] 返回值: ${"已输入密码"}');

            // 用户取消
            debugPrint('[密码对话框] 将使用密码重试解压，尝试次数: $attempts/$maxAttempts');
          } else if (!result.success) {
            // 非密码错误，不重试
            needRetry = false;
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isExtracting = false;
            _result = archive_svc.ExtractResult.failure(errorMessage: e.toString());
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
    return lowerError.contains('password') || lowerError.contains('encrypted') || lowerError.contains('密码');
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
          : _isStopped
          ? Row(
              children: [
                Icon(Icons.stop_circle, color: Colors.orange[600], size: 24),
                const SizedBox(width: 8),
                const Text('已停止'),
              ],
            )
          : (_result?.success == true
                ? Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green[600], size: 24),
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
                Icon(Icons.folder_zip, color: Colors.amber[700], size: 20),
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
            // 不确定进度条（后台解压中）
            const LinearProgressIndicator(minHeight: 8),
            const SizedBox(height: 12),
            Text(_statusMessage, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              '大文件解压可能需要较长时间，请耐心等待',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
            ),
          ] else if (_result != null) ...[
            // 结果显示
            if (_isStopped) ...[
              // 停止状态
              Row(
                children: [
                  Icon(Icons.folder_zip, color: Colors.amber[700], size: 20),
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
              // 提示信息
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[300]!, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget._isRarOrZip ? '由于技术限制，停止信号可能延迟生效。请稍后到"解压记录"查看结果。' : '解压已停止，部分文件已保存到目标位置。请稍后到"解压记录"查看结果。',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ),
              if (_result!.targetPath.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '位置（${_getRootDisplayName(_result!.targetPath)}）：',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    _formatPathDisplay(_result!.targetPath),
                    style: theme.textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ] else if (_result!.success) ...[
              // 成功 - 文件流向
              Row(
                children: [
                  Icon(Icons.folder_zip, color: Colors.amber[700], size: 20),
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
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                child: Text(
                  _formatPathDisplay(_result!.targetPath),
                  style: theme.textTheme.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 部分失败提示
              if (!_result!.success && _result!.extractedFiles != null && _result!.extractedFiles! > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange[300]!, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('部分文件解压失败', style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange[900])),
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
                  Icon(Icons.error, color: Colors.red[600], size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _result!.errorMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
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
        if (_isExtracting) ...[
          TextButton(
            onPressed: _stopExtraction,
            style: TextButton.styleFrom(foregroundColor: Colors.orange[700]),
            child: const Text('停止'),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('后台运行')),
        ] else ...[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
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
