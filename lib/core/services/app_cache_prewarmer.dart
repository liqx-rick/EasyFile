import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/services/file_count_cache.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/core/utils/cancellation_token.dart';

/// 应用缓存预热器
///
/// 功能：
/// - 在应用启动或空闲时，后台静默扫描已安装的应用
/// - 提前准备缓存，避免用户首次进入时的延迟
/// - 支持增量扫描（只扫描缓存过期的应用）
///
/// 使用时机：
/// 1. 应用启动后 5-10 秒（等待首页加载完成）
/// 2. 应用从后台恢复时
/// 3. 用户在首页停留时（检测到无操作 3 秒后）
///
/// 使用示例：
/// ```dart
/// // 在 main.dart 或首页初始化时
/// final prewarmer = AppCachePrewarmer(
///   detectionService: detectionService,
///   scanner: unifiedScanner,
/// );
///
/// // 延迟启动预热（避免影响首页性能）
/// Future.delayed(Duration(seconds: 5), () {
///   prewarmer.prewarmAll();
/// });
/// ```
class AppCachePrewarmer {
  final AppDetectionService _detectionService;
  final UnifiedAppScanner _scanner;
  final FileCountCache? _fileCountCache;

  /// 是否正在预热
  bool _isPrewarming = false;

  /// 预热延迟时间（避免影响首页加载）
  static const Duration _prewarmDelay = Duration(seconds: 5);

  /// 单个应用超时时间（避免卡住）
  static const Duration _singleAppTimeout = Duration(seconds: 30);

  AppCachePrewarmer({
    required AppDetectionService detectionService,
    required UnifiedAppScanner scanner,
    FileCountCache? fileCountCache,
  })  : _detectionService = detectionService,
        _scanner = scanner,
        _fileCountCache = fileCountCache;

  /// 预热所有已安装应用的缓存
  ///
  /// [forceAll] 是否强制扫描所有应用（默认只扫描缓存过期的）
  /// [highPriorityOnly] 是否仅扫描高优先级应用（如微信、QQ等）
  Future<void> prewarmAll({
    bool forceAll = false,
    bool highPriorityOnly = true,
  }) async {
    if (_isPrewarming) {
      logger.w('AppCachePrewarmer - 预热已在进行中，跳过');
      return;
    }

    _isPrewarming = true;
    logger.i('========== 开始缓存预热 ==========');
    logger.i('模式: ${forceAll ? '强制全部' : '增量'}, '
        '优先级: ${highPriorityOnly ? '仅高优先级' : '全部'}');

    try {
      // 获取所有启用的应用配置
      final allConfigs = await AppConfig.instance.appScanner.getEnabledApps();

      // 过滤出需要预热的应用
      final targetConfigs = highPriorityOnly ? allConfigs.where((c) => c.priority >= 1).toList() : allConfigs;

      logger.i('目标应用: ${targetConfigs.length} 个');

      int scanned = 0;
      int skipped = 0;
      int failed = 0;

      for (final config in targetConfigs) {
        try {
          // 检查应用是否安装
          final detectionResult = await _detectionService.detectApp(config);
          if (!detectionResult.isInstalled) {
            logger.d('应用未安装，跳过: ${config.appName}');
            skipped++;
            continue;
          }

          // 检查缓存是否需要更新
          if (!forceAll) {
            final cachedCount = _fileCountCache != null ? await _fileCountCache!.getFileCount(config.appKey) : null;

            if (cachedCount != null) {
              logger.d('缓存有效，跳过: ${config.appName} ($cachedCount 文件)');
              skipped++;
              continue;
            }
          }

          // 执行扫描（带超时保护和取消机制）
          logger.i('预热扫描: ${config.appName} (${config.appKey})...');
          final stopwatch = Stopwatch()..start();
          final cancellationToken = CancellationToken();
          bool scanTimedOut = false;
          bool scanCancelled = false;

          try {
            await _scanner
                .scanApp(
              appKey: config.appKey,
              updateCache: true,
              useMediaStore: true,
              forceRefresh: forceAll,
              cancellationToken: cancellationToken,
            )
                .timeout(
              _singleAppTimeout,
              onTimeout: () {
                scanTimedOut = true;
                cancellationToken.cancel();
                throw TimeoutException('扫描超时: ${config.appName}');
              },
            );

            stopwatch.stop();
            
            // 仅在扫描成功且未超时的情况下计为成功
            if (!scanTimedOut && !scanCancelled) {
              scanned++;
              logger.i('✅ ${config.appName} 预热完成 (${stopwatch.elapsedMilliseconds}ms)');
            }
          } on TimeoutException catch (e) {
            stopwatch.stop();
            failed++;
            logger.e('预热失败: ${config.appName} - 超时 (${stopwatch.elapsedMilliseconds}ms)');
            logger.w('⚠️ 超时扫描已取消，未写入缓存');
          } on CancelledException catch (e) {
            stopwatch.stop();
            scanCancelled = true;
            failed++;
            logger.e('预热失败: ${config.appName} - 已取消 (${stopwatch.elapsedMilliseconds}ms)');
          } catch (e) {
            stopwatch.stop();
            failed++;
            logger.e('预热失败: ${config.appName} - $e');
          }
      }

      logger.i('========== 缓存预热完成 ==========');
      logger.i('已扫描: $scanned, 跳过: $skipped, 失败: $failed');
    } finally {
      _isPrewarming = false;
    }
  }

  /// 延迟启动预热（推荐用法）
  void prewarmWithDelay({
    Duration delay = _prewarmDelay,
    bool forceAll = false,
    bool highPriorityOnly = true,
  }) {
    logger.i('计划在 ${delay.inSeconds} 秒后开始预热');
    Future.delayed(delay, () {
      prewarmAll(
        forceAll: forceAll,
        highPriorityOnly: highPriorityOnly,
      );
    });
  }

  /// 预热单个应用
  Future<bool> prewarmSingleApp(String appKey) async {
    try {
      logger.i('预热单个应用: $appKey');
      await _scanner.scanApp(
        appKey: appKey,
        updateCache: true,
        useMediaStore: true,
        forceRefresh: false,
      );
      logger.i('✅ $appKey 预热完成');
      return true;
    } catch (e) {
      logger.e('预热失败: $appKey - $e');
      return false;
    }
  }

  /// 检查是否正在预热
  bool get isPrewarming => _isPrewarming;
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => message;
}
