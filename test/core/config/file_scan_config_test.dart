import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/config/file_scan_config.dart';
import 'package:easyfile/core/config/storage/mock_config_storage.dart';

void main() {
  group('FileScanConfig - Algorithm Parameters', () {
    late MockConfigStorage storage;
    late FileScanConfig config;

    setUp(() {
      storage = MockConfigStorage();
      config = FileScanConfig(storage);
    });

    group('垃圾文件扫描深度配置', () {
      test('should return default scan depths', () {
        expect(config.junkScanDepthDefault, 10);
        expect(config.junkScanDepthAppData, 3);
        expect(config.junkScanDepthMedia, 5);
      });

      test('should load custom scan depths from storage', () async {
        // 预设自定义值
        await storage.setInt('scan_junk_scan_depth_default', 8);
        await storage.setInt('scan_junk_scan_depth_app_data', 2);
        await storage.setInt('scan_junk_scan_depth_media', 4);

        // 创建新配置实例
        final newConfig = FileScanConfig(storage);

        expect(newConfig.junkScanDepthDefault, 8);
        expect(newConfig.junkScanDepthAppData, 2);
        expect(newConfig.junkScanDepthMedia, 4);
      });
    });

    group('缓存管理配置', () {
      test('should return default cache size', () {
        expect(config.smartCacheMaxSizeMB, 50);
        expect(config.smartCacheMaxSizeBytes, 50 * 1024 * 1024);
      });

      test('should load custom cache size from storage', () async {
        await storage.setInt('scan_smart_cache_max_size_mb', 100);

        final newConfig = FileScanConfig(storage);

        expect(newConfig.smartCacheMaxSizeMB, 100);
        expect(newConfig.smartCacheMaxSizeBytes, 100 * 1024 * 1024);
      });

      test('should correctly convert MB to bytes', () {
        expect(config.smartCacheMaxSizeBytes,
            config.smartCacheMaxSizeMB * 1024 * 1024);
      });
    });

    group('大文件扫描配置', () {
      test('should return default large file settings', () {
        expect(config.largeFileThreshold, 50);
        expect(config.largeFileMaxResults, 300);
        expect(config.largeFileCacheExpiry, 7);
        expect(config.largeFileScanTimeout, 90);
      });

      test('should update large file threshold', () async {
        await config.setLargeFileThreshold(100);
        expect(config.largeFileThreshold, 100);
      });
    });

    group('新文件扫描配置', () {
      test('should return default new file settings', () {
        expect(config.newFilesRetentionDays, 7);
        expect(config.newFilesDisplayCount, 100);
        expect(config.newFilesCacheExpiry, 1);
      });

      test('should update new files retention days', () async {
        await config.setNewFilesRetentionDays(14);
        expect(config.newFilesRetentionDays, 14);
      });

      test('should update new files display count', () async {
        await config.setNewFilesDisplayCount(50);
        expect(config.newFilesDisplayCount, 50);
      });
    });

    group('重复文件扫描配置', () {
      test('should return default duplicate file settings', () {
        expect(config.duplicateFileMinSize, 102400); // 100KB in bytes
        expect(config.duplicateFileMinSizeInKB, 100); // 100KB
      });

      test('should correctly convert bytes to KB', () {
        expect(config.duplicateFileMinSizeInKB,
            (config.duplicateFileMinSize / 1024).round());
      });
    });

    group('回收站配置', () {
      test('should return default trash settings', () {
        expect(config.trashEnabled, true);
        expect(config.trashRetentionDays, 7);
        expect(config.trashRetentionOptions, [3, 7, 15, 30]);
      });

      test('should update trash enabled state', () async {
        await config.setTrashEnabled(false);
        expect(config.trashEnabled, false);
      });

      test('should update trash retention days', () async {
        await config.setTrashRetentionDays(15);
        expect(config.trashRetentionDays, 15);
      });

      test('should validate trash retention days', () async {
        expect(
          () => config.setTrashRetentionDays(10), // 不在选项列表中
          throwsArgumentError,
        );
      });
    });

    group('首页推荐配置', () {
      test('should return default recommendation threshold', () {
        expect(config.recommendationFileCountThreshold, 5);
        expect(config.recommendationThresholdOptions,
            [3, 5, 10, 20, 30, 50, 100, 1000, 3000]);
      });

      test('should update recommendation threshold', () async {
        await config.setRecommendationFileCountThreshold(10);
        expect(config.recommendationFileCountThreshold, 10);
      });

      test('should validate recommendation threshold', () async {
        expect(
          () => config.setRecommendationFileCountThreshold(7), // 不在选项列表中
          throwsArgumentError,
        );
      });

      test('should load custom recommendation threshold from storage',
          () async {
        await storage.setInt('scan_recommendation_file_count_threshold', 50);

        final newConfig = FileScanConfig(storage);
        expect(newConfig.recommendationFileCountThreshold, 50);
      });
    });

    group('配置重置', () {
      test('should reset all configs to defaults', () async {
        // 修改多个配置
        await storage.setInt('scan_junk_scan_depth_default', 15);
        await storage.setInt('scan_smart_cache_max_size_mb', 100);
        await config.setLargeFileThreshold(200);
        await config.setNewFilesRetentionDays(14);

        // 验证已修改
        final modifiedConfig = FileScanConfig(storage);
        expect(modifiedConfig.junkScanDepthDefault, 15);
        expect(modifiedConfig.smartCacheMaxSizeMB, 100);

        // 重置
        await config.reset();

        // 创建新实例验证已恢复默认值
        final resetConfig = FileScanConfig(storage);
        expect(resetConfig.junkScanDepthDefault, 10);
        expect(resetConfig.smartCacheMaxSizeMB, 50);
        expect(resetConfig.largeFileThreshold, 50);
        expect(resetConfig.newFilesRetentionDays, 7);
      });
    });

    group('远程配置合并', () {
      test('should merge remote config', () async {
        final remoteConfig = {
          'large_file_threshold': 80,
          'junk_scan_depth_default': 12,
          'smart_cache_max_size_mb': 80,
        };

        await config.mergeWith(remoteConfig);

        // 验证已合并
        final newConfig = FileScanConfig(storage);
        expect(newConfig.largeFileThreshold, 80);
        expect(newConfig.junkScanDepthDefault, 12);
        expect(newConfig.smartCacheMaxSizeMB, 80);
      });

      test('should handle empty remote config', () async {
        await config.mergeWith({});

        // 验证配置未改变
        expect(config.largeFileThreshold, 50);
        expect(config.junkScanDepthDefault, 10);
      });
    });

    group('边界值测试', () {
      test('should handle minimum scan depths', () async {
        await storage.setInt('scan_junk_scan_depth_default', 1);
        await storage.setInt('scan_junk_scan_depth_app_data', 1);
        await storage.setInt('scan_junk_scan_depth_media', 1);

        final newConfig = FileScanConfig(storage);
        expect(newConfig.junkScanDepthDefault, 1);
        expect(newConfig.junkScanDepthAppData, 1);
        expect(newConfig.junkScanDepthMedia, 1);
      });

      test('should handle large scan depths', () async {
        await storage.setInt('scan_junk_scan_depth_default', 50);

        final newConfig = FileScanConfig(storage);
        expect(newConfig.junkScanDepthDefault, 50);
      });

      test('should handle very small cache size', () async {
        await storage.setInt('scan_smart_cache_max_size_mb', 1);

        final newConfig = FileScanConfig(storage);
        expect(newConfig.smartCacheMaxSizeMB, 1);
        expect(newConfig.smartCacheMaxSizeBytes, 1024 * 1024);
      });

      test('should handle very large cache size', () async {
        await storage.setInt('scan_smart_cache_max_size_mb', 500);

        final newConfig = FileScanConfig(storage);
        expect(newConfig.smartCacheMaxSizeMB, 500);
        expect(newConfig.smartCacheMaxSizeBytes, 500 * 1024 * 1024);
      });
    });

    group('配置持久化', () {
      test('should persist scan depth settings', () async {
        await storage.setInt('scan_junk_scan_depth_default', 8);
        await storage.setInt('scan_junk_scan_depth_app_data', 2);
        await storage.setInt('scan_junk_scan_depth_media', 4);

        // 创建新实例（模拟应用重启）
        final newConfig = FileScanConfig(storage);

        expect(newConfig.junkScanDepthDefault, 8);
        expect(newConfig.junkScanDepthAppData, 2);
        expect(newConfig.junkScanDepthMedia, 4);
      });

      test('should persist cache settings', () async {
        await storage.setInt('scan_smart_cache_max_size_mb', 75);

        final newConfig = FileScanConfig(storage);
        expect(newConfig.smartCacheMaxSizeMB, 75);
      });
    });

    group('实际场景测试', () {
      test('should support performance optimization for low-end devices',
          () async {
        // 低端设备：减少扫描深度，降低缓存大小
        await storage.setInt('scan_junk_scan_depth_default', 6);
        await storage.setInt('scan_junk_scan_depth_app_data', 2);
        await storage.setInt('scan_smart_cache_max_size_mb', 25);

        final lowEndConfig = FileScanConfig(storage);

        expect(lowEndConfig.junkScanDepthDefault, 6);
        expect(lowEndConfig.junkScanDepthAppData, 2);
        expect(lowEndConfig.smartCacheMaxSizeMB, 25);
      });

      test('should support aggressive scanning for high-end devices', () async {
        // 高端设备：增加扫描深度，提高缓存大小
        await storage.setInt('scan_junk_scan_depth_default', 15);
        await storage.setInt('scan_junk_scan_depth_app_data', 5);
        await storage.setInt('scan_smart_cache_max_size_mb', 100);

        final highEndConfig = FileScanConfig(storage);

        expect(highEndConfig.junkScanDepthDefault, 15);
        expect(highEndConfig.junkScanDepthAppData, 5);
        expect(highEndConfig.smartCacheMaxSizeMB, 100);
      });

      test('should support A/B testing for scan strategies', () async {
        // 策略A：深度扫描（可能发现更多垃圾文件，但耗时更长）
        await storage.setInt('scan_junk_scan_depth_default', 12);

        // 策略B：快速扫描（牺牲部分完整性，提升速度）
        final fastConfig = FileScanConfig(MockConfigStorage());
        await fastConfig.reset();
        final strategyBStorage = MockConfigStorage();
        await strategyBStorage.setInt('scan_junk_scan_depth_default', 6);

        final deepConfig = FileScanConfig(storage);
        final fastConfigReloaded = FileScanConfig(strategyBStorage);

        expect(deepConfig.junkScanDepthDefault, 12);
        expect(fastConfigReloaded.junkScanDepthDefault, 6);
      });

      test('should support emergency performance fix', () async {
        // 紧急情况：用户反馈扫描太慢，远程下发配置快速止血
        final emergencyConfig = {
          'junk_scan_depth_default': 5,
          'junk_scan_depth_app_data': 2,
          'junk_scan_depth_media': 3,
          'large_file_scan_timeout': 30,
        };

        await config.mergeWith(emergencyConfig);

        final newConfig = FileScanConfig(storage);
        expect(newConfig.junkScanDepthDefault, 5);
        expect(newConfig.junkScanDepthAppData, 2);
        expect(newConfig.junkScanDepthMedia, 3);
        expect(newConfig.largeFileScanTimeout, 30);
      });
    });

    group('配置组合测试', () {
      test('should work with different depth combinations', () async {
        await storage.setInt('scan_junk_scan_depth_default', 10);
        await storage.setInt('scan_junk_scan_depth_app_data', 3);
        await storage.setInt('scan_junk_scan_depth_media', 5);

        final config = FileScanConfig(storage);

        // 验证不同目录类型的深度配置
        expect(config.junkScanDepthDefault,
            greaterThan(config.junkScanDepthMedia));
        expect(config.junkScanDepthMedia,
            greaterThan(config.junkScanDepthAppData));
      });

      test('should maintain relationship between cache size units', () async {
        await storage.setInt('scan_smart_cache_max_size_mb', 60);

        final config = FileScanConfig(storage);

        // MB 和 Bytes 应该保持正确的换算关系
        expect(config.smartCacheMaxSizeBytes,
            config.smartCacheMaxSizeMB * 1024 * 1024);
      });
    });
  });
}
