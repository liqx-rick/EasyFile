import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/utils/file_utils.dart';

class FileOperationSheet extends StatelessWidget {
  final FileItem file;
  final Function(FileOperation) onOperation;

  const FileOperationSheet({
    super.key,
    required this.file,
    required this.onOperation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(
          top: 16, left: 0, right: 0, bottom: 8), // 减少底部padding
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  file.isDirectory ? Icons.folder : Icons.insert_drive_file,
                  color: file.isDirectory ? Colors.amber : Colors.blue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min, // 添加这个约束
                    children: [
                      Text(
                        file.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        file.isDirectory ? '文件夹' : FileUtils.formatFileSize(file.size),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12), // 减少间距
          const Divider(height: 1),
          _buildOperationTile(
            context,
            icon: Icons.content_copy,
            title: '复制',
            subtitle: '复制到其他位置',
            onTap: () => _handleOperation(context, FileOperation.copy),
          ),
          _buildOperationTile(
            context,
            icon: Icons.drive_file_move,
            title: '移动',
            subtitle: '移动到其他位置',
            onTap: () => _handleOperation(context, FileOperation.move),
          ),
          _buildOperationTile(
            context,
            icon: Icons.edit,
            title: '重命名',
            subtitle: '修改文件名',
            onTap: () => _handleOperation(context, FileOperation.rename),
          ),
          _buildOperationTile(
            context,
            icon: Icons.delete,
            title: '删除',
            subtitle: '永久删除文件',
            color: Colors.red,
            onTap: () => _handleOperation(context, FileOperation.delete),
          ),
          const SizedBox(height: 8), // 减少底部间距
        ],
      ),
    );
  }

  Widget _buildOperationTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    final tileColor = color ?? Theme.of(context).colorScheme.onSurface;

    return ListTile(
      dense: true, // 使ListTile更紧凑
      visualDensity: VisualDensity.compact, // 进一步减少密度
      leading: Icon(icon, color: tileColor),
      title: Text(
        title,
        style: TextStyle(color: tileColor),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: tileColor.withValues(alpha: 0.6)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }

  void _handleOperation(BuildContext context, FileOperation operation) {
    logger.d('File operation selected: $operation for ${file.name}');
    Navigator.of(context).pop();
    onOperation(operation);
  }
}

enum FileOperation {
  copy,
  move,
  rename,
  delete,
}
