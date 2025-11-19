import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/data/services/folder_analyzer.dart';

void main() {
  group('FolderAnalyzer Tests', () {
    late FolderAnalyzer analyzer;

    setUp(() {
      analyzer = FolderAnalyzer();
    });

    test('应该正确分析文件夹统计', () async {
      // 使用测试项目中的实际文件夹
      final testPath = Directory.current.path;

      final stats = await analyzer.analyzeFolderStats(
        testPath,
        maxDepth: 1,
        includeHidden: false,
      );

      expect(stats, isNotNull);
      expect(stats.totalFiles, greaterThan(0));
    });

    test('应该正确检测文件类型', () async {
      final testPath = '${Directory.current.path}/test';

      if (Directory(testPath).existsSync()) {
        final stats = await analyzer.analyzeFolderStats(testPath, maxDepth: 1);

        expect(stats.fileTypeCounts, isNotNull);
      }
    });

    test('应该检测到临时文件夹', () {
      expect(
          analyzer.isTempOrCacheFolder('/storage/emulated/0/.cache'), isTrue);
      expect(analyzer.isTempOrCacheFolder('/storage/emulated/0/temp'), isTrue);
      expect(analyzer.isTempOrCacheFolder('/storage/emulated/0/MyFolder'),
          isFalse);
    });

    test('应该正确判断是否有足够内容', () async {
      final testPath = Directory.current.path;
      final hasContent = await analyzer.hasEnoughContent(
        testPath,
        minFiles: 1,
        minSizeMB: 0.1,
      );

      expect(hasContent, isTrue);
    });
  });
}
