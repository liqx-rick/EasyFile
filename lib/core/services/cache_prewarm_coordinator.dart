import 'dart:async';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/platform/mediastore_scanner_channel.dart';
import 'package:easyfile/core/services/app_cache_prewarmer.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/services/file_count_cache.dart';
import 'package:easyfile/core/services/mediastore_cache_service.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/core/services/video_thumbnail_prewarmer.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/utils/thumbnail_cache_manager.dart';

/// 缓存预热协调器
///
/// 统一管理应用启动时的多个缓存预热任务：
/// 1. 缩略图缓存初始化
/// 2. MediaStore 缓存预热
/// 3. 应用文件缓存预热
/// 4. 视频缩略图预热（可选）
///
/// 设计理念：
/// - 优先级队列：关键任务优先执行
/// - 并发控制：避免同时运行过多耗时任务
/// - 资源限制：监控内存和CPU使用
/// - 进度监控：实时反馈预热进度
/// - 错误隔离：单个任务失败不影响其他任务
///
/// 执行策略：
/// - 阶段1（启动时）：关键缓存同步初始化（缩略图目录）
/// - 阶段2（延迟3秒）：高优先级预热（MediaStore）
/// - 阶段3（延迟5秒）：低优先级预热（应用文件）
/// - 阶段4（延迟8秒）：按需预热（视频缩略图，可选）
///
/// 使用示例：
/// ```dart
/// // 在 main.dart 中
/// await CachePrewarmCoordinator.instance.initialize();
/// CachePrewarmCoordinator.instance.startPrewarming();
///
/// // 可选：为视频分类页面预热缩略图
/// CachePrewarmCoordinator.instance.prewarmVideoThumbnails(videoFiles);
/// ```
class CachePrewarmCoordinator {
  static final CachePrewarmCoordinator _instance = CachePrewarmCoordinator._internal();
  static CachePrewarmCoordinator get instance => _instance;
  CachePrewarmCoordinator._internal();

  /// 初始化状态
  bool _initialized = false;

  /// 预热进度流（当前任务名称 + 进度百分比）
  final StreamController<PrewarmProgress> _progressController = StreamController<PrewarmProgress>.broadcast();

  /// 预热状态
  PrewarmStatus _status = PrewarmStatus.idle;

  /// 取消令牌
  final Set<String> _cancelledTasks = {};

  // ========================================
  // 服务实例
  // ========================================

  ThumbnailCacheManager? _thumbnailCache;
  MediaStoreCacheService? _mediaStoreCache;
  AppCachePrewarmer? _appCachePrewarmer;
  VideoThumbnailPrewarmer? _videoThumbnailPrewarmer;

  // ========================================
  // 公共接口
  // ========================================

  /// 预热进度流
  Stream<PrewarmProgress> get progressStream => _progressController.stream;

  /// 当前状态
  PrewarmStatus get status => _status;

  /// 是否正在预热
  bool get isPrewarming => _status == PrewarmStatus.prewarming;

  /// 初始化协调器
  Future<void> initialize() async {
    if (_initialized) return;

    logger.i('========== 初始化缓存预热协调器 ==========');

    // 初始化缩略图缓存（同步执行，阻塞启动）
    await _initThumbnailCache();

    _initialized = true;
    logger.i('✓ 缓存预热协调器初始化完成');
  }

  /// 启动预热任务（异步执行，不阻塞UI）
  void startPrewarming() {
    if (!_initialized) {
      logger.w('协调器未初始化，跳过预热');
      return;
    }

    if (_status == PrewarmStatus.prewarming) {
      logger.w('预热任务已在执行中，跳过');
      return;
    }

    _status = PrewarmStatus.prewarming;
    logger.i('========== 启动缓存预热 ==========');

    // 异步执行预热流程
    _executePrewarmPipeline();
  }

  /// 取消预热
  void cancelPrewarming() {
    logger.i('取消所有预热任务');
    _status = PrewarmStatus.cancelled;
    _cancelledTasks.addAll(['mediastore', 'appfiles']);
  }

