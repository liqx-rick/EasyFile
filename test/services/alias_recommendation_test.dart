import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/data/services/alias_recommendation_service.dart';
import 'package:easyfile/data/models/folder_stats.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';

void main() {
  group('AliasRecommendationService Tests', () {
    late AliasRecommendationService service;

    setUp(() {
      service = AliasRecommendationService();
    });

    test('应该为特殊路径推荐正确别名', () {
      final alias1 = service.recommendAlias(
        path: '/storage/emulated/0/DCIM',
        originalName: 'DCIM',
      );
      expect(alias1, equals('相机照片'));

      final alias2 = service.recommendAlias(
        path: '/storage/emulated/0/Download',
        originalName: 'Download',
      );
      expect(alias2, equals('下载'));
    });

    test('应该为WhatsApp文件夹推荐正确别名', () {
      final alias = service.recommendAlias(
        path: '/storage/emulated/0/WhatsApp/Media/WhatsApp Images',
        originalName: 'WhatsApp Images',
        type: QuickAccessFolderType.appSubfolder,
      );
      expect(alias, equals('WhatsApp图片'));
    });

    test('应该为微信文件夹推荐正确别名', () {
      final alias = service.recommendAlias(
        path: '/storage/emulated/0/tencent/MicroMsg/Download',
        originalName: 'Download',
        type: QuickAccessFolderType.appSubfolder,
      );
      expect(alias, equals('微信下载'));
    });

    test('应该基于内容类型推荐别名', () {
      final stats = FolderStats(
        totalFiles: 100,
        totalFolders: 5,
        fileTypeCounts: {
          FileType.image: 85,
          FileType.video: 10,
          FileType.other: 5,
        },
        totalSizeMB: 500.0,
        lastModified: DateTime.now(),
      );

      final alias = service.recommendAlias(
        path: '/storage/emulated/0/MyPhotos',
        originalName: 'MyPhotos',
        stats: stats,
      );
      
      expect(alias, contains('图片'));
    });

    test('应该验证别名合法性', () {
      expect(service.isValidAlias('正常文件夹'), isTrue);
      expect(service.isValidAlias('My Folder'), isTrue);
      expect(service.isValidAlias(''), isFalse);
      expect(service.isValidAlias('Folder/Name'), isFalse);
      expect(service.isValidAlias('Folder:Name'), isFalse);
    });

    test('应该清理非法别名', () {
      expect(service.sanitizeAlias('Folder/Name'), equals('Folder-Name'));
      expect(service.sanitizeAlias('File:Name'), equals('File-Name'));
      expect(service.sanitizeAlias('A  B  C'), equals('A B C'));
    });

    test('应该生成别名变体', () {
      expect(service.generateAliasVariant('测试', 0), equals('测试'));
      expect(service.generateAliasVariant('测试', 1), equals('测试 (1)'));
      expect(service.generateAliasVariant('测试', 2), equals('测试 (2)'));
    });

    test('应该计算别名相似度', () {
      expect(service.calculateAliasSimilarity('测试', '测试'), equals(100));
      expect(service.calculateAliasSimilarity('测试文件夹', '测试'), greaterThan(50));
      expect(service.calculateAliasSimilarity('ABC', 'XYZ'), lessThan(50));
    });
  });
}
