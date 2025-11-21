import 'package:flutter/material.dart';

/// 底部文件夹导航栏组件
/// 用于在子文件夹中提供返回上级目录的功能
/// 设计目标：优化移动端单手操作体验
class FolderNavigationBar extends StatelessWidget {
  final String currentPath;
  final VoidCallback onBackPressed;

  const FolderNavigationBar({
    super.key,
    required this.currentPath,
    required this.onBackPressed,
  });

  /// 格式化路径显示，移除Android存储前缀
  String _formatPath(String path) {
    // 移除 /storage/emulated/0 前缀
    const androidStoragePrefix = '/storage/emulated/0';
    if (path.startsWith(androidStoragePrefix)) {
      final relativePath = path.substring(androidStoragePrefix.length);
      // 如果是根目录，显示 "/"
      if (relativePath.isEmpty || relativePath == '/') {
        return '/';
      }
      // 确保路径以 / 开头
      return relativePath.startsWith('/') ? relativePath : '/$relativePath';
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onBackPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_back,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _formatPath(currentPath),
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
