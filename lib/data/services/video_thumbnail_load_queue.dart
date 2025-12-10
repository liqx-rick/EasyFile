import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/utils/thumbnail_cache_manager.dart';

/// 视频缩略图加载队列服务
///
/// 限制同时加载的视频缩略图数量，避免创建过多MediaCodec实例
/// 解决Android系统MediaCodec资源池耗尽导致的崩溃问题
///
/// 工作原理：
/// 1. 所有缩略图加载请求进入队列
/// 2. 同时最多只有N个（默认3个）请求在处理
/// 3. 其他请求等待，直到有空闲槽位
/// 4. 优先从磁盘缓存加载，只有缓存未命中时才解码视频
class VideoThumbnailLoadQueue {
  static final VideoThumbnailLoadQueue _instance =
      VideoThumbnailLoadQueue._internal();
  factory VideoThumbnailLoadQueue() => _instance;
  VideoThumbnailLoadQueue._internal();

  // 最大并发加载数量（关键参数：防止MediaCodec资源耗尽）
  static const int _maxConcurrent = 3;

  // 当前正在处理的加载数量
  int _activeLoads = 0;

  // 等待队列（混合类型：缩略图和时长请求）
  final Queue<dynamic> _queue = Queue();

  // 是否暂停队列处理（进入视频播放器时暂停）
  bool _isPaused = false;

  // 缓存管理器
  final _cacheManager = ThumbnailCacheManager();

  /// 加载视频缩略图（带队列控制）
  ///
  /// [videoPath] 视频文件路径
  /// [size] 缩略图显示大小（用于优化生成尺寸）
  /// Returns: 缩略图数据，失败返回null
  Future<Uint8List?> loadThumbnail(String videoPath, double size) async {
    final completer = Completer<Uint8List?>();

    // 创建加载请求
    final request = _LoadRequest(
      videoPath: videoPath,
      size: size,
      completer: completer,
    );

    // 加入队列
    _queue.add(request);
    logger.d(
        'Thumbnail load request queued: $videoPath (queue size: ${_queue.length})');

    // 尝试处理队列
    _processQueue();

    return completer.future;
  }

  /// 加载视频时长（带队列控制和缓存）
  ///
  /// [videoPath] 视频文件路径
  /// Returns: 格式化的时长字符串，失败返回null
  Future<String?> loadDuration(String videoPath) async {
    try {
      // 1. 优先从SharedPreferences缓存加载
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'video_duration_$videoPath';
      final cachedDuration = prefs.getString(cacheKey);

      if (cachedDuration != null) {
        logger.d('Loaded duration from cache: $videoPath');
        return cachedDuration;
      }

      // 2. 缓存未命中，使用队列读取
      final completer = Completer<String?>();

      final request = _DurationRequest(
        videoPath: videoPath,
        completer: completer,
      );

      _queue.add(request);
      logger.d(
          'Duration load request queued: $videoPath (queue size: ${_queue.length})');

      _processQueue();

      return completer.future;
    } catch (e) {
      logger.e('Error loading video duration: $e');
      return null;
    }
  }

  /// 处理队列中的请求
  void _processQueue() {
    // 如果暂停，不处理
    if (_isPaused) {
      logger.d('Queue is paused, skipping processing');
      return;
    }

    // 如果已达到最大并发数，不处理
    if (_activeLoads >= _maxConcurrent) {
      logger.d('Max concurrent loads reached ($_activeLoads/$_maxConcurrent)');
      return;
    }

    // 如果队列为空，不处理
    if (_queue.isEmpty) {
      return;
    }

    // 取出一个请求
    final request = _queue.removeFirst();
    _activeLoads++;

    logger.d(
        'Processing request (active: $_activeLoads/$_maxConcurrent, queued: ${_queue.length})');

    // 异步处理请求
    _handleRequest(request).then((_) {
      _activeLoads--;
      logger.d(
          'Request completed (active: $_activeLoads/$_maxConcurrent, queued: ${_queue.length})');

      // 处理下一个请求
      _processQueue();
    }).catchError((error) {
      _activeLoads--;
      logger.e('Request error: $error');

      // 即使出错也继续处理队列
      _processQueue();
    });
  }

  /// 处理单个加载请求
  Future<void> _handleRequest(dynamic request) async {
    if (request is _LoadRequest) {
      await _handleThumbnailRequest(request);
    } else if (request is _DurationRequest) {
      await _handleDurationRequest(request);
    }
  }

