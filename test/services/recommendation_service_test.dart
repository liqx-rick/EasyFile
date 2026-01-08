import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/services/recommendation_service.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/config/app_scanner_config.dart';
import 'package:easyfile/core/services/app_statistics_cache.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/core/services/app_scan_result.dart';
import 'package:easyfile/data/models/recommendation_card.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/config/storage/mock_config_storage.dart';

/// 测试用的应用统计缓存（不执行实际缓存）
class MockAppStatisticsCache extends AppStatisticsCache {
  @override
  Future<void> initialize() async {
    // Mock实现不需要实际初始化
  }

  @override
  Future<AppStatistics?> get(String appKey) async {
    // Mock实现始终返回null，让测试走实际扫描逻辑
    return null;
  }

  @override
  Future<void> set(String appKey, AppStatistics statistics) async {
    // Mock实现不执行实际缓存
  }
}

/// 测试用的应用检测服务（可控制检测结果）
class MockAppDetectionService extends AppDetectionService {
  final Map<String, bool> _installedApps;

  MockAppDetectionService({
    Map<String, bool>? installedApps,
  }) : _installedApps = installedApps ?? {};

  @override
  Future<AppDetectionResult> detectApp(AppConfigData config) async {
    // 检查第一个包名
    if (config.packageNames.isNotEmpty) {
      final packageName = config.packageNames.first;
      final isInstalled = _installedApps[packageName] ?? false;

      return AppDetectionResult(
        isInstalled: isInstalled,
        packageName: isInstalled ? packageName : null,
        detectionMethod: 'mock',
      );
    }

    return AppDetectionResult(isInstalled: false);
  }
}

/// 测试用的统一扫描器（可控制文件数量）
class MockUnifiedAppScanner extends UnifiedAppScanner {
  final Map<String, int> _fileCounts;

  MockUnifiedAppScanner(
    super.detectionService, {
    Map<String, int>? fileCounts,
  }) : _fileCounts = fileCounts ?? {};

  @override
  Future<int?> getFileCountFast({required String appKey}) async {
    return _fileCounts[appKey];
  }

  @override
  Future<AppScanResult> scanApp({
    required String appKey,
    List<String> additionalPaths = const [],
    bool withIcon = false,
    bool useMediaStore = true,
    bool updateCache = true,
  }) async {
    final fileCount = _fileCounts[appKey] ?? 0;

    return AppScanResult(
      appName: appKey,
      packageName: 'com.test.$appKey',
      isInstalled: true,
      allFiles: List.generate(fileCount, (i) => null as dynamic), // 模拟文件列表
      mediaStoreFiles: const [],
      pathScanFiles: const [],
      differenceFiles: const [],
      mediaStoreDuration: Duration.zero,
      pathScanDuration: Duration.zero,
    );
  }
}

