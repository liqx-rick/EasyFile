import 'package:flutter/material.dart';

/// 无权限空状态组件
/// 当用户未授予存储权限时显示此引导页面
class EmptyStatePermission extends StatelessWidget {
  final VoidCallback onRequestPermission;
  final bool isPermanentlyDenied;

  const EmptyStatePermission({
    super.key,
    required this.onRequestPermission,
    this.isPermanentlyDenied = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 图标
            Icon(
              Icons.folder_off_outlined,
              size: 80,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),

            // 标题
            Text(
              '需要访问存储权限',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // 说明文字
            Text(
              isPermanentlyDenied
                  ? 'EasyFile 需要"所有文件访问权限"来浏览和管理您的文件。\n\n请在弹出的设置页面中，打开"允许管理所有文件"开关。'
                  : 'EasyFile 需要存储权限来浏览和管理您的文件。\n\n建议选择"允许访问所有媒体"以获得完整功能。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // 权限说明卡片
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '权限用途说明',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildPermissionItem(
                    context,
                    Icons.photo_library_outlined,
                    '浏览图片、视频和音频文件',
                  ),
                  const SizedBox(height: 8),
                  _buildPermissionItem(
                    context,
                    Icons.description_outlined,
                    '管理文档和其他文件',
                  ),
                  const SizedBox(height: 8),
                  _buildPermissionItem(
                    context,
                    Icons.folder_outlined,
                    '创建和管理文件夹',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 授权按钮
            FilledButton.icon(
              onPressed: onRequestPermission,
              icon: Icon(
                isPermanentlyDenied ? Icons.settings : Icons.check_circle,
              ),
              label: Text(
                isPermanentlyDenied ? '前往设置' : '授予权限',
                style: const TextStyle(fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            // 提示文字
            if (!isPermanentlyDenied) ...[
              const SizedBox(height: 16),
              Text(
                '点击按钮后将弹出权限请求对话框',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionItem(
    BuildContext context,
    IconData icon,
    String text,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.7),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}
