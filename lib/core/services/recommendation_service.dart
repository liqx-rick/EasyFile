import 'dart:typed_data';

import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/data/models/recommendation_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

///
/// 核心设计：
/// - 薄封装层：不重复实现检测逻辑，完全复用 AppDetectionService 和 UnifiedAppScanner
/// - 配置统一：应用类卡片配置来自 AppScannerConfigs，UI配置来自 RecommendationConfig
/// - 固定推荐：首次扫描后固定显示，不随阈值动态变化
/// - 性能最优：完全依赖缓存机制，首页加载 <10ms
///
/// 架构：
/// ```
/// RecommendationService
///   ├── AppDetectionService (应用安装检测 + 持久化缓存)
///   ├── UnifiedAppScanner (文件数量查询 + 24小时缓存)
///   ├── SharedPreferences (已选定应用列表持久化)
///   └── RecommendationConfig (UI配置：图标、颜色、标题)
/// ```
///
/// 推荐策略：
/// 1. 首次使用：扫描所有应用 → 应用阈值过滤 → 保存已选定列表
/// 2. 后续使用：读取已选定列表 → 检查应用是否仍安装 → 返回卡片
/// 3. 应用卸载：自动移除并补充备选卡片
/// 4. 重置推荐：清除已选定列表 → 重新扫描（仅开发者选项）
///
/// 性能：
/// - 首次扫描：~100ms（需要统计文件数量）
/// - 后续加载：<10ms（读取已选定列表）
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
  /// 持久化存储Key - 已选定的应用Key列表
  static const String _keySelectedAppKeys = 'recommendation_selected_app_keys';

  /// 持久化存储Key - 选择时间戳
  static const String _keySelectionTimestamp = 'recommendation_selection_timestamp';

  /// 持久化存储Key - 选择时使用的阈值
  static const String _keySelectionThreshold = 'recommendation_selection_threshold';

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

  /// 获取推荐卡片列表（固定推荐，最多4个）
  ///
  /// 新策略流程：
  /// 1. 检查是否有已选定列表
  ///    - 有：读取列表 → 检查应用是否仍安装 → 返回卡片
  ///    - 无：执行初始化扫描 → 应用阈值过滤 → 保存列表 → 返回卡片
  /// 2. 不足4个时，补充系统类托底卡片
  ///
  /// [forceRefresh] 是否强制刷新（仅供内部使用，外部调用请使用 resetRecommendations）
  ///
  /// 性能：
  /// - 首次扫描：~100ms（需要统计文件数量）
  /// - 后续加载：<10ms（读取已选定列表）
  Future<List<RecommendationCard>> getRecommendations({bool forceRefresh = false}) async {
    final stopwatch = Stopwatch()..start();
    logger.i('========== 开始生成推荐卡片 ==========');

    List<String>? selectedAppKeys;

    if (forceRefresh) {
      logger.i('🔄 强制刷新，执行初始化扫描');
      selectedAppKeys = await _performInitialScan();
    } else {
      // 尝试读取已选定列表
      selectedAppKeys = await _loadSelectedAppKeys();

      if (selectedAppKeys == null) {
        logger.i('📋 首次使用，执行初始化扫描');
        selectedAppKeys = await _performInitialScan();
      } else {
        logger.d('✅ 使用已选定列表: ${selectedAppKeys.join(", ")}');
      }
    }

    // 根据已选定列表生成卡片
    final displayCards = await _generateCardsFromSelection(selectedAppKeys);

    stopwatch.stop();
    logger.i('========== 推荐卡片生成完成 ==========');
    logger.i('结果: ${displayCards.length} 个卡片, 耗时: ${stopwatch.elapsedMilliseconds}ms');

    return displayCards;
  }

  /// 执行初始化扫描（首次使用或重置后）
  ///
  /// 流程：
  /// 1. 获取所有启用的应用配置（按priority排序）
  /// 2. 遍历检测：应用是否安装
  /// 3. 对已安装的应用执行扫描并写入缓存
  /// 4. 保存符合条件的应用Key列表
  /// 5. 返回已选定的应用Key列表
  Future<List<String>> _performInitialScan() async {
    final threshold = AppConfig.instance.fileScan.recommendationFileCountThreshold;
    logger.i('🔍 初始化扫描，阈值: $threshold');

    final selectedAppKeys = <String>[];
    final enabledApps = await AppConfig.instance.appScanner.getEnabledApps();

    for (final appConfig in enabledApps) {
      if (selectedAppKeys.length >= 4) {
        logger.d('已找到4个符合条件的应用，停止扫描');
        break;
      }

      logger.d('扫描应用: ${appConfig.appName}');

      // 清除缓存以确保获取最新的安装状态（特别是重新安装的应用）
      if (appConfig.packageNames.isNotEmpty) {
        for (final pkg in appConfig.packageNames) {
          await _detectionService.clearPackageCache(pkg);
        }
      }

      // 检测应用是否安装
      final detectionResult = await _detectionService.detectApp(appConfig);
      if (!detectionResult.isInstalled) {
        logger.d('  应用未安装，跳过');
        continue;
      }

      // 应用已安装，扫描文件数量
      logger.d('  已安装，扫描文件数量...');
      final scanResult = await _scanner.scanApp(
        appKey: appConfig.appKey,
        withIcon: false, // 不获取图标，提升速度
        updateCache: true, // 写入缓存
      );

      // 判断是否达到阈值
      if (scanResult.totalCount >= threshold) {
        selectedAppKeys.add(appConfig.appKey);
        logger.d('  ✅ 文件数量 ${scanResult.totalCount} >= $threshold，添加到列表');
      } else {
        logger.d('  文件数量 ${scanResult.totalCount} < $threshold，不符合条件');
      }
    }

    // 保存已选定列表
    await _saveSelectedAppKeys(selectedAppKeys, threshold);

    logger.i('初始化扫描完成，已选定 ${selectedAppKeys.length} 个应用');
    return selectedAppKeys;
  }

  /// 根据已选定列表生成卡片
  ///
  /// 流程：
  /// 1. 遍历已选定的应用Key
  /// 2. 检查应用是否仍然安装（可能被卸载）
  /// 3. 生成推荐卡片
  /// 4. 不足4个时，补充系统类托底卡片
  Future<List<RecommendationCard>> _generateCardsFromSelection(List<String> selectedAppKeys) async {
    final displayCards = <RecommendationCard>[];
    final stillInstalledKeys = <String>[];

    // 检查每个已选定的应用是否仍然安装
    for (final appKey in selectedAppKeys) {
      if (displayCards.length >= 4) break;

      // 获取应用配置
      final appConfig = await AppConfig.instance.appScanner.getAppConfig(appKey);
      if (appConfig == null) {
        logger.w('未找到应用配置: $appKey');
        continue;
      }

      // 清除缓存以确保获取最新的安装状态
      if (appConfig.packageNames.isNotEmpty) {
        for (final pkg in appConfig.packageNames) {
          await _detectionService.clearPackageCache(pkg);
        }
      }

      // 检测应用是否仍然安装（使用最新状态）
      final detectionResult = await _detectionService.detectApp(appConfig);
      if (!detectionResult.isInstalled) {
        logger.i('✗ 应用 ${appConfig.appName} 已卸载，从推荐列表移除');
        continue;
      }

      stillInstalledKeys.add(appKey);

      // 获取UI配置
      final uiConfig = defaultRecommendationConfigs.where((c) => c.appKey == appKey).firstOrNull;

      if (uiConfig == null) {
        logger.w('未找到应用 $appKey 的 UI 配置');
        continue;
      }

      // 获取应用图标
      Uint8List? appIcon;
      if (detectionResult.packageName != null) {
        appIcon = await _detectionService.getAppIcon(detectionResult.packageName!);
      }

      // 从持久化缓存获取文件数量（如果可用）
      int fileCount = 0;
      final cachedCount = await _scanner.getFileCountFast(appKey: appKey);
      if (cachedCount != null && cachedCount > 0) {
        fileCount = cachedCount;
        logger.d('  使用持久化缓存文件数: $fileCount');
      } else {
        logger.d('  持久化缓存未命中，文件数显示为0');
      }

      // 生成卡片
      final card = RecommendationCard.fromConfig(
        uiConfig,
        fileCount: fileCount, // 使用持久化缓存的文件数量
        appIcon: appIcon,
      );

      displayCards.add(card);
      logger.d('✅ 添加应用卡片: ${appConfig.appName}');
    }

    // 如果已选定列表发生变化（应用被卸载），更新持久化存储
    if (stillInstalledKeys.length != selectedAppKeys.length) {
      logger.i('检测到应用卸载，更新已选定列表');
      final threshold = await _loadSelectionThreshold() ?? AppConfig.instance.fileScan.recommendationFileCountThreshold;
      await _saveSelectedAppKeys(stillInstalledKeys, threshold);
    }

    // 不足4个，补充系统类托底卡片
    if (displayCards.length < 4) {
      logger.d('应用类卡片不足4个，补充系统类托底卡片');

      final systemConfigs = defaultRecommendationConfigs.where((c) => !c.isAppCard);

      for (final config in systemConfigs) {
        if (displayCards.length >= 4) break;

        logger.d('添加托底卡片: ${config.title}');
        final card = await _checkSystemCard(config, forceRefresh: false);
        displayCards.add(card);
      }
    }

    return displayCards;
  }

  /// 读取已选定的应用Key列表
  Future<List<String>?> _loadSelectedAppKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getStringList(_keySelectedAppKeys);
      return keys;
    } catch (e) {
      logger.e('读取已选定列表失败: $e');
      return null;
    }
  }

  /// 保存已选定的应用Key列表
  Future<void> _saveSelectedAppKeys(List<String> appKeys, int threshold) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keySelectedAppKeys, appKeys);
      await prefs.setInt(_keySelectionTimestamp, DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt(_keySelectionThreshold, threshold);
      logger.d('已保存选定列表: ${appKeys.join(", ")}, 阈值: $threshold');
    } catch (e) {
      logger.e('保存已选定列表失败: $e');
    }
  }

  /// 读取选择时使用的阈值
  Future<int?> _loadSelectionThreshold() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keySelectionThreshold);
    } catch (e) {
      logger.e('读取选择阈值失败: $e');
      return null;
    }
  }

  /// 获取推荐选择信息（用于设置页面显示）
  Future<Map<String, dynamic>> getSelectionInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedKeys = prefs.getStringList(_keySelectedAppKeys);
    final timestamp = prefs.getInt(_keySelectionTimestamp);
    final threshold = prefs.getInt(_keySelectionThreshold);

    return {
      'hasSelection': selectedKeys != null && selectedKeys.isNotEmpty,
      'selectedCount': selectedKeys?.length ?? 0,
      'selectionTime': timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null,
      'selectionThreshold': threshold,
      'selectedAppKeys': selectedKeys,
    };
  }

  /// 检测系统类卡片（托底卡片）
  ///
  /// 系统类卡片不需要应用检测，直接返回
  Future<RecommendationCard> _checkSystemCard(RecommendationConfig config, {bool forceRefresh = false}) async {
    logger.d('生成系统托底卡片: ${config.type}');

    // 直接返回占位卡片，不显示统计数据
    return RecommendationCard.fromConfig(
      config,
      fileCount: 0, // 不显示统计数据
    );
  }

  /// 重置推荐（清除已选定列表，重新扫描）
  ///
  /// 使用场景：
  /// - 用户在开发者选项中调整阈值后，需要重新选择应用
  /// - 用户想重新初始化推荐列表
  ///
  /// 流程：
  /// 1. 清除已选定列表
  /// 2. 清除文件数量缓存
  /// 3. 重新执行初始化扫描
  Future<List<RecommendationCard>> resetRecommendations() async {
    logger.i('🔄 重置推荐（清除已选定列表）');

    try {
      // 清除已选定列表
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keySelectedAppKeys);
      await prefs.remove(_keySelectionTimestamp);
      await prefs.remove(_keySelectionThreshold);
      logger.d('已清除已选定列表');

      // 清除文件数量缓存
      await _scanner.clearFileCountCache();
      logger.d('已清除文件数量缓存');

      // 清除内存扫描结果缓存（静态缓存，保存了无权限时的 0 文件结果）
      _scanner.clearMemoryCache();
      logger.d('已清除内存扫描缓存');

      // 清除应用安装状态缓存
      await _detectionService.clearCache();
      logger.d('已清除应用安装状态缓存');

      // 重新执行初始化扫描
      return await getRecommendations(forceRefresh: true);
    } catch (e) {
      logger.e('重置推荐失败: $e');
      rethrow;
    }
  }

  /// 获取缓存统计信息（调试用）
  Map<String, dynamic> getCacheStats() {
    return {
      'detectionService': _detectionService.getCacheStats(),
      'configCount': configs.length,
    };
  }
}
