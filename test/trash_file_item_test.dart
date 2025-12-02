import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/data/models/trash_file_item.dart';

void main() {
  group('TrashFileItem Tests', () {
    test('should create TrashFileItem with all properties', () {
      final now = DateTime.now();
      final item = TrashFileItem(
        name: 'test.txt',
        path: '/storage/emulated/0/.Trash/test.txt',
        size: 1024,
        modified: now,
        trashedTime: now,
        originalPath: '/storage/emulated/0/Download/test.txt',
        isDirectory: false,
      );

      expect(item.name, 'test.txt');
      expect(item.path, '/storage/emulated/0/.Trash/test.txt');
      expect(item.size, 1024);
      expect(item.modified, now);
      expect(item.trashedTime, now);
      expect(item.originalPath, '/storage/emulated/0/Download/test.txt');
      expect(item.isDirectory, false);
    });

    test('should serialize to JSON correctly', () {
      final now = DateTime.now();
      final item = TrashFileItem(
        name: 'test.txt',
        path: '/storage/emulated/0/.Trash/test.txt',
        size: 2048,
        modified: now,
        trashedTime: now,
        isDirectory: false,
      );

      final json = item.toJson();

      expect(json['name'], 'test.txt');
      expect(json['path'], '/storage/emulated/0/.Trash/test.txt');
      expect(json['size'], 2048);
      expect(json['modified'], now.toIso8601String());
      expect(json['trashedTime'], now.toIso8601String());
      expect(json['isDirectory'], false);
    });

    test('should deserialize from JSON correctly', () {
      final now = DateTime.now();
      final json = {
        'name': 'test.txt',
        'path': '/storage/emulated/0/.Trash/test.txt',
        'size': 4096,
        'modified': now.toIso8601String(),
        'trashedTime': now.toIso8601String(),
        'originalPath': '/storage/emulated/0/Download/test.txt',
        'isDirectory': true,
      };

      final item = TrashFileItem.fromJson(json);

      expect(item.name, 'test.txt');
      expect(item.path, '/storage/emulated/0/.Trash/test.txt');
      expect(item.size, 4096);
      expect(item.modified, now);
      expect(item.trashedTime, now);
      expect(item.originalPath, '/storage/emulated/0/Download/test.txt');
      expect(item.isDirectory, true);
    });

    test('should identify .Trash directory name', () {
      final item = TrashFileItem(
        name: 'test.txt',
        path: '/storage/emulated/0/.Trash/test.txt',
        size: 0,
        modified: DateTime.now(),
      );

      expect(item.trashDirectoryName, '.Trash');
    });

    test('should identify .Trash-xxxx directory name', () {
      final item = TrashFileItem(
        name: 'test.txt',
        path: '/storage/emulated/0/.Trash-1000/files/test.txt',
        size: 0,
        modified: DateTime.now(),
      );

      expect(item.trashDirectoryName, '.Trash-1000');
    });

    test('should return default trash name if not in trash directory', () {
      final item = TrashFileItem(
        name: 'test.txt',
        path: '/storage/emulated/0/Download/test.txt',
        size: 0,
        modified: DateTime.now(),
      );

      expect(item.trashDirectoryName, '回收站');
    });

    test('should copy with modified properties', () {
      final now = DateTime.now();
      final original = TrashFileItem(
        name: 'original.txt',
        path: '/path/original.txt',
        size: 100,
        modified: now,
        isDirectory: false,
      );

      final copied = original.copyWith(
        name: 'copied.txt',
        size: 200,
      );

      expect(copied.name, 'copied.txt');
      expect(copied.size, 200);
      expect(copied.path, '/path/original.txt'); // 未修改
      expect(copied.modified, now); // 未修改
      expect(copied.isDirectory, false); // 未修改
    });

    test('should compare equality based on path and size', () {
      final now = DateTime.now();
      final item1 = TrashFileItem(
        name: 'test.txt',
        path: '/path/test.txt',
        size: 1024,
        modified: now,
      );

      final item2 = TrashFileItem(
        name: 'test.txt',
        path: '/path/test.txt',
        size: 1024,
        modified: now.add(const Duration(hours: 1)),
      );

      expect(item1, equals(item2));
      expect(item1.hashCode, equals(item2.hashCode));
    });

    test('should not be equal if path differs', () {
      final now = DateTime.now();
      final item1 = TrashFileItem(
        name: 'test.txt',
        path: '/path1/test.txt',
        size: 1024,
        modified: now,
      );

      final item2 = TrashFileItem(
        name: 'test.txt',
        path: '/path2/test.txt',
        size: 1024,
        modified: now,
      );

      expect(item1, isNot(equals(item2)));
    });

    test('should not be equal if size differs', () {
      final now = DateTime.now();
      final item1 = TrashFileItem(
        name: 'test.txt',
        path: '/path/test.txt',
        size: 1024,
        modified: now,
      );

      final item2 = TrashFileItem(
        name: 'test.txt',
        path: '/path/test.txt',
        size: 2048,
        modified: now,
      );

      expect(item1, isNot(equals(item2)));
    });

    test('should have correct toString representation', () {
      final now = DateTime.now();
      final item = TrashFileItem(
        name: 'test.txt',
        path: '/storage/.Trash/test.txt',
        size: 512,
        modified: now,
        trashedTime: now,
      );

      final str = item.toString();

      expect(str, contains('test.txt'));
      expect(str, contains('512'));
      expect(str, contains('/storage/.Trash/test.txt'));
    });
  });
}
