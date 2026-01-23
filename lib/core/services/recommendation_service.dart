import 'dart:typed_data';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/recommendation_card.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/core/config/app_config.dart';

///
/// 核心设计：
/// - 薄封装层：不重复实现检测逻辑，完全复用 AppDetectionService 和 UnifiedAppScanner
/// - 配置统一：应用类卡片配置来自 AppScannerConfigs，UI配置来自 RecommendationConfig
/// - 性能最优：完全依赖缓存机制，首页加载 <10ms
///
/// 架构：
/// ```
/// RecommendationService
///   ├── AppDetectionService (应用安装检测 + 持久化缓存)
///   ├── UnifiedAppScanner (文件数量查询 + 6小时缓存)
///   └── RecommendationConfig (UI配置：图标、颜色、标题)
/// ```
///
/// 性能：
/// - <10ms（全部命中缓存）
///
/// 使用示例：
/// ```dart
/// // 1. 初始化服务
/// final detectionService = AppDetectionService();
/// await detectionService.initialize();
///
/// final scanner = UnifiedAppScanner(detectionService);
///
/// // 2. 创建推荐服务
/// final recommendationService = RecommendationService(
///   detectionService: detectionService,
///   scanner: scanner,
/// );
///
/// // 3. 获取推荐卡片（超快，<10ms）
/// final cards = await recommendationService.getRecommendations();
/// ```
class RecommendationService {
  /// 推荐配置列表（UI配置）
  final List<RecommendationConfig> configs;

  /// 应用检测服务（必需）
  final AppDetectionService _detectionService;

  /// 统一扫描器（必需）
  final UnifiedAppScanner _scanner;

  RecommendationService({
    required AppDetectionService detectionService,
    required UnifiedAppScanner scanner,
    List<RecommendationConfig>? configs,
  })  : _detectionService = detectionService,
        _scanner = scanner,
        configs = configs ?? defaultRecommendationConfigs;

  /// 获取推荐卡片列表（已过滤+排序，最多4个）
  ///
  /// 流程：
  /// 1. 从 AppScannerConfig 获取按 priority 排序的启用应用
  /// 2. 遍历应用配置，检测安装 + 文件数量（全部使用缓存）
  /// 3. 从 defaultRecommendationConfigs 获取对应的 UI 配置
  /// 4. 不足4个时，补充系统类托底卡片
  /// 5. 返回最多4个符合条件的卡片
  ///
  /// [forceRefresh] 是否强制刷新（清除缓存后重新扫描）
  ///
  /// 性能：
  /// - 首次加载（无缓存）：~50ms（应用检测 4×10ms + 初始化）
  /// - 后续加载（有缓存）：<10ms（全部命中缓存）
  ///
  /// 注意：排序由 AppScannerConfig.priority 控制，不再依赖 configs 数组顺序
  Future<List<RecommendationCard>> getRecommendations(
      {bool forceRefresh = false}) async {
    final stopwatch = Stopwatch()..start();
    final displayCards = <RecommendationCard>[];

    // 从AppConfig加载文件数量阈值
    final threshold =
        AppConfig.instance.fileScan.recommendationFileCountThreshold;

    logger.i('========== 开始生成推荐卡片 ==========');
    logger.d('文件数量阈值: $threshold');
    logger.d('forceRefresh: $forceRefresh');

    // 1. 获取按 priority 排序的启用应用配置
    final enabledApps = await AppConfig.instance.appScanner.getEnabledApps();
    logger.d('启用应用数量: ${enabledApps.length}');

    // 2. 遍历应用配置（已按 priority 排序）
    for (final appConfig in enabledApps) {
      // 已达到4个，停止检测
      if (displayCards.length >= 4) {
        logger.d('已达到4个推荐卡片，停止检测');
        break;
      }

      // 3. 从 defaultRecommendationConfigs 获取对应的 UI 配置
      final uiConfig = defaultRecommendationConfigs
          .where((c) => c.appKey == appConfig.appKey)
          .firstOrNull;

      if (uiConfig == null) {
        logger.w(
            '未找到应用 ${appConfig.appKey} 的 UI 配置，跳过');
        continue;
      }

      logger.d(
          '检测应用: ${appConfig.appName} (priority: ${appConfig.priority})');

      // 4. 检测应用卡片
      final card = await _checkAppCard(uiConfig, threshold);
      if (card != null) {
        displayCards.add(card);
        logger.d('  ✓ 添加到推荐列表 (文件数: ${card.fileCount})');
      }
    }

    // 5. 不足4个，补充系统类托底卡片
    if (displayCards.length < 4) {
      logger.d('应用类卡片不足4个，补充系统类托底卡片');

      final systemConfigs =
          defaultRecommendationConfigs.where((c) => !c.isAppCard);

      for (final config in systemConfigs) {
        if (displayCards.length >= 4) break;

        logger.d('添加托底卡片: ${config.title}');
        final card = await _checkSystemCard(config, forceRefresh: forceRefresh);
        displayCards.add(card);
        logger.d('  ✓ 添加托底卡片 (文件数: ${card.fileCount})');
      }
    }

    stopwatch.stop();
    logger.i('========== 推荐卡片生成完成 ==========');
    logger.i(
        '结果: ${displayCards.length} 个卡片, 耗时: ${stopwatch.elapsedMilliseconds}ms');

    return displayCards;
  }