  /// 取消特定任务
  void cancelTask(String taskName) {
    logger.i('取消预热任务: $taskName');
    _cancelledTasks.add(taskName);
  }

  /// 预热视频缩略图（按需调用）
  ///
  /// [videos] 视频文件列表
  /// [maxVideos] 最多预热多少个视频（默认100）
  ///
  /// 使用场景：
  /// - 视频分类页面加载完成后
  /// - 应用推荐页面（微信/QQ等）视频加载后
  Future<void> prewarmVideoThumbnails(
    List<FileItem> videos, {
    int maxVideos = 100,
  }) async {
    try {
      logger.i('========== 开始预热视频缩略图 ==========');

      _videoThumbnailPrewarmer ??= VideoThumbnailPrewarmer();

      await _videoThumbnailPrewarmer!.prewarmThumbnails(
        videos,
        maxVideos: maxVideos,
      );

      logger.i('========== 视频缩略图预热完成 ==========');
    } catch (e) {
      logger.e('视频缩略图预热失败: $e');
    }
  }

  // ========================================
  // 内部实现
  // ========================================

  /// 初始化缩略图缓存（同步执行）
  Future<void> _initThumbnailCache() async {
    logger.i('【阶段1】初始化缩略图缓存...');
    _emitProgress('缩略图缓存', 0.0);

    try {
      _thumbnailCache = ThumbnailCacheManager();
      await _thumbnailCache!.init();
      final diagnosis = await _thumbnailCache!.diagnoseCache();

      if (diagnosis['initialized'] == false || diagnosis['cacheDirNull'] == true) {
        final success = await _thumbnailCache!.forceReinitialize();
        if (!success) {
          logger.w('✗ 缩略图缓存初始化失败');
          _emitProgress('缩略图缓存', 1.0, error: '初始化失败');
          return;
        }
      }

      logger.i('✓ 缩略图缓存初始化完成');
      _emitProgress('缩略图缓存', 1.0);
    } catch (e) {
      logger.e('✗ 缩略图缓存初始化异常: $e');
      _emitProgress('缩略图缓存', 1.0, error: e.toString());
    }
  }

  /// 执行预热流程
  Future<void> _executePrewarmPipeline() async {
    try {
      // 阶段2：延迟3秒后预热 MediaStore（高优先级）
      await Future.delayed(Duration(seconds: 3));
      if (_status == PrewarmStatus.cancelled) return;

      await _prewarmMediaStore();

      // 阶段3：延迟5秒后预热应用文件（低优先级）
      await Future.delayed(Duration(seconds: 2));
      if (_status == PrewarmStatus.cancelled) return;

      await _prewarmAppFiles();

      // 阶段4：延迟3秒后预热视频缩略图（可选，后台执行）
      await Future.delayed(Duration(seconds: 3));
      if (_status == PrewarmStatus.cancelled) return;

      await _prewarmVideoThumbnailsInternal();

      // 所有任务完成
      _status = PrewarmStatus.completed;
      logger.i('========== 缓存预热全部完成 ==========');
      _emitProgress('全部任务', 1.0);
    } catch (e) {
      _status = PrewarmStatus.failed;
      logger.e('缓存预热失败: $e');
      _emitProgress('预热流程', 1.0, error: e.toString());
    }
  }

  /// 预热 MediaStore 缓存
  Future<void> _prewarmMediaStore() async {
    if (_cancelledTasks.contains('mediastore')) {
      logger.i('MediaStore 预热已取消');
      return;
    }

    logger.i('【阶段2】预热 MediaStore 缓存...');
    _emitProgress('MediaStore', 0.0);

    try {
      _mediaStoreCache = MediaStoreCacheService();
      await _mediaStoreCache!.initialize();
      logger.i('✓ MediaStore 缓存服务初始化完成');

      _emitProgress('MediaStore', 0.5);

      // 执行预热
      await _mediaStoreCache!.warmUp();
      logger.i('✓ MediaStore 缓存预热完成');
      _emitProgress('MediaStore', 1.0);
    } catch (e) {
      logger.e('✗ MediaStore 缓存预热失败: $e');
      _emitProgress('MediaStore', 1.0, error: e.toString());
    }
  }

