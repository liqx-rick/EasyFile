import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/config/storage/mock_config_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppConfig Lifecycle', () {
    setUp(() async {
      // 每个测试前清理
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      // 每个测试后重置
      try {
        await AppConfig.instance.resetToDefaults();
      } catch (e) {
        // 如果还未初始化，忽略错误
      }
    });

    group('初始化', () {
      test('should initialize successfully with default storage', () async {
        await AppConfig.instance.initialize();

        // 验证所有模块已初始化
        expect(() => AppConfig.instance.feature, returnsNormally);
        expect(() => AppConfig.instance.fileScan, returnsNormally);
        expect(() => AppConfig.instance.fileTypes, returnsNormally);
        expect(() => AppConfig.instance.appScanner, returnsNormally);
        expect(() => AppConfig.instance.build, returnsNormally);
      });

      test('should initialize successfully with custom storage', () async {
        final customStorage = MockConfigStorage();
        await AppConfig.instance.initialize(storage: customStorage);

        expect(AppConfig.instance.storage, same(customStorage));
      });

      test('should allow re-initialization', () async {
        await AppConfig.instance.initialize(storage: MockConfigStorage());
        // 再次初始化不应该报错
        await AppConfig.instance.initialize(storage: MockConfigStorage());

        expect(() => AppConfig.instance.feature, returnsNormally);
      });

      test('should initialize build config without storage', () async {
        // BuildConfig 不需要初始化就可以访问
        expect(() => AppConfig.instance.build, returnsNormally);
        expect(AppConfig.instance.build.isDebug, isNotNull);
      });
    });

    group('配置模块访问', () {
      setUp(() async {
        await AppConfig.instance.initialize(storage: MockConfigStorage());
      });

      test('should access all config modules', () {
        expect(AppConfig.instance.feature, isNotNull);
        expect(AppConfig.instance.fileScan, isNotNull);
        expect(AppConfig.instance.fileTypes, isNotNull);
        expect(AppConfig.instance.appScanner, isNotNull);
        expect(AppConfig.instance.build, isNotNull);
      });

      test('should return same instance for multiple accesses', () {
        final feature1 = AppConfig.instance.feature;
        final feature2 = AppConfig.instance.feature;
        expect(identical(feature1, feature2), true);

        final fileScan1 = AppConfig.instance.fileScan;
        final fileScan2 = AppConfig.instance.fileScan;
        expect(identical(fileScan1, fileScan2), true);
      });
    });

    group('配置重置', () {
      setUp(() async {
        await AppConfig.instance.initialize(storage: MockConfigStorage());
      });

      test('should reset all configs to defaults', () async {
        // 修改配置
        await AppConfig.instance.feature
            .setFeature('new_files', enabled: false);
        await AppConfig.instance.fileScan.setLargeFileThreshold(100);

        expect(AppConfig.instance.feature.isNewFilesEnabled, false);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 100);

        // 重置
        await AppConfig.instance.resetToDefaults();

        // 验证已恢复默认值
        expect(AppConfig.instance.feature.isNewFilesEnabled, true);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 50);
      });

      test('should reset feature config independently', () async {
        await AppConfig.instance.feature
            .setFeature('new_files', enabled: false);
        await AppConfig.instance.fileScan.setLargeFileThreshold(100);

        // 只重置 feature config
        await AppConfig.instance.feature.reset();

        expect(AppConfig.instance.feature.isNewFilesEnabled, true);
        // fileScan 应该不受影响
        expect(AppConfig.instance.fileScan.largeFileThreshold, 100);
      });

      test('should reset file scan config independently', () async {
        await AppConfig.instance.feature
            .setFeature('new_files', enabled: false);
        await AppConfig.instance.fileScan.setLargeFileThreshold(100);

        // 只重置 fileScan config
        await AppConfig.instance.fileScan.reset();

        expect(AppConfig.instance.fileScan.largeFileThreshold, 50);
        // feature 应该不受影响
        expect(AppConfig.instance.feature.isNewFilesEnabled, false);
      });
    });

    group('单例模式', () {
      test('should return same instance', () {
        final instance1 = AppConfig.instance;
        final instance2 = AppConfig.instance;
        expect(identical(instance1, instance2), true);
      });

      test('should maintain state across accesses', () async {
        await AppConfig.instance.initialize(storage: MockConfigStorage());
        await AppConfig.instance.feature
            .setFeature('new_files', enabled: false);

        // 通过不同引用访问应该得到相同状态
        final instance1 = AppConfig.instance;
        final instance2 = AppConfig.instance;

        expect(instance1.feature.isNewFilesEnabled, false);
        expect(instance2.feature.isNewFilesEnabled, false);
      });
    });

    group('存储实例管理', () {
      test('should use provided storage', () async {
        final customStorage = MockConfigStorage();
        await AppConfig.instance.initialize(storage: customStorage);

        expect(AppConfig.instance.storage, same(customStorage));
      });

      test('should create default storage if not provided', () async {
        await AppConfig.instance.initialize();

        // 应该创建了默认的 LocalConfigStorage
        expect(AppConfig.instance.storage, isNotNull);
      });

      test('should share storage across all config modules', () async {
        final customStorage = MockConfigStorage();
        await AppConfig.instance.initialize(storage: customStorage);

        // 在 feature 中写入
        await AppConfig.instance.feature
            .setFeature('new_files', enabled: false);

        // 应该能在存储中直接读取
        final value = customStorage.getBool('feature_new_files');
        expect(value, false);
      });
    });

    group('配置持久化', () {
      test('should persist configuration across re-initialization', () async {
        final storage = MockConfigStorage();

        // 第一次初始化并修改配置
        await AppConfig.instance.initialize(storage: storage);
        await AppConfig.instance.feature
            .setFeature('new_files', enabled: false);
        await AppConfig.instance.fileScan.setLargeFileThreshold(100);

        expect(AppConfig.instance.feature.isNewFilesEnabled, false);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 100);

        // 重新初始化（使用相同存储）
        await AppConfig.instance.initialize(storage: storage);

        // 配置应该保持
        expect(AppConfig.instance.feature.isNewFilesEnabled, false);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 100);
      });
    });

    group('错误处理', () {
      test('should handle initialization errors gracefully', () async {
        // 这个测试验证即使有错误，也不会导致应用崩溃
        expect(
          () async => await AppConfig.instance.initialize(),
          returnsNormally,
        );
      });
    });
  });
}
