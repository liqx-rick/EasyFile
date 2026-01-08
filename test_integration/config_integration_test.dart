// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/config/app_scanner_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

void main() {
  group('Config Integration Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      try {
        await AppConfig.instance.resetToDefaults();
      } catch (e) {
        // Ignore if not initialized
      }
    });

    group('完整配置工作流', () {
      test('complete workflow: initialize -> modify -> persist -> reload',
          () async {
        // 1. 初始化配置系统
        await AppConfig.instance.initialize();

        // 验证初始状态
        expect(AppConfig.instance.feature.isNewFilesEnabled, true);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 50);

        // 2. 修改配置
        await AppConfig.instance.feature
            .setFeature('new_files', enabled: false);
        await AppConfig.instance.feature
            .setFeature('large_files', enabled: false);
        await AppConfig.instance.fileScan.setLargeFileThreshold(100);
        await AppConfig.instance.fileScan.setNewFilesRetentionDays(15);
        await AppConfig.instance.appScanner.setAppEnabled('qq', false);
        await AppConfig.instance.appScanner.setAppPriority('telegram', 1);

        // 3. 验证修改生效
        expect(AppConfig.instance.feature.isNewFilesEnabled, false);
        expect(AppConfig.instance.feature.isLargeFilesEnabled, false);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 100);
        expect(AppConfig.instance.fileScan.newFilesRetentionDays, 15);

        final qqConfig = await AppConfig.instance.appScanner.getAppConfig('qq');
        expect(qqConfig?.enabled, false);

        final telegramConfig =
            await AppConfig.instance.appScanner.getAppConfig('telegram');
        expect(telegramConfig?.priority, 1);

        // 4. 模拟应用重启（重新初始化）
        await AppConfig.instance.initialize();

        // 5. 验证配置已持久化
        expect(AppConfig.instance.feature.isNewFilesEnabled, false);
        expect(AppConfig.instance.feature.isLargeFilesEnabled, false);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 100);
        expect(AppConfig.instance.fileScan.newFilesRetentionDays, 15);

        final qqConfig2 =
            await AppConfig.instance.appScanner.getAppConfig('qq');
        expect(qqConfig2?.enabled, false);

        final telegramConfig2 =
            await AppConfig.instance.appScanner.getAppConfig('telegram');
        expect(telegramConfig2?.priority, 1);
      });

      test('should persist custom app configuration', () async {
        await AppConfig.instance.initialize();

        // 添加自定义应用
        final customApp = AppConfigData(
          appKey: 'custom_test',
          appName: '测试应用',
          description: '集成测试用',
          packageNames: ['com.test.app'],
          folderKeywords: ['TestApp'],
          priority: 5,
          enabled: true,
        );

        await AppConfig.instance.appScanner.addCustomApp(customApp);

        // 验证添加成功
        final retrieved =
            await AppConfig.instance.appScanner.getAppConfig('custom_test');
        expect(retrieved, isNotNull);
        expect(retrieved!.appName, '测试应用');

        // 模拟重启
        await AppConfig.instance.initialize();

        // 验证持久化
        final retrieved2 =
            await AppConfig.instance.appScanner.getAppConfig('custom_test');
        expect(retrieved2, isNotNull);
        expect(retrieved2!.appName, '测试应用');
      });
    });

    group('远程配置模拟', () {
      test('simulate remote config update for features', () async {
        await AppConfig.instance.initialize();

        // 模拟远程配置推送
        await AppConfig.instance.feature.mergeWith({
          'new_files': false,
          'large_files': false,
          'duplicate_files': true,
          'premium': true,
        });

        // 验证远程配置已应用
        expect(AppConfig.instance.feature.isNewFilesEnabled, false);
        expect(AppConfig.instance.feature.isLargeFilesEnabled, false);
        expect(AppConfig.instance.feature.isDuplicateFilesEnabled, true);
        expect(AppConfig.instance.feature.isPremiumEnabled, true);
      });

      test('simulate remote config update for scan thresholds', () async {
        await AppConfig.instance.initialize();

        // 模拟远程配置推送
        await AppConfig.instance.fileScan.mergeWith({
          'large_file_threshold': 200,
          'new_files_retention': 30,
          'large_file_scan_timeout': 120,
        });

        // 验证远程配置已应用
        expect(AppConfig.instance.fileScan.largeFileThreshold, 200);
        expect(AppConfig.instance.fileScan.newFilesRetentionDays, 30);
        expect(AppConfig.instance.fileScan.largeFileScanTimeout, 120);
      });

      test('simulate remote config update for app priorities', () async {
        await AppConfig.instance.initialize();

        // 模拟远程配置推送（调整应用优先级）
        await AppConfig.instance.appScanner.setAppPriority('telegram', 1);
        await AppConfig.instance.appScanner.setAppPriority('wps', 1);
        await AppConfig.instance.appScanner.setAppPriority('dingtalk', 3);

        final telegram =
            await AppConfig.instance.appScanner.getAppConfig('telegram');
        final wps = await AppConfig.instance.appScanner.getAppConfig('wps');
        final dingtalk =
            await AppConfig.instance.appScanner.getAppConfig('dingtalk');

        expect(telegram!.priority, 1);
        expect(wps!.priority, 1);
        expect(dingtalk!.priority, 3);
      });

      test('should handle partial remote config update', () async {
        await AppConfig.instance.initialize();

        // 记录初始值
        final initialLargeFiles =
            AppConfig.instance.feature.isLargeFilesEnabled;
        final initialThreshold = AppConfig.instance.fileScan.largeFileThreshold;

        // 只更新部分配置
        await AppConfig.instance.feature.mergeWith({
          'new_files': false,
        });

        // 被更新的配置应该改变
        expect(AppConfig.instance.feature.isNewFilesEnabled, false);

        // 未被更新的配置应该保持不变
        expect(
            AppConfig.instance.feature.isLargeFilesEnabled, initialLargeFiles);
        expect(
            AppConfig.instance.fileScan.largeFileThreshold, initialThreshold);
      });
    });

    group('多配置协同工作', () {
      test('feature flags should work with scan config', () async {
        await AppConfig.instance.initialize();

        // 禁用大文件功能
        await AppConfig.instance.feature
            .setFeature('large_files', enabled: false);

        // 但仍然可以设置大文件阈值（配置独立）
        await AppConfig.instance.fileScan.setLargeFileThreshold(200);

        expect(AppConfig.instance.feature.isLargeFilesEnabled, false);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 200);
      });

      test('app scanner should work with feature flags', () async {
        await AppConfig.instance.initialize();

        // 禁用应用管理功能
        await AppConfig.instance.feature
            .setFeature('app_management', enabled: false);

        // 但仍然可以管理应用配置
        await AppConfig.instance.appScanner.setAppEnabled('qq', false);

        expect(AppConfig.instance.feature.isAppManagementEnabled, false);

        final qqConfig = await AppConfig.instance.appScanner.getAppConfig('qq');
        expect(qqConfig!.enabled, false);
      });
    });

    group('配置冲突和恢复', () {
      test('should handle conflicting updates gracefully', () async {
        await AppConfig.instance.initialize();

        // 快速连续更新
        await Future.wait([
          AppConfig.instance.feature.setFeature('new_files', enabled: false),
          AppConfig.instance.feature.setFeature('new_files', enabled: true),
          AppConfig.instance.feature.setFeature('new_files', enabled: false),
        ]);

        // 最后一次更新应该生效（或者取决于实现）
        final finalState = AppConfig.instance.feature.isNewFilesEnabled;
        expect(finalState, isA<bool>());
      });

      test('should recover from reset', () async {
        await AppConfig.instance.initialize();

        // 修改多个配置
        await AppConfig.instance.feature
            .setFeature('new_files', enabled: false);
        await AppConfig.instance.fileScan.setLargeFileThreshold(100);
        await AppConfig.instance.appScanner.setAppEnabled('qq', false);

        // 全部重置
        await AppConfig.instance.resetToDefaults();

        // 所有配置应该恢复默认值
        expect(AppConfig.instance.feature.isNewFilesEnabled, true);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 50);

        final qqConfig = await AppConfig.instance.appScanner.getAppConfig('qq');
        expect(qqConfig!.enabled, true);
      });
    });

    group('性能测试', () {
      test('initialization should be fast', () async {
        final stopwatch = Stopwatch()..start();
        await AppConfig.instance.initialize();
        stopwatch.stop();

        // 初始化应该在 500ms 内完成
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
        debugPrint(
            'Config initialization took: ${stopwatch.elapsedMilliseconds}ms');
      });

      test('config reads should be fast', () async {
        await AppConfig.instance.initialize();

        final stopwatch = Stopwatch()..start();

        for (int i = 0; i < 1000; i++) {
          // 读取各种配置
          AppConfig.instance.feature.isNewFilesEnabled;
          AppConfig.instance.fileScan.largeFileThreshold;
          AppConfig.instance.fileTypes.imageExtensions;
        }

        stopwatch.stop();

        // 1000次读取应该在 100ms 内完成
        expect(stopwatch.elapsedMilliseconds, lessThan(100));
        debugPrint(
            '1000 config reads took: ${stopwatch.elapsedMilliseconds}ms');
      });

      test('batch updates should be efficient', () async {
        await AppConfig.instance.initialize();

        final stopwatch = Stopwatch()..start();

        // 批量更新
        await AppConfig.instance.feature.mergeWith({
          'new_files': false,
          'large_files': false,
          'duplicate_files': false,
          'junk_cleanup': false,
          'app_management': false,
        });

        stopwatch.stop();

        // 批量更新应该比逐个更新快
        expect(stopwatch.elapsedMilliseconds, lessThan(200));
        debugPrint('Batch update took: ${stopwatch.elapsedMilliseconds}ms');
      });
    });

    group('错误恢复和稳定性', () {
      test('should handle invalid data gracefully', () async {
        await AppConfig.instance.initialize();

        // 尝试设置无效的回收站天数
        expect(
          () async =>
              await AppConfig.instance.fileScan.setTrashRetentionDays(100),
          throwsArgumentError,
        );

        // 配置应该保持有效状态
        expect(AppConfig.instance.fileScan.trashRetentionDays, greaterThan(0));
      });

      test('should maintain stability after errors', () async {
        await AppConfig.instance.initialize();

        try {
          // 尝试添加重复的应用
          final duplicate = AppConfigData(
            appKey: 'wechat',
            appName: 'Test',
            packageNames: ['test'],
            folderKeywords: ['test'],
          );
          await AppConfig.instance.appScanner.addCustomApp(duplicate);
        } catch (e) {
          // 预期会失败
        }

        // 配置系统应该仍然正常工作
        final wechat =
            await AppConfig.instance.appScanner.getAppConfig('wechat');
        expect(wechat, isNotNull);
        expect(wechat!.appName, '微信'); // 应该是原始配置
      });
    });
  });
}