  /// 预热应用文件缓存
  Future<void> _prewarmAppFiles() async {
    if (_cancelledTasks.contains('appfiles')) {
      logger.i('应用文件预热已取消');
      return;
    }

    logger.i('【阶段3】预热应用文件缓存...');
    _emitProgress('应用文件', 0.0);

    try {
      // 初始化服务
      final detectionService = AppDetectionService();
      await detectionService.initialize();
      _emitProgress('应用文件', 0.2);

      final fileCountCache = FileCountCache();
      await fileCountCache.initialize();
      _emitProgress('应用文件', 0.3);

      final scanner = UnifiedAppScanner(
        detectionService,
        fileCountCache: fileCountCache,
      );
      _emitProgress('应用文件', 0.4);

      // 创建预热器
      _appCachePrewarmer = AppCachePrewarmer(
        detectionService: detectionService,
        scanner: scanner,
        fileCountCache: fileCountCache,
      );

      // 开始预热（仅高优先级应用）
      await _appCachePrewarmer!.prewarmAll(
        forceAll: false,
        highPriorityOnly: true,
      );

      logger.i('✓ 应用文件缓存预热完成');
      _emitProgress('应用文件', 1.0);
    } catch (e) {
      logger.e('✗ 应用文件缓存预热失败: $e');
      _emitProgress('应用文件', 1.0, error: e.toString());
    }
  }

  /// 预热视频缩略图（内部方法，启动时调用）
  Future<void> _prewarmVideoThumbnailsInternal() async {
    if (_cancelledTasks.contains('videothumbnails')) {
      logger.i('视频缩略图预热已取消');
      return;
    }

    logger.i('【阶段4】预热视频缩略图...');
    _emitProgress('视频缩略图', 0.0);

    try {
      // 从 MediaStore 获取所有视频（快速）
      final videos = await MediaStoreScannerChannel.scanVideos();

      if (videos.isEmpty) {
        logger.i('未找到视频文件，跳过预热');
        _emitProgress('视频缩略图', 1.0);
        return;
      }

      logger.i('找到 ${videos.length} 个视频，开始预热前 50 个');
      _emitProgress('视频缩略图', 0.2);

      // 预热前150个视频（常用的）
      _videoThumbnailPrewarmer ??= VideoThumbnailPrewarmer();
      await _videoThumbnailPrewarmer!.prewarmThumbnails(
        videos,
        maxVideos: 150, // 启动时只预热150个，避免耗时过长
        batchSize: 3, // 每批3个，减少资源占用
        batchDelay: Duration(milliseconds: 500), // 更长延迟，避免影响应用
      );

      logger.i('✓ 视频缩略图预热完成');
      _emitProgress('视频缩略图', 1.0);
    } catch (e) {
      logger.e('✗ 视频缩略图预热失败: $e');
      _emitProgress('视频缩略图', 1.0, error: e.toString());
    }
  }

  /// 发送进度更新
  void _emitProgress(String taskName, double progress, {String? error}) {
    _progressController.add(PrewarmProgress(
      taskName: taskName,
      progress: progress,
      error: error,
    ));
  }

  /// 释放资源
  void dispose() {
    _progressController.close();
  }
}

/// 预热进度
class PrewarmProgress {
  /// 任务名称
  final String taskName;

  /// 进度（0.0 - 1.0）
  final double progress;

  /// 错误信息（如果有）
  final String? error;

  PrewarmProgress({
    required this.taskName,
    required this.progress,
    this.error,
  });

  /// 是否完成
  bool get isCompleted => progress >= 1.0;

  /// 是否失败
  bool get isFailed => error != null;

  /// 进度百分比
  int get progressPercent => (progress * 100).round();

  @override
  String toString() {
    if (isFailed) {
      return '[$taskName] 失败: $error';
    }
    return '[$taskName] $progressPercent%';
  }
}

/// 预热状态
enum PrewarmStatus {
  /// 空闲（未开始）
  idle,

  /// 预热中
  prewarming,

  /// 已完成
  completed,

  /// 已取消
  cancelled,

  /// 失败
  failed,
}
