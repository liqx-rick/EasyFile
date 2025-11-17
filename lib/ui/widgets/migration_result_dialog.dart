import 'package:flutter/material.dart';
import '../../data/services/data_migration_service.dart';

/// 数据迁移结果对话框
class MigrationResultDialog extends StatelessWidget {
  final MigrationResult result;

  const MigrationResultDialog({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasErrors = result.failedCount > 0;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            hasErrors ? Icons.warning_amber : Icons.check_circle,
            color: hasErrors ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 12),
          const Text('数据迁移完成'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 迁移统计
            _buildStatRow('总计', result.totalCount, theme),
            _buildStatRow('成功', result.successCount, theme, Colors.green),
            if (result.skippedCount > 0)
              _buildStatRow('跳过', result.skippedCount, theme, Colors.orange),
            if (result.failedCount > 0)
              _buildStatRow('失败', result.failedCount, theme, Colors.red),

            // 错误信息
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                '错误详情：',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              ...result.errors.take(5).map(
                    (error) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $error',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              if (result.errors.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '... 还有 ${result.errors.length - 5} 个错误',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],

            // 说明文本
            if (result.successCount > 0) ...[
              const SizedBox(height: 16),
              Text(
                '您的收藏已成功迁移到快捷访问功能。',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('确定'),
        ),
      ],
    );
  }

  /// 构建统计行
  Widget _buildStatRow(
    String label,
    int count,
    ThemeData theme, [
    Color? valueColor,
  ]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label：',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          Text(
            count.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  /// 显示迁移结果对话框
  static void show(BuildContext context, MigrationResult result) {
    showDialog(
      context: context,
      builder: (context) => MigrationResultDialog(result: result),
    );
  }
}