void main() {
  setUpAll(() async {
    // 初始化AppConfig用于测试
    await AppConfig.instance.initialize(storage: MockConfigStorage());
  });

  group('RecommendationService 过滤逻辑测试', () {
    test('所有应用未安装 - 应返回4个托底卡片', () async {
      final detectionService = MockAppDetectionService(
        installedApps: {
          'com.tencent.mm': false,
          'com.tencent.mobileqq': false,
          'org.telegram.messenger': false,
          'cn.wps.moffice_eng': false,
        },
      );

      final scanner = MockUnifiedAppScanner(detectionService);
      final statisticsCache = MockAppStatisticsCache();
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
      );

      final cards = await service.getRecommendations();

      expect(cards.length, 4);
      expect(cards[0].type, RecommendationType.memories);
      expect(cards[1].type, RecommendationType.videos);
      expect(cards[2].type, RecommendationType.recordings);
      expect(cards[3].type, RecommendationType.largeFiles);
    });

    test('微信已安装但文件数不足 - 应被过滤', () async {
      final detectionService = MockAppDetectionService(
        installedApps: {
          'com.tencent.mm': true,
        },
      );

      final scanner = MockUnifiedAppScanner(
        detectionService,
        fileCounts: {
          'wechat': 2, // 只有2个文件，要求>3
        },
      );
      final statisticsCache = MockAppStatisticsCache();
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
      );

      final cards = await service.getRecommendations();

      // 微信被过滤，显示托底卡片
      expect(cards.length, 4);
      expect(cards.any((c) => c.type == RecommendationType.wechat), false);
    });

    test('微信已安装且文件数足够 - 应显示为第一个', () async {
      final detectionService = MockAppDetectionService(
        installedApps: {
          'com.tencent.mm': true,
        },
      );

      final scanner = MockUnifiedAppScanner(
        detectionService,
        fileCounts: {
          'wechat': 50, // 文件数>3
        },
      );
      final statisticsCache = MockAppStatisticsCache();
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
      );

      final cards = await service.getRecommendations();

      expect(cards.length, 4);
      expect(cards[0].type, RecommendationType.wechat);
      expect(cards[0].fileCount, 50);
    });

    test('微信+QQ都满足条件 - 应按优先级显示', () async {
      final detectionService = MockAppDetectionService(
        installedApps: {
          'com.tencent.mm': true,
          'com.tencent.mobileqq': true,
        },
      );

      final scanner = MockUnifiedAppScanner(
        detectionService,
        fileCounts: {
          'wechat': 50,
          'qq': 30,
        },
      );
      final statisticsCache = MockAppStatisticsCache();
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
      );

      final cards = await service.getRecommendations();

      expect(cards.length, 4);
      expect(cards[0].type, RecommendationType.wechat);
      expect(cards[1].type, RecommendationType.qq);
      expect(cards[2].type, RecommendationType.memories); // 托底
      expect(cards[3].type, RecommendationType.videos); // 托底
    });

    test('所有应用都满足条件 - 应只返回前4个', () async {
      final detectionService = MockAppDetectionService(
        installedApps: {
          'com.tencent.mm': true,
          'com.tencent.mobileqq': true,
          'org.telegram.messenger': true,
          'cn.wps.moffice_eng': true,
        },
      );

      final scanner = MockUnifiedAppScanner(
        detectionService,
        fileCounts: {
          'wechat': 50,
          'qq': 30,
          'telegram': 25,
          'wps': 20,
        },
      );
      final statisticsCache = MockAppStatisticsCache();
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
      );

      final cards = await service.getRecommendations();

      // 只返回前4个
      expect(cards.length, 4);
      expect(cards[0].type, RecommendationType.wechat);
      expect(cards[1].type, RecommendationType.qq);
      expect(cards[2].type, RecommendationType.telegram);
      expect(cards[3].type, RecommendationType.wps);
    });
  });

  group('RecommendationService 自定义配置测试', () {
    test('使用自定义配置列表', () async {
      final customConfigs = [
        const RecommendationConfig(
          type: RecommendationType.memories,
          title: '自定义时光记忆',
          icon: Icons.camera,
          color: Colors.red,
          minFileCount: 0,
        ),
      ];

      final detectionService = MockAppDetectionService();
      final scanner = MockUnifiedAppScanner(detectionService);
      final statisticsCache = MockAppStatisticsCache();
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
        configs: customConfigs,
      );

      final cards = await service.getRecommendations();

      expect(cards.length, 1);
      expect(cards[0].title, '自定义时光记忆');
    });

    test('空配置列表 - 应返回空数组', () async {
      final detectionService = MockAppDetectionService();
      final scanner = MockUnifiedAppScanner(detectionService);
      final statisticsCache = MockAppStatisticsCache();
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
        configs: [],
      );

      final cards = await service.getRecommendations();

      expect(cards.isEmpty, true);
    });
  });

  group('RecommendationService 边界情况测试', () {
    test('文件数量刚好等于最小值 - 应被过滤', () async {
      final detectionService = MockAppDetectionService(
        installedApps: {
          'com.tencent.mm': true,
        },
      );

      final scanner = MockUnifiedAppScanner(
        detectionService,
        fileCounts: {
          'wechat': 3, // 等于minFileCount
        },
      );
      final statisticsCache = MockAppStatisticsCache();
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
      );

      final cards = await service.getRecommendations();

      // 微信被过滤（要求 > 3，不是 >= 3）
      expect(cards.any((c) => c.type == RecommendationType.wechat), false);
    });

    test('文件数量刚好大于最小值 - 应通过', () async {
      final detectionService = MockAppDetectionService(
        installedApps: {
          'com.tencent.mm': true,
        },
      );

      final scanner = MockUnifiedAppScanner(
        detectionService,
        fileCounts: {
          'wechat': 4, // 大于minFileCount
        },
      );
      final statisticsCache = MockAppStatisticsCache();
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
      );

      final cards = await service.getRecommendations();

      expect(cards[0].type, RecommendationType.wechat);
    });

    test('托底卡片文件数为0也应显示', () async {
      final detectionService = MockAppDetectionService();
      final scanner = MockUnifiedAppScanner(
        detectionService,
        fileCounts: {}, // 所有返回0
      );
      final statisticsCache = MockAppStatisticsCache();
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
      );

      final cards = await service.getRecommendations();

      expect(cards.length, 4);
      expect(cards[0].fileCount, 0);
      expect(cards[1].fileCount, 0);
      expect(cards[2].fileCount, 0);
      expect(cards[3].fileCount, 0);
    });
  });

  group('RecommendationService 刷新功能测试', () {
    test('refreshRecommendations 应重新生成卡片', () async {
      final detectionService = MockAppDetectionService(
        installedApps: {
          'com.tencent.mm': true,
        },
      );

      final scanner = MockUnifiedAppScanner(
        detectionService,
        fileCounts: {
          'wechat': 50,
        },
      );
      final statisticsCache = MockAppStatisticsCache();
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
      );

      final cards = await service.refreshRecommendations();

      expect(cards.length, 4);
      expect(cards[0].type, RecommendationType.wechat);
    });
  });
}
