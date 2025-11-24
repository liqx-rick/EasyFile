import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:easyfile/core/logger.dart';

/// 视频时长缓存服务
///
/// 用于缓存视频时长信息，避免重复读取视频元数据
class VideoDurationCacheService {
  static const String _keyPrefix = 'video_duration_';
  static final VideoDurationCacheService _instance =
      VideoDurationCacheService._internal();

  factory VideoDurationCacheService() => _instance;

  VideoDurationCacheService._internal();

  /// 获取视频时长（带缓存）
  ///
  /// 返回格式化的时长字符串，如 "2:34", "1:23:45"
  /// 如果获取失败或视频无效，返回 null
  Future<String?> getVideoDuration(String videoPath) async {
    try {
      // 检查缓存
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _keyPrefix + videoPath;
      final cachedDuration = prefs.getString(cacheKey);

      if (cachedDuration != null) {
        return cachedDuration;
      }

      // 缓存未命中，读取视频时长
      final duration = await _readVideoDuration(videoPath);

      if (duration != null) {
        // 格式化并缓存
        final formattedDuration = _formatDuration(duration);
        await prefs.setString(cacheKey, formattedDuration);
        return formattedDuration;
      }

      return null;
    } catch (e) {
      logger.e('Failed to get video duration for $videoPath: $e');
      return null;
    }
  }

  /// 读取视频时长
  Future<Duration?> _readVideoDuration(String videoPath) async {
    VideoPlayerController? controller;
    try {
      final file = File(videoPath);
      if (!await file.exists()) {
        return null;
      }

      controller = VideoPlayerController.file(file);
      
      // 添加超时机制，避免卡住
      await controller.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Video initialization timeout');
        },
      );

      // 检查是否初始化成功
      if (!controller.value.isInitialized) {
        return null;
      }

      final duration = controller.value.duration;
      
      // 验证时长是否有效
      if (duration == Duration.zero) {
        logger.w('Video duration is zero for: $videoPath');
        return null;
      }
      
      return duration;
    } on TimeoutException catch (e) {
      logger.w('Timeout reading video duration for $videoPath: $e');
      return null;
    } on PlatformException catch (e) {
      // Android ExoPlayer 编解码器错误
      logger.w('Platform error reading video duration for $videoPath: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      logger.w('Error reading video duration for $videoPath: $e');
      return null;
    } finally {
      try {
        await controller?.dispose();
      } catch (e) {
        logger.w('Error disposing video controller: $e');
      }
    }
  }

  /// 格式化时长
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

  /// 清除指定视频的缓存
  Future<void> clearCache(String videoPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _keyPrefix + videoPath;
      await prefs.remove(cacheKey);
    } catch (e) {
      logger.e('Failed to clear cache for $videoPath: $e');
    }
  }

  /// 清除所有视频时长缓存
  Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final videoDurationKeys =
          keys.where((key) => key.startsWith(_keyPrefix)).toList();

      for (final key in videoDurationKeys) {
        await prefs.remove(key);
      }

      logger.i(
          'Cleared ${videoDurationKeys.length} video duration cache entries');
    } catch (e) {
      logger.e('Failed to clear all video duration cache: $e');
    }
  }
}
