import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/preferences/system_trash_preferences.dart';

/// 系统回收站36小时缓存策略测试
///
/// 验证修复后的行为：
/// 1. 无论文件大小，都应该记录扫描时间
/// 2. 36小时内不应该重复扫描
/// 3. 超过36小时后才重新扫描
void main() {
  group('SystemTrashPreferences - 36小时缓存策略', () {
    setUp(() async {
      // 每次测试前清理 SharedPreferences
      SharedPreferences.setMockInitialValues({});
      await SystemTrashPreferences.resetAll();
    });

    test('场景1: 从未扫描过，应该返回true（需要扫描）', () async {
      final shouldScan = await SystemTrashPreferences.isLastScanOlderThan(
        const Duration(hours: 36),
      );
      expect(shouldScan, true, reason: '从未扫描过，应该需要扫描');
    });

    test('场景2: 刚扫描完，不应该重复扫描', () async {
      // 记录扫描时间
      await SystemTrashPreferences.setLastScanTimeNow();

      // 立即检查
      final shouldScan = await SystemTrashPreferences.isLastScanOlderThan(
        const Duration(hours: 36),
      );
      expect(shouldScan, false, reason: '刚扫描完，不应该重复扫描');
    });

    test('场景3: 1小时后，仍在36小时内，不应该扫描', () async {
      // 模拟1小时前的扫描
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'system_trash_last_scan_time',
        oneHourAgo.millisecondsSinceEpoch,
      );

      final shouldScan = await SystemTrashPreferences.isLastScanOlderThan(
        const Duration(hours: 36),
      );
      expect(shouldScan, false, reason: '1小时前扫描过，36小时内不应该重复扫描');
    });

    test('场景4: 35小时后，仍在36小时内，不应该扫描', () async {
      // 模拟35小时前的扫描
      final hours35Ago = DateTime.now().subtract(const Duration(hours: 35));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'system_trash_last_scan_time',
        hours35Ago.millisecondsSinceEpoch,
      );

      final shouldScan = await SystemTrashPreferences.isLastScanOlderThan(
        const Duration(hours: 36),
      );
      expect(shouldScan, false, reason: '35小时前扫描过，36小时内不应该重复扫描');
    });

    test('场景5: 37小时后，超过36小时，应该重新扫描', () async {
      // 模拟37小时前的扫描
      final hours37Ago = DateTime.now().subtract(const Duration(hours: 37));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'system_trash_last_scan_time',
        hours37Ago.millisecondsSinceEpoch,
      );

      final shouldScan = await SystemTrashPreferences.isLastScanOlderThan(
        const Duration(hours: 36),
      );
      expect(shouldScan, true, reason: '37小时前扫描过，超过36小时应该重新扫描');
    });

    test('场景6: 2天后，超过36小时，应该重新扫描', () async {
      // 模拟2天前的扫描
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'system_trash_last_scan_time',
        twoDaysAgo.millisecondsSinceEpoch,
      );

      final shouldScan = await SystemTrashPreferences.isLastScanOlderThan(
        const Duration(hours: 36),
      );
      expect(shouldScan, true, reason: '2天前扫描过，超过36小时应该重新扫描');
    });

    test('场景7: 设置扫描时间后可以正确读取', () async {
      final beforeSet = DateTime.now();
      await SystemTrashPreferences.setLastScanTimeNow();
      final afterSet = DateTime.now();

      final lastScanTime = await SystemTrashPreferences.getLastScanTime();
      expect(lastScanTime, isNotNull, reason: '应该成功设置扫描时间');
      expect(
        lastScanTime!.isAfter(beforeSet.subtract(const Duration(seconds: 1))),
        true,
        reason: '扫描时间应该在设置时间附近',
      );
      expect(
        lastScanTime.isBefore(afterSet.add(const Duration(seconds: 1))),
        true,
        reason: '扫描时间应该在设置时间附近',
      );
    });

    test('场景8: 清除扫描时间后，应该返回null', () async {
      // 先设置
      await SystemTrashPreferences.setLastScanTimeNow();
      expect(await SystemTrashPreferences.getLastScanTime(), isNotNull);

      // 清除
      await SystemTrashPreferences.clearLastScanTime();
      final lastScanTime = await SystemTrashPreferences.getLastScanTime();
      expect(lastScanTime, isNull, reason: '清除后应该返回null');
    });

    test('场景9: 清除后再次检查，应该需要扫描', () async {
      // 先设置
      await SystemTrashPreferences.setLastScanTimeNow();
      expect(
        await SystemTrashPreferences.isLastScanOlderThan(
          const Duration(hours: 36),
        ),
        false,
      );

      // 清除
      await SystemTrashPreferences.clearLastScanTime();

      // 检查应该需要扫描
      final shouldScan = await SystemTrashPreferences.isLastScanOlderThan(
        const Duration(hours: 36),
      );
      expect(shouldScan, true, reason: '清除后应该需要扫描');
    });
  });

  group('SystemTrashPreferences - 抑制期组合测试', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SystemTrashPreferences.resetAll();
    });

    test('场景10: 用户忽略期内，即使超过36小时也不扫描', () async {
      // 模拟37小时前的扫描
      final hours37Ago = DateTime.now().subtract(const Duration(hours: 37));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'system_trash_last_scan_time',
        hours37Ago.millisecondsSinceEpoch,
      );

      // 设置用户忽略期（7天）
      await SystemTrashPreferences.setUserDismissedPeriod(
        const Duration(days: 7),
      );

      // 检查扫描时间
      final scanTimeExpired = await SystemTrashPreferences.isLastScanOlderThan(
        const Duration(hours: 36),
      );
      expect(scanTimeExpired, true, reason: '扫描时间已过期');

      // 检查忽略期
      final inDismissedPeriod =
          await SystemTrashPreferences.isInUserDismissedPeriod();
      expect(inDismissedPeriod, true, reason: '在用户忽略期内');
    });

    test('场景11: 清理抑制期内，即使超过36小时也不扫描', () async {
      // 模拟37小时前的扫描
      final hours37Ago = DateTime.now().subtract(const Duration(hours: 37));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'system_trash_last_scan_time',
        hours37Ago.millisecondsSinceEpoch,
      );

      // 设置清理抑制期（7天）
      await SystemTrashPreferences.setCleanedSuppressionPeriod(
        const Duration(days: 7),
      );

      // 检查扫描时间
      final scanTimeExpired = await SystemTrashPreferences.isLastScanOlderThan(
        const Duration(hours: 36),
      );
      expect(scanTimeExpired, true, reason: '扫描时间已过期');

      // 检查抑制期
      final inSuppressionPeriod =
          await SystemTrashPreferences.isInCleanedSuppressionPeriod();
      expect(inSuppressionPeriod, true, reason: '在清理抑制期内');
    });

    test('场景12: 所有条件都不满足时，应该允许扫描', () async {
      // 37小时前的扫描（超过36小时）
      final hours37Ago = DateTime.now().subtract(const Duration(hours: 37));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'system_trash_last_scan_time',
        hours37Ago.millisecondsSinceEpoch,
      );

      // 不设置任何抑制期

      // 所有检查都应该允许扫描
      final scanTimeExpired = await SystemTrashPreferences.isLastScanOlderThan(
        const Duration(hours: 36),
      );
      final inDismissedPeriod =
          await SystemTrashPreferences.isInUserDismissedPeriod();
      final inSuppressionPeriod =
          await SystemTrashPreferences.isInCleanedSuppressionPeriod();

      expect(scanTimeExpired, true, reason: '扫描时间已过期');
      expect(inDismissedPeriod, false, reason: '不在用户忽略期');
      expect(inSuppressionPeriod, false, reason: '不在清理抑制期');
    });
  });

  group('SystemTrashPreferences - 边界条件测试', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SystemTrashPreferences.resetAll();
    });

    test('场景13: 正好36小时，应该需要扫描（边界值）', () async {
      // 模拟正好36小时前的扫描
      final exactly36Hours = DateTime.now().subtract(const Duration(hours: 36));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'system_trash_last_scan_time',
        exactly36Hours.millisecondsSinceEpoch,
      );

      final shouldScan = await SystemTrashPreferences.isLastScanOlderThan(
        const Duration(hours: 36),
      );
      // 实现中使用 elapsed > duration，由于时间流逝，elapsed 会大于36小时
      expect(shouldScan, true,
          reason: '正好36小时前（加上执行时间），elapsed > duration，应该扫描');
    });

    test('场景14: 36小时+1毫秒，应该需要扫描', () async {
      // 模拟36小时+1毫秒前的扫描
      final just36HoursPlus = DateTime.now().subtract(
        const Duration(hours: 36, milliseconds: 1),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'system_trash_last_scan_time',
        just36HoursPlus.millisecondsSinceEpoch,
      );

      final shouldScan = await SystemTrashPreferences.isLastScanOlderThan(
        const Duration(hours: 36),
      );
      expect(shouldScan, true, reason: '36小时+1毫秒，elapsed > duration，应该扫描');
    });
  });
}
