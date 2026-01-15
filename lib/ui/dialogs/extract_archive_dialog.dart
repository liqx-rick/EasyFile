import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/ui/dialogs/extraction_progress_dialog.dart';
import 'package:easyfile/ui/widgets/folder_picker_dialog.dart';

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

  /// 选择目标目录
  Future<void> _chooseTargetDirectory() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(
        currentPath: _targetBaseDir,
        title: '选择解压目标位置',
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _targetBaseDir = result;
      });
    }
  }

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
      return '/${path.substring('/storage/emulated/0/'.length)}';
    }
    return path;
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
          autoRename: true, // 始终启用自动重命名
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('解压'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文件信息
            Row(
              children: [
                Icon(
                  Icons.folder_zip,
                  color: Colors.amber[700],
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.archiveFile.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 目标目录选择 - 标签包含根目录名称
            Text(
              '到（${_getRootDisplayName(_targetBaseDir)}）：',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _chooseTargetDirectory,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[100], // 灰色背景
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatPathDisplay(_targetBaseDir),
                        style: theme.textTheme.bodyMedium,
                        maxLines: 3, // 增加到3行，提供更多显示空间
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.folder_open,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 文件夹名称 - 黄色背景
            TextField(
              controller: _folderNameController,
              decoration: InputDecoration(
                labelText: '文件夹',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.amber[50], // 黄色背景
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                suffixIcon: _folderNameController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _folderNameController.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _startExtraction,
          child: const Text('开始解压'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _folderNameController.dispose();
    super.dispose();
  }
}
