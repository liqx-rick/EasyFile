import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:easyfile/core/services/app_trash_manager.dart';
import 'package:easyfile/core/database/app_trash_database.dart';
import 'package:easyfile/core/settings/app_trash_settings.dart';
import 'package:easyfile/data/models/app_trash_item.dart';

import 'app_trash_manager_test.mocks.dart';

@GenerateMocks([AppTrashDatabase, AppTrashSettings])
void main() {
  late MockAppTrashDatabase mockDatabase;
  late MockAppTrashSettings mockSettings;
  late AppTrashManager trashManager;

  setUp(() {
    mockDatabase = MockAppTrashDatabase();
    mockSettings = MockAppTrashSettings();
    trashManager = AppTrashManager(
      database: mockDatabase,
      settings: mockSettings,
    );
  });

  group('AppTrashManager - 清理过期文件测试', () {
    test('cleanExpiredFiles 应该删除所有过期文件', () async {
      // Arrange - 准备测试数据
      const retentionDays = 7;
      final now = DateTime.now();
      
      // 创建过期文件（8天前）
      final expiredItems = [
        AppTrashItem(
          id: 'expired-1',
          trashPath: '/data/.trash/old_file1.txt',
          originalPath: '/storage/old_file1.txt',
          fileName: 'old_file1.txt',
          size: 1024,
          mimeType: 'text/plain',
          deletedAt: now.subtract(const Duration(days: 8)),
        ),
        AppTrashItem(
          id: 'expired-2',
          trashPath: '/data/.trash/old_file2.jpg',
          originalPath: '/storage/old_file2.jpg',
          fileName: 'old_file2.jpg',
          size: 2048,
          mimeType: 'image/jpeg',
          deletedAt: now.subtract(const Duration(days: 10)),
        ),
      ];

      // Mock设置和数据库行为
      when(mockSettings.retentionDays).thenReturn(retentionDays);
      when(mockDatabase.getExpired(retentionDays))
          .thenAnswer((_) async => expiredItems);
      when(mockDatabase.delete(any)).thenAnswer((_) async => 1);

      // Act - 执行清理
      final result = await trashManager.cleanExpiredFiles();

      // Assert - 验证结果
      expect(result['deleted'], 2);
      expect(result['size'], 3072); // 1024 + 2048
      
      // 验证数据库删除被调用了2次
      verify(mockDatabase.delete('expired-1')).called(1);
      verify(mockDatabase.delete('expired-2')).called(1);
    });

    test('cleanExpiredFiles 没有过期文件时应该返回0', () async {
      // Arrange
      const retentionDays = 7;
      when(mockSettings.retentionDays).thenReturn(retentionDays);
      when(mockDatabase.getExpired(retentionDays))
          .thenAnswer((_) async => []);

      // Act
      final result = await trashManager.cleanExpiredFiles();

      // Assert
      expect(result['deleted'], 0);
      expect(result['size'], 0);
      verifyNever(mockDatabase.delete(any));
    });

    test('cleanExpiredFiles 应该根据不同的保留天数清理', () async {
      // Arrange - 30天保留期
      const retentionDays = 30;
      final now = DateTime.now();
      
      // 创建31天前的文件（过期）
      final expiredItems = [
        AppTrashItem(
          id: 'very-old',
          trashPath: '/data/.trash/very_old.txt',
          originalPath: '/storage/very_old.txt',
          fileName: 'very_old.txt',
          size: 5000,
          mimeType: 'text/plain',
          deletedAt: now.subtract(const Duration(days: 31)),
        ),
      ];

      when(mockSettings.retentionDays).thenReturn(retentionDays);
      when(mockDatabase.getExpired(retentionDays))
          .thenAnswer((_) async => expiredItems);
      when(mockDatabase.delete(any)).thenAnswer((_) async => 1);

      // Act
      final result = await trashManager.cleanExpiredFiles();

      // Assert
      expect(result['deleted'], 1);
      expect(result['size'], 5000);
      verify(mockDatabase.delete('very-old')).called(1);
    });

    test('cleanExpiredFiles 单个文件删除失败不应该影响其他文件', () async {
      // Arrange
      const retentionDays = 7;
      final now = DateTime.now();
      
      final expiredItems = [
        AppTrashItem(
          id: 'success-1',
          trashPath: '/data/.trash/file1.txt',
          originalPath: '/storage/file1.txt',
          fileName: 'file1.txt',
          size: 1000,
          mimeType: 'text/plain',
          deletedAt: now.subtract(const Duration(days: 8)),
        ),
        AppTrashItem(
          id: 'fail',
          trashPath: '/data/.trash/file2.txt',
          originalPath: '/storage/file2.txt',
          fileName: 'file2.txt',
          size: 2000,
          mimeType: 'text/plain',
          deletedAt: now.subtract(const Duration(days: 9)),
        ),
        AppTrashItem(
          id: 'success-2',
          trashPath: '/data/.trash/file3.txt',
          originalPath: '/storage/file3.txt',
          fileName: 'file3.txt',
          size: 3000,
          mimeType: 'text/plain',
          deletedAt: now.subtract(const Duration(days: 10)),
        ),
      ];

      when(mockSettings.retentionDays).thenReturn(retentionDays);
      when(mockDatabase.getExpired(retentionDays))
          .thenAnswer((_) async => expiredItems);
      
      // 第2个文件删除失败
      when(mockDatabase.delete('success-1')).thenAnswer((_) async => 1);
      when(mockDatabase.delete('fail'))
          .thenThrow(Exception('Delete failed'));
      when(mockDatabase.delete('success-2')).thenAnswer((_) async => 1);

      // Act
      final result = await trashManager.cleanExpiredFiles();

      // Assert - 应该成功删除2个文件（跳过失败的）
      expect(result['deleted'], 2);
      expect(result['size'], 4000); // 1000 + 3000
      
      verify(mockDatabase.delete('success-1')).called(1);
      verify(mockDatabase.delete('fail')).called(1);
      verify(mockDatabase.delete('success-2')).called(1);
    });

    test('cleanExpiredFiles 处理大量过期文件', () async {
      // Arrange - 创建100个过期文件
      const retentionDays = 7;
      final now = DateTime.now();
      
      final expiredItems = List.generate(
        100,
        (i) => AppTrashItem(
          id: 'expired-$i',
          trashPath: '/data/.trash/file_$i.txt',
          originalPath: '/storage/file_$i.txt',
          fileName: 'file_$i.txt',
          size: 1000,
          mimeType: 'text/plain',
          deletedAt: now.subtract(const Duration(days: 8)),
        ),
      );

      when(mockSettings.retentionDays).thenReturn(retentionDays);
      when(mockDatabase.getExpired(retentionDays))
          .thenAnswer((_) async => expiredItems);
      when(mockDatabase.delete(any)).thenAnswer((_) async => 1);

      // Act
      final result = await trashManager.cleanExpiredFiles();

      // Assert
      expect(result['deleted'], 100);
      expect(result['size'], 100000); // 100 * 1000
    });
  });

  group('AppTrashManager - startAutoCleanup 测试', () {
    test('startAutoCleanup 应该立即执行一次清理', () async {
      // Arrange
      const retentionDays = 7;
      when(mockSettings.retentionDays).thenReturn(retentionDays);
      when(mockDatabase.getExpired(retentionDays))
          .thenAnswer((_) async => []);

      // Act
      await trashManager.startAutoCleanup();

      // Assert - 验证getExpired被调用
      verify(mockDatabase.getExpired(retentionDays)).called(1);
    });
  });

  group('AppTrashManager - 统计信息测试', () {
    test('getStatistics 应该返回正确的统计信息', () async {
      // Arrange
      const retentionDays = 7;
      when(mockSettings.retentionDays).thenReturn(retentionDays);
      when(mockDatabase.getTotalCount()).thenAnswer((_) async => 42);
      when(mockDatabase.getTotalSize()).thenAnswer((_) async => 1024000);
      when(mockDatabase.getCountByType()).thenAnswer((_) async => {
            'image/jpeg': 10,
            'video/mp4': 5,
            'text/plain': 27,
          });

      // Act
      final stats = await trashManager.getStatistics();

      // Assert
      expect(stats['totalCount'], 42);
      expect(stats['totalSize'], 1024000);
      expect(stats['retentionDays'], 7);
      expect(stats['countByType'], isA<Map>());
      expect(stats['countByType']['image/jpeg'], 10);
    });
  });

  group('AppTrashManager - 清空回收站测试', () {
    test('emptyTrash 应该删除所有文件', () async {
      // Arrange
      final now = DateTime.now();
      final allItems = [
        AppTrashItem(
          id: 'item-1',
          trashPath: '/data/.trash/file1.txt',
          originalPath: '/storage/file1.txt',
          fileName: 'file1.txt',
          size: 1000,
          mimeType: 'text/plain',
          deletedAt: now.subtract(const Duration(days: 1)),
        ),
        AppTrashItem(
          id: 'item-2',
          trashPath: '/data/.trash/file2.txt',
          originalPath: '/storage/file2.txt',
          fileName: 'file2.txt',
          size: 2000,
          mimeType: 'text/plain',
          deletedAt: now.subtract(const Duration(days: 3)),
        ),
      ];

      when(mockDatabase.getAll()).thenAnswer((_) async => allItems);
      when(mockDatabase.delete(any)).thenAnswer((_) async => 1);

      // Act
      final result = await trashManager.emptyTrash();

      // Assert
      expect(result['success'], 2);
      expect(result['failed'], 0);
      expect(result['totalSize'], 3000);
      
      verify(mockDatabase.delete('item-1')).called(1);
      verify(mockDatabase.delete('item-2')).called(1);
    });

    test('emptyTrash 回收站为空时应该返回0', () async {
      // Arrange
      when(mockDatabase.getAll()).thenAnswer((_) async => []);

      // Act
      final result = await trashManager.emptyTrash();

      // Assert
      expect(result['success'], 0);
      expect(result['failed'], 0);
      expect(result['totalSize'], 0);
      verifyNever(mockDatabase.delete(any));
    });
  });

  group('AppTrashManager - 即将过期文件测试', () {
    test('getExpiringSoonItems 应该返回即将过期的文件', () async {
      // Arrange
      const retentionDays = 7;
      final now = DateTime.now();
      
      final expiringSoonItems = [
        AppTrashItem(
          id: 'expiring-1',
          trashPath: '/data/.trash/file1.txt',
          originalPath: '/storage/file1.txt',
          fileName: 'file1.txt',
          size: 1000,
          mimeType: 'text/plain',
          deletedAt: now.subtract(const Duration(days: 5)), // 还有2天
        ),
        AppTrashItem(
          id: 'expiring-2',
          trashPath: '/data/.trash/file2.txt',
          originalPath: '/storage/file2.txt',
          fileName: 'file2.txt',
          size: 2000,
          mimeType: 'text/plain',
          deletedAt: now.subtract(const Duration(days: 6)), // 还有1天
        ),
      ];

      when(mockSettings.retentionDays).thenReturn(retentionDays);
      when(mockDatabase.getExpiringSoon(retentionDays))
          .thenAnswer((_) async => expiringSoonItems);

      // Act
      final items = await trashManager.getExpiringSoonItems();

      // Assert
      expect(items.length, 2);
      expect(items[0].id, 'expiring-1');
      expect(items[1].id, 'expiring-2');
      verify(mockDatabase.getExpiringSoon(retentionDays)).called(1);
    });
  });
}
