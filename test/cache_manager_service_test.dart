import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/services/cache_manager_service.dart';

void main() {
  group('CacheManagerService Tests', () {
    late CacheManagerService cacheManager;

    setUp(() {
      cacheManager = CacheManagerService();
    });

    test('should format size correctly', () {
      expect(cacheManager.formatSize(500), '500 B');
      expect(cacheManager.formatSize(1024), '1.0 KB');
      expect(cacheManager.formatSize(1024 * 1024), '1.0 MB');
      expect(cacheManager.formatSize(1024 * 1024 * 1024), '1.0 GB');
      expect(cacheManager.formatSize(1536), '1.5 KB');
      expect(cacheManager.formatSize(1024 * 1024 + 512 * 1024), '1.5 MB');

      // 测试大文件列表缓存的大小格式化
      expect(cacheManager.formatSize(500 * 1024), '500.0 KB');
      expect(cacheManager.formatSize(1024 * 1024 + 512 * 1024), '1.5 MB');
    });

    test('CacheType extension should return correct display names', () {
      expect(CacheType.thumbnail.displayName, '缩略图缓存');
      expect(CacheType.log.displayName, '日志文件');
      expect(CacheType.categoryScan.displayName, '分类扫描缓存');
      expect(CacheType.searchHistory.displayName, '搜索历史');
      expect(CacheType.videoPlayback.displayName, '视频播放数据');
    });

    test('CacheItem should format size correctly', () {
      final item = CacheItem(
        name: 'Test Cache',
        description: 'Test Description',
        size: 1024 * 1024,
        type: CacheType.thumbnail,
      );

      expect(item.formattedSize, '1.0 MB');

      // 测试文件列表缓存的场景
      final largeCacheItem = CacheItem(
        name: 'Category File Lists',
        description: 'Contains file list data',
        size: 800 * 1024, // 800KB
        type: CacheType.categoryScan,
      );

      expect(largeCacheItem.formattedSize, '800.0 KB');
    });

    test('ClearAllResult should report success correctly', () {
      final successResult = ClearAllResult(
        successCount: 5,
        failCount: 0,
        errors: [],
      );

      expect(successResult.hasError, false);
      expect(successResult.message, '已清理 5 项缓存');

      final partialResult = ClearAllResult(
        successCount: 4,
        failCount: 1,
        errors: ['缩略图缓存'],
      );

      expect(partialResult.hasError, true);
      expect(partialResult.message, '已清理 4 项，1 项失败');
    });

    test('should have correct number of cache types', () {
      // 验证枚举数量与预期一致
      expect(CacheType.values.length, 5);
    });
  });
}
