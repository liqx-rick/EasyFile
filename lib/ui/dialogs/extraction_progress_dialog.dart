import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/services/archive_service.dart' as archive_svc;
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/di/locator.dart';
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

  @override
  State<ExtractionProgressDialog> createState() =>
      _ExtractionProgressDialogState();
}

class _ExtractionProgressDialogState extends State<ExtractionProgressDialog> {
  final archive_svc.ArchiveService _archiveService = archive_svc.ArchiveService();

  bool _isExtracting = true;
  double _progress = 0.0;
  archive_svc.ExtractResult? _result;
  String _statusMessage = '准备解压...';

  @override
  void initState() {
    super.initState();
    _startExtraction();
  }

  /// 开始解压
  Future<void> _startExtraction() async {
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
    }
  }

  /// 查看解压后的文件
  Future<void> _viewExtractedFiles() async {
    if (_result == null || !_result!.success) return;

    final presenter = locator<FilePresenter>();
    final viewModel = context.read<FileViewModel>();

    // 关闭对话框
    Navigator.pop(context);

    // 保存解压上下文信息（用于显示提示条）
    viewModel.setExtractionContext(
      sourceName: widget.archiveFile.name,
      targetPath: _result!.targetPath,
    );

    // 导航到解压后的文件夹
    await presenter.loadFiles(_result!.targetPath, isRootNavigation: true);
    viewModel.setCurrentTab(TabView.browse);
  }

  /// 查看解压位置（跳转到父目录并高亮）
  Future<void> _viewLocation() async {
    if (_result == null || !_result!.success) return;

    final presenter = locator<FilePresenter>();
    final viewModel = context.read<FileViewModel>();

    // 关闭对话框
    Navigator.pop(context);

    // 获取父目录
    final targetDir = Directory(_result!.targetPath);
    final parentPath = targetDir.parent.path;

    // 保存解压上下文信息
    viewModel.setExtractionContext(
      sourceName: widget.archiveFile.name,
      targetPath: _result!.targetPath,
      shouldHighlight: true,
    );

    // 导航到父目录
    await presenter.loadFiles(parentPath, isRootNavigation: true);
    viewModel.setCurrentTab(TabView.browse);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Text(_isExtracting ? '正在解压' : '解压结果'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 文件信息
          Text(
            '文件: ${widget.archiveFile.name}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),

          // 进度指示器或结果
          if (_isExtracting) ...[
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
              // 成功
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Colors.green[600],
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '解压成功！',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '已解压 ${_result!.extractedFiles ?? 0} 个文件',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '位置:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _result!.targetPath,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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
              Row(
                children: [
                  Icon(
                    Icons.error,
                    color: Colors.red[600],
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '解压失败',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.red[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_result!.errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _result!.errorMessage,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
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
          if (_result?.success == true) ...[
            // 查看位置（跳转到父目录并高亮）
            TextButton.icon(
              onPressed: _viewLocation,
              icon: const Icon(Icons.location_on, size: 18),
              label: const Text('查看位置'),
            ),
            // 查看文件（进入文件夹）
            ElevatedButton.icon(
              onPressed: _viewExtractedFiles,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('查看文件'),
            ),
          ],
        ],
      ],
    );
  }
}
