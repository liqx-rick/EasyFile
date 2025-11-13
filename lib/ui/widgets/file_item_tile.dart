import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/utils/time_formatter.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/ui/widgets/image_thumbnail.dart';
import 'package:easyfile/ui/widgets/real_video_thumbnail.dart';
import 'package:easyfile/ui/widgets/audio_cover_widget.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';

class FileItemTile extends StatelessWidget {
  final FileItem file;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFavoriteToggle; // 收藏按钮回调
  final bool isFavorite; // 是否已收藏
  final bool showFullPath;
  final bool showAccessTime;
  final DateTime? accessTime;

  const FileItemTile({
    super.key,
    required this.file,
    this.onTap,
    this.onLongPress,
    this.onFavoriteToggle,
    this.isFavorite = false,
    this.showFullPath = false,
    this.showAccessTime = false,
    this.accessTime,
  });

  @override
  Widget build(BuildContext context) {
    final isImage = !file.isDirectory && FileUtils.isImageFile(file.name);
    final isVideo = !file.isDirectory && FileUtils.isVideoFile(file.name);
    final isAudio = !file.isDirectory && FileUtils.isAudioFile(file.name);
    final isDocument = !file.isDirectory && FileUtils.isDocumentFile(file.name);
    
    return ListTile(
      leading: isImage
          ? ImageThumbnail(
              imagePath: file.path,
              size: 40,
            )
          : isVideo
              ? RealVideoThumbnail(
                  videoPath: file.path,
                  size: 40,
                )
              : isAudio
                  ? AudioCoverWidget(
                      audioPath: file.path,
                      size: 40,
                    )
                  : isDocument
                      ? DocumentIconWidgetRounded(
                          fileName: file.name,
                          size: 40,
                        )
                      : Icon(
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
      subtitle: showFullPath
          ? SizedBox(
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
                    file.isDirectory ? '文件夹' : FileUtils.formatFileSize(file.size),
                    style: const TextStyle(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            )
          : Text(
              _buildSubtitleText(),
              style: TextStyle(
                fontSize: 11,
                color: showAccessTime
                    ? Colors.grey[600]
                    : Theme.of(context).textTheme.bodySmall?.color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      isThreeLine: showFullPath,
      trailing: _buildTrailing(),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  /// 构建trailing部分（收藏按钮 + 文件夹图标）
  Widget? _buildTrailing() {
    if (file.isDirectory) {
      return const Icon(Icons.chevron_right);
    }
    
    // 文件显示收藏按钮
    if (onFavoriteToggle != null) {
      return IconButton(
        icon: Icon(
          isFavorite ? Icons.star : Icons.star_border,
          color: isFavorite ? Colors.amber : Colors.grey,
          size: 20,
        ),
        onPressed: onFavoriteToggle,
        tooltip: isFavorite ? '取消收藏' : '收藏',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      );
    }
    
    return null;
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



  String _buildSubtitleText() {
    if (file.isDirectory) {
      return '文件夹';
    }

    final sizeText = FileUtils.formatFileSize(file.size);

    // 如果需要显示访问时间且时间不为空
    if (showAccessTime && accessTime != null) {
      final timeText = TimeFormatter.formatRelativeTime(accessTime!);
      return '$sizeText · $timeText';
    }

    return sizeText;
  }
}
