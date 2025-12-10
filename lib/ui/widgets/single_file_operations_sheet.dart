import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/ui/services/single_file_operations_service.dart';
import 'package:easyfile/ui/widgets/image_thumbnail.dart';
import 'package:easyfile/ui/widgets/real_video_thumbnail.dart';
import 'package:easyfile/utils/file_utils.dart';

/// 单文件操作菜单组件
///
/// 在长按文件/文件夹时显示的操作菜单，提供：
/// 
/// 文件夹操作：
/// - 重命名
/// - 移动
/// - 复制
/// - 删除
///
/// 文件操作：
/// - 收藏/取消收藏
/// - 重命名
/// - 移动
/// - 复制
/// - 分享
/// - 打印（图片、PDF、文本）
/// - 查看详情
/// - 删除
///
/// 使用方式：
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   builder: (context) => SingleFileOperationsSheet(
///     file: fileItem,
///     service: singleFileOperationsService,
///   ),
/// );
/// ```
class SingleFileOperationsSheet extends StatelessWidget {
  final FileItem file;
  final SingleFileOperationsService service;

  const SingleFileOperationsSheet({
    super.key,
    required this.file,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 文件信息头部
          _buildHeader(context),

          const Divider(height: 1),

          // 操作列表
          _buildOperationsList(context),

          // 底部安全区域
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  /// 构建文件信息头部
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // 文件图标/缩略图
          _buildFileIcon(),

          const SizedBox(width: 12),

          // 文件基本信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  file.isDirectory
                      ? '文件夹'
                      : FileUtils.formatFileSize(file.size),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          // 关闭按钮
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  /// 构建操作列表
  Widget _buildOperationsList(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 文件夹操作
        if (file.isDirectory) ...[
          _buildOperationTile(
            context,
            icon: Icons.edit,
            label: '重命名',
            onTap: () => _handleOperation(
              context,
              () => service.renameFile(file),
            ),
          ),
          _buildOperationTile(
            context,
            icon: Icons.drive_file_move,
            label: '移动',
            onTap: () => _handleOperation(
              context,
              () => service.moveFile(file),
            ),
          ),
          _buildOperationTile(
            context,
            icon: Icons.content_copy,
            label: '复制',
            onTap: () => _handleOperation(
              context,
              () => service.copyFile(file),
            ),
          ),
          const Divider(height: 1),
          _buildOperationTile(
            context,
            icon: Icons.delete,
            label: '删除',
            color: Colors.red,
            onTap: () => _handleOperation(
              context,
              () => service.deleteFile(file),
            ),
          ),
        ],

        // 文件操作
        if (!file.isDirectory) ...[
          // 收藏/取消收藏
          _buildOperationTile(
            context,
            icon: service.viewModel.isFavoriteFile(file.path)
                ? Icons.star
                : Icons.star_border,
            label: service.viewModel.isFavoriteFile(file.path)
                ? '取消收藏'
                : '添加到收藏',
            color: Colors.amber,
            onTap: () => _handleOperation(
              context,
              () => service.toggleFavorite(file),
            ),
          ),

          // 重命名
          _buildOperationTile(
            context,
            icon: Icons.edit,
            label: '重命名',
            onTap: () => _handleOperation(
              context,
              () => service.renameFile(file),
            ),
          ),

          // 移动
          _buildOperationTile(
            context,
            icon: Icons.drive_file_move,
            label: '移动',
            onTap: () => _handleOperation(
              context,
              () => service.moveFile(file),
            ),
          ),

          // 复制
          _buildOperationTile(
            context,
            icon: Icons.content_copy,
            label: '复制',
            onTap: () => _handleOperation(
              context,
              () => service.copyFile(file),
            ),
          ),

          // 分享
          _buildOperationTile(
            context,
            icon: Icons.share,
            label: '分享',
            onTap: () => _handleOperation(
              context,
              () => service.shareFile(file),
            ),
          ),

          // 打印（仅支持的文件类型）
          if (service.canPrint(file))
            _buildOperationTile(
              context,
              icon: Icons.print,
              label: '打印',
              onTap: () => _handleOperation(
                context,
                () => service.printFile(file),
              ),
            ),

          const Divider(height: 1),

          // 查看详情（使用 BottomSheet 版本）
          _buildOperationTile(
            context,
            icon: Icons.info_outline,
            label: '查看详情',
            onTap: () {
              Navigator.pop(context); // 关闭操作菜单
              service.showFileDetails(file, useBottomSheet: true); // 使用 BottomSheet
            },
          ),

          const Divider(height: 1),

          // 删除
          _buildOperationTile(
            context,
            icon: Icons.delete,
            label: '删除',
            color: Colors.red,
            onTap: () => _handleOperation(
              context,
              () => service.deleteFile(file),
            ),
          ),
        ],
      ],
    );
  }

  /// 构建操作项
  Widget _buildOperationTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, size: 22, color: color),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          color: color,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      dense: true,
    );
  }

  /// 构建文件图标/缩略图
  Widget _buildFileIcon() {
    if (FileUtils.isImageFile(file.name)) {
      return ImageThumbnail(imagePath: file.path, size: 48);
    } else if (FileUtils.isVideoFile(file.name)) {
      return RealVideoThumbnail(
        videoPath: file.path,
        size: 48,
        showDuration: false,
      );
    } else if (file.isDirectory) {
      return const Icon(Icons.folder, size: 48, color: Colors.amber);
    } else {
      return Icon(
        Icons.insert_drive_file,
        size: 48,
        color: Colors.grey[600],
      );
    }
  }

  /// 处理操作（关闭菜单并执行操作）
  Future<void> _handleOperation(
    BuildContext context,
    Future<dynamic> Function() operation,
  ) async {
    Navigator.pop(context); // 先关闭菜单
    await operation(); // 再执行操作
  }
}
