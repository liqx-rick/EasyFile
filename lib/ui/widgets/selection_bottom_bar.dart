import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/core/logger.dart';

/// 批量选择操作底部工具栏
///
/// 提供文件/文件夹的批量操作功能，包括：
/// - 复制（单个）
/// - 重命名（单个）
/// - 分享（仅文件）
/// - 移动
/// - 收藏/取消收藏（仅文件）
/// - 删除
class SelectionBottomBar extends StatelessWidget {
  /// 选中项的路径集合
  final Set<String> selectedPaths;

  /// 是否所有选中的文件都已收藏
  final bool isAllFavorite;

  /// 复制操作回调（单个项目）
  final VoidCallback? onCopy;

  /// 重命名操作回调（单个项目）
  final VoidCallback? onRename;

  /// 分享操作回调（仅文件）
  final VoidCallback? onShare;

  /// 移动操作回调
  final VoidCallback? onMove;

  /// 收藏/取消收藏操作回调（仅文件）
  final VoidCallback? onToggleFavorite;

  /// 删除操作回调
  final VoidCallback? onDelete;

  const SelectionBottomBar({
    super.key,
    required this.selectedPaths,
    required this.isAllFavorite,
    this.onCopy,
    this.onRename,
    this.onShare,
    this.onMove,
    this.onToggleFavorite,
    this.onDelete,
  });

  /// 统计选中项的文件和文件夹信息
  _SelectionStats _calculateStats() {
    int fileCount = 0;
    int folderCount = 0;
    int totalSize = 0;

    for (final path in selectedPaths) {
      try {
        final entity = FileSystemEntity.typeSync(path);
        if (entity == FileSystemEntityType.directory) {
          folderCount++;
        } else if (entity == FileSystemEntityType.file) {
          fileCount++;
          try {
            totalSize += File(path).lengthSync();
          } catch (e) {
            logger.w('Failed to get file size: $path');
          }
        }
      } catch (e) {
        logger.w('Failed to check file type: $path');
      }
    }

    return _SelectionStats(
      fileCount: fileCount,
      folderCount: folderCount,
      totalSize: totalSize,
      hasOnlyFiles: folderCount == 0 && fileCount > 0,
      isSingleSelection: selectedPaths.length == 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _calculateStats();
    final hasSelection = selectedPaths.isNotEmpty;

    return BottomAppBar(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // 显示选中信息
            Expanded(
              child: Text(
                hasSelection ? _buildSelectionInfo(stats) : '请选择文件或文件夹',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: hasSelection ? null : Colors.grey,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 操作按钮 - 始终显示，通过启用/禁用控制
            // 复制按钮（单个文件/文件夹）
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed:
                  stats.isSingleSelection && onCopy != null ? onCopy : null,
              tooltip: '复制',
              color: stats.isSingleSelection ? null : Colors.grey,
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(
                horizontal: -4,
                vertical: -4,
              ),
            ),

            // 重命名按钮（单个文件/文件夹）
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed:
                  stats.isSingleSelection && onRename != null ? onRename : null,
              tooltip: '重命名',
              color: stats.isSingleSelection ? null : Colors.grey,
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(
                horizontal: -4,
                vertical: -4,
              ),
            ),

            // 分享按钮（只有文件可以分享）
            if (onShare != null)
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: stats.hasOnlyFiles && hasSelection ? onShare : null,
                tooltip: '分享',
                color: stats.hasOnlyFiles && hasSelection ? null : Colors.grey,
                padding: EdgeInsets.zero,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
              ),

            // 移动按钮
            IconButton(
              icon: const Icon(Icons.drive_file_move),
              onPressed: hasSelection && onMove != null ? onMove : null,
              tooltip: '移动',
              color: hasSelection ? null : Colors.grey,
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),

            // 批量收藏/取消收藏按钮（只有文件可以收藏）
            IconButton(
              icon: Icon(isAllFavorite ? Icons.star : Icons.star_border),
              onPressed:
                  stats.hasOnlyFiles && hasSelection && onToggleFavorite != null
                      ? onToggleFavorite
                      : null,
              tooltip: isAllFavorite ? '取消收藏' : '添加收藏',
              color: stats.hasOnlyFiles && hasSelection
                  ? (isAllFavorite ? Colors.amber : null)
                  : Colors.grey,
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),

            // 删除按钮
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: hasSelection && onDelete != null ? onDelete : null,
              tooltip: '删除',
              color: hasSelection ? null : Colors.grey,
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建选中信息文本
  String _buildSelectionInfo(_SelectionStats stats) {
    final parts = <String>[];
    if (stats.fileCount > 0) parts.add('${stats.fileCount} 个文件');
    if (stats.folderCount > 0) parts.add('${stats.folderCount} 个文件夹');
    final info = parts.join('，');
    if (stats.totalSize > 0) {
      return '$info · ${FileUtils.formatFileSize(stats.totalSize)}';
    }
    return info;
  }
}

/// 选中项统计信息
class _SelectionStats {
  final int fileCount;
  final int folderCount;
  final int totalSize;
  final bool hasOnlyFiles;
  final bool isSingleSelection;

  _SelectionStats({
    required this.fileCount,
    required this.folderCount,
    required this.totalSize,
    required this.hasOnlyFiles,
    required this.isSingleSelection,
  });
}
