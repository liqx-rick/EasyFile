import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/ui/widgets/unified_view_config.dart';
import 'package:easyfile/ui/widgets/image_thumbnail.dart';
import 'package:easyfile/ui/widgets/real_video_thumbnail.dart';
import 'package:easyfile/ui/widgets/audio_cover_widget.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';
import 'package:easyfile/utils/file_utils.dart';

/// 统一的网格项组件
///
/// 为三个页面（file_browser_page, category_file_page, storage_page）
/// 提供一致的网格视图实现。
///
/// 特性：
/// - 响应式缩略图大小（72-96px）
/// - 统一的布局和样式
/// - 支持选中状态
/// - 可选的收藏按钮
/// - 完整的文件类型支持（图片/视频/音频/文档/文件夹）
///
/// 示例:
/// ```dart
/// UnifiedGridItem(
///   file: fileItem,
///   isSelected: false,
///   isFavorite: true,
///   showFavoriteButton: true,
///   onTap: () => openFile(fileItem),
///   onLongPress: () => selectFile(fileItem),
///   onFavoriteToggle: () async => toggleFavorite(fileItem),
/// )
/// ```
class UnifiedGridItem extends StatelessWidget {
  /// 要显示的文件项
  final FileItem file;

  /// 是否选中
  final bool isSelected;

  /// 是否收藏
  final bool isFavorite;

  /// 是否显示收藏按钮
  final bool showFavoriteButton;

  /// 点击回调
  final VoidCallback? onTap;

  /// 长按回调
  final VoidCallback? onLongPress;

  /// 收藏切换回调
  final Future<void> Function()? onFavoriteToggle;

  /// 统一视图配置
  final UnifiedViewConfig? config;

  const UnifiedGridItem({
    super.key,
    required this.file,
    this.isSelected = false,
    this.isFavorite = false,
    this.showFavoriteButton = true,
    this.onTap,
    this.onLongPress,
    this.onFavoriteToggle,
    this.config,
  });

  @override
  Widget build(BuildContext context) {
    // 使用传入的配置或创建新配置
    final viewConfig = config ?? UnifiedViewConfig.fromContext(context);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? viewConfig.getSelectedBackgroundColor(context)
              : viewConfig.getUnselectedBackgroundColor(context),
          borderRadius:
              BorderRadius.circular(UnifiedViewConfig.gridBorderRadius),
        ),
        child: Stack(
          children: [
            // 主内容区域
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(UnifiedViewConfig.gridItemPadding),
                child: Column(
                  children: [
                    // 图标区域 - 在顶部
                    const SizedBox(height: 4),
                    _buildThumbnail(context, viewConfig),
                    const Spacer(), // 弹性空间
                    const SizedBox(height: 2), // 图标和文件名之间最小间距
                    // 文件名区域 - 固定在底部
                    SizedBox(
                      height: UnifiedViewConfig.fileNameHeight,
                      child: Text(
                        file.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: UnifiedViewConfig.fileNameStyle,
                      ),
                    ),
                    const SizedBox(height: 2), // 文件名和文件大小之间固定间距
                    // 文件大小 - 固定在最底部
                    SizedBox(
                      height: UnifiedViewConfig.fileSizeHeight,
                      child: !file.isDirectory
                          ? Text(
                              FileUtils.formatFileSize(file.size),
                              style: UnifiedViewConfig.fileSizeStyle(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            // 收藏按钮 - 仅在已收藏时显示
            if (showFavoriteButton && isFavorite && !file.isDirectory)
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onFavoriteToggle,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.star,
                      size: UnifiedViewConfig.favoriteIconSize,
                      color: Colors.amber,
                    ),
                  ),
                ),
              ),
            // 选中指示器
            if (isSelected)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    size: UnifiedViewConfig.checkboxSize - 4,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建缩略图/图标
  Widget _buildThumbnail(BuildContext context, UnifiedViewConfig config) {
    final thumbnailSize = config.gridThumbnailSize;

    // 检查文件类型
    final isImage = !file.isDirectory && FileUtils.isImageFile(file.name);
    final isVideo = !file.isDirectory && FileUtils.isVideoFile(file.name);
    final isAudio = !file.isDirectory && FileUtils.isAudioFile(file.name);
    final isDocument = !file.isDirectory && FileUtils.isDocumentFile(file.name);

    if (isImage) {
      return ImageThumbnail(
        imagePath: file.path,
        size: thumbnailSize,
      );
    } else if (isVideo) {
      return RealVideoThumbnail(
        videoPath: file.path,
        size: thumbnailSize,
      );
    } else if (isAudio) {
      return AudioCoverWidget(
        audioPath: file.path,
        size: thumbnailSize,
      );
    } else if (isDocument) {
      return DocumentIconWidget(
        fileName: file.name,
        size: thumbnailSize * 0.75, // 文档图标稍小
      );
    } else {
      // 文件夹或其他文件
      return Icon(
        file.isDirectory ? Icons.folder : Icons.insert_drive_file,
        size: thumbnailSize * 0.6,
        color: file.isDirectory ? Colors.amber : Colors.blue,
      );
    }
  }
}
