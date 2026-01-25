import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easyfile/core/services/extraction_notification_manager.dart';
import 'package:easyfile/core/models/extraction_completion_info.dart';
import 'package:easyfile/ui/pages/extracted_files_browser_page.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/di/locator.dart';
import 'dart:io';

/// 解压完成通知横幅
///
/// 显示在 ArchiveViewerPage 顶部，可展开/折叠
class ExtractionNotificationBanner extends StatelessWidget {
  final ExtractionNotificationManager manager;

  const ExtractionNotificationBanner({
    super.key,
    required this.manager,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: manager,
      builder: (context, child) {
        // 没有通知时不显示
        if (!manager.hasNotifications) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 折叠状态的标题栏
              _buildCollapsedHeader(context, theme),
              // 展开状态的任务列表
              if (manager.isExpanded) _buildExpandedList(context, theme),
            ],
          ),
        );
      },
    );
  }

  /// 构建折叠状态的标题栏
  Widget _buildCollapsedHeader(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 左侧：展开/收起按钮
          InkWell(
            onTap: () => manager.toggleExpanded(),
            child: Icon(
              manager.isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          // 中间：文本（可点击展开）
          Expanded(
            child: InkWell(
              onTap: () => manager.toggleExpanded(),
              child: Text(
                '${manager.notificationCount}个解压任务已完成',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // 右侧：关闭按钮
          InkWell(
            onTap: () => _showClearAllDialog(context),
            child: Icon(
              Icons.close,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建展开状态的任务列表
  Widget _buildExpandedList(BuildContext context, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 操作栏（全部清除按钮）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '解压完成通知',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    _showClearAllDialog(context);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '全部清除',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 任务列表
          ...manager.completions.map((info) => _buildTaskItem(
                context,
                theme,
                info,
              )),
        ],
      ),
    );
  }

  /// 构建单个任务项
  Widget _buildTaskItem(
    BuildContext context,
    ThemeData theme,
    ExtractionCompletionInfo info,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 文件名和状态
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Icon(
                  info.isSuccess ? Icons.check_circle : Icons.error,
                  size: 16,
                  color: info.isSuccess
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    info.archiveName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // 文件数量
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 0, 12, 12),
            child: Text(
              info.isSuccess
                  ? '${info.fileCount} 个文件'
                  : info.errorMessage ?? '解压失败',
              style: theme.textTheme.bodySmall?.copyWith(
                color: info.isSuccess
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
              ),
            ),
          ),
          // 操作按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (info.isSuccess) ...[
                  TextButton.icon(
                    onPressed: () => _openExtractedFolder(context, info),
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('查看'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                TextButton.icon(
                  onPressed: () => _removeNotification(context, info),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('删除'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 打开解压后的文件夹
  void _openExtractedFolder(
    BuildContext context,
    ExtractionCompletionInfo info,
  ) {
    // 检查文件夹是否存在
    final dir = Directory(info.extractPath);
    if (!dir.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('解压文件夹已被删除'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 获取必要的依赖
    final presenter = locator<FilePresenter>();
    final viewModel = context.read<FileViewModel>();

    // 跳转到解压文件浏览页面
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ExtractedFilesBrowserPage(
          archiveName: info.archiveName,
          extractedPath: info.extractPath,
          presenter: presenter,
          viewModel: viewModel,
        ),
      ),
    );
  }

  /// 移除通知
  void _removeNotification(
    BuildContext context,
    ExtractionCompletionInfo info,
  ) {
    manager.removeCompletion(info.id);
  }

  /// 显示清除所有通知的确认对话框
  void _showClearAllDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除所有通知'),
        content: const Text('确定要清除所有解压完成通知吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              manager.clearAll();
              Navigator.of(context).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
