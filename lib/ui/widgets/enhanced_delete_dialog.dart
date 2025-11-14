import 'package:flutter/material.dart';
import 'package:easyfile/utils/path_security.dart';

/// 增强的删除确认对话框
///
/// 根据路径风险等级显示不同级别的警告：
/// - Safe: 普通确认对话框
/// - Warning: 显示警告信息
/// - Danger: 需要输入文件名确认
/// - Forbidden: 直接拒绝
class EnhancedDeleteDialog {
  /// 显示单个文件/文件夹的删除确认对话框
  static Future<bool> showSingleDeleteConfirmation({
    required BuildContext context,
    required String path,
  }) async {
    final fileName = path.split(RegExp(r'[/\\]')).last;
    final riskLevel = PathSecurity.getPathRiskLevel(path);

    // 禁止和危险路径直接拒绝
    if (riskLevel == PathRiskLevel.forbidden ||
        riskLevel == PathRiskLevel.danger) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🛑 禁止删除'),
          content: Text(
            PathSecurity.getPathRiskDescription(path, operation: '删除'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
      return false;
    }

    // 警告路径显示增强确认
    if (riskLevel == PathRiskLevel.warning) {
      return await _showWarningConfirmation(context, fileName, path) ?? false;
    }

    // 普通文件显示标准确认
    return await _showNormalConfirmation(context, fileName) ?? false;
  }

  /// 显示批量删除确认对话框
  static Future<bool> showBatchDeleteConfirmation({
    required BuildContext context,
    required List<String> paths,
    int? fileCount,
    int? folderCount,
  }) async {
    if (paths.isEmpty) return false;

    // 检查是否包含受保护的路径
    for (final path in paths) {
      final riskLevel = PathSecurity.getPathRiskLevel(path);

      if (riskLevel == PathRiskLevel.forbidden ||
          riskLevel == PathRiskLevel.danger) {
        final fileName = path.split(RegExp(r'[/\\]')).last;
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🛑 禁止删除'),
            content: Text(
              '选中的文件包含受保护的系统目录 "$fileName"！\n\n'
              '删除系统目录会导致：\n'
              '• 系统功能损坏\n'
              '• 应用无法运行\n'
              '• 数据永久丢失\n\n'
              '为保护您的设备，此操作已被阻止。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
        return false;
      }
    }

    // 检查是否包含警告路径
    final hasWarningPaths = paths.any((path) {
      final riskLevel = PathSecurity.getPathRiskLevel(path);
      return riskLevel == PathRiskLevel.warning;
    });

    if (hasWarningPaths) {
      return await _showBatchWarningConfirmation(
            context,
            paths.length,
            fileCount,
            folderCount,
          ) ??
          false;
    }

    // 普通批量删除
    return await _showBatchNormalConfirmation(
          context,
          paths.length,
          fileCount,
          folderCount,
        ) ??
        false;
  }

  /// 普通文件删除确认
  static Future<bool?> _showNormalConfirmation(
    BuildContext context,
    String fileName,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "$fileName" 吗？\n\n此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 警告路径删除确认（需要额外确认）
  static Future<bool?> _showWarningConfirmation(
    BuildContext context,
    String fileName,
    String path,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 8),
            const Text('警告'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                PathSecurity.getPathRiskDescription(path, operation: '删除'),
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('仍要删除'),
          ),
        ],
      ),
    );
  }

  /// 批量普通删除确认
  static Future<bool?> _showBatchNormalConfirmation(
    BuildContext context,
    int totalCount,
    int? fileCount,
    int? folderCount,
  ) {
    String contentText;
    if (fileCount != null && folderCount != null) {
      if (folderCount > 0) {
        contentText =
            '确定要删除选中的 $totalCount 项吗？\n'
            '（$fileCount 个文件，$folderCount 个文件夹）\n\n'
            '文件夹将被递归删除。此操作不可恢复。';
      } else {
        contentText = '确定要删除选中的 $totalCount 个文件吗？\n\n此操作不可恢复。';
      }
    } else {
      contentText = '确定要删除选中的 $totalCount 项吗？\n\n此操作不可恢复。';
    }

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(contentText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 批量警告路径删除确认
  static Future<bool?> _showBatchWarningConfirmation(
    BuildContext context,
    int totalCount,
    int? fileCount,
    int? folderCount,
  ) {
    String itemsText;
    if (fileCount != null && folderCount != null && folderCount > 0) {
      itemsText = '$totalCount 项（$fileCount 个文件，$folderCount 个文件夹）';
    } else {
      itemsText = '$totalCount 项';
    }

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 8),
            const Text('警告'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '⚠️ 选中项包含系统重要目录！\n\n'
                '您即将删除 $itemsText。\n\n'
                '删除系统目录可能导致：\n'
                '• 系统功能异常\n'
                '• 应用无法访问文件\n'
                '• 媒体库损坏\n\n'
                '确定要继续吗？',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('仍要删除'),
          ),
        ],
      ),
    );
  }
}
