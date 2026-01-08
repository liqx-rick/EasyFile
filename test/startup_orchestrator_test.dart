import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/services/startup/first_install_service.dart';
import 'package:easyfile/core/services/startup/cache_service.dart';
import 'package:get_it/get_it.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Startup Services Injection Tests', () {
    setUpAll(() async {
      setupLocator();
      // Wait for async services to initialize
      await Future.delayed(const Duration(milliseconds: 500));
    });

    test('FirstInstallService should be registered and instantiable', () {
      final service = GetIt.instance<FirstInstallService>();
      expect(service, isNotNull);
    });

    test('CacheService should be registered and instantiable', () {
      final service = GetIt.instance<CacheService>();
      expect(service, isNotNull);
    });

    group('FirstInstallService Methods', () {
      test('isInitialized should be callable', () async {
        final service = GetIt.instance<FirstInstallService>();
        final result = await service.isInitialized();
        expect(result, isA<bool>());
      });

      test('clearInitialization should be callable', () async {
        final service = GetIt.instance<FirstInstallService>();
        expect(() => service.clearInitialization(), returnsNormally);
      });
    });

    group('CacheService Methods', () {
      test('isCacheValid should be callable', () async {
        final service = GetIt.instance<CacheService>();
        final result = await service.isCacheValid();
        expect(result, isA<bool>());
      });

      test('updateLastScanTime should be callable', () async {
        final service = GetIt.instance<CacheService>();
        expect(() => service.updateLastScanTime(), returnsNormally);
      });
    });
  });
}
