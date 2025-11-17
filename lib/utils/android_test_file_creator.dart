import 'dart:io';
import 'dart:math';

import 'package:easyfile/core/logger.dart';

/// Android 测试文件创建工具
class AndroidTestFileCreator {
  static const String androidRoot = '/storage/emulated/0';

  /// 创建测试文件结构
  static Future<void> createTestStructure() async {
    logger.i('🚀 开始在 Android 模拟器上创建测试文件...');

    if (!Platform.isAndroid) {
      logger.w('❌ 当前平台不是 Android，无法创建测试文件');
      return;
    }

    try {
      // 创建用户自定义文件夹
      final userFolders = {
        'MyPhotos': _createImageFiles,
        'WorkFiles': _createMixedFiles,
        'FamilyVideos': _createVideoFiles,
        'PersonalMusic': _createMusicFiles,
        'ProjectDocuments': _createDocumentFiles,
      };

      int totalFolders = 0;
      int totalFiles = 0;

      for (final entry in userFolders.entries) {
        final result = await _createUserFolder(entry.key, entry.value);
        if (result['success'] == true) {
          totalFolders++;
          totalFiles += result['fileCount'] as int;
        }
      }

      logger.i('✅ 测试文件创建完成！');
      logger.i('📊 统计: 文件夹 $totalFolders 个，文件 $totalFiles 个');
    } catch (e, stack) {
      logger.e('❌ 创建测试文件失败: $e\n$stack');
    }
  }

  /// 创建用户文件夹
  static Future<Map<String, dynamic>> _createUserFolder(
    String folderName,
    Future<int> Function(String) createFiles,
  ) async {
    try {
      final folderPath = '$androidRoot/$folderName';
      final folder = Directory(folderPath);

      logger.i('📁 创建文件夹: $folderName');

      // 创建主文件夹
      if (!folder.existsSync()) {
        folder.createSync(recursive: true);
      }

      // 创建文件
      final fileCount = await createFiles(folderPath);

      logger.i('   ✓ $folderName 创建完成 ($fileCount 个文件)');
      return {'success': true, 'fileCount': fileCount};
    } catch (e) {
      logger.e('   ✗ 创建 $folderName 失败: $e');
      return {'success': false, 'fileCount': 0};
    }
  }

  /// 创建图片文件（深度3层）
  static Future<int> _createImageFiles(String basePath) async {
    int count = 0;
    final years = ['2023', '2024', '2025'];
    final extensions = ['jpg', 'png', 'gif', 'webp'];

    for (final year in years) {
      final yearPath = '$basePath/$year';
      Directory(yearPath).createSync(recursive: true);

      for (var month = 1; month <= 3; month++) {
        final monthPath = '$yearPath/${month.toString().padLeft(2, '0')}';
        Directory(monthPath).createSync(recursive: true);

        // 每月3-5张图片
        for (var i = 1; i <= Random().nextInt(3) + 3; i++) {
          final ext = extensions[Random().nextInt(extensions.length)];
          final filePath = '$monthPath/photo_$i.$ext';
          if (await _createDummyFile(filePath, 'Fake image file')) {
            count++;
          }
        }
      }
    }
    return count;
  }

  /// 创建视频文件（深度2层）
  static Future<int> _createVideoFiles(String basePath) async {
    int count = 0;
    final categories = ['Vacation', 'Family', 'Work'];
    final extensions = ['mp4', 'avi', 'mkv', 'mov'];

    for (final category in categories) {
      final categoryPath = '$basePath/$category';
      Directory(categoryPath).createSync(recursive: true);

      for (final subFolder in ['2024', '2025']) {
        final subPath = '$categoryPath/$subFolder';
        Directory(subPath).createSync(recursive: true);

        for (var i = 1; i <= 2; i++) {
          final ext = extensions[Random().nextInt(extensions.length)];
          final filePath = '$subPath/video_$i.$ext';
          if (await _createDummyFile(filePath, 'Fake video file')) {
            count++;
          }
        }
      }
    }
    return count;
  }

