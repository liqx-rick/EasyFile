import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/data/models/folder_stats.dart';
import 'package:easyfile/data/models/app_dir_config.dart';

void main() {
  group('QuickAccess Integration Tests', () {
    test('应该正确创建QuickAccessFolder从旧数据', () {
      // 模拟从旧数据手动迁移
      final oldFavoriteData = {
        'id': 'test_123',
        'name': '下载',
        'path': '/storage/emulated/0/Download',
        'iconName': 'download',
        'createdAt': DateTime.now().toIso8601String(),
        'pinned': true,
      };

      // 手动创建QuickAccessFolder
      final quickAccess = QuickAccessFolder(
        id: oldFavoriteData['id'] as String,
        path: oldFavoriteData['path'] as String,
        originalName: oldFavoriteData['name'] as String,
        type: QuickAccessFolderType.system,
        createdAt: DateTime.parse(oldFavoriteData['createdAt'] as String),
        iconName: oldFavoriteData['iconName'] as String,
      );

      expect(quickAccess.id, equals('test_123'));
      expect(quickAccess.displayName, equals('下载'));
      expect(quickAccess.type, equals(QuickAccessFolderType.system));
    });

    test('应该正确处理别名优先级', () {
      final folder1 = QuickAccessFolder(
        id: '1',
        path: '/test',
        originalName: 'TestFolder',
        type: QuickAccessFolderType.other,
        createdAt: DateTime.now(),
      );
      expect(folder1.displayName, equals('TestFolder'));

      final folder2 = folder1.copyWith(
        recommendedAlias: 'Test Folder (推荐)',
      );
      expect(folder2.displayName, equals('Test Folder (推荐)'));

      final folder3 = folder2.copyWith(
        userAlias: '我的测试文件夹',
      );
      expect(folder3.displayName, equals('我的测试文件夹'));
    });

    test('应该正确识别文件夹类型', () {
      final systemFolder = QuickAccessFolder(
        id: '1',
        path: '/storage/emulated/0/Download',
        originalName: 'Download',
        type: QuickAccessFolderType.system,
        createdAt: DateTime.now(),
      );
      expect(systemFolder.categoryDisplay, equals('系统目录'));

      final appFolder = QuickAccessFolder(
        id: '2',
        path: '/storage/emulated/0/WhatsApp',
        originalName: 'WhatsApp',
        type: QuickAccessFolderType.other,
        createdAt: DateTime.now(),
      );
      expect(appFolder.categoryDisplay, equals('其他文件夹'));

      final appSubfolder = QuickAccessFolder(
        id: '3',
        path: '/storage/emulated/0/WhatsApp/Media/Images',
        originalName: 'Images',
        type: QuickAccessFolderType.other,
        createdAt: DateTime.now(),
      );
      expect(appSubfolder.categoryDisplay, equals('其他文件夹'));

      final userFolder = QuickAccessFolder(
        id: '4',
        path: '/storage/emulated/0/MyCustomFolder',
        originalName: 'MyCustomFolder',
        type: QuickAccessFolderType.other,
        createdAt: DateTime.now(),
      );
      expect(userFolder.categoryDisplay, equals('其他文件夹'));
    });

    test('应该正确序列化和反序列化', () {
      final original = QuickAccessFolder(
        id: 'test_001',
        path: '/storage/emulated/0/TestFolder',
        originalName: 'TestFolder',
        recommendedAlias: 'Test Folder',
        userAlias: '测试文件夹',
        type: QuickAccessFolderType.other,
        createdAt: DateTime.now(),
        lastAccessedAt: DateTime.now(),
        accessCount: 5,
        stats: FolderStats(
          totalFiles: 100,
          totalFolders: 10,
          fileTypeCounts: {FileCategory.image: 80, FileCategory.video: 20},
          totalSizeMB: 500.0,
          lastModified: DateTime.now(),
        ),
        iconName: 'folder',
      );

      final json = original.toJson();
      final restored = QuickAccessFolder.fromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.path, equals(original.path));
      expect(restored.originalName, equals(original.originalName));
      expect(restored.recommendedAlias, equals(original.recommendedAlias));
      expect(restored.userAlias, equals(original.userAlias));
      expect(restored.type, equals(original.type));
      expect(restored.accessCount, equals(original.accessCount));
      expect(restored.stats?.totalFiles, equals(100));
    });

    test('应该验证应用配置完整性', () {
      expect(AppDirConfigs.tier1Apps.length, equals(15));
      expect(AppDirConfigs.tier2Apps.length, equals(20));
      expect(AppDirConfigs.tier3Apps.length, equals(15));
      expect(AppDirConfigs.allApps.length, equals(50));

      // 检查高优先级应用
      final highPriority = AppDirConfigs.highPriorityApps;
      expect(highPriority.every((app) => app.priority == 1), isTrue);

      // 检查是否包含常用应用
      final appNames = AppDirConfigs.allApps.map((a) => a.name).toList();
      expect(appNames, contains('WhatsApp'));
      expect(appNames, contains('WeChat'));
      expect(appNames, contains('TikTok'));
    });
  });
}
