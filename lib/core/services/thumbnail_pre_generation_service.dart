import 'dart:async';
import 'dart:ui';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/services/video_thumbnail_load_queue.dart';
import 'package:easyfile/utils/thumbnail_cache_manager.dart';

/// 缩略图预生成服务
///
/// 功能：在后台预生成视频缩略图，避免用户首次加载时的5秒延迟
///
/// 使用场景：
/// - 应用初始化完成后，后台预生成所有视频缩略图
/// - 新扫描到视频后，立即预生成缩略图
///
/// 特点：
/// - 复用现有的 VideoThumbnailLoadQueue（保持3个并发限制）
/// - 不阻塞UI线程
/// - 支持进度回调
/// - 自动跳过已缓存的视频
/// - 错误容忍：单个视频失败不影响其他视频
///
/// 使用示例：
/// ```dart
/// final service = ThumbnailPreGenerationService();
///
/// // 预生成所有视频缩略图
/// await service.preGenerateThumbnails(
///   videoFiles,
///   onProgress: (current, total) {
///     print('Progress: $current/$total');
///   },
/// );
/// ```
class ThumbnailPreGenerationService {
  final VideoThumbnailLoadQueue _loadQueue = VideoThumbnailLoadQueue();
  final ThumbnailCacheManager _cacheManager = ThumbnailCacheManager();

  bool _isGenerating = false;
  int _totalVideos = 0;
  int _completedVideos = 0;
  int _skippedVideos = 0;
  int _failedVideos = 0;

  /// 是否正在生成
  bool get isGenerating => _isGenerating;

  /// 当前进度（已完成数量）
  int get completedCount => _completedVideos;

  /// 总数量
  int get totalCount => _totalVideos;

  /// 预生成缩略图
  ///
  /// 参数：
  /// - videoFiles: 视频文件列表
  /// - onProgress: 进度回调 (current, total)
  /// - onComplete: 完成回调
  ///
  /// 返回值：统计信息
  /// ```dart
  /// {
  ///   'total': 总数,
  ///   'completed': 成功数,
  ///   'skipped': 跳过数（已缓存）,
  ///   'failed': 失败数
  /// }
  /// ```
  Future<Map<String, int>> preGenerateThumbnails(
    List<FileItem> videoFiles, {
    Function(int current, int total)? onProgress,
    VoidCallback? onComplete,
  }) async {
    if (_isGenerating) {
      logger.w('[ThumbnailPreGeneration] 已经在生成中，跳过此次请求');
      return {
        'total': 0,
        'completed': 0,
        'skipped': 0,
        'failed': 0,
      };
    }

    _isGenerating = true;
    _totalVideos = videoFiles.length;
    _completedVideos = 0;
    _skippedVideos = 0;
    _failedVideos = 0;

    logger.i('[ThumbnailPreGeneration] 开始预生成 $_totalVideos 个视频缩略图');

    try {
      for (var i = 0; i < videoFiles.length; i++) {
        final video = videoFiles[i];

        try {
          // 检查是否已缓存
          final cached = await _cacheManager.getCached(video.path);
          if (cached != null) {
            _skippedVideos++;
            logger.i('[ThumbnailPreGeneration] 跳过已缓存 (${i + 1}/$_totalVideos): ${video.name}');
          } else {
            // 通过队列生成缩略图（复用现有队列，自动排队）
            // size参数设为200.0（与实际显示尺寸一致）
            logger.i('[ThumbnailPreGeneration] 开始生成 (${i + 1}/$_totalVideos): ${video.name}');
            final result = await _loadQueue.loadThumbnail(video.path, 200.0);

            if (result != null) {
              _completedVideos++;
              logger.i('[ThumbnailPreGeneration] ✅ 成功生成 (${i + 1}/$_totalVideos): ${video.name}');
            } else {
              _failedVideos++;
              logger.w('[ThumbnailPreGeneration] ❌ 生成失败 (${i + 1}/$_totalVideos): ${video.name}');
            }
          }

          // ⚡ 同时预加载视频时长（避免滚动时卡顿）
          _loadQueue.loadDuration(video.path).catchError((e) {
            logger.d('[ThumbnailPreGeneration] 时长加载失败: ${video.name}');
          });

          // 回调进度
          onProgress?.call(_completedVideos + _skippedVideos + _failedVideos, _totalVideos);
        } catch (e) {
          _failedVideos++;
          logger.e('[ThumbnailPreGeneration] 生成异常 (${i + 1}/$_totalVideos): ${video.name}, error: $e');
          // 继续处理下一个视频（错误容忍）
        }
      }

      logger.i(
        '[ThumbnailPreGeneration] 预生成完成: '
        '总数=$_totalVideos, 成功=$_completedVideos, 跳过=$_skippedVideos, 失败=$_failedVideos',
      );

      // 完成回调
      onComplete?.call();
    } finally {
      _isGenerating = false;
    }

    return {
      'total': _totalVideos,
      'completed': _completedVideos,
      'skipped': _skippedVideos,
      'failed': _failedVideos,
    };
  }

  /// 预生成单个视频缩略图
  ///
  /// 用于新扫描到单个视频时的即时预生成
  Future<bool> preGenerateSingle(String videoPath) async {
    try {
      // 检查缓存
      final cached = await _cacheManager.getCached(videoPath);
      if (cached != null) {
        logger.d('[ThumbnailPreGeneration] 单个预生成跳过（已缓存）: $videoPath');
        return true;
      }

      // 生成
      final result = await _loadQueue.loadThumbnail(videoPath, 200.0);
      if (result != null) {
        logger.d('[ThumbnailPreGeneration] 单个预生成成功: $videoPath');
        return true;
      } else {
        logger.w('[ThumbnailPreGeneration] 单个预生成失败: $videoPath');
        return false;
      }
    } catch (e) {
      logger.e('[ThumbnailPreGeneration] 单个预生成异常: $videoPath, error: $e');
      return false;
    }
  }

  /// 取消预生成（预留，当前队列不支持取消）
  void cancel() {
    if (_isGenerating) {
      logger.w('[ThumbnailPreGeneration] 请求取消预生成（当前队列不支持取消，将在下个视频后停止）');
      _isGenerating = false;
    }
  }
}
