import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyfile/core/models/large_file_scan_config.dart';
import 'package:easyfile/core/services/large_file_cache_manager.dart';
import 'package:easyfile/data/models/file_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LargeFileCacheManager 缓存有效期测试', () {
    late LargeFileCacheManager cacheManager;
    final testFiles = [
      FileItem(
        name: 'test.mp4',
        path: '/storage/test.mp4',
        size: 100 * 1024 * 1024,
        modified: DateTime.now(),
        isDirectory: false,
      ),
    ];
    final testConfig = const LargeFileScanConfig();

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('默认7天有效期 - 缓存应该被创建', () async {
      cacheManager = LargeFileCacheManager(); // 默认7天

      await cacheManager.saveCache(files: testFiles, config: testConfig);
      final cache = await cacheManager.loadCache();

      expect(cache, isNotNull);
      expect(cache!.files.length, 1);
      expect(cache.files.first.name, 'test.mp4');
    });

    test('自定义3天有效期 - 4天前的缓存应该失效', () async {
      cacheManager = LargeFileCacheManager(cacheExpiryDays: 3);

      await cacheManager.saveCache(files: testFiles, config: testConfig);

      // 修改时间戳为4天前（3天配置下应该失效）
      final prefs = await SharedPreferences.getInstance();
      final fourDaysAgo = DateTime.now()
          .subtract(const Duration(days: 4))
          .millisecondsSinceEpoch;
      await prefs.setInt('large_file_scan_timestamp', fourDaysAgo);

      final cache = await cacheManager.loadCache();
      expect(cache, isNull); // 3天配置下，4天前的缓存应该失效
    });

    test('模拟缓存过期 - 8天后缓存应该失效', () async {
      cacheManager = LargeFileCacheManager(cacheExpiryDays: 7);

      // 保存缓存
      await cacheManager.saveCache(files: testFiles, config: testConfig);

      // 手动修改时间戳为8天前
      final prefs = await SharedPreferences.getInstance();
      final eightDaysAgo = DateTime.now()
          .subtract(const Duration(days: 8))
          .millisecondsSinceEpoch;
      await prefs.setInt('large_file_scan_timestamp', eightDaysAgo);

      // 再次加载，应该返回null（已过期）
      final cache = await cacheManager.loadCache();
      expect(cache, isNull);

      // 验证缓存是否被清空
      expect(prefs.getString('large_file_scan_cache'), isNull);
    });

    test('边界测试 - 正好7天应该有效', () async {
      cacheManager = LargeFileCacheManager(cacheExpiryDays: 7);

      await cacheManager.saveCache(files: testFiles, config: testConfig);

      // 修改时间戳为正好7天前（减1秒避免边界问题）
      final prefs = await SharedPreferences.getInstance();
      final sevenDaysAgo = DateTime.now()
          .subtract(const Duration(days: 7, seconds: -1))
          .millisecondsSinceEpoch;
      await prefs.setInt('large_file_scan_timestamp', sevenDaysAgo);

      final cache = await cacheManager.loadCache();
      expect(cache, isNotNull); // 应该还有效
    });

    test('边界测试 - 超过7天1秒应该失效', () async {
      cacheManager = LargeFileCacheManager(cacheExpiryDays: 7);

      await cacheManager.saveCache(files: testFiles, config: testConfig);

      // 修改时间戳为7天1秒前
      final prefs = await SharedPreferences.getInstance();
      final sevenDaysOneSecondAgo = DateTime.now()
          .subtract(const Duration(days: 7, seconds: 1))
          .millisecondsSinceEpoch;
      await prefs.setInt('large_file_scan_timestamp', sevenDaysOneSecondAgo);

      final cache = await cacheManager.loadCache();
      expect(cache, isNull); // 应该失效
    });

    test('不同有效期配置 - 1天配置', () async {
      cacheManager = LargeFileCacheManager(cacheExpiryDays: 1);

      await cacheManager.saveCache(files: testFiles, config: testConfig);

      // 修改时间戳为2天前
      final prefs = await SharedPreferences.getInstance();
      final twoDaysAgo = DateTime.now()
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch;
      await prefs.setInt('large_file_scan_timestamp', twoDaysAgo);

      final cache = await cacheManager.loadCache();
      expect(cache, isNull); // 1天配置下，2天前的缓存应该失效
    });

    test('不同有效期配置 - 30天配置', () async {
      cacheManager = LargeFileCacheManager(cacheExpiryDays: 30);

      await cacheManager.saveCache(files: testFiles, config: testConfig);

      // 修改时间戳为7天前（30天配置下应该还有效）
      final prefs = await SharedPreferences.getInstance();
      final sevenDaysAgo = DateTime.now()
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch;
      await prefs.setInt('large_file_scan_timestamp', sevenDaysAgo);

      final cache = await cacheManager.loadCache();
      expect(cache, isNotNull); // 30天配置下，7天前的缓存应该有效
    });

    test('清除缓存后重新加载应该返回null', () async {
      cacheManager = LargeFileCacheManager();

      await cacheManager.saveCache(files: testFiles, config: testConfig);
      await cacheManager.clearCache();

      final cache = await cacheManager.loadCache();
      expect(cache, isNull);
    });
  });
}
