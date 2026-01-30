import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/config/app_scanner_config.dart';
import 'package:easyfile/core/config/storage/mock_config_storage.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/services/app_scan_result.dart';
import 'package:easyfile/core/services/recommendation_service.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/core/utils/cancellation_token.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/recommendation_card.dart';
import 'package:flutter_test/flutter_test.dart';

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
    bool forceRefresh = false,
    CancellationToken? cancellationToken,
  }) async {
    // 返回与getFileCountFast一致的文件数量
    final count = _fileCounts[appKey] ?? 0;
    final now = DateTime.now();
    return AppScanResult(
      appName: appKey,
      packageName: 'com.test.$appKey',
      isInstalled: true,
      allFiles: List.generate(
        count,
        (i) => FileItem(
          name: 'file_$i.txt',
          path: '/mock/path/file_$i.txt',
          isDirectory: false,
          size: 1024,
          modified: now,
        ),
      ),
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
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
      );

      final cards = await service.getRecommendations();

      expect(cards.length, 4);
      // 验证都是系统类托底卡片
      expect(cards.every((c) => c.appKey == null), true);
      final cardTypes = cards.map((c) => c.type).toSet();
      expect(
          cardTypes,
          containsAll([
            RecommendationType.memories,
            RecommendationType.videos,
            RecommendationType.recordings,
            RecommendationType.largeFiles,
          ]));
    });

    test('微信已安装 - 应显示为第一个（方案A：不检查文件数）', () async {
      final detectionService = MockAppDetectionService(
        installedApps: {
          'com.tencent.mm': true,
        },
      );

      final scanner = MockUnifiedAppScanner(
        detectionService,
        fileCounts: {
          'wechat': 2, // 方案A：文件数不再用于过滤
        },
      );
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
      );

      final cards = await service.getRecommendations();

      // 方案A：应用已安装就会显示
      expect(cards.length, 4);
      expect(cards.any((c) => c.type == RecommendationType.wechat), true);
      expect(cards[0].type, RecommendationType.wechat); // 微信priority=1，应在第一个
    });

    test('微信已安装 - fileCount为0（方案A：不显示统计）', () async {
      final detectionService = MockAppDetectionService(
        installedApps: {
          'com.tencent.mm': true,
        },
      );

      final scanner = MockUnifiedAppScanner(
        detectionService,
        fileCounts: {
          'wechat': 50, // 方案A：文件数不用于显示
        },
      );
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
      );

      final cards = await service.getRecommendations();

      expect(cards.length, 4);
      expect(cards[0].type, RecommendationType.wechat);
      expect(cards[0].fileCount, 0); // 方案A：总是返回0
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
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
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
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
      );

      final cards = await service.getRecommendations();

      // 只返回前4个，按priority排序
      expect(cards.length, 4);
      expect(cards.every((c) => c.appKey != null), true); // 都是应用卡片

      // 验证按priority排序（wechat=1, wps=2, qq=3, dingtalk=4）
      final cardTypes = cards.map((c) => c.type).toList();
      expect(
          cardTypes,
          containsAll([
            RecommendationType.wechat,
            RecommendationType.wps,
            RecommendationType.qq,
            RecommendationType.dingtalk,
          ]));

      // 验证顺序正确
      expect(cardTypes[0], RecommendationType.wechat);
      expect(cardTypes[1], RecommendationType.wps);
      expect(cardTypes[2], RecommendationType.qq);
      expect(cardTypes[3], RecommendationType.dingtalk);
    });
  });

  group('RecommendationService 边界情况测试', () {
    test('应用已安装即显示（方案A：不检查文件数量边界）', () async {
      final detectionService = MockAppDetectionService(
        installedApps: {
          'com.tencent.mm': true,
        },
      );

      final scanner = MockUnifiedAppScanner(
        detectionService,
        fileCounts: {
          'wechat': 3, // 方案A：文件数不影响显示
        },
      );
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
      );

      final cards = await service.getRecommendations();

      // 方案A：应用已安装就会显示
      expect(cards.any((c) => c.type == RecommendationType.wechat), true);
    });

    test('应用已安装就显示（方案A：不检查文件数）', () async {
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
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
      );

      final cards = await service.getRecommendations();

      expect(cards[0].type, RecommendationType.wechat);
      expect(cards[0].fileCount, 0); // 方案A：不显示文件数
    });

    test('托底卡片文件数为0也应显示', () async {
      final detectionService = MockAppDetectionService();
      final scanner = MockUnifiedAppScanner(
        detectionService,
        fileCounts: {}, // 所有返回0
      );
      final service = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
      );

      final cards = await service.getRecommendations();

      expect(cards.length, 4);
      expect(cards[0].fileCount, 0);
      expect(cards[1].fileCount, 0);
      expect(cards[2].fileCount, 0);
      expect(cards[3].fileCount, 0);
    });
  });
}
