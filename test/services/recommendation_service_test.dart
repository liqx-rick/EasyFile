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

/// 测试用的应用统计缓存（可控制返回的统计数据）
class MockAppStatisticsCache extends AppStatisticsCache {
  final Map<String, int> _fileCounts;

  MockAppStatisticsCache({Map<String, int>? fileCounts})
      : _fileCounts = fileCounts ?? {};

  @override
  Future<void> initialize() async {
    // Mock实现不需要实际初始化
  }

  @override
  Future<AppStatistics?> get(String appKey) async {
    final fileCount = _fileCounts[appKey];
    if (fileCount == null) {
      return null;
    }

    // 返回Mock统计数据（不会过期）
    return AppStatistics(
      fileCount: fileCount,
      totalSize: fileCount * 1024 * 1024, // 假设每个文件1MB
      weeklyGrowth: 0,
      cachedAt: DateTime.now(),
    );
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
    return AppScanResult(
      appName: appKey,
      packageName: 'com.test.$appKey',
      isInstalled: true,
      allFiles: const [], // 返回空列表而不是null列表
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
      // 验证都是系统类托底卡片
      expect(cards.every((c) => c.appKey == null), true);
      final cardTypes = cards.map((c) => c.type).toSet();
      expect(cardTypes, containsAll([
        RecommendationType.memories,
        RecommendationType.videos,
        RecommendationType.recordings,
        RecommendationType.largeFiles,
      ]));
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
      final statisticsCache = MockAppStatisticsCache(
        fileCounts: {
          'wechat': 2, // 返回文件数量
        },
      );
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
      final statisticsCache = MockAppStatisticsCache(
        fileCounts: {
          'wechat': 50,
        },
      );
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
      final statisticsCache = MockAppStatisticsCache(
        fileCounts: {
          'wechat': 50,
          'qq': 30,
        },
      );
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
      );

      final cards = await service.getRecommendations();

      expect(cards.length, 4);
      // 验证微信和QQ都在列表中
      expect(cards.any((c) => c.type == RecommendationType.wechat), true);
      expect(cards.any((c) => c.type == RecommendationType.qq), true);
      // 验证微信在QQ之前（priority: wechat=1, qq=3）
      final wechatIndex = cards.indexWhere((c) => c.type == RecommendationType.wechat);
      final qqIndex = cards.indexWhere((c) => c.type == RecommendationType.qq);
      expect(wechatIndex < qqIndex, true);
      // 剩余2个应该是托底卡片
      final appCardCount = cards.where((c) => c.appKey != null).length;
      expect(appCardCount, 2);
    });

    test('所有应用都满足条件 - 应只返回前4个', () async {
      final detectionService = MockAppDetectionService(
        installedApps: {
          'com.tencent.mm': true,
          'com.tencent.mobileqq': true,
          'org.telegram.messenger': true,
          'cn.wps.moffice_eng': true,
          'com.alibaba.android.rimet': true,
        },
      );

      final scanner = MockUnifiedAppScanner(
        detectionService,
        fileCounts: {
          'wechat': 50,
          'wps': 40,
          'qq': 30,
          'telegram': 25,
          'dingtalk': 20,
        },
      );
      final statisticsCache = MockAppStatisticsCache(
        fileCounts: {
          'wechat': 50,
          'wps': 40,
          'qq': 30,
          'telegram': 25,
          'dingtalk': 20,
        },
      );
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
      );

      final cards = await service.getRecommendations();

      // 只返回前4个，按priority排序
      expect(cards.length, 4);
      expect(cards.every((c) => c.appKey != null), true); // 都是应用卡片
      
      // 验证按priority排序（wechat=1, wps=2, qq=3, telegram=4）
      final cardTypes = cards.map((c) => c.type).toList();
      expect(cardTypes, containsAll([
        RecommendationType.wechat,
        RecommendationType.wps,
        RecommendationType.qq,
        RecommendationType.telegram,
      ]));
      
      // 验证顺序正确
      expect(cardTypes[0], RecommendationType.wechat);
      expect(cardTypes[1], RecommendationType.wps);
      expect(cardTypes[2], RecommendationType.qq);
      expect(cardTypes[3], RecommendationType.telegram);
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
      final statisticsCache = MockAppStatisticsCache(
        fileCounts: {
          'wechat': 3,
        },
      );
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
          'wechat': 6,
        },
      );
      final statisticsCache = MockAppStatisticsCache(
        fileCounts: {
          'wechat': 6, // 文件数>5（阈值）
        },
      );
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
      final statisticsCache = MockAppStatisticsCache(
        fileCounts: {
          'wechat': 50,
        },
      );
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
