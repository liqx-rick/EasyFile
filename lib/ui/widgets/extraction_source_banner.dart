import 'package:flutter/material.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:provider/provider.dart';

/// 解压来源提示条
/// 
/// 在文件浏览页面顶部显示解压来源信息，提供返回快捷入口
class ExtractionSourceBanner extends StatelessWidget {
  const ExtractionSourceBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<FileViewModel>();
    final theme = Theme.of(context);

    // 如果没有解压上下文信息，不显示
    if (viewModel.extractionSourceName == null) {
      return const SizedBox.shrink();
    }

    // 只在解压目标路径或其父目录显示
    if (!viewModel.isExtractionTarget && !viewModel.isExtractionParent) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '已从压缩包解压',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  viewModel.extractionSourceName!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 关闭按钮
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              viewModel.clearExtractionContext();
            },
            tooltip: '关闭提示',
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            padding: EdgeInsets.zero,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
