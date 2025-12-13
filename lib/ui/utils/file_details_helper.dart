import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/junk_file_item.dart';
import 'package:easyfile/data/models/trash_file_item.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/ui/widgets/file_list_item_builder.dart';

/// 文件详情显示辅助类
/// 提供统一的文件详情面板显示方法
class FileDetailsHelper {
  /// 显示 FileItem 详情的 BottomSheet
  static void showFileDetailsBottomSheet(
    BuildContext context,
    FileItem file,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      isScrollControlled: true,
      constraints: isLandscape
          ? BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            )
          : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏（带关闭按钮）
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    file.isDirectory ? '文件夹详情' : '文件详情',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 内容区域（可滚动）
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 文件名/文件夹名
                    _buildDetailRow(
                      file.isDirectory ? '文件夹名' : '文件名',
                      file.name,
                      colorScheme,
                      isSelectable: true,
                    ),
                    const SizedBox(height: 16),

                    // 完整路径
                    _buildDetailRow(
                      '完整路径',
                      file.path,
                      colorScheme,
                      isSelectable: true,
                    ),
                    const SizedBox(height: 16),

                    // 文件大小（仅文件显示）
                    if (!file.isDirectory) ...[
                      _buildDetailRow(
                        '文件大小',
                        FileSizeFormatter.formatBytes(file.size),
                        colorScheme,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 文件夹子文件统计
                    if (file.isDirectory)
                      FutureBuilder<Map<String, int>>(
                        future: _getFolderStats(file.path),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            final stats = snapshot.data!;
                            final fileCount = stats['files'] ?? 0;
                            final folderCount = stats['folders'] ?? 0;
                            return Column(
                              children: [
                                _buildDetailRow(
                                  '包含内容',
                                  '$fileCount 个文件，$folderCount 个文件夹',
                                  colorScheme,
                                ),
                                const SizedBox(height: 16),
                              ],
                            );
                          } else if (snapshot.hasError) {
                            return Column(
                              children: [
                                _buildDetailRow(
                                  '包含内容',
                                  '无法读取',
                                  colorScheme,
                                ),
                                const SizedBox(height: 16),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                _buildDetailRow(
                                  '包含内容',
                                  '统计中...',
                                  colorScheme,
                                ),
                                const SizedBox(height: 16),
                              ],
                            );
                          }
                        },
                      ),

                    // 修改时间
                    _buildDetailRow(
                      '修改时间',
                      _formatDateTime(file.modified),
                      colorScheme,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 显示 JunkFileItem 详情的 BottomSheet
  static void showJunkFileDetailsBottomSheet(
    BuildContext context,
    JunkFileItem file,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    // 横屏模式下使用更大的高度比例
    final maxHeight = isLandscape ? screenHeight * 0.8 : screenHeight * 0.6;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight,
          minHeight: isLandscape ? screenHeight * 0.5 : 0,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // 标题
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  '文件详情',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 内容区域（可滚动）
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 文件名
                    _buildDetailRow(
                      '文件名',
                      file.name,
                      colorScheme,
                      isSelectable: true,
                    ),
                    const SizedBox(height: 16),

                    // 类型
                    _buildDetailRow(
                      '类型',
                      file.type.displayName,
                      colorScheme,
                    ),
                    const SizedBox(height: 16),

                    // 文件大小
                    _buildDetailRow(
                      '文件大小',
                      FileSizeFormatter.formatBytes(file.size),
                      colorScheme,
                    ),
                    const SizedBox(height: 16),

                    // 修改时间
                    _buildDetailRow(
                      '修改时间',
                      FileListItemBuilder.formatDetailDate(file.modified),
                      colorScheme,
                    ),

                    // 包名（如果有）
                    if (file.packageName != null) ...[
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        '包名',
                        file.packageName!,
                        colorScheme,
                        isSelectable: true,
                      ),
                    ],

                    const SizedBox(height: 16),
                    Divider(color: colorScheme.outlineVariant),
                    const SizedBox(height: 16),

                    // 完整路径
                    _buildDetailRow(
                      '完整路径',
                      file.path,
                      colorScheme,
                      isSelectable: true,
                      isPath: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: file.path));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('路径已复制到剪贴板'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('复制路径'),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建详情行
  static Widget _buildDetailRow(
    String label,
    String value,
    ColorScheme colorScheme, {
    bool isSelectable = false,
    bool isPath = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label：',
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: isSelectable
              ? SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface,
                    fontFamily: isPath ? 'monospace' : null,
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface,
                    fontFamily: isPath ? 'monospace' : null,
                  ),
                ),
        ),
      ],
    );
  }

  /// 格式化日期时间
  static String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// 获取文件夹统计信息（文件数和子文件夹数）
  static Future<Map<String, int>> _getFolderStats(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        return {'files': 0, 'folders': 0};
      }

      int fileCount = 0;
      int folderCount = 0;

      final entities = dir.listSync(followLinks: false);
      for (var entity in entities) {
        if (entity is File) {
          fileCount++;
        } else if (entity is Directory) {
          folderCount++;
        }
      }

      return {'files': fileCount, 'folders': folderCount};
    } catch (e) {
      return {'files': 0, 'folders': 0};
    }
  }

  /// 显示 TrashFileItem 详情的 BottomSheet
  /// 
  /// [trashBinName] - 回收站名称（需要从页面传入）
  /// [fileTypeLabel] - 文件类型标签（需要从页面传入）
  static void showTrashFileDetailsBottomSheet(
    BuildContext context,
    TrashFileItem file, {
    required String trashBinName,
    required String fileTypeLabel,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    // 横屏模式下使用更大的高度比例
    final maxHeight = isLandscape ? screenHeight * 0.8 : screenHeight * 0.6;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight,
          minHeight: isLandscape ? screenHeight * 0.5 : 0,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // 标题
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  '文件详情',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 详情内容区域（可滚动）
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow('文件名', file.name, colorScheme),
                    _buildDetailRow('文件类型', fileTypeLabel, colorScheme),
                    _buildDetailRow(
                      '大小',
                      FileSizeFormatter.formatBytes(file.size),
                      colorScheme,
                    ),
                    _buildDetailRow(
                      '删除时间',
                      FileListItemBuilder.formatDetailDate(
                          file.trashedTime ?? file.modified),
                      colorScheme,
                    ),
                    _buildDetailRow('回收站', trashBinName, colorScheme),
                    _buildDetailRow('完整路径', file.path, colorScheme,
                        isPath: true),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: file.path));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('路径已复制到剪贴板')),
                    );
                  },
                  child: const Text('复制路径'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }
}
