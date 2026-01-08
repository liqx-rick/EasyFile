import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/data/models/app_trash_item.dart';

/// 快速冒烟测试 - Phase 1 基础架构
///
/// 只测试AppTrashItem模型的核心逻辑（不依赖Android环境）
/// 注意：Settings和PathSecurity的测试需要完整环境，留到Phase 2在真机测试
void main() {
  group('AppTrashItem 模型测试', () {
    test('应该正确创建回收站文件项', () {
      final item = AppTrashItem(
        id: 'test-id-123',
        trashPath: '/data/.trash/1234567890_photo.jpg',
        originalPath: '/storage/emulated/0/DCIM/photo.jpg',
        fileName: 'photo.jpg',
        size: 1024000,
        mimeType: 'image/jpeg',
        deletedAt: DateTime(2025, 12, 1),
      );

      expect(item.id, 'test-id-123');
      expect(item.fileName, 'photo.jpg');
      expect(item.size, 1024000);
      expect(item.mimeType, 'image/jpeg');
    });

    test('应该正确计算文件删除天数', () {
      final now = DateTime.now();
      final threeDaysAgo = now.subtract(const Duration(days: 3));

      final item = AppTrashItem(
        id: 'test-id',
        trashPath: '/data/.trash/file.txt',
        originalPath: '/storage/file.txt',
        fileName: 'file.txt',
        size: 100,
        mimeType: 'text/plain',
        deletedAt: threeDaysAgo,
      );

      expect(item.ageDays, 3);
    });

    test('应该正确判断即将过期的文件', () {
      final now = DateTime.now();
      const retentionDays = 7;

      // 5天前删除（距离7天清理还有2天，应该即将过期）
      final fiveDaysAgo = now.subtract(const Duration(days: 5));
      final itemExpiringSoon = AppTrashItem(
        id: 'test-id-1',
        trashPath: '/data/.trash/file1.txt',
        originalPath: '/storage/file1.txt',
        fileName: 'file1.txt',
        size: 100,
        mimeType: 'text/plain',
        deletedAt: fiveDaysAgo,
      );

      expect(itemExpiringSoon.isExpiringSoon(retentionDays), true);

      // 1天前删除（还很早，不会即将过期）
      final oneDayAgo = now.subtract(const Duration(days: 1));
      final itemNotExpiring = AppTrashItem(
        id: 'test-id-2',
        trashPath: '/data/.trash/file2.txt',
        originalPath: '/storage/file2.txt',
        fileName: 'file2.txt',
        size: 100,
        mimeType: 'text/plain',
        deletedAt: oneDayAgo,
      );

      expect(itemNotExpiring.isExpiringSoon(retentionDays), false);
    });

    test('应该正确判断已过期的文件', () {
      final now = DateTime.now();
      final retentionDays = 7;

      // 8天前删除（已过期）
      final eightDaysAgo = now.subtract(const Duration(days: 8));
      final expiredItem = AppTrashItem(
        id: 'test-id',
        trashPath: '/data/.trash/file.txt',
        originalPath: '/storage/file.txt',
        fileName: 'file.txt',
        size: 100,
        mimeType: 'text/plain',
        deletedAt: eightDaysAgo,
      );

      expect(expiredItem.isExpired(retentionDays), true);
    });

    test('应该正确识别文件类型', () {
      final imageItem = AppTrashItem(
        id: 'id1',
        trashPath: '/data/.trash/photo.jpg',
        originalPath: '/storage/photo.jpg',
        fileName: 'photo.jpg',
        size: 1000,
        mimeType: 'image/jpeg',
        deletedAt: DateTime.now(),
      );
      expect(imageItem.fileTypeCategory, FileTypeCategory.image);

      final videoItem = AppTrashItem(
        id: 'id2',
        trashPath: '/data/.trash/video.mp4',
        originalPath: '/storage/video.mp4',
        fileName: 'video.mp4',
        size: 1000,
        mimeType: 'video/mp4',
        deletedAt: DateTime.now(),
      );
      expect(videoItem.fileTypeCategory, FileTypeCategory.video);

      final docItem = AppTrashItem(
        id: 'id3',
        trashPath: '/data/.trash/doc.pdf',
        originalPath: '/storage/doc.pdf',
        fileName: 'doc.pdf',
        size: 1000,
        mimeType: 'application/pdf',
        deletedAt: DateTime.now(),
      );
      expect(docItem.fileTypeCategory, FileTypeCategory.document);
    });

    test('应该正确序列化为JSON', () {
      final item = AppTrashItem(
        id: 'test-id-123',
        trashPath: '/data/.trash/file.txt',
        originalPath: '/storage/file.txt',
        fileName: 'file.txt',
        size: 2048,
        mimeType: 'text/plain',
        deletedAt: DateTime(2025, 12, 8, 10, 30, 0),
        thumbnailPath: '/data/.trash/thumbnails/file.thumb',
      );

      final json = item.toJson();

      expect(json['id'], 'test-id-123');
      expect(json['trashPath'], '/data/.trash/file.txt');
      expect(json['originalPath'], '/storage/file.txt');
      expect(json['fileName'], 'file.txt');
      expect(json['size'], 2048);
      expect(json['mimeType'], 'text/plain');
      expect(json['deletedAt'], isA<int>());
      expect(json['thumbnailPath'], '/data/.trash/thumbnails/file.thumb');
    });

    test('应该正确从JSON反序列化', () {
      final json = {
        'id': 'test-id-456',
        'trashPath': '/data/.trash/photo.jpg',
        'originalPath': '/storage/DCIM/photo.jpg',
        'fileName': 'photo.jpg',
        'size': 1024000,
        'mimeType': 'image/jpeg',
        'deletedAt': DateTime(2025, 12, 8).millisecondsSinceEpoch,
        'thumbnailPath': null,
      };

      final item = AppTrashItem.fromJson(json);

      expect(item.id, 'test-id-456');
      expect(item.trashPath, '/data/.trash/photo.jpg');
      expect(item.originalPath, '/storage/DCIM/photo.jpg');
      expect(item.fileName, 'photo.jpg');
      expect(item.size, 1024000);
      expect(item.mimeType, 'image/jpeg');
      expect(item.thumbnailPath, null);
    });

    test('JSON序列化往返应该保持数据一致性', () {
      final original = AppTrashItem(
        id: 'round-trip-test',
        trashPath: '/data/.trash/test.dat',
        originalPath: '/storage/test.dat',
        fileName: 'test.dat',
        size: 4096,
        mimeType: 'application/octet-stream',
        deletedAt: DateTime(2025, 12, 8, 15, 45, 30),
      );

      final json = original.toJson();
      final restored = AppTrashItem.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.trashPath, original.trashPath);
      expect(restored.originalPath, original.originalPath);
      expect(restored.fileName, original.fileName);
      expect(restored.size, original.size);
      expect(restored.mimeType, original.mimeType);
      expect(restored.deletedAt.millisecondsSinceEpoch,
          original.deletedAt.millisecondsSinceEpoch);
    });

    test('应该正确转换为数据库Map', () {
      final item = AppTrashItem(
        id: 'db-test-id',
        trashPath: '/data/.trash/file.bin',
        originalPath: '/storage/file.bin',
        fileName: 'file.bin',
        size: 8192,
        mimeType: 'application/octet-stream',
        deletedAt: DateTime(2025, 12, 8, 12, 0, 0),
      );

      final map = item.toMap();

      expect(map['id'], 'db-test-id');
      expect(map['trash_path'], '/data/.trash/file.bin');
      expect(map['original_path'], '/storage/file.bin');
      expect(map['file_name'], 'file.bin');
      expect(map['file_size'], 8192);
      expect(map['mime_type'], 'application/octet-stream');
      expect(map['deleted_at'], isA<int>());
      expect(map['thumbnail_path'], null);
    });

    test('应该正确从数据库Map创建', () {
      final map = {
        'id': 'db-map-test',
        'trash_path': '/data/.trash/video.mp4',
        'original_path': '/storage/Movies/video.mp4',
        'file_name': 'video.mp4',
        'file_size': 104857600,
        'mime_type': 'video/mp4',
        'deleted_at': DateTime(2025, 12, 7).millisecondsSinceEpoch,
        'thumbnail_path': '/data/.trash/thumb.jpg',
      };

      final item = AppTrashItem.fromMap(map);

      expect(item.id, 'db-map-test');
      expect(item.trashPath, '/data/.trash/video.mp4');
      expect(item.originalPath, '/storage/Movies/video.mp4');
      expect(item.fileName, 'video.mp4');
      expect(item.size, 104857600);
      expect(item.mimeType, 'video/mp4');
      expect(item.thumbnailPath, '/data/.trash/thumb.jpg');
    });
  });
}
