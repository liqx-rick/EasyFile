import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/config/duplicate_files_recommendation_config.dart';
import 'package:easyfile/core/config/storage/mock_config_storage.dart';

void main() {
  group('DuplicateFilesRecommendationConfig', () {
    late MockConfigStorage storage;
    late DuplicateFilesRecommendationConfig config;

    setUp(() {
      storage = MockConfigStorage();
      config = DuplicateFilesRecommendationConfig(storage);
    });

    group('默认值测试', () {
      test('should return default algorithm parameters', () {
        expect(config.timeDecayScorePerDay, 5);
        expect(config.sizeSimilarityThreshold, 1024);
        expect(config.timeSimilarityThreshold, 3600);
        expect(config.pathDepthThreshold, 9);
      });

      test('should return default scoring rules', () {
        expect(config.systemNativeDirectoryScore, 1500);
        expect(config.userCreatedFirstLevelScore, 1000);
        expect(config.userCreatedSecondLevelScore, 800);
        expect(config.downloadDirectoryScore, 500);
        expect(config.appSubdirectoryPenalty, 500);
        expect(config.positiveKeywordScore, 500);
        expect(config.negativeKeywordPenalty, 300);
        expect(config.positivePathKeywordScore, 300);
        expect(config.negativePathKeywordPenalty, 250);
        expect(config.appDataDirectoryPenalty, 400);
        expect(config.hashNamePenalty, 200);
        expect(config.hiddenDirectoryPenalty, 200);
        expect(config.pathTooDeepPenalty, 150);
      });

      test('should return default keyword lists', () {
        expect(config.positiveKeywords, isNotEmpty);
        expect(config.negativeKeywords, isNotEmpty);
        expect(config.positivePathKeywords, isNotEmpty);
        expect(config.negativePathKeywords, isNotEmpty);

        // 验证关键中文关键词存在
        expect(config.positiveKeywords, contains('最终版'));
        expect(config.negativeKeywords, contains('副本'));
      });

      test('should return default app patterns', () {
        expect(config.appDataPatterns, isNotEmpty);
        expect(config.appSubdirectoryPatterns, isNotEmpty);

        // 验证关键应用特征存在
        expect(config.appDataPatterns, contains('com.tencent.mm'));
        expect(config.appSubdirectoryPatterns, contains('/weixin/'));
      });

      test('should return system native directories', () {
        final dirs = DuplicateFilesRecommendationConfig.systemNativeDirectories;
        expect(dirs, isNotEmpty);
        expect(dirs, contains('/storage/emulated/0/dcim'));
        expect(dirs, contains('/storage/emulated/0/pictures'));
        expect(dirs, contains('/storage/emulated/0/documents'));
      });
    });

    group('算法参数设置', () {
      test('should set time decay score per day', () async {
        await config.setTimeDecayScorePerDay(10);
        expect(config.timeDecayScorePerDay, 10);
      });

      test('should validate time decay score range', () async {
        expect(
          () => config.setTimeDecayScorePerDay(0),
          throwsArgumentError,
        );
        expect(
          () => config.setTimeDecayScorePerDay(21),
          throwsArgumentError,
        );
      });

      test('should set size similarity threshold', () async {
        await config.setSizeSimilarityThreshold(2048);
        expect(config.sizeSimilarityThreshold, 2048);
      });

      test('should validate size similarity threshold', () async {
        expect(
          () => config.setSizeSimilarityThreshold(-1),
          throwsArgumentError,
        );
      });

      test('should set time similarity threshold', () async {
        await config.setTimeSimilarityThreshold(7200);
        expect(config.timeSimilarityThreshold, 7200);
      });

      test('should validate time similarity threshold', () async {
        expect(
          () => config.setTimeSimilarityThreshold(-1),
          throwsArgumentError,
        );
      });

      test('should set path depth threshold', () async {
        await config.setPathDepthThreshold(12);
        expect(config.pathDepthThreshold, 12);
      });

      test('should validate path depth threshold', () async {
        expect(
          () => config.setPathDepthThreshold(0),
          throwsArgumentError,
        );
      });
    });

    group('关键词更新', () {
      test('should update positive keywords', () async {
        final newKeywords = ['测试1', '测试2'];
        await config.updatePositiveKeywords(newKeywords);
        expect(config.positiveKeywords, newKeywords);
      });

      test('should update negative keywords', () async {
        final newKeywords = ['删除', '临时'];
        await config.updateNegativeKeywords(newKeywords);
        expect(config.negativeKeywords, newKeywords);
      });

      test('should update app data patterns', () async {
        final newPatterns = ['com.test.app', 'com.example.app'];
        await config.updateAppDataPatterns(newPatterns);
        expect(config.appDataPatterns, newPatterns);
      });

      test('should update app subdirectory patterns', () async {
        final newPatterns = ['/test/', '/example/'];
        await config.updateAppSubdirectoryPatterns(newPatterns);
        expect(config.appSubdirectoryPatterns, newPatterns);
      });
    });

    group('配置重置', () {
      test('should reset all custom configs to defaults', () async {
        // 修改配置
        await config.setTimeDecayScorePerDay(10);
        await config.setSizeSimilarityThreshold(2048);
        await config.updatePositiveKeywords(['测试']);

        // 验证已修改
        expect(config.timeDecayScorePerDay, 10);
        expect(config.sizeSimilarityThreshold, 2048);
        expect(config.positiveKeywords, ['测试']);

        // 重置
        await config.reset();

        // 验证已恢复默认值
        expect(config.timeDecayScorePerDay, 5);
        expect(config.sizeSimilarityThreshold, 1024);
        expect(config.positiveKeywords, isNot(['测试']));
        expect(config.positiveKeywords, contains('最终版'));
      });
    });

    group('边界值测试', () {
      test('should handle extreme time decay values', () async {
        await config.setTimeDecayScorePerDay(1); // 最小值
        expect(config.timeDecayScorePerDay, 1);

        await config.setTimeDecayScorePerDay(20); // 最大值
        expect(config.timeDecayScorePerDay, 20);
      });

      test('should handle zero threshold values', () async {
        await config.setSizeSimilarityThreshold(0);
        expect(config.sizeSimilarityThreshold, 0);

        await config.setTimeSimilarityThreshold(0);
        expect(config.timeSimilarityThreshold, 0);
      });

      test('should handle large threshold values', () async {
        await config.setSizeSimilarityThreshold(1024 * 1024); // 1MB
        expect(config.sizeSimilarityThreshold, 1024 * 1024);

        await config.setTimeSimilarityThreshold(86400 * 7); // 7天
        expect(config.timeSimilarityThreshold, 86400 * 7);
      });
    });

    group('配置持久化', () {
      test('should persist algorithm parameters', () async {
        await config.setTimeDecayScorePerDay(8);
        await config.setSizeSimilarityThreshold(512);
        await config.setTimeSimilarityThreshold(1800);
        await config.setPathDepthThreshold(15);

        // 创建新实例（模拟应用重启）
        final newConfig = DuplicateFilesRecommendationConfig(storage);

        // 验证配置已持久化
        expect(newConfig.timeDecayScorePerDay, 8);
        expect(newConfig.sizeSimilarityThreshold, 512);
        expect(newConfig.timeSimilarityThreshold, 1800);
        expect(newConfig.pathDepthThreshold, 15);
      });

      test('should persist keyword lists', () async {
        final customPositive = ['完成', '最新'];
        final customNegative = ['删除', '废弃'];

        await config.updatePositiveKeywords(customPositive);
        await config.updateNegativeKeywords(customNegative);

        // 创建新实例
        final newConfig = DuplicateFilesRecommendationConfig(storage);

        expect(newConfig.positiveKeywords, customPositive);
        expect(newConfig.negativeKeywords, customNegative);
      });
    });

    group('实际场景测试', () {
      test('should support A/B testing scenarios', () async {
        // 场景A：激进的时间衰减（快速淘汰旧文件）
        await config.setTimeDecayScorePerDay(10);
        expect(config.timeDecayScorePerDay, 10);
        // 10天后时间因素就完全不起作用了

        // 场景B：保守的时间衰减（重视历史文件）
        await config.setTimeDecayScorePerDay(2);
        expect(config.timeDecayScorePerDay, 2);
        // 50天后时间因素才不起作用
      });

      test('should support device-specific optimization', () async {
        // 低端设备：提高相似度阈值，减少精细比较
        await config.setSizeSimilarityThreshold(10 * 1024); // 10KB
        await config.setTimeSimilarityThreshold(3600 * 3); // 3小时

        expect(config.sizeSimilarityThreshold, 10 * 1024);
        expect(config.timeSimilarityThreshold, 3600 * 3);
      });

      test('should support custom app patterns for new apps', () async {
        // 新流行应用上线后，可以远程更新识别特征
        final updatedPatterns = [
          ...config.appDataPatterns,
          'com.newapp.popular',
          'com.trending.app',
        ];

        await config.updateAppDataPatterns(updatedPatterns);
        expect(config.appDataPatterns, contains('com.newapp.popular'));
        expect(config.appDataPatterns, contains('com.trending.app'));
      });
    });
  });
}