  /// 创建音乐文件（深度2层）
  static Future<int> _createMusicFiles(String basePath) async {
    int count = 0;
    final artists = ['Artist_A', 'Artist_B', 'Artist_C'];
    final extensions = ['mp3', 'flac', 'wav', 'm4a'];

    for (final artist in artists) {
      final artistPath = '$basePath/$artist';
      Directory(artistPath).createSync(recursive: true);

      for (final album in ['Album_1', 'Album_2']) {
        final albumPath = '$artistPath/$album';
        Directory(albumPath).createSync(recursive: true);

        for (var i = 1; i <= 3; i++) {
          final ext = extensions[Random().nextInt(extensions.length)];
          final filePath = '$albumPath/track_$i.$ext';
          if (await _createDummyFile(filePath, 'Fake music file')) {
            count++;
          }
        }
      }
    }
    return count;
  }

  /// 创建文档文件（深度1层）
  static Future<int> _createDocumentFiles(String basePath) async {
    int count = 0;
    final categories = {
      'Reports': ['pdf', 'doc', 'docx', 'txt'],
      'Presentations': ['ppt', 'pptx'],
      'Spreadsheets': ['xls', 'xlsx', 'csv'],
    };

    for (final entry in categories.entries) {
      final categoryPath = '$basePath/${entry.key}';
      Directory(categoryPath).createSync(recursive: true);

      for (var i = 1; i <= 4; i++) {
        final ext = entry.value[Random().nextInt(entry.value.length)];
        final filePath = '$categoryPath/document_$i.$ext';
        if (await _createDummyFile(filePath, 'Fake document file')) {
          count++;
        }
      }
    }
    return count;
  }

  /// 创建混合文件（深度5层）
  static Future<int> _createMixedFiles(String basePath) async {
    int count = 0;

    // 深度5层测试
    final deepPath = '$basePath/Level1/Level2/Level3/Level4/Level5';
    Directory(deepPath).createSync(recursive: true);

    final deepFiles = ['deep_image.jpg', 'deep_video.mp4', 'deep_doc.pdf'];
    for (final filename in deepFiles) {
      if (await _createDummyFile('$deepPath/$filename', 'Deep test file')) {
        count++;
      }
    }

    // 浅层混合文件
    final categories = {
      'Photos': ['image1.jpg', 'image2.png'],
      'Videos': ['video1.mp4'],
      'Docs': ['document.pdf', 'spreadsheet.xlsx'],
    };

    for (final entry in categories.entries) {
      final categoryPath = '$basePath/${entry.key}';
      Directory(categoryPath).createSync(recursive: true);

      for (final filename in entry.value) {
        if (await _createDummyFile('$categoryPath/$filename', 'Test file')) {
          count++;
        }
      }
    }

    return count;
  }

  /// 创建虚拟文件
  static Future<bool> _createDummyFile(String filePath, String content) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        await file.writeAsString(content);
        return true;
      }
      return false;
    } catch (e) {
      logger.d('创建文件失败 $filePath: $e');
      return false;
    }
  }

  /// 清理测试文件
  static Future<void> cleanupTestFiles() async {
    logger.i('🗑️ 开始清理测试文件...');

    if (!Platform.isAndroid) {
      logger.w('❌ 当前平台不是 Android');
      return;
    }

    final testFolders = [
      'MyPhotos',
      'WorkFiles',
      'FamilyVideos',
      'PersonalMusic',
      'ProjectDocuments',
    ];

    int deletedCount = 0;
    for (final folderName in testFolders) {
      try {
        final folderPath = '$androidRoot/$folderName';
        final folder = Directory(folderPath);
        if (folder.existsSync()) {
          folder.deleteSync(recursive: true);
          deletedCount++;
          logger.i('   ✓ 已删除: $folderName');
        }
      } catch (e) {
        logger.e('   ✗ 删除失败 $folderName: $e');
      }
    }

    logger.i('✅ 清理完成！删除了 $deletedCount 个文件夹');
  }
}
