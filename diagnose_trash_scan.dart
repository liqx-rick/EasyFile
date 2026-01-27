import 'dart:io';

import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/preferences/system_trash_preferences.dart';
import 'package:easyfile/core/services/trash_file_service.dart';
import 'package:flutter/material.dart';

/// 系统回收站扫描诊断脚本
///
/// 用于检查系统回收站扫描功能为什么没有执行
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  logger.i('========== 系统回收站扫描诊断 ==========\n');

  // 1. 检查SharedPreferences状态
  logger.i('1. 检查SharedPreferences状态：');

  final lastScanTime = await SystemTrashPreferences.getLastScanTime();
  logger.i('   - 上次扫描时间: ${lastScanTime ?? "从未扫描"}');

  if (lastScanTime != null) {
    final elapsed = DateTime.now().difference(lastScanTime);
    logger.i('   - 距离现在: ${elapsed.inHours}小时${elapsed.inMinutes % 60}分钟');
    logger.i('   - 是否超过36小时: ${elapsed.inHours >= 36}');
  }

  final userDismissedUntil = await SystemTrashPreferences.getUserDismissedUntil();
  logger.i('   - 用户忽略截止时间: ${userDismissedUntil ?? "未设置"}');

  if (userDismissedUntil != null) {
    final inDismissedPeriod = DateTime.now().isBefore(userDismissedUntil);
    logger.i('   - 是否在忽略期内: $inDismissedPeriod');
  }

  final cleanedUntil = await SystemTrashPreferences.getCleanedUntil();
  logger.i('   - 清理抑制截止时间: ${cleanedUntil ?? "未设置"}');

  if (cleanedUntil != null) {
    final inSuppressionPeriod = DateTime.now().isBefore(cleanedUntil);
    logger.i('   - 是否在抑制期内: $inSuppressionPeriod');
  }

  // 2. 检查是否应该显示提示
  logger.i('\n2. 检查是否应该显示提示：');

  final config = AppConfig.instance.fileScan;
  final shouldScanByTime = await SystemTrashPreferences.isLastScanOlderThan(
    Duration(hours: config.systemTrashScanCacheHours),
  );
  logger.i('   - 扫描缓存已过期(${config.systemTrashScanCacheHours}小时): $shouldScanByTime');

  final isInUserDismissed = await SystemTrashPreferences.isInUserDismissedPeriod();
  logger.i('   - 在用户忽略期内(${config.systemTrashUserDismissDays}天): $isInUserDismissed');

  final isInSuppressionPeriod = await SystemTrashPreferences.isInCleanedSuppressionPeriod();
  logger.i('   - 在清理抑制期内(${config.systemTrashCleanSuppressionDays}天): $isInSuppressionPeriod');

  final shouldShow = shouldScanByTime && !isInUserDismissed && !isInSuppressionPeriod;
  logger.i('   - 最终结论: ${shouldShow ? "应该显示提示" : "不应该显示提示"}');

  // 3. 尝试扫描回收站
  logger.i('\n3. 尝试扫描回收站：');

  try {
    // 初始化依赖注入
    setupLocator();

    final service = TrashFileService();
    await service.initialize();

    logger.i('   - 正在扫描系统回收站...');

    final config = AppConfig.instance.fileScan;
    final stats = await service.getOldFilesStatistics(
      months: config.systemTrashOldFileMonths,
      forceRefresh: true,
    );

    final count = stats['count'] as int;
    final sizeMB = stats['sizeMB'] as int;
    final oldestFileDate = stats['oldestFileDate'] as DateTime?;

    logger.i('   - 扫描完成！');
    logger.i('   - 文件数量: $count');
    logger.i('   - 占用空间: ${sizeMB}MB');
    logger.i('   - 最久文件: ${oldestFileDate ?? "无"}');
    logger.i('   - 是否满足显示阈值(>=${config.systemTrashScanThresholdMB}MB): ${sizeMB >= config.systemTrashScanThresholdMB}');

    // 4. 给出诊断结论
    logger.i('\n========== 诊断结论 ==========');

    if (!shouldShow) {
      logger.i('【原因】系统回收站扫描被抑制：');
      if (!shouldScanByTime) {
        logger.i('  - 距离上次扫描未超过${config.systemTrashScanCacheHours}小时');
      }
      if (isInUserDismissed) {
        logger.i('  - 用户设置了${config.systemTrashUserDismissDays}天内不再提示');
      }
      if (isInSuppressionPeriod) {
        logger.i('  - 清理后${config.systemTrashCleanSuppressionDays}天内的抑制期');
      }
      logger.i('\n【解决方案】');
      logger.i('  1. 等待抑制期结束');
      logger.i('  2. 或运行以下命令清除抑制状态：');
      logger.i('     await SystemTrashPreferences.resetAll()');
    } else if (sizeMB < config.systemTrashScanThresholdMB) {
      logger.i('【原因】系统回收站文件未达到显示阈值：');
      logger.i('  - 当前: ${sizeMB}MB');
      logger.i('  - 阈值: ${config.systemTrashScanThresholdMB}MB');
      logger.i('\n【解决方案】');
      logger.i('  这是正常的，只有当回收站有>=${config.systemTrashScanThresholdMB}MB的旧文件时才会显示提示');
    } else {
      logger.i('【原因】未知，功能应该正常工作');
      logger.i('  - 检查垃圾文件清理页面是否正确调用了_loadOrScanSystemTrash()');
      logger.i('  - 检查是否有异常被捕获但未记录');
    }
  } catch (e, stackTrace) {
    logger.e('   ❌ 扫描失败: $e');
    logger.e('   堆栈跟踪: $stackTrace');
  }

  logger.i('\n========== 诊断完成 ==========');
  exit(0);
}
