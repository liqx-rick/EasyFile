import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/preferences/system_trash_preferences.dart';

/// 系统回收站扫描行为测试
///
/// 模拟修复前后的实际场景，验证36小时缓存策略是否正确实现
void main() {
  group('修复验证：模拟实际扫描场景', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SystemTrashPreferences.resetAll();
    });

    /// 模拟 _shouldShowSystemTrashPrompt() 的完整逻辑
    Future<bool> shouldShowPrompt() async {
      // 检查上次扫描时间（36小时缓存策略）
      if (!await SystemTrashPreferences.isLastScanOlderThan(
        const Duration(hours: 36),
      )) {
        return false;
      }

      // 检查用户忽略期（7天）
      if (await SystemTrashPreferences.isInUserDismissedPeriod()) {
        return false;
      }

      // 检查清理抑制期（7天）
      if (await SystemTrashPreferences.isInCleanedSuppressionPeriod()) {
        return false;
      }

      return true;
    }

    /// 模拟扫描并记录时间（修复后的逻辑）
    Future<void> scanAndRecordTime() async {
      // 模拟扫描（实际会调用 getOldFilesStatistics）
      // ...扫描逻辑...

      // 关键：无论文件大小，都记录扫描时间
      await SystemTrashPreferences.setLastScanTimeNow();
    }

    test('【修复前的问题】80MB文件，1小时后会重新扫描', () async {
      // T=0: 首次进入，扫描发现80MB
      expect(await shouldShowPrompt(), true, reason: 'T=0: 首次进入，应该扫描');

      // 模拟修复前的逻辑：只有>=100MB才记录时间
      // await scanAndRecordTime(); // ❌ 不执行

      // T=1小时: 再次进入
      // 模拟1小时后
      // 由于没有记录lastScanTime，36小时检查会返回true
      expect(
        await SystemTrashPreferences.isLastScanOlderThan(
          const Duration(hours: 36),
        ),
        true,
        reason: 'T=1小时: 没有lastScanTime，会判断为需要扫描',
      );
      expect(
        await shouldShowPrompt(),
        true,
        reason: 'T=1小时: 问题重现 - 会重新扫描',
      );
    });

    test('【修复后的行为】80MB文件，36小时内不会重新扫描', () async {
      // T=0: 首次进入，扫描发现80MB
      expect(await shouldShowPrompt(), true, reason: 'T=0: 首次进入，应该扫描');

      // 修复后的逻辑：无论文件大小都记录时间
      await scanAndRecordTime(); // ✅ 执行

      // T=1小时: 再次进入
      final prefs = await SharedPreferences.getInstance();
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      await prefs.setInt(
        'system_trash_last_scan_time',
        oneHourAgo.millisecondsSinceEpoch,
      );

      expect(
        await SystemTrashPreferences.isLastScanOlderThan(
          const Duration(hours: 36),
        ),
        false,
        reason: 'T=1小时: 有lastScanTime且在36小时内',
      );
      expect(
        await shouldShowPrompt(),
        false,
        reason: 'T=1小时: 修复成功 - 不会重新扫描',
      );
    });

    test('【修复后的行为】80MB文件，37小时后才重新扫描', () async {
      // T=0: 首次进入并记录时间
      await scanAndRecordTime();

      // T=37小时: 再次进入
      final prefs = await SharedPreferences.getInstance();
      final hours37Ago = DateTime.now().subtract(const Duration(hours: 37));
      await prefs.setInt(
        'system_trash_last_scan_time',
        hours37Ago.millisecondsSinceEpoch,
      );

      expect(
        await SystemTrashPreferences.isLastScanOlderThan(
          const Duration(hours: 36),
        ),
        true,
        reason: 'T=37小时: 超过36小时，应该扫描',
      );
      expect(
        await shouldShowPrompt(),
        true,
        reason: 'T=37小时: 超过36小时，允许重新扫描',
      );
    });

    test('完整时间线测试：模拟多次进入页面', () async {
      // T=0分钟: 首次进入
      expect(await shouldShowPrompt(), true, reason: 'T=0: 首次扫描');
      await scanAndRecordTime();

      // T=30分钟: 再次进入
      var prefs = await SharedPreferences.getInstance();
      var scanTime = DateTime.now().subtract(const Duration(minutes: 30));
      await prefs.setInt(
          'system_trash_last_scan_time', scanTime.millisecondsSinceEpoch);
      expect(await shouldShowPrompt(), false, reason: 'T=30分钟: 不扫描');

      // T=1小时: 再次进入
      scanTime = DateTime.now().subtract(const Duration(hours: 1));
      await prefs.setInt(
          'system_trash_last_scan_time', scanTime.millisecondsSinceEpoch);
      expect(await shouldShowPrompt(), false, reason: 'T=1小时: 不扫描');

      // T=12小时: 再次进入
      scanTime = DateTime.now().subtract(const Duration(hours: 12));
      await prefs.setInt(
          'system_trash_last_scan_time', scanTime.millisecondsSinceEpoch);
      expect(await shouldShowPrompt(), false, reason: 'T=12小时: 不扫描');

      // T=24小时: 再次进入
      scanTime = DateTime.now().subtract(const Duration(hours: 24));
      await prefs.setInt(
          'system_trash_last_scan_time', scanTime.millisecondsSinceEpoch);
      expect(await shouldShowPrompt(), false, reason: 'T=24小时: 不扫描');

      // T=35小时: 再次进入
      scanTime = DateTime.now().subtract(const Duration(hours: 35));
      await prefs.setInt(
          'system_trash_last_scan_time', scanTime.millisecondsSinceEpoch);
      expect(await shouldShowPrompt(), false, reason: 'T=35小时: 不扫描');

      // T=37小时: 再次进入
      scanTime = DateTime.now().subtract(const Duration(hours: 37));
      await prefs.setInt(
          'system_trash_last_scan_time', scanTime.millisecondsSinceEpoch);
      expect(await shouldShowPrompt(), true, reason: 'T=37小时: 应该扫描');
    });

    test('抑制期优先级测试：即使超过36小时，抑制期也生效', () async {
      // 设置37小时前的扫描时间
      final prefs = await SharedPreferences.getInstance();
      final hours37Ago = DateTime.now().subtract(const Duration(hours: 37));
      await prefs.setInt(
          'system_trash_last_scan_time', hours37Ago.millisecondsSinceEpoch);

      // 设置用户忽略期
      await SystemTrashPreferences.setUserDismissedPeriod(
        const Duration(days: 7),
      );

      expect(
        await SystemTrashPreferences.isLastScanOlderThan(
          const Duration(hours: 36),
        ),
        true,
        reason: '扫描时间已过期',
      );
      expect(
        await shouldShowPrompt(),
        false,
        reason: '虽然超过36小时，但在用户忽略期内，不扫描',
      );
    });
  });

  group('性能影响分析', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SystemTrashPreferences.resetAll();
    });

    test('修复前：频繁扫描统计', () async {
      int scanCount = 0;

      // 模拟修复前：不记录扫描时间
      for (int hour = 0; hour < 48; hour++) {
        final shouldScan = await SystemTrashPreferences.isLastScanOlderThan(
          const Duration(hours: 36),
        );
        if (shouldScan) {
          scanCount++;
          // 注意：修复前不记录时间，所以每次都会扫描
        }
      }

      // 修复前：由于没有记录时间，48小时内会扫描48次
      expect(scanCount, 48, reason: '修复前：每次都扫描，48小时内扫描48次');
    });

    test('修复后：合理扫描统计', () async {
      int scanCount = 0;

      // 模拟修复后：记录扫描时间
      for (int hour = 0; hour < 48; hour++) {
        final shouldScan = await SystemTrashPreferences.isLastScanOlderThan(
          const Duration(hours: 36),
        );

        if (shouldScan) {
          scanCount++;
          // 修复后：记录扫描时间
          await SystemTrashPreferences.setLastScanTimeNow();
        }

        // 模拟时间流逝1小时
        if (hour < 47) {
          final prefs = await SharedPreferences.getInstance();
          final currentScanTime =
              await SystemTrashPreferences.getLastScanTime();
          if (currentScanTime != null) {
            final nextHour = currentScanTime.subtract(const Duration(hours: 1));
            await prefs.setInt(
              'system_trash_last_scan_time',
              nextHour.millisecondsSinceEpoch,
            );
          }
        }
      }

      // 修复后：48小时内只扫描2次（0小时、37小时）
      expect(scanCount, 2, reason: '修复后：48小时内只扫描2次');
    });
  });
}
