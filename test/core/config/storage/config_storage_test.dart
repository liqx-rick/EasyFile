import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/config/storage/local_config_storage.dart';
import 'package:easyfile/core/config/storage/mock_config_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LocalConfigStorage', () {
    late LocalConfigStorage storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = await LocalConfigStorage.create();
    });

    group('基础 CRUD 操作', () {
      test('should set and get string', () async {
        await storage.setString('test_key', 'test_value');
        expect(storage.getString('test_key'), 'test_value');
      });

      test('should set and get int', () async {
        await storage.setInt('test_int', 42);
        expect(storage.getInt('test_int'), 42);
      });

      test('should set and get bool', () async {
        await storage.setBool('test_bool', true);
        expect(storage.getBool('test_bool'), true);
      });

      test('should return null for non-existent key', () {
        expect(storage.getString('non_existent'), isNull);
        expect(storage.getInt('non_existent'), isNull);
        expect(storage.getBool('non_existent'), isNull);
      });

      test('should remove key', () async {
        await storage.setString('test_key', 'value');
        expect(storage.getString('test_key'), 'value');

        await storage.remove('test_key');
        expect(storage.getString('test_key'), isNull);
      });
    });

    group('批量操作', () {
      test('should set all values', () async {
        await storage.setAll({
          'key1': 'value1',
          'key2': 42,
          'key3': true,
        });

        expect(storage.getString('key1'), 'value1');
        expect(storage.getInt('key2'), 42);
        expect(storage.getBool('key3'), true);
      });

      test('should get all keys', () async {
        await storage.setString('test1', 'value1');
        await storage.setInt('test2', 42);
        await storage.setBool('test3', true);

        final keys = storage.getKeys();
        expect(keys, containsAll(['test1', 'test2', 'test3']));
      });



      test('should clear all', () async {
        await storage.setString('key1', 'value1');
        await storage.setInt('key2', 42);

        await storage.clear();

        expect(storage.getKeys().isEmpty, true);
      });
    });

    group('边界情况', () {
      test('should handle empty string', () async {
        await storage.setString('empty', '');
        expect(storage.getString('empty'), '');
      });

      test('should handle negative numbers', () async {
        await storage.setInt('negative', -100);
        expect(storage.getInt('negative'), -100);
      });

      test('should handle zero', () async {
        await storage.setInt('zero', 0);
        expect(storage.getInt('zero'), 0);
      });

      test('should handle very long string', () async {
        final longString = 'x' * 10000;
        await storage.setString('long', longString);
        expect(storage.getString('long'), longString);
      });

      test('should overwrite existing value', () async {
        await storage.setString('key', 'old');
        expect(storage.getString('key'), 'old');

        await storage.setString('key', 'new');
        expect(storage.getString('key'), 'new');
      });

      test('should handle special characters in key', () async {
        await storage.setString('key_with-special.chars', 'value');
        expect(storage.getString('key_with-special.chars'), 'value');
      });

      test('should handle unicode values', () async {
        await storage.setString('unicode', '你好世界 🌍');
        expect(storage.getString('unicode'), '你好世界 🌍');
      });
    });

    group('类型安全', () {
      test('should throw when getting wrong type', () async {
        await storage.setString('string_key', 'value');
        // SharedPreferences throws when type doesn't match
        expect(() => storage.getInt('string_key'), throwsA(isA<TypeError>()));
        expect(() => storage.getBool('string_key'), throwsA(isA<TypeError>()));
      });

      test('should handle bool true/false', () async {
        await storage.setBool('true', true);
        await storage.setBool('false', false);

        expect(storage.getBool('true'), true);
        expect(storage.getBool('false'), false);
      });
    });
  });

  group('MockConfigStorage', () {
    test('should work without SharedPreferences', () async {
      final mock = MockConfigStorage();

      await mock.setString('test', 'value');
      expect(mock.getString('test'), 'value');

      await mock.setInt('num', 123);
      expect(mock.getInt('num'), 123);

      await mock.setBool('flag', true);
      expect(mock.getBool('flag'), true);
    });

    test('should isolate between instances', () async {
      final mock1 = MockConfigStorage();
      final mock2 = MockConfigStorage();

      await mock1.setString('key', 'value1');
      await mock2.setString('key', 'value2');

      expect(mock1.getString('key'), 'value1');
      expect(mock2.getString('key'), 'value2');
    });

    test('should support all operations', () async {
      final mock = MockConfigStorage();

      // Set multiple values
      await mock.setAll({
        'str': 'text',
        'num': 42,
        'bool': true,
      });

      expect(mock.getString('str'), 'text');
      expect(mock.getInt('num'), 42);
      expect(mock.getBool('bool'), true);

      // Get all keys
      final keys = mock.getKeys();
      expect(keys, containsAll(['str', 'num', 'bool']));

      // Remove
      await mock.remove('str');
      expect(mock.getString('str'), isNull);

      // Clear
      await mock.clear();
      expect(mock.getKeys().isEmpty, true);
    });

    test('should handle concurrent operations', () async {
      final mock = MockConfigStorage();

      // 并发写入
      await Future.wait([
        mock.setString('key1', 'value1'),
        mock.setString('key2', 'value2'),
        mock.setInt('key3', 123),
      ]);

      expect(mock.getString('key1'), 'value1');
      expect(mock.getString('key2'), 'value2');
      expect(mock.getInt('key3'), 123);
    });
  });

  group('Storage Comparison', () {
    test('LocalConfigStorage and MockConfigStorage should behave same', () async {
      SharedPreferences.setMockInitialValues({});
      final local = await LocalConfigStorage.create();
      final mock = MockConfigStorage();

      // 执行相同操作
      await local.setString('test', 'value');
      await mock.setString('test', 'value');

      expect(local.getString('test'), mock.getString('test'));

      await local.setInt('num', 42);
      await mock.setInt('num', 42);

      expect(local.getInt('num'), mock.getInt('num'));
    });
  });
}
