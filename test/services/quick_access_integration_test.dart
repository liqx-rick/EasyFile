import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/data/models/folder_stats.dart';
import 'package:easyfile/data/models/app_dir_config.dart';
import 'package:easyfile/data/services/alias_recommendation_service.dart';

void main() {
  group('QuickAccess Integration Tests', () {
    test('应该正确转换FavoriteItem到QuickAccessFolder', () {
      // 模拟从旧数据迁移
      final oldFavorite = {
        'id': 'test_123',
        'name': '下载',
        'path': '/storage/emulated/0/Download',
        'iconName': 'download',
        'createdAt': DateTime.now().toIso8601String(),
        'pinned': true,
      };

      // 创建QuickAccessFolder
      final quickAccess = QuickAccessFolder(
        id: oldFavorite['id'] as String,
        path: oldFavorite['path'] as String,
        originalName: oldFavorite['name'] as String,
        type: QuickAccessFolderType.system,
        createdAt: DateTime.parse(oldFavorite['createdAt'] as String),
        pinned: oldFavorite['pinned'] as bool,
        iconName: oldFavorite['iconName'] as String,
      );

      expect(quickAccess.id, equals('test_123'));
      expect(quickAccess.displayName, equals('下载'));
      expect(quickAccess.type, equals(QuickAccessFolderType.system));
      expect(quickAccess.pinned, isTrue);
    });

    test('应该正确处理别名优先级', () {
      final folder1 = QuickAccessFolder(
        id: '1',
        path: '/test',
        originalName: 'TestFolder',
        type: QuickAccessFolderType.userCustom,
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
        type: QuickAccessFolderType.appRoot,
        createdAt: DateTime.now(),
      );
      expect(appFolder.categoryDisplay, equals('应用目录'));

      final appSubfolder = QuickAccessFolder(
        id: '3',
        path: '/storage/emulated/0/WhatsApp/Media/Images',
        originalName: 'Images',
        type: QuickAccessFolderType.appSubfolder,
        parentApp: 'WhatsApp',
        createdAt: DateTime.now(),
      );
      expect(appSubfolder.categoryDisplay, equals('应用目录 - WhatsApp'));

      final userFolder = QuickAccessFolder(
        id: '4',
        path: '/storage/emulated/0/MyCustomFolder',
        originalName: 'MyCustomFolder',
        type: QuickAccessFolderType.userCustom,
        createdAt: DateTime.now(),
      );
      expect(userFolder.categoryDisplay, equals('我的文件夹'));
    });

    test('应该正确序列化和反序列化', () {
      final original = QuickAccessFolder(
        id: 'test_001',
        path: '/storage/emulated/0/TestFolder',
        originalName: 'TestFolder',
        recommendedAlias: 'Test Folder',
        userAlias: '测试文件夹',
        type: QuickAccessFolderType.userCustom,
        createdAt: DateTime.now(),
        lastAccessedAt: DateTime.now(),
        accessCount: 5,
        pinned: true,
        stats: FolderStats(
          totalFiles: 100,
          totalFolders: 10,
          fileTypeCounts: {FileType.image: 80, FileType.video: 20},
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
      expect(restored.pinned, equals(original.pinned));
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

    test('应该为应用配置推荐正确别名', () {
      final service = AliasRecommendationService();
      
      final whatsappAlias = service.recommendAlias(
        path: '/storage/emulated/0/WhatsApp/Media/WhatsApp Images',
        originalName: 'WhatsApp Images',
        type: QuickAccessFolderType.appSubfolder,
      );
      expect(whatsappAlias, equals('WhatsApp图片'));

      final wechatAlias = service.recommendAlias(
        path: '/storage/emulated/0/tencent/MicroMsg/download',
        originalName: 'download',
        type: QuickAccessFolderType.appSubfolder,
      );
      expect(wechatAlias, equals('微信下载'));
    });
  });
}
