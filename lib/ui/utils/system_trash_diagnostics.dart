import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/preferences/system_trash_preferences.dart';
import 'package:easyfile/core/services/trash_file_service.dart';
import 'package:flutter/material.dart';

/// 系统回收站诊断工具
///
/// 用于开发者选项中诊断系统回收站扫描功能
class SystemTrashDiagnostics {
  /// 显示系统回收站诊断信息对话框
  static Future<void> show(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在检查系统回收站...'),
          ],
        ),
      ),
    );

    try {
      final config = AppConfig.instance.fileScan;

      // 检查SharedPreferences状态
      final lastScanTime = await SystemTrashPreferences.getLastScanTime();
      final userDismissedUntil = await SystemTrashPreferences.getUserDismissedUntil();
      final cleanedUntil = await SystemTrashPreferences.getCleanedUntil();

      final shouldScanByTime = await SystemTrashPreferences.isLastScanOlderThan(
        Duration(hours: config.systemTrashScanCacheHours),
      );
      final isInUserDismissed = await SystemTrashPreferences.isInUserDismissedPeriod();
      final isInSuppressionPeriod = await SystemTrashPreferences.isInCleanedSuppressionPeriod();

      // 强制扫描回收站
      final service = await locator.getAsync<TrashFileService>();
      await service.initialize();

      final stats = await service.getOldFilesStatistics(
        months: config.systemTrashOldFileMonths,
        forceRefresh: true,
      );

      final count = stats['count'] as int;
      final sizeMB = stats['sizeMB'] as int;
      final oldestFileDate = stats['oldestFileDate'] as DateTime?;

      if (!context.mounted) return;

      Navigator.of(context).pop(); // 关闭加载对话框

      // 显示诊断结果
      if (!context.mounted) return;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('系统回收站诊断'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSection(
                  '📊 扫描结果',
                  [
                    '文件数量: $count',
                    '占用空间: ${sizeMB}MB',
                    '最久文件: ${oldestFileDate ?? "无"}',
                    '显示阈值: ${sizeMB >= config.systemTrashScanThresholdMB ? "✅ 已达到(>=${config.systemTrashScanThresholdMB}MB)" : "❌ 未达到(<${config.systemTrashScanThresholdMB}MB)"}',
                  ],
                ),
                const Divider(height: 24),
                _buildSection(
                  '🔍 抑制状态',
                  [
                    '上次扫描: ${lastScanTime ?? "从未扫描"}',
                    if (lastScanTime != null) '距离现在: ${DateTime.now().difference(lastScanTime).inHours}小时',
                    '缓存已过期(${config.systemTrashScanCacheHours}小时): ${shouldScanByTime ? "✅ 是" : "❌ 否"}',
                    '',
                    '用户忽略期(${config.systemTrashUserDismissDays}天): ${isInUserDismissed ? "⚠️ 是" : "✅ 否"}',
                    if (userDismissedUntil != null) '  截止: $userDismissedUntil',
                    '',
                    '清理抑制期(${config.systemTrashCleanSuppressionDays}天): ${isInSuppressionPeriod ? "⚠️ 是" : "✅ 否"}',
                    if (cleanedUntil != null) '  截止: $cleanedUntil',
                  ],
                ),
                const Divider(height: 24),
                _buildSection(
                  '💡 结论',
                  [
                    _getDiagnosticConclusion(
                      config: config,
                      shouldScanByTime: shouldScanByTime,
                      isInUserDismissed: isInUserDismissed,
                      isInSuppressionPeriod: isInSuppressionPeriod,
                      sizeMB: sizeMB,
                    ),
                  ],
                  textColor: Colors.red.shade700,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                
                await SystemTrashPreferences.resetAll();
                navigator.pop();
                
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('已清除所有抑制状态'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('重置抑制状态'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      if (!context.mounted) return;
      
      
      Navigator.of(context).pop(); // 关闭加载对话框
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('诊断失败'),
          content: Text('错误: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    }
  }

  static Widget _buildSection(
    String title,
    List<String> items, {
    Color? textColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 13,
                  color: textColor,
                ),
              ),
            )),
      ],
    );
  }

  static String _getDiagnosticConclusion({
    required dynamic config,
    required bool shouldScanByTime,
    required bool isInUserDismissed,
    required bool isInSuppressionPeriod,
    required int sizeMB,
  }) {
    if (!shouldScanByTime) {
      return '系统回收站扫描被抑制：距离上次扫描未超过${config.systemTrashScanCacheHours}小时';
    }
    if (isInUserDismissed) {
      return '系统回收站扫描被抑制：用户设置了${config.systemTrashUserDismissDays}天内不再提示';
    }
    if (isInSuppressionPeriod) {
      return '系统回收站扫描被抑制：清理后${config.systemTrashCleanSuppressionDays}天内的抑制期';
    }
    if (sizeMB < config.systemTrashScanThresholdMB) {
      return '系统回收站文件未达到显示阈值：当前${sizeMB}MB < ${config.systemTrashScanThresholdMB}MB';
    }
    return '✅ 应该显示系统回收站提示（如果没有显示，可能是页面加载时的异常）';
  }
}
