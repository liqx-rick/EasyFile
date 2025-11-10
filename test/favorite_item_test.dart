import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/data/models/favorite_item.dart';

void main() {
  group('FavoriteItem Tests', () {
    test('should create favorite item correctly', () {
      final now = DateTime.now();
      final favorite = FavoriteItem(
        id: 'test-id',
        name: 'Test Folder',
        path: '/test/path',
        createdAt: now,
      );

      expect(favorite.id, 'test-id');
      expect(favorite.name, 'Test Folder');
      expect(favorite.path, '/test/path');
      expect(favorite.createdAt, now);
      expect(favorite.iconName, isNull);
      expect(favorite.lastAccessedAt, isNull);
    });

    test('should serialize to and from JSON correctly', () {
      final now = DateTime.now();
      final original = FavoriteItem(
        id: 'test-id',
        name: 'Test Folder',
        path: '/test/path',
        iconName: 'folder',
        createdAt: now,
        lastAccessedAt: now,
      );

      final json = original.toJson();
      final restored = FavoriteItem.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.path, original.path);
      expect(restored.iconName, original.iconName);
      expect(restored.createdAt, original.createdAt);
      expect(restored.lastAccessedAt, original.lastAccessedAt);
    });

    test('should create copy with modified properties', () {
      final original = FavoriteItem(
        id: 'test-id',
        name: 'Test Folder',
        path: '/test/path',
        createdAt: DateTime.now(),
      );

      final modified = original.copyWith(
        name: 'Modified Name',
        iconName: 'star',
      );

      expect(modified.id, original.id);
      expect(modified.name, 'Modified Name');
      expect(modified.path, original.path);
      expect(modified.iconName, 'star');
      expect(modified.createdAt, original.createdAt);
    });
  });
}
