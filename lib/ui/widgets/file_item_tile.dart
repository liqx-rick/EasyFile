import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/utils/time_formatter.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/ui/widgets/image_thumbnail.dart';
import 'package:easyfile/ui/widgets/real_video_thumbnail.dart';
import 'package:easyfile/ui/widgets/audio_cover_widget.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';

/// 文件列表项组件
///
/// 用于在列表模式下显示文件/文件夹信息
/// 支持：
/// - 自动识别文件类型并显示对应的缩略图/图标
/// - 视频缩略图通过 RealVideoThumbnail 自动显示时长
/// - 收藏功能
/// - 选择模式
class FileItemTile extends StatefulWidget {
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
    this.leadingSize = 40,
    this.titleFontSize = 14,
    this.subtitleFontSize = 11,
    this.favoriteIconSize = 20,
    this.contentPaddingOverride =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
    this.dense = true,
  });

  @override
  State<FileItemTile> createState() => _FileItemTileState();
}

class _FileItemTileState extends State<FileItemTile> {
  @override
  Widget build(BuildContext context) {
    final isImage =
        !widget.file.isDirectory && FileUtils.isImageFile(widget.file.name);
    final isVideo =
        !widget.file.isDirectory && FileUtils.isVideoFile(widget.file.name);
    final isAudio =
        !widget.file.isDirectory && FileUtils.isAudioFile(widget.file.name);
    final isDocument =
        !widget.file.isDirectory && FileUtils.isDocumentFile(widget.file.name);

    return ListTile(
      dense: widget.dense,
      contentPadding: widget.contentPaddingOverride,
      minVerticalPadding: 0,
      leading: isImage
          ? ImageThumbnail(
              imagePath: widget.file.path, size: widget.leadingSize)
          : isVideo
              ? RealVideoThumbnail(
                  videoPath: widget.file.path,
                  size: widget.leadingSize,
                  showDuration: false, // 列表模式不显示时长标签
                )
              : isAudio
                  ? AudioCoverWidget(
                      audioPath: widget.file.path, size: widget.leadingSize)
                  : isDocument
                      ? DocumentIconWidgetRounded(
                          fileName: widget.file.name, size: widget.leadingSize)
                      : Icon(
                          widget.file.isDirectory
                              ? Icons.folder
                              : _getFileIcon(),
                          color: widget.file.isDirectory
                              ? Colors.amber
                              : _getFileColor(),
                          size: widget.leadingSize,
                        ),
      title: Text(
        widget.file.name,
        style: TextStyle(
          fontWeight:
              widget.file.isDirectory ? FontWeight.w500 : FontWeight.normal,
          fontSize: widget.titleFontSize,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: widget.showFullPath
          ? SizedBox(
              height: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: Text(
                      widget.file.path,
                      style: TextStyle(
                          fontSize: widget.subtitleFontSize,
                          color: Colors.blue),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    widget.file.isDirectory
                        ? '文件夹'
                        : FileUtils.formatFileSize(widget.file.size),
                    style: TextStyle(fontSize: widget.subtitleFontSize),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            )
          : Text(
              _buildSubtitleText(),
              style: TextStyle(
                fontSize: widget.subtitleFontSize,
                color:
                    widget.showAccessTime ? Colors.grey[600] : Colors.grey[500],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      isThreeLine: widget.showFullPath,
      trailing: _buildTrailing(),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
    );
  }

  /// 构建trailing部分（收藏按钮 + 复选框，或文件夹图标）
  Widget? _buildTrailing() {
    if (widget.file.isDirectory) {
      // 文件夹显示右箭头（或复选框）
      if (widget.showCheckbox) {
        return SizedBox(
          width: 32,
          child: Transform.scale(
            scale: 0.75, // 缩放到18px，与收藏按钮大小一致
            child: Checkbox(
              value: widget.isSelected,
              onChanged: widget.onTap != null ? (_) => widget.onTap!() : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        );
      }
      return const Icon(Icons.chevron_right);
    }

    // 文件：同时显示收藏按钮和复选框（如果在选择模式）
    if (widget.showCheckbox && widget.onFavoriteToggle != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 收藏按钮 - 仅在已收藏时显示
          if (widget.isFavorite)
            SizedBox(
              width: 32,
              child: Transform.scale(
                scale: 0.75, // 与复选框使用相同的缩放比例
                child: IconButton(
                  icon: const Icon(
                    Icons.star,
                    color: Colors.amber,
                  ),
                  onPressed: widget.onFavoriteToggle,
                  tooltip: '取消收藏',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ),
            ),
          // 复选框
          SizedBox(
            width: 32,
            child: Transform.scale(
              scale: 0.75, // 缩放到18px，与收藏按钮大小一致
              child: Checkbox(
                value: widget.isSelected,
                onChanged: widget.onTap != null ? (_) => widget.onTap!() : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      );
    }

    // 仅显示复选框
    if (widget.showCheckbox) {
      return SizedBox(
        width: 32,
        child: Transform.scale(
          scale: 0.75, // 缩放到18px，与收藏按钮大小一致
          child: Checkbox(
            value: widget.isSelected,
            onChanged: widget.onTap != null ? (_) => widget.onTap!() : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
    }

    // 显示收藏按钮或占位空间 - 保持所有文件对齐
    if (widget.onFavoriteToggle != null) {
      return SizedBox(
        width: 32,
        child: widget.isFavorite
            ? Transform.scale(
                scale: 0.75, // 与复选框使用相同的缩放比例
                child: IconButton(
                  icon: const Icon(
                    Icons.star,
                    color: Colors.amber,
                  ),
                  onPressed: widget.onFavoriteToggle,
                  tooltip: '取消收藏',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              )
            : const SizedBox(width: 32), // 占位空间，保持对齐
      );
    }

    return null;
  }

  IconData _getFileIcon() {
    final extension = widget.file.name.toLowerCase().split('.').last;
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
    final extension = widget.file.name.toLowerCase().split('.').last;
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
    if (widget.file.isDirectory) {
      return '文件夹';
    }

    final sizeText = FileUtils.formatFileSize(widget.file.size);

    // 组合所有部分：大小 · 访问时间
    // 注意：视频时长已由 RealVideoThumbnail 在缩略图上显示，无需在此处重复
    final parts = <String>[
      sizeText,
      if (widget.showAccessTime && widget.accessTime != null)
        TimeFormatter.formatRelativeTime(widget.accessTime!),
    ];

    return parts.join(' · ');
  }
}
