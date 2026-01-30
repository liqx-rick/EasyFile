import 'dart:async';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/services/video_thumbnail_load_queue.dart';

/// 视频缩略图预热服务
///
/// 功能：
/// - 后台提前生成视频缩略图并缓存到磁盘
/// - 减少用户滑动列表时的 loading 状态
/// - 优先预热前 N 个视频（通常是用户最先看到的）
///
/// 使用场景：
/// - 视频分类页面加载完成后
/// - 应用推荐页面（微信/QQ等）视频加载后
/// - 文件夹页面视频列表加载后
///
/// 使用示例：
/// ```dart
/// // 在视频列表加载完成后
/// final prewarmer = VideoThumbnailPrewarmer();
/// prewarmer.prewarmThumbnails(videoFiles);
/// ```
class VideoThumbnailPrewarmer {
  /// 默认预热视频数量（前100个）
  static const int defaultMaxVideos = 100;

  /// 每批处理数量（避免 MediaCodec 资源耗尽）
  static const int defaultBatchSize = 5;

  /// 批次间延迟（确保不影响 UI 响应）
  static const Duration defaultBatchDelay = Duration(milliseconds: 300);

  /// 是否正在预热
  bool _isPrewarming = false;

  /// 取消令牌
  bool _cancelled = false;

  /// 预热进度流
  final StreamController<PrewarmProgress> _progressController = StreamController<PrewarmProgress>.broadcast();

  /// 预热进度流
  Stream<PrewarmProgress> get progressStream => _progressController.stream;

  /// 是否正在预热
  bool get isPrewarming => _isPrewarming;

  /// 预热视频缩略图
  ///
  /// [videos] 视频文件列表
  /// [maxVideos] 最多预热多少个视频（默认100）
  /// [batchSize] 每批处理数量（默认5）
  /// [batchDelay] 批次间延迟（默认300ms）
  Future<void> prewarmThumbnails(
    List<FileItem> videos, {
    int maxVideos = defaultMaxVideos,
    int batchSize = defaultBatchSize,
    Duration batchDelay = defaultBatchDelay,
  }) async {
    if (_isPrewarming) {
      logger.w('VideoThumbnailPrewarmer - 预热已在进行中，跳过');
      return;
    }

    if (videos.isEmpty) {
      logger.i('VideoThumbnailPrewarmer - 无视频需要预热');
      return;
    }

    _isPrewarming = true;
    _cancelled = false;

    try {
      final videosToProcess = videos.take(maxVideos).toList();
      logger.i('🔥 VideoThumbnailPrewarmer - 开始预热 ${videosToProcess.length} 个视频缩略图');

      int processed = 0;
      int succeeded = 0;
      int failed = 0;

      for (int i = 0; i < videosToProcess.length; i += batchSize) {
        // 检查是否取消
        if (_cancelled) {
          logger.i('VideoThumbnailPrewarmer - 预热已取消');
          break;
        }

        final batch = videosToProcess.skip(i).take(batchSize).toList();

        // 延迟，确保不影响 UI 响应
        await Future.delayed(batchDelay);

        // 并行处理这一批
        final results = await Future.wait(
          batch.map((file) async {
            try {
              logger.d('🔥 预热视频: ${file.path}');
              final queue = VideoThumbnailLoadQueue();
              // 使用96.0匹配实际显示的最大尺寸（普通模式）
              // 生成分辨率: 96*4=384px，足以覆盖各种屏幕尺寸
              final thumbnail = await queue.loadThumbnail(file.path, 96.0);
              if (thumbnail != null) {
                logger.d('✅ 预热成功: ${file.name} (${thumbnail.length} bytes)');
                return true;
              } else {
                logger.w('❌ 预热失败（null）: ${file.name}');
                return false;
              }
            } catch (e) {
              logger.e('❌ 预热异常: ${file.path} - $e');
              return false;
            }
          }),
        );

        // 统计结果
        for (final success in results) {
          processed++;
          if (success) {
            succeeded++;
          } else {
            failed++;
          }
        }

        // 发送进度更新
        _progressController.add(PrewarmProgress(
          processed: processed,
          total: videosToProcess.length,
          succeeded: succeeded,
          failed: failed,
        ));

        if (processed % 20 == 0) {
          logger.i('🔥 预热进度: $processed/${videosToProcess.length} (成功: $succeeded, 失败: $failed)');
        }
      }

      logger.i('🔥 VideoThumbnailPrewarmer - 预热完成');
      logger.i('   总计: $processed 个');
      logger.i('   成功: $succeeded 个');
      logger.i('   失败: $failed 个');
    } finally {
      _isPrewarming = false;
    }
  }

  /// 预热单个视频
  Future<bool> prewarmSingleVideo(String videoPath) async {
    try {
      final queue = VideoThumbnailLoadQueue();
      final thumbnail = await queue.loadThumbnail(videoPath, 80.0);
      return thumbnail != null;
    } catch (e) {
      logger.e('预热单个视频失败: $videoPath - $e');
      return false;
    }
  }

  /// 取消预热
  void cancel() {
    logger.i('VideoThumbnailPrewarmer - 取消预热');
    _cancelled = true;
  }

  /// 释放资源
  void dispose() {
    _progressController.close();
  }
}

/// 预热进度
class PrewarmProgress {
  /// 已处理数量
  final int processed;

  /// 总数量
  final int total;

  /// 成功数量
  final int succeeded;

  /// 失败数量
  final int failed;

  PrewarmProgress({
    required this.processed,
    required this.total,
    required this.succeeded,
    required this.failed,
  });

  /// 进度百分比（0.0 - 1.0）
  double get progress => total > 0 ? processed / total : 0.0;

  /// 进度百分比（0 - 100）
  int get progressPercent => (progress * 100).round();

  /// 是否完成
  bool get isCompleted => processed >= total;

  @override
  String toString() {
    return '预热进度: $processed/$total ($progressPercent%) - 成功: $succeeded, 失败: $failed';
  }
}
