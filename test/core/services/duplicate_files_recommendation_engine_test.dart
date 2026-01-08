import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/config/storage/config_storage.dart';
import 'package:easyfile/core/services/duplicate_files_recommendation_engine.dart';
import 'package:easyfile/data/models/file_item.dart';

// Mock 存储实现
class MockConfigStorage implements ConfigStorage {
  final Map<String, dynamic> _data = {};

  @override
  String? getString(String key) => _data[key] as String?;

  @override
  int? getInt(String key) => _data[key] as int?;

  @override
  double? getDouble(String key) => _data[key] as double?;

  @override
  bool? getBool(String key) => _data[key] as bool?;

  @override
  List<String>? getStringList(String key) => _data[key] as List<String>?;

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = value;
    return true;
  }

  @override
  bool containsKey(String key) => _data.containsKey(key);

  @override
  Future<void> setAll(Map<String, dynamic> values) async {
    _data.addAll(values);
  }

  @override
  Set<String> getKeys() => _data.keys.toSet();

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final mockStorage = MockConfigStorage();
    await AppConfig.instance.initialize(storage: mockStorage);
  });

  group('DuplicateFilesRecommendationEngine - 基础功能', () {
    test('Engine 可以正常实例化', () {
      const engine = DuplicateFilesRecommendationEngine();
      expect(engine, isNotNull);
    });

    test('sortFilesByRecommendation 返回排序后的列表', () {
      const engine = DuplicateFilesRecommendationEngine();

      final file1 = FileItem(
        name: 'test1.jpg',
        path: '/storage/emulated/0/download/test1.jpg',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final file2 = FileItem(
        name: 'test2.jpg',
        path: '/storage/emulated/0/dcim/test2.jpg',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final sorted = engine.sortFilesByRecommendation([file1, file2]);

      expect(sorted.length, equals(2));
      expect(sorted[0].path, contains('dcim')); // DCIM 应该排在前面
    });
  });

  group('DuplicateFilesRecommendationEngine - 目录评分', () {
    const engine = DuplicateFilesRecommendationEngine();

    test('系统原生目录得分最高', () {
      final dcimFile = FileItem(
        name: 'photo.jpg',
        path: '/storage/emulated/0/dcim/camera/photo.jpg',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final downloadFile = FileItem(
        name: 'photo.jpg',
        path: '/storage/emulated/0/download/photo.jpg',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final files = [dcimFile, downloadFile];
      final dcimScore = engine.calculateRecommendScore(dcimFile, files);
      final downloadScore = engine.calculateRecommendScore(downloadFile, files);

      expect(dcimScore, greaterThan(downloadScore));
    });

    test('用户自建目录优于Download目录', () {
      final userFile = FileItem(
        name: 'doc.pdf',
        path: '/storage/emulated/0/工作文档/doc.pdf',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final downloadFile = FileItem(
        name: 'doc.pdf',
        path: '/storage/emulated/0/download/doc.pdf',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final files = [userFile, downloadFile];
      final userScore = engine.calculateRecommendScore(userFile, files);
      final downloadScore = engine.calculateRecommendScore(downloadFile, files);

      expect(userScore, greaterThan(downloadScore));
    });

    test('应用子目录得分降低', () {
      final normalFile = FileItem(
        name: 'photo.jpg',
        path: '/storage/emulated/0/pictures/photo.jpg',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final weixinFile = FileItem(
        name: 'photo.jpg',
        path: '/storage/emulated/0/tencent/weixin/photo.jpg',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final files = [normalFile, weixinFile];
      final normalScore = engine.calculateRecommendScore(normalFile, files);
      final weixinScore = engine.calculateRecommendScore(weixinFile, files);

      expect(normalScore, greaterThan(weixinScore));
    });
  });

  group('DuplicateFilesRecommendationEngine - 关键词评分', () {
    const engine = DuplicateFilesRecommendationEngine();

    test('正向关键词加分', () {
      final finalFile = FileItem(
        name: '报告_最终版.pdf',
        path: '/storage/emulated/0/download/报告_最终版.pdf',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final normalFile = FileItem(
        name: '报告.pdf',
        path: '/storage/emulated/0/download/报告.pdf',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final files = [finalFile, normalFile];
      final finalScore = engine.calculateRecommendScore(finalFile, files);
      final normalScore = engine.calculateRecommendScore(normalFile, files);

      expect(finalScore, greaterThan(normalScore));
    });

    test('负向关键词扣分', () {
      final copyFile = FileItem(
        name: '照片 副本.jpg',
        path: '/storage/emulated/0/download/照片 副本.jpg',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final normalFile = FileItem(
        name: '照片.jpg',
        path: '/storage/emulated/0/download/照片.jpg',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final files = [copyFile, normalFile];
      final copyScore = engine.calculateRecommendScore(copyFile, files);
      final normalScore = engine.calculateRecommendScore(normalFile, files);

      expect(copyScore, lessThan(normalScore));
    });
  });

  group('DuplicateFilesRecommendationEngine - 文件名检测', () {
    const engine = DuplicateFilesRecommendationEngine();

    test('微信导出文件识别并扣分', () {
      final weixinExport = FileItem(
        name: 'mmexport1642156789.jpg',
        path: '/storage/emulated/0/download/mmexport1642156789.jpg',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final normalFile = FileItem(
        name: 'photo.jpg',
        path: '/storage/emulated/0/download/photo.jpg',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final files = [weixinExport, normalFile];
      final weixinScore = engine.calculateRecommendScore(weixinExport, files);
      final normalScore = engine.calculateRecommendScore(normalFile, files);

      expect(weixinScore, lessThan(normalScore));
    });

    test('UUID格式文件识别并扣分', () {
      final uuidFile = FileItem(
        name: '550e8400-e29b-41d4-a716-446655440000.jpg',
        path:
            '/storage/emulated/0/download/550e8400-e29b-41d4-a716-446655440000.jpg',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final normalFile = FileItem(
        name: 'vacation_photo.jpg',
        path: '/storage/emulated/0/download/vacation_photo.jpg',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final files = [uuidFile, normalFile];
      final uuidScore = engine.calculateRecommendScore(uuidFile, files);
      final normalScore = engine.calculateRecommendScore(normalFile, files);

      expect(uuidScore, lessThan(normalScore));
    });
  });

  group('DuplicateFilesRecommendationEngine - 时间和大小', () {
    const engine = DuplicateFilesRecommendationEngine();

    test('较新的文件得分更高', () {
      final newFile = FileItem(
        name: 'doc.pdf',
        path: '/storage/emulated/0/download/doc.pdf',
        size: 1024,
        modified: DateTime(2024, 1, 10),
        isDirectory: false,
      );

      final oldFile = FileItem(
        name: 'doc.pdf',
        path: '/storage/emulated/0/download/doc_old.pdf',
        size: 1024,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final files = [newFile, oldFile];
      final newScore = engine.calculateRecommendScore(newFile, files);
      final oldScore = engine.calculateRecommendScore(oldFile, files);

      expect(newScore, greaterThan(oldScore));
    });

    test('较大的文件得分更高', () {
      final largeFile = FileItem(
        name: 'photo.jpg',
        path: '/storage/emulated/0/download/photo_large.jpg',
        size: 2048,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final smallFile = FileItem(
        name: 'photo.jpg',
        path: '/storage/emulated/0/download/photo_small.jpg',
        size: 512,
        modified: DateTime(2024, 1, 1),
        isDirectory: false,
      );

      final files = [largeFile, smallFile];
      final largeScore = engine.calculateRecommendScore(largeFile, files);
      final smallScore = engine.calculateRecommendScore(smallFile, files);

      expect(largeScore, greaterThan(smallScore));
    });
  });
}
