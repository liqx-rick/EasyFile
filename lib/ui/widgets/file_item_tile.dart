import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';

class FileItemTile extends StatelessWidget {
  final FileItem file;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showFullPath;
  
  const FileItemTile({
    super.key, 
    required this.file,
    this.onTap,
    this.onLongPress,
    this.showFullPath = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        file.isDirectory ? Icons.folder : _getFileIcon(),
        color: file.isDirectory ? Colors.amber : _getFileColor(),
      ),
      title: Text(
        file.name,
        style: TextStyle(
          fontWeight: file.isDirectory ? FontWeight.w500 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: showFullPath ? SizedBox(
        height: 32, // 固定高度避免溢出
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                file.path,
                style: const TextStyle(fontSize: 11, color: Colors.blue),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              file.isDirectory 
                  ? '文件夹'
                  : _formatFileSize(file.size),
              style: const TextStyle(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ) : Text(
        file.isDirectory 
            ? '文件夹'
            : _formatFileSize(file.size),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: showFullPath,
      trailing: file.isDirectory ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  IconData _getFileIcon() {
    final extension = file.name.toLowerCase().split('.').last;
    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return Icons.image;
      case 'txt':
      case 'md':
        return Icons.description;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.article;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.audiotrack;
      case 'mp4':
      case 'avi':
      case 'mkv':
        return Icons.movie;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.archive;
      case 'dart':
      case 'java':
      case 'py':
      case 'js':
      case 'html':
      case 'css':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor() {
    final extension = file.name.toLowerCase().split('.').last;
    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return Colors.green;
      case 'txt':
      case 'md':
        return Colors.blue;
      case 'pdf':
        return Colors.red;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Colors.purple;
      case 'mp4':
      case 'avi':
      case 'mkv':
        return Colors.orange;
      case 'zip':
      case 'rar':
      case '7z':
        return Colors.brown;
      case 'dart':
      case 'java':
      case 'py':
      case 'js':
      case 'html':
      case 'css':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
