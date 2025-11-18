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
  final bool isSelected; // 是否处于选中状态
  final bool showCheckbox; // 是否显示复选框
  // 可配置项（保持向后兼容的默认值）
  final double leadingSize; // 缩略图或图标大小（像素）
  final double titleFontSize;
  final double subtitleFontSize;
  final double favoriteIconSize;
  final EdgeInsetsGeometry contentPaddingOverride;
  final bool dense;

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
    this.isSelected = false,
    this.showCheckbox = false,
    this.leadingSize = 30,
    this.titleFontSize = 14,
    this.subtitleFontSize = 11,
    this.favoriteIconSize = 20,
    this.contentPaddingOverride =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
    this.dense = true,
  });

  @override
  Widget build(BuildContext context) {
    final isImage = !file.isDirectory && FileUtils.isImageFile(file.name);
    final isVideo = !file.isDirectory && FileUtils.isVideoFile(file.name);
    final isAudio = !file.isDirectory && FileUtils.isAudioFile(file.name);
    final isDocument = !file.isDirectory && FileUtils.isDocumentFile(file.name);

    return ListTile(
      dense: dense,
      contentPadding: contentPaddingOverride,
      minVerticalPadding: 0,
      leading: isImage
          ? ImageThumbnail(imagePath: file.path, size: leadingSize)
          : isVideo
              ? RealVideoThumbnail(videoPath: file.path, size: leadingSize)
              : isAudio
                  ? AudioCoverWidget(audioPath: file.path, size: leadingSize)
                  : isDocument
                      ? DocumentIconWidgetRounded(
                          fileName: file.name, size: leadingSize)
                      : Icon(
                          file.isDirectory ? Icons.folder : _getFileIcon(),
                          color:
                              file.isDirectory ? Colors.amber : _getFileColor(),
                          size: leadingSize,
                        ),
      title: Text(
        file.name,
        style: TextStyle(
          fontWeight: file.isDirectory ? FontWeight.w500 : FontWeight.normal,
          fontSize: titleFontSize,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: showFullPath
          ? SizedBox(
              height: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: Text(
                      file.path,
                      style: TextStyle(
                          fontSize: subtitleFontSize, color: Colors.blue),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    file.isDirectory
                        ? '文件夹'
                        : FileUtils.formatFileSize(file.size),
                    style: TextStyle(fontSize: subtitleFontSize),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            )
          : Text(
              _buildSubtitleText(),
              style: TextStyle(
                fontSize: subtitleFontSize,
                color: showAccessTime ? Colors.grey[600] : Colors.grey[500],
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

  /// 构建trailing部分（收藏按钮 + 复选框，或文件夹图标）
  Widget? _buildTrailing() {
    if (file.isDirectory) {
      // 文件夹显示右箭头（或复选框）
      if (showCheckbox) {
        return SizedBox(
          width: 32,
          child: Transform.scale(
            scale: 0.75, // 缩放到18px，与收藏按钮大小一致
            child: Checkbox(
              value: isSelected,
              onChanged: onTap != null ? (_) => onTap!() : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        );
      }
      return const Icon(Icons.chevron_right);
    }

    // 文件：同时显示收藏按钮和复选框（如果在选择模式）
    if (showCheckbox && onFavoriteToggle != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 收藏按钮 - 仅在已收藏时显示
          if (isFavorite)
            SizedBox(
              width: 32,
              child: Transform.scale(
                scale: 0.75, // 与复选框使用相同的缩放比例
                child: IconButton(
                  icon: const Icon(
                    Icons.star,
                    color: Colors.amber,
                  ),
                  onPressed: onFavoriteToggle,
                  tooltip: '取消收藏',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ),
            ),
          // 复选框
          SizedBox(
            width: 32,
            child: Transform.scale(
              scale: 0.75, // 缩放到18px，与收藏按钮大小一致
              child: Checkbox(
                value: isSelected,
                onChanged: onTap != null ? (_) => onTap!() : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      );
    }

    // 仅显示复选框
    if (showCheckbox) {
      return SizedBox(
        width: 32,
        child: Transform.scale(
          scale: 0.75, // 缩放到18px，与收藏按钮大小一致
          child: Checkbox(
            value: isSelected,
            onChanged: onTap != null ? (_) => onTap!() : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
    }

    // 仅显示收藏按钮 - 只在已收藏时显示
    if (onFavoriteToggle != null && isFavorite) {
      return SizedBox(
        width: 32,
        child: Transform.scale(
          scale: 0.75, // 与复选框使用相同的缩放比例
          child: IconButton(
            icon: const Icon(
              Icons.star,
              color: Colors.amber,
            ),
            onPressed: onFavoriteToggle,
            tooltip: '取消收藏',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
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
