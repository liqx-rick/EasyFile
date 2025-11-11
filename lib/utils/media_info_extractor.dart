import 'dart:io';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:easyfile/core/logger.dart';
import 'package:path/path.dart' as path;

/// 详细媒体信息类
class DetailedMediaInfo {
  // 通用信息
  final String fileName;
  final int fileSize;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final Duration? duration;
  final String format;

  // 视频特定
  final int? width;
  final int? height;
  final double? aspectRatio;

  // 音频特定
  final String? title;
  final String? artist;
  final String? album;
  final String? year;
  final String? genre;

  DetailedMediaInfo({
    required this.fileName,
    required this.fileSize,
    required this.createdAt,
    required this.modifiedAt,
    required this.format,
    this.duration,
    this.width,
    this.height,
    this.aspectRatio,
    this.title,
    this.artist,
    this.album,
    this.year,
    this.genre,
  });
}

/// 媒体信息提取器
class MediaInfoExtractor {
  /// 提取视频详细信息
  Future<DetailedMediaInfo> extractVideoInfo(String videoPath) async {
    final file = File(videoPath);
    final stat = await file.stat();

    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(file);
      await controller.initialize();

      final info = DetailedMediaInfo(
        fileName: path.basename(videoPath),
        fileSize: stat.size,
        createdAt: stat.changed,
        modifiedAt: stat.modified,
        format: path.extension(videoPath).replaceFirst('.', '').toUpperCase(),
        duration: controller.value.duration,
        width: controller.value.size.width.toInt(),
        height: controller.value.size.height.toInt(),
        aspectRatio: controller.value.aspectRatio,
      );

      return info;
    } catch (e) {
      logger.e('Error extracting video info: $e');
      // 返回基本信息
      return DetailedMediaInfo(
        fileName: path.basename(videoPath),
        fileSize: stat.size,
        createdAt: stat.changed,
        modifiedAt: stat.modified,
        format: path.extension(videoPath).replaceFirst('.', '').toUpperCase(),
      );
    } finally {
      controller?.dispose();
    }
  }

  /// 提取音频详细信息
  Future<DetailedMediaInfo> extractAudioInfo(String audioPath) async {
    final file = File(audioPath);
    final stat = await file.stat();

    // 获取时长
    Duration? duration;
    try {
      final player = AudioPlayer();
      await player.setSourceDeviceFile(audioPath);
      await Future.delayed(const Duration(milliseconds: 500));
      duration = await player.getDuration();
      player.dispose();
    } catch (e) {
      logger.e('Error getting audio duration: $e');
    }

    // 从文件名提取基本信息（简化版）
    final fileName = path.basenameWithoutExtension(audioPath);

    return DetailedMediaInfo(
      fileName: path.basename(audioPath),
      fileSize: stat.size,
      createdAt: stat.changed,
      modifiedAt: stat.modified,
      format: path.extension(audioPath).replaceFirst('.', '').toUpperCase(),
      duration: duration,
      title: fileName, // 使用文件名作为标题
    );
  }
}
