import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/services/app_management_service.dart';
import 'package:easyfile/core/services/app_storage_service.dart';
import 'package:easyfile/core/services/app_storage_cache_manager.dart';
import 'package:easyfile/core/services/usage_stats_service.dart';
import 'package:easyfile/data/models/app_info.dart';
import 'package:easyfile/core/di/locator.dart';

void main() {
  // 在所有测试前初始化 Flutter 绑定和依赖注入
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupLocator();
  });

  // 在所有测试后清理
  tearDownAll(() {
    locator.reset();
  });

  group('AppManagementService Tests', () {
    late AppManagementService appService;
    late AppStorageService storageService;
    late AppStorageCacheManager cacheManager;
    late UsageStatsService usageStatsService;

    setUp(() {
      cacheManager = AppStorageCacheManager();
      storageService = AppStorageService();
      usageStatsService = UsageStatsService();
      appService = AppManagementService(
        storageService,
        cacheManager,
        usageStatsService,
      );
    });

    // Skip this test as it requires platform channel implementation
    test('getInstalledApps should return a list', () async {
      // This test requires native Android implementation
      // Skip in unit test environment
    }, skip: 'Requires platform channel implementation');

    test('sortBySize should sort correctly', () {
      final testApps = [
        EasyFileAppInfo(
          name: 'App1',
          packageName: 'com.test.app1',
          versionName: '1.0',
          versionCode: 1,
          isSystemApp: false,
          storageInfo: AppStorageInfo(
            appSize: 1000,
            dataSize: 500,
            cacheSize: 200,
          ),
        ),
        EasyFileAppInfo(
          name: 'App2',
          packageName: 'com.test.app2',
          versionName: '1.0',
          versionCode: 1,
          isSystemApp: false,
          storageInfo: AppStorageInfo(
            appSize: 5000,
            dataSize: 1000,
            cacheSize: 500,
          ),
        ),
      ];

      final sorted = appService.sortBySize(testApps);

      expect(sorted.length, 2);
      expect(sorted[0].name, 'App2'); // 更大的应该在前面
      expect(sorted[1].name, 'App1');
    });

    test('sortByName should sort alphabetically', () {
      final testApps = [
        EasyFileAppInfo(
          name: 'Zebra',
          packageName: 'com.test.zebra',
          versionName: '1.0',
          versionCode: 1,
          isSystemApp: false,
        ),
        EasyFileAppInfo(
          name: 'Apple',
          packageName: 'com.test.apple',
          versionName: '1.0',
          versionCode: 1,
          isSystemApp: false,
        ),
      ];

      final sorted = appService.sortByName(testApps);

      expect(sorted.length, 2);
      expect(sorted[0].name, 'Apple');
      expect(sorted[1].name, 'Zebra');
    });

    test('searchApps should filter by name', () async {
      final testApps = [
        EasyFileAppInfo(
          name: 'Chrome',
          packageName: 'com.android.chrome',
          versionName: '1.0',
          versionCode: 1,
          isSystemApp: false,
        ),
        EasyFileAppInfo(
          name: 'Gmail',
          packageName: 'com.google.gmail',
          versionName: '1.0',
          versionCode: 1,
          isSystemApp: false,
        ),
      ];

      final filtered = await appService.searchApps(testApps, 'chrome');

      expect(filtered.length, 1);
      expect(filtered[0].name, 'Chrome');
    });

    test('filterByMinSize should filter correctly', () {
      final testApps = [
        EasyFileAppInfo(
          name: 'SmallApp',
          packageName: 'com.test.small',
          versionName: '1.0',
          versionCode: 1,
          isSystemApp: false,
          storageInfo: AppStorageInfo(
            appSize: 1000,
            dataSize: 500,
            cacheSize: 200,
          ),
        ),
        EasyFileAppInfo(
          name: 'LargeApp',
          packageName: 'com.test.large',
          versionName: '1.0',
          versionCode: 1,
          isSystemApp: false,
          storageInfo: AppStorageInfo(
            appSize: 10000000,
            dataSize: 5000000,
            cacheSize: 500000,
          ),
        ),
      ];

      final filtered = appService.filterByMinSize(testApps, 1000000); // 1MB

      expect(filtered.length, 1);
      expect(filtered[0].name, 'LargeApp');
    });
  });

  group('EasyFileAppInfo Tests', () {
    test('totalSize should calculate correctly', () {
      final app = EasyFileAppInfo(
        name: 'TestApp',
        packageName: 'com.test.app',
        versionName: '1.0',
        versionCode: 1,
        isSystemApp: false,
        storageInfo: AppStorageInfo(
          appSize: 1000,
          dataSize: 500,
          cacheSize: 200,
        ),
      );

      // totalSize = appSize + dataSize (dataSize already includes cache)
      expect(app.totalSize, 1500);
    });

    test('copyWith should create new instance', () {
      final original = EasyFileAppInfo(
        name: 'TestApp',
        packageName: 'com.test.app',
        versionName: '1.0',
        versionCode: 1,
        isSystemApp: false,
      );

      final updated = original.copyWith(
        storageInfo: AppStorageInfo(
          appSize: 1000,
          dataSize: 500,
          cacheSize: 200,
        ),
      );

      expect(updated.name, original.name);
      expect(updated.storageInfo, isNotNull);
      expect(original.storageInfo, isNull);
    });
  });

  group('AppStorageInfo Tests', () {
    test('totalSize should sum all sizes', () {
      final storage = AppStorageInfo(
        appSize: 1000,
        dataSize: 2000,
        cacheSize: 500,
      );

      // totalSize = appSize + dataSize (cache is already included in dataSize)
      expect(storage.totalSize, 3000);
    });

    test('fromJson and toJson should work correctly', () {
      final original = AppStorageInfo(
        appSize: 1000,
        dataSize: 2000,
        cacheSize: 500,
      );

      final json = original.toJson();
      final restored = AppStorageInfo.fromJson(json);

      expect(restored.appSize, original.appSize);
      expect(restored.dataSize, original.dataSize);
      expect(restored.cacheSize, original.cacheSize);
    });
  });
}