  /// 检测应用类卡片
  ///
  /// 流程：
  /// 1. 获取应用配置（从 AppScannerConfigs）
  /// 2. 检测应用是否安装（持久化缓存，<2ms）
  /// 3. 尝试使用统计数据缓存（包含文件数量、总大小、本周新增）
  /// 4. 如果缓存未命中，执行完整扫描并缓存结果
  ///
  /// 返回：符合条件的卡片，否则返回 null
  Future<RecommendationCard?> _checkAppCard(
      RecommendationConfig config, int threshold) async {
    final appKey = config.appKey;
    if (appKey == null) {
      logger.w('  应用Key为空，跳过');
      return null;
    }

    // 1. 获取应用配置
    final appConfig = await AppConfig.instance.appScanner.getAppConfig(appKey);
    if (appConfig == null) {
      logger.w('  未找到应用配置: $appKey');
      return null;
    }

    // 2. 检测应用是否安装（持久化缓存）
    final detectionResult = await _detectionService.detectApp(appConfig);
    if (!detectionResult.isInstalled) {
      logger.d('  应用未安装: ${appConfig.appName}');
      return null;
    }

    logger.d('  应用已安装: ${appConfig.appName}');

    // 3. 获取应用图标（无需统计数据，立即返回）
    Uint8List? appIcon;
    if (detectionResult.packageName != null) {
      appIcon =
          await _detectionService.getAppIcon(detectionResult.packageName!);
    }

    logger.d('  ✅ 应用检测完成，跳过统计扫描（方案A优化）');

    return RecommendationCard.fromConfig(
      config,
      fileCount: 0, // 不显示统计数据
      appIcon: appIcon,
    );
  }

  /// 检测系统类卡片（托底卡片）
  ///
  /// 系统类卡片不需要应用检测，直接返回
  /// 实现真实的文件统计和大小计算（使用缓存服务）
  ///
  /// [forceRefresh] 是否强制刷新（清除缓存后重新扫描）
  Future<RecommendationCard> _checkSystemCard(RecommendationConfig config,
      {bool forceRefresh = false}) async {
    logger.i('检查系统卡片: ${config.type} (跳过统计扫描，方案A优化)');

    // 直接返回占位卡片，不执行真实扫描
    return RecommendationCard.fromConfig(
      config,
      fileCount: 0, // 不显示统计数据
    );
  }

  /// 刷新推荐卡片（清除缓存并重新加载）
  ///
  /// 使用场景：
  /// - 用户下拉刷新
  /// - 应用安装/卸载后
  /// - 检测到数据不准确
  Future<List<RecommendationCard>> refreshRecommendations() async {
    logger.i('刷新推荐卡片（清除应用检测缓存）');

    // 清除应用文件数量缓存（方案A优化：仅清理实际使用的缓存）
    await _scanner.clearFileCountCache();

    // 重新生成推荐
    return await getRecommendations(forceRefresh: true);
  }

  /// 获取缓存统计信息（调试用）
  Map<String, dynamic> getCacheStats() {
    return {
      'detectionService': _detectionService.getCacheStats(),
      'configCount': configs.length,
    };
  }
}
