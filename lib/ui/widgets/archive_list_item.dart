import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/utils/file_utils.dart';

/// Checkbox位置枚举（临时定义，应该在file_collection_view.dart中）
enum CheckboxPosition { leading, trailing }

/// 压缩包列表项组件
///
/// 专门用于压缩包管理页面的列表项显示
/// 特性：
/// - 文件名支持两行显示（如果一行显示不下）
/// - 文件大小和创建日期显示在一行
/// - 右侧显示解压按钮
/// - 支持角标显示（已解压标记）
class ArchiveListItem extends StatelessWidget {
  final FileItem file;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onExtract; // 解压按钮回调
  final bool isSelected; // 是否处于选中状态
  final bool hasExtracted; // 是否已解压（显示角标）
  final bool showCheckbox; // 是否显示复选框
  final CheckboxPosition checkboxPosition; // 复选框位置（修复问题4）
  final bool showExtractButton; // 是否显示解压按钮（编辑模式下隐藏）

  const ArchiveListItem({
    super.key,
    required this.file,
    this.onTap,
    this.onLongPress,
    this.onExtract,
    this.isSelected = false,
    this.hasExtracted = false,
    this.showCheckbox = false,
    this.checkboxPosition = CheckboxPosition.leading, // 默认左侧（向后兼容）
    this.showExtractButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 左侧：复选框（编辑模式且位置为leading）或图标（带角标）
            if (showCheckbox && checkboxPosition == CheckboxPosition.leading)
              Checkbox(
                value: isSelected,
                onChanged: (_) => onTap?.call(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )
            else if (!showCheckbox || checkboxPosition == CheckboxPosition.trailing)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildArchiveIcon(),
                  // 角标：已解压标记（内嵌到图标右上角）
                  if (hasExtracted)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check,
                          size: 14,
                          color: Colors.green[600],
                          weight: 700,
                        ),
                      ),
                    ),
                ],
              ),

            const SizedBox(width: 12),

            // 中间：文件信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 文件名（最多两行）
                  Text(
                    file.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // 文件大小 + 创建日期
                  Text(
                    _buildSubtitleText(),
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

            // 右侧：复选框（编辑模式且位置为trailing）或解压按钮（非编辑模式）
            if (showCheckbox && checkboxPosition == CheckboxPosition.trailing) ...[
              const SizedBox(width: 8),
              Checkbox(
                value: isSelected,
                onChanged: (_) => onTap?.call(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ] else if (showExtractButton && !showCheckbox) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_zip_outlined, size: 18),
                label: const Text('解压'),
                onPressed: onExtract,
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建压缩包图标
  Widget _buildArchiveIcon() {
    // 统一使用压缩包图标，不区分格式
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.folder_zip,
        size: 32,
        color: Colors.orange,
      ),
    );
  }

  /// 构建副标题文本（文件大小 + 创建日期）
  String _buildSubtitleText() {
    final sizeText = FileUtils.formatFileSize(file.size);
    final dateText = _formatDate(file.modified);
    return '$sizeText • $dateText';
  }

  /// 格式化日期
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      // 今天
      return '今天 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      // 昨天
      return '昨天 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      // 一周内
      return '${difference.inDays}天前';
    } else if (difference.inDays < 30) {
      // 一个月内
      final weeks = (difference.inDays / 7).floor();
      return '$weeks周前';
    } else if (difference.inDays < 365) {
      // 一年内
      return '${date.month}月${date.day}日';
    } else {
      // 超过一年
      return '${date.year}年${date.month}月${date.day}日';
    }
  }
}