  /// 处理缩略图加载请求
  Future<void> _handleThumbnailRequest(_LoadRequest request) async {
    try {
      // 1. 优先从缓存加载
      final cachedData = await _cacheManager.getCached(request.videoPath);
      if (cachedData != null) {
        logger.d('Loaded from cache: ${request.videoPath}');
        request.completer.complete(cachedData);
        return;
      }

      // 2. 验证视频文件是否存在且可读
      final videoFile = File(request.videoPath);
      if (!await videoFile.exists()) {
        logger.w('Video file does not exist: ${request.videoPath}');
        request.completer.complete(null);
        return;
      }

      final fileSize = await videoFile.length();
      if (fileSize == 0) {
        logger.w('Video file is empty (0 bytes): ${request.videoPath}');
        request.completer.complete(null);
        return;
      }

      // 3. 缓存未命中，生成新缩略图
      logger.d('Generating thumbnail: ${request.videoPath} (file size: $fileSize bytes)');

      final thumbnailData = await VideoThumbnail.thumbnailData(
        video: request.videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: request.size > 64 ? 256 : 128,
        quality: 75,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          logger.w('Thumbnail generation timeout: ${request.videoPath}');
          return null;
        },
      );

      if (thumbnailData != null && thumbnailData.isNotEmpty) {
        // 4. 验证生成的缩略图数据
        if (thumbnailData.length < 100) {
          logger.w('Generated thumbnail too small (${thumbnailData.length} bytes), possibly corrupted: ${request.videoPath}');
          request.completer.complete(null);
          return;
        }

        // 5. 保存到缓存（只在数据有效时保存）
        final saved = await _cacheManager.saveCache(request.videoPath, thumbnailData);
        if (saved) {
          logger.d('Thumbnail generated and cached: ${request.videoPath} (${thumbnailData.length} bytes)');
        } else {
          logger.w('Thumbnail generated but failed to cache: ${request.videoPath}');
        }
        request.completer.complete(thumbnailData);
      } else {
        logger.w('Failed to generate thumbnail or empty data: ${request.videoPath}');
        request.completer.complete(null);
      }
    } catch (e) {
      logger.e('Error handling thumbnail request for ${request.videoPath}: $e');
      request.completer.complete(null); // 失败时返回null而不是error，避免UI崩溃
    }
  }

  /// 暂停队列处理（进入视频播放器时调用）
  void pause() {
    logger.i('VideoThumbnailLoadQueue paused');
    _isPaused = true;
  }

  /// 恢复队列处理（退出视频播放器时调用）
  void resume() {
    logger.i('VideoThumbnailLoadQueue resumed');
    _isPaused = false;
    _processQueue(); // 立即处理队列中的请求
  }

  /// 清空队列（用于页面销毁等场景）
  void clearQueue() {
    logger.i('Clearing load queue (${_queue.length} items)');
    while (_queue.isNotEmpty) {
      final request = _queue.removeFirst();
      if (request is _LoadRequest) {
        request.completer.complete(null);
      } else if (request is _DurationRequest) {
        request.completer.complete(null);
      }
    }
  }

  /// 获取队列状态信息（用于调试）
  Map<String, dynamic> getQueueStatus() {
    return {
      'activeLoads': _activeLoads,
      'queuedLoads': _queue.length,
      'maxConcurrent': _maxConcurrent,
      'isPaused': _isPaused,
    };
  }

  /// 格式化视频时长
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// 处理时长读取请求
  Future<void> _handleDurationRequest(_DurationRequest request) async {
    VideoPlayerController? controller;
    try {
      final file = File(request.videoPath);
      if (!await file.exists()) {
        request.completer.complete(null);
        return;
      }

      controller = VideoPlayerController.file(file);

      await controller.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          logger.w('Duration read timeout: ${request.videoPath}');
          return null;
        },
      );

      if (controller.value.isInitialized) {
        final duration = controller.value.duration;

        if (duration != Duration.zero) {
          final formattedDuration = _formatDuration(duration);

          // 保存到缓存
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              'video_duration_${request.videoPath}', formattedDuration);

          logger.d('Duration read and cached: ${request.videoPath}');
          request.completer.complete(formattedDuration);
        } else {
          request.completer.complete(null);
        }
      } else {
        request.completer.complete(null);
      }
    } on PlatformException catch (e) {
      logger.w(
          'Platform error reading duration: ${request.videoPath} - ${e.code}');
      request.completer.complete(null);
    } catch (e) {
      logger.e('Error reading duration: $e');
      request.completer.completeError(e);
    } finally {
      try {
        await controller?.dispose();
      } catch (e) {
        logger.w('Error disposing controller: $e');
      }
    }
  }
}

/// 内部类：缩略图加载请求
class _LoadRequest {
  final String videoPath;
  final double size;
  final Completer<Uint8List?> completer;

  _LoadRequest({
    required this.videoPath,
    required this.size,
    required this.completer,
  });
}

/// 内部类：时长读取请求
class _DurationRequest {
  final String videoPath;
  final Completer<String?> completer;

  _DurationRequest({
    required this.videoPath,
    required this.completer,
  });
}
