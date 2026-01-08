import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/config/build_config.dart';

void main() {
  group('BuildConfig', () {
    late BuildConfig config;

    setUp(() {
      config = BuildConfig();
    });

    group('构建模式检查', () {
      test('should have correct build mode', () {
        // 测试环境应该是 debug 模式
        expect(config.isDebug, true);
        expect(config.isRelease, false);
        expect(config.isProfile, false);
      });

      test('build modes should be mutually exclusive', () {
        // Debug、Release、Profile 只能有一个为 true
        final modes = [config.isDebug, config.isRelease, config.isProfile];
        final trueCount = modes.where((m) => m).length;
        expect(trueCount, 1);
      });
    });

    group('环境配置', () {
      test('should have correct environment', () {
        final env = config.environment;
        expect(env, isNotNull);

        // 测试环境应该是 development
        expect(env.isDev, true);
        expect(env.isProd, false);
        expect(env.isStaging, false);
      });

      test('environment should match build mode', () {
        // Debug → Development
        if (config.isDebug) {
          expect(config.environment, Environment.development);
        }
        // Profile → Staging
        else if (config.isProfile) {
          expect(config.environment, Environment.staging);
        }
        // Release → Production
        else if (config.isRelease) {
          expect(config.environment, Environment.production);
        }
      });
    });

    group('应用信息', () {
      test('should have correct package name', () {
        expect(config.packageName, 'com.guangqi.easyfile');
        expect(config.packageName, isNotEmpty);
        expect(config.packageName, contains('.'));
      });

      test('should have correct app name', () {
        expect(config.appName, 'EasyFile');
        expect(config.appName, isNotEmpty);
      });

      test('package name should follow convention', () {
        // 包名应该是小写，使用点分隔
        expect(config.packageName,
            matches(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'));
      });
    });

    group('平台支持', () {
      test('should have correct platform support', () {
        expect(config.supportsAndroid, true);
        expect(config.supportsIOS, false);
      });

      test('should support at least one platform', () {
        expect(config.supportsAndroid || config.supportsIOS, true);
      });
    });

    group('Environment 枚举', () {
      test('development environment should work correctly', () {
        const env = Environment.development;
        expect(env.isDev, true);
        expect(env.isStaging, false);
        expect(env.isProd, false);
      });

      test('staging environment should work correctly', () {
        const env = Environment.staging;
        expect(env.isDev, false);
        expect(env.isStaging, true);
        expect(env.isProd, false);
      });

      test('production environment should work correctly', () {
        const env = Environment.production;
        expect(env.isDev, false);
        expect(env.isStaging, false);
        expect(env.isProd, true);
      });

      test('environments should be mutually exclusive', () {
        for (final env in Environment.values) {
          final flags = [env.isDev, env.isStaging, env.isProd];
          final trueCount = flags.where((f) => f).length;
          expect(trueCount, 1);
        }
      });
    });

    group('配置一致性', () {
      test('should have consistent configuration', () {
        // 应用名和包名应该有关联
        expect(config.packageName.toLowerCase(), contains('easyfile'));
        expect(config.appName.toLowerCase(), contains('easy'));
      });

      test('multiple instances should return same values', () {
        final config1 = BuildConfig();
        final config2 = BuildConfig();

        expect(config1.isDebug, config2.isDebug);
        expect(config1.packageName, config2.packageName);
        expect(config1.appName, config2.appName);
        expect(config1.supportsAndroid, config2.supportsAndroid);
      });
    });
  });
}
