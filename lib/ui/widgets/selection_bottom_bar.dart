import 'dart:io';
import 'package:flutter/material.dart';
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
  /// 用于判断是否可以执行特定操作（如分享仅支持文件）
  _SelectionStats _calculateStats() {
    int fileCount = 0;
    int folderCount = 0;

    for (final path in selectedPaths) {
      try {
        final entity = FileSystemEntity.typeSync(path);
        if (entity == FileSystemEntityType.directory) {
          folderCount++;
        } else if (entity == FileSystemEntityType.file) {
          fileCount++;
        }
      } catch (e) {
        logger.w('Failed to check file type: $path');
      }
    }

    return _SelectionStats(
      fileCount: fileCount,
      folderCount: folderCount,
      hasOnlyFiles: folderCount == 0 && fileCount > 0,
      hasFiles: fileCount > 0,
      isSingleSelection: selectedPaths.length == 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _calculateStats();
    final hasSelection = selectedPaths.isNotEmpty;

    return BottomAppBar(
      height: 66,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            // 显示选中信息
            Expanded(
              child: Text(
                hasSelection ? '已选择 ${selectedPaths.length} 项' : '请选择文件或文件夹',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: hasSelection ? null : Colors.grey,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 操作按钮区域 - 移动、删除、更多
            const SizedBox(width: 8),
            
            // 移动按钮
            TextButton.icon(
              icon: const Icon(Icons.drive_file_move, size: 18),
              label: const Text('移动'),
              onPressed: hasSelection && onMove != null ? onMove : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),

            const SizedBox(width: 4),

            // 删除按钮
            TextButton.icon(
              icon: const Icon(Icons.delete, size: 18),
              label: const Text('删除'),
              onPressed: hasSelection && onDelete != null ? onDelete : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),

            const SizedBox(width: 4),

            // 更多菜单按钮
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 22),
              tooltip: '更多操作',
              enabled: hasSelection,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              iconColor: hasSelection ? null : Colors.grey,
              position: PopupMenuPosition.under,
              offset: const Offset(0, 8),
              onSelected: (value) {
                switch (value) {
                  case 'copy':
                    onCopy?.call();
                    break;
                  case 'rename':
                    onRename?.call();
                    break;
                  case 'share':
                    onShare?.call();
                    break;
                  case 'favorite':
                    onToggleFavorite?.call();
                    break;
                }
              },
              itemBuilder: (context) => [
                // 复制
                PopupMenuItem<String>(
                  value: 'copy',
                  enabled: hasSelection && onCopy != null,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: SizedBox(
                    width: 120,
                    child: Row(
                      children: [
                        Icon(
                          Icons.copy,
                          size: 20,
                          color: hasSelection
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '复制',
                          style: TextStyle(
                            fontSize: 14,
                            color: hasSelection
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 重命名（仅单选）
                PopupMenuItem<String>(
                  value: 'rename',
                  enabled: stats.isSingleSelection && onRename != null,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: SizedBox(
                    width: 120,
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit,
                          size: 20,
                          color: stats.isSingleSelection
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '重命名',
                            style: TextStyle(
                              fontSize: 14,
                              color: stats.isSingleSelection
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        if (!stats.isSingleSelection)
                          Text(
                            '需单选',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // 分享（仅文件）
                if (onShare != null)
                  PopupMenuItem<String>(
                    value: 'share',
                    enabled: stats.hasOnlyFiles && hasSelection,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: SizedBox(
                      width: 120,
                      child: Row(
                        children: [
                          Icon(
                            Icons.share,
                            size: 20,
                            color: stats.hasOnlyFiles
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '分享',
                              style: TextStyle(
                                fontSize: 14,
                                color: stats.hasOnlyFiles
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          if (!stats.hasOnlyFiles)
                            Text(
                              '仅文件',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                // 收藏/取消收藏（仅文件）
                if (onToggleFavorite != null)
                  PopupMenuItem<String>(
                    value: 'favorite',
                    enabled: stats.hasFiles && hasSelection,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: SizedBox(
                      width: 140,
                      child: Row(
                        children: [
                          Icon(
                            isAllFavorite ? Icons.star : Icons.star_border,
                            size: 20,
                            color: stats.hasFiles
                                ? (isAllFavorite
                                    ? Colors.amber
                                    : Theme.of(context).colorScheme.onSurface)
                                : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isAllFavorite ? '取消收藏' : '添加收藏',
                              style: TextStyle(
                                fontSize: 14,
                                color: stats.hasFiles
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          if (!stats.hasFiles)
                            Text(
                              '仅文件',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 选中项统计信息
/// 用于判断操作按钮的可用性
class _SelectionStats {
  final int fileCount;
  final int folderCount;
  final bool hasOnlyFiles; // 只有文件，没有文件夹（用于分享功能判断）
  final bool hasFiles; // 有文件（不管是否有文件夹，用于收藏功能判断）
  final bool isSingleSelection; // 单选（用于重命名功能判断）

  _SelectionStats({
    required this.fileCount,
    required this.folderCount,
    required this.hasOnlyFiles,
    required this.hasFiles,
    required this.isSingleSelection,
  });
}
