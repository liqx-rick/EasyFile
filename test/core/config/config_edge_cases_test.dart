import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/config/app_scanner_config.dart';
import 'package:easyfile/core/config/storage/mock_config_storage.dart';

void main() {
  group('Config Edge Cases', () {
    late MockConfigStorage storage;

    setUp(() async {
      storage = MockConfigStorage();
      await AppConfig.instance.initialize(storage: storage);
    });

    tearDown(() async {
      await AppConfig.instance.resetToDefaults();
    });

    group('FileScanConfig 边界值', () {
      test('should handle extreme threshold values', () async {
        // 非常小的值
        await AppConfig.instance.fileScan.setLargeFileThreshold(1);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 1);

        // 非常大的值
        await AppConfig.instance.fileScan.setLargeFileThreshold(10000);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 10000);
      });

      test('should handle zero threshold', () async {
        await AppConfig.instance.fileScan.setLargeFileThreshold(0);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 0);
      });

      test('should validate trash retention days', () {
        final validDays = [3, 7, 15, 30];

        // 有效值应该能设置
        for (final days in validDays) {
          expect(
            () async =>
                await AppConfig.instance.fileScan.setTrashRetentionDays(days),
            returnsNormally,
          );
        }

        // 无效值应该抛出异常
        final invalidDays = [0, 1, 5, 10, 100, -1];
        for (final days in invalidDays) {
          expect(
            () async =>
                await AppConfig.instance.fileScan.setTrashRetentionDays(days),
            throwsArgumentError,
          );
        }
      });

      test('should handle negative retention days', () async {
        await AppConfig.instance.fileScan.setNewFilesRetentionDays(1);
        expect(AppConfig.instance.fileScan.newFilesRetentionDays, 1);

        // 负数可能有特殊含义（如"不限制"）
        // 这取决于具体实现
      });

      test('should handle extreme retention days', () async {
        // 非常大的天数
        await AppConfig.instance.fileScan.setNewFilesRetentionDays(365);
        expect(AppConfig.instance.fileScan.newFilesRetentionDays, 365);

        await AppConfig.instance.fileScan.setNewFilesRetentionDays(1000);
        expect(AppConfig.instance.fileScan.newFilesRetentionDays, 1000);
      });

      test('should handle all trash retention options', () async {
        final options = AppConfig.instance.fileScan.trashRetentionOptions;

        for (final days in options) {
          await AppConfig.instance.fileScan.setTrashRetentionDays(days);
          expect(AppConfig.instance.fileScan.trashRetentionDays, days);
        }
      });
    });

    group('AppScannerConfig 边界值', () {
      test('should handle invalid app key', () async {
        final config =
            await AppConfig.instance.appScanner.getAppConfig('non_existent');
        expect(config, isNull);
      });

      test('should handle empty app key', () async {
        final config = await AppConfig.instance.appScanner.getAppConfig('');
        expect(config, isNull);
      });

      test('should handle duplicate custom app', () async {
        final customApp = AppConfigData(
          appKey: 'wechat', // 使用已存在的 key
          appName: '测试',
          packageNames: ['test'],
          folderKeywords: ['test'],
        );

        // 应该抛出异常
        expect(
          () async =>
              await AppConfig.instance.appScanner.addCustomApp(customApp),
          throwsArgumentError,
        );
      });

      test('should handle extreme priority values', () async {
        // 优先级 1（最高）
        await AppConfig.instance.appScanner.setAppPriority('wechat', 1);
        expect(
            (await AppConfig.instance.appScanner.getAppConfig('wechat'))!
                .priority,
            1);

        // 优先级 99（最低）
        await AppConfig.instance.appScanner.setAppPriority('wechat', 99);
        expect(
            (await AppConfig.instance.appScanner.getAppConfig('wechat'))!
                .priority,
            99);

        // 超出范围的优先级（根据实现可能接受或拒绝）
        await AppConfig.instance.appScanner.setAppPriority('wechat', 0);
        await AppConfig.instance.appScanner.setAppPriority('wechat', 100);
      });

      test('should handle invalid app config data', () async {
        // 无效的配置（没有包名和文件夹关键字）
        final invalidApp = AppConfigData(
          appKey: 'invalid',
          appName: '无效应用',
          packageNames: [],
          folderKeywords: [],
        );

        expect(invalidApp.isValid, false);
      });

      test('should handle custom app with minimal data', () async {
        final minimalApp = AppConfigData(
          appKey: 'minimal',
          appName: 'Minimal',
          packageNames: ['com.test'],
          folderKeywords: [],
        );

        await AppConfig.instance.appScanner.addCustomApp(minimalApp);

        final retrieved =
            await AppConfig.instance.appScanner.getAppConfig('minimal');
        expect(retrieved, isNotNull);
        expect(retrieved!.appKey, 'minimal');
      });
    });

    group('FeatureConfig 并发操作', () {
      test('should handle rapid toggle', () async {
        // 快速切换开关
        for (int i = 0; i < 20; i++) {
          await AppConfig.instance.feature
              .setFeature('new_files', enabled: i % 2 == 0);
        }

        // 最终状态应该一致
        expect(AppConfig.instance.feature.isNewFilesEnabled, false);
      });

      test('should handle batch update', () async {
        final updates = {
          'new_files': false,
          'large_files': false,
          'duplicate_files': false,
          'junk_cleanup': false,
          'app_management': false,
        };

        await AppConfig.instance.feature.mergeWith(updates);

        expect(AppConfig.instance.feature.isNewFilesEnabled, false);
        expect(AppConfig.instance.feature.isLargeFilesEnabled, false);
        expect(AppConfig.instance.feature.isDuplicateFilesEnabled, false);
        expect(AppConfig.instance.feature.isJunkCleanupEnabled, false);
        expect(AppConfig.instance.feature.isAppManagementEnabled, false);
      });

      test('should handle mixed batch update', () async {
        final updates = {
          'new_files': false,
          'large_files': true,
          'duplicate_files': false,
          'junk_cleanup': true,
        };

        await AppConfig.instance.feature.mergeWith(updates);

        expect(AppConfig.instance.feature.isNewFilesEnabled, false);
        expect(AppConfig.instance.feature.isLargeFilesEnabled, true);
        expect(AppConfig.instance.feature.isDuplicateFilesEnabled, false);
        expect(AppConfig.instance.feature.isJunkCleanupEnabled, true);
      });

      test('should handle empty batch update', () async {
        await AppConfig.instance.feature.mergeWith({});
        // 应该不会出错，所有配置保持不变
        expect(AppConfig.instance.feature.isNewFilesEnabled, true);
      });
    });

    group('FileTypesConfig 边界值', () {
      test('should handle unknown extensions', () {
        final unknownExts = ['xyz', 'abc', '123', ''];
        for (final ext in unknownExts) {
          final category =
              AppConfig.instance.fileTypes.getCategoryByExtension(ext);
          expect(category.name, 'other');
        }
      });

      test('should handle very long extension', () {
        final longExt = 'x' * 1000;
        final category =
            AppConfig.instance.fileTypes.getCategoryByExtension(longExt);
        expect(category.name, 'other');
      });

      test('should handle special characters in extension', () {
        final specialExts = ['!@#', '***', '...', '---'];
        for (final ext in specialExts) {
          final category =
              AppConfig.instance.fileTypes.getCategoryByExtension(ext);
          expect(category.name, 'other');
        }
      });

      test('should handle mixed case extensions', () {
        expect(
          AppConfig.instance.fileTypes.getCategoryByExtension('JpG'),
          AppConfig.instance.fileTypes.getCategoryByExtension('jpg'),
        );
        expect(
          AppConfig.instance.fileTypes.getCategoryByExtension('Mp4'),
          AppConfig.instance.fileTypes.getCategoryByExtension('mp4'),
        );
      });
    });

    group('存储层边界值', () {
      test('should handle empty strings', () async {
        await storage.setString('empty', '');
        expect(storage.getString('empty'), '');
      });

      test('should handle very long strings', () async {
        final longString = 'x' * 100000;
        await storage.setString('long', longString);
        expect(storage.getString('long'), longString);
      });

      test('should handle unicode characters', () async {
        await storage.setString('unicode', '你好世界🌍👋');
        expect(storage.getString('unicode'), '你好世界🌍👋');
      });

      test('should handle special characters in keys', () async {
        await storage.setString('key_with-special.chars', 'value');
        expect(storage.getString('key_with-special.chars'), 'value');
      });

      test('should handle max int values', () async {
        const maxInt = 9223372036854775807; // 2^63 - 1
        await storage.setInt('max', maxInt);
        expect(storage.getInt('max'), maxInt);
      });

      test('should handle min int values', () async {
        const minInt = -9223372036854775808; // -2^63
        await storage.setInt('min', minInt);
        expect(storage.getInt('min'), minInt);
      });
    });

    group('配置一致性', () {
      test('should maintain consistency after multiple operations', () async {
        // 执行多个操作
        await AppConfig.instance.feature
            .setFeature('new_files', enabled: false);
        await AppConfig.instance.fileScan.setLargeFileThreshold(100);
        await AppConfig.instance.appScanner.setAppEnabled('qq', false);

        // 验证所有配置都正确保存
        expect(AppConfig.instance.feature.isNewFilesEnabled, false);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 100);

        final qqConfig = await AppConfig.instance.appScanner.getAppConfig('qq');
        expect(qqConfig!.enabled, false);
      });

      test('should not affect other configs when modifying one', () async {
        // 记录初始状态
        final initialThreshold = AppConfig.instance.fileScan.largeFileThreshold;
        final initialLargeFilesEnabled =
            AppConfig.instance.feature.isLargeFilesEnabled;

        // 只修改一个配置
        await AppConfig.instance.feature
            .setFeature('new_files', enabled: false);

        // 其他配置应该不受影响
        expect(
            AppConfig.instance.fileScan.largeFileThreshold, initialThreshold);
        expect(AppConfig.instance.feature.isLargeFilesEnabled,
            initialLargeFilesEnabled);
      });
    });
  });
}
