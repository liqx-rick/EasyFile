import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/ui/dialogs/extraction_progress_dialog.dart';

/// 解压对话框
/// 
/// 允许用户选择解压目标目录和文件夹名称
class ExtractArchiveDialog extends StatefulWidget {
  final FileItem archiveFile;

  const ExtractArchiveDialog({
    super.key,
    required this.archiveFile,
  });

  @override
  State<ExtractArchiveDialog> createState() => _ExtractArchiveDialogState();
}

class _ExtractArchiveDialogState extends State<ExtractArchiveDialog> {
  late TextEditingController _folderNameController;
  late String _targetBaseDir;
  bool _autoRename = true;

  @override
  void initState() {
    super.initState();

    // 默认：文件所在目录
    _targetBaseDir = File(widget.archiveFile.path).parent.path;

    // 默认：压缩包名（去扩展名）
    final archiveName = widget.archiveFile.name;
    final nameWithoutExt = _getNameWithoutExtension(archiveName);
    _folderNameController = TextEditingController(text: nameWithoutExt);
  }

  /// 获取不含扩展名的文件名
  String _getNameWithoutExtension(String fileName) {
    // 处理双扩展名，如 .tar.gz
    if (fileName.endsWith('.tar.gz') ||
        fileName.endsWith('.tar.bz2') ||
        fileName.endsWith('.tar.xz')) {
      return fileName.substring(0, fileName.length - 7);
    }
    
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1) return fileName;
    return fileName.substring(0, lastDot);
  }

  /// 获取完整的解压路径
  String get _fullPath {
    return '$_targetBaseDir/${_folderNameController.text}';
  }

  /// 选择目标目录（使用 SAF）
  Future<void> _chooseTargetDirectory() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择解压目标目录',
        initialDirectory: _targetBaseDir,
      );

      if (result != null && mounted) {
        setState(() {
          _targetBaseDir = result;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择目录失败: $e')),
        );
      }
    }
  }

  /// 开始解压
  Future<void> _startExtraction() async {
    // 验证文件夹名称
    final folderName = _folderNameController.text.trim();
    if (folderName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入文件夹名称')),
      );
      return;
    }

    // 关闭当前对话框
    Navigator.pop(context);

    // 显示进度对话框并开始解压
    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => ExtractionProgressDialog(
          archiveFile: widget.archiveFile,
          targetBaseDir: _targetBaseDir,
          folderName: folderName,
          autoRename: _autoRename,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('解压压缩包'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文件信息
            _buildFileInfo(theme),
            const SizedBox(height: 20),

            // 目标目录选择
            Text(
              '解压到:',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _chooseTargetDirectory,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                  color: colorScheme.surface,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _targetBaseDir,
                        style: theme.textTheme.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.folder_open,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '更改',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 文件夹名称
            TextField(
              controller: _folderNameController,
              decoration: const InputDecoration(
                labelText: '文件夹名称',
                border: OutlineInputBorder(),
                hintText: '输入解压后的文件夹名称',
              ),
              onChanged: (_) => setState(() {}), // 更新完整路径显示
            ),
            const SizedBox(height: 12),

            // 完整路径显示
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '完整路径: $_fullPath/',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 选项
            CheckboxListTile(
              title: const Text('如果文件夹已存在，自动重命名'),
              subtitle: const Text('例如: backup → backup_1'),
              value: _autoRename,
              onChanged: (value) => setState(() => _autoRename = value!),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _startExtraction,
          child: const Text('开始解压'),
        ),
      ],
    );
  }

  Widget _buildFileInfo(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '大小: ${FileSizeFormatter.formatBytes(widget.archiveFile.size)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _folderNameController.dispose();
    super.dispose();
  }
}
