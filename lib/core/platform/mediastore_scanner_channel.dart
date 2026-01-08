import 'package:flutter/services.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';

/// MediaStore 扫描类型枚举
/// 提供类型安全的扫描类型定义
enum MediaScanType {
  /// 图片文件
  image,

  /// 音频文件
  audio,

  /// 视频文件
  video,

  /// 文档文件
  document,

  /// APK文件
  apk,

  /// 压缩包文件
  archive,

  /// 相机照片（时光记忆）
  cameraImage,

  /// 相机视频（生活剪影）
  cameraVideo,

  /// 录音文件（声音记录）
  recording,
}

/// 统一的 MediaStore 扫描通道
/// 支持所有媒体类型：Image, Audio, Video, Document, APK, Archive
class MediaStoreScannerChannel {
  static const _channel = MethodChannel('easyfile/mediastore_scanner');
  static const _nativeCameraChannel =
      MethodChannel('easyfile/native_camera_test');

  /// 扫描指定类型的文件
  ///
  /// [type] 媒体类型枚举
  ///
  /// 使用示例：
  /// ```dart
  /// final images = await MediaStoreScannerChannel.scan(MediaScanType.image);
  /// final videos = await MediaStoreScannerChannel.scan(MediaScanType.video);
  /// ```
  static Future<List<FileItem>> scan(MediaScanType type) async {
    final typeStr = type.name;
    try {
      logger.i('MediaStore扫描开始 - 类型: $typeStr');
      final startTime = DateTime.now();

      final List<dynamic> result = await _channel.invokeMethod(
        'scan',
        {'type': typeStr},
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      logger.i(
          'MediaStore扫描完成 - 类型: $typeStr, 数量: ${result.length}, 耗时: ${duration.inMilliseconds}ms');

      final files = <FileItem>[];

      for (final item in result) {
        final map = Map<String, dynamic>.from(item as Map);

        files.add(FileItem(
          name: map['name'] as String,
          path: map['path'] as String,
          size: (map['size'] as num).toInt(),
          modified: DateTime.fromMillisecondsSinceEpoch(
            (map['modified'] as num).toInt(),
          ),
          isDirectory: false,
        ));
      }

      return files;
    } catch (e) {
      logger.e('MediaStore扫描失败 - 类型: $typeStr, 错误: $e');
      rethrow;
    }
  }

  /// 获取扫描统计信息
  ///
  /// [type] 媒体类型枚举
  static Future<Map<String, dynamic>> getScanStats(MediaScanType type) async {
    final typeStr = type.name;
    try {
      logger.i('获取MediaStore扫描统计 - 类型: $typeStr');

      final Map<dynamic, dynamic> result = await _channel.invokeMethod(
        'getScanStats',
        {'type': typeStr},
      );

      return Map<String, dynamic>.from(result);
    } catch (e) {
      logger.e('获取扫描统计失败 - 类型: $typeStr, 错误: $e');
      rethrow;
    }
  }

  // ========== 便捷方法 ==========

  /// 扫描所有图片
  static Future<List<FileItem>> scanImages() => scan(MediaScanType.image);

  /// 扫描所有音频
  static Future<List<FileItem>> scanAudio() => scan(MediaScanType.audio);

  /// 扫描所有视频
  static Future<List<FileItem>> scanVideos() => scan(MediaScanType.video);

  /// 扫描所有文档
  static Future<List<FileItem>> scanDocuments() => scan(MediaScanType.document);

  /// 扫描所有APK
  static Future<List<FileItem>> scanApks() => scan(MediaScanType.apk);

  /// 扫描所有压缩包
  static Future<List<FileItem>> scanArchives() => scan(MediaScanType.archive);

  /// 扫描相机照片（时光记忆）
  static Future<List<FileItem>> scanCameraImages() =>
      scan(MediaScanType.cameraImage);

  /// 扫描相机视频（生活剪影）
  static Future<List<FileItem>> scanCameraVideos() =>
      scan(MediaScanType.cameraVideo);

  /// 扫描录音文件（声音记录）
  static Future<List<FileItem>> scanRecordings() =>
      scan(MediaScanType.recording);

  // ========== 统计信息便捷方法 ==========

  /// 获取图片扫描统计
  static Future<Map<String, dynamic>> getImageStats() =>
      getScanStats(MediaScanType.image);

  /// 获取音频扫描统计
  static Future<Map<String, dynamic>> getAudioStats() =>
      getScanStats(MediaScanType.audio);

  /// 获取视频扫描统计
  static Future<Map<String, dynamic>> getVideoStats() =>
      getScanStats(MediaScanType.video);

  /// 获取文档扫描统计
  static Future<Map<String, dynamic>> getDocumentStats() =>
      getScanStats(MediaScanType.document);

  /// 获取APK扫描统计
  static Future<Map<String, dynamic>> getApkStats() =>
      getScanStats(MediaScanType.apk);

  /// 获取压缩包扫描统计
  static Future<Map<String, dynamic>> getArchiveStats() =>
      getScanStats(MediaScanType.archive);

  // ========== 包名快速扫描方法 ==========

  /// 通过系统相机包名快速扫描照片（时光记忆优化版本）
  /// 速度快（约100-500ms），只返回系统相机应用创建的照片
  static Future<List<FileItem>> scanCameraPackagePhotos() async {
    try {
      logger.i('开始通过相机包名扫描照片...');
      final startTime = DateTime.now();

      final List<dynamic> result =
          await _nativeCameraChannel.invokeMethod('scanCameraPackagePhotos');

      final files = result.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return FileItem(
          path: map['path'] as String,
          name: map['name'] as String,
          size: (map['size'] as num).toInt(),
          isDirectory: false,
          modified: DateTime.fromMillisecondsSinceEpoch(
              (map['dateAdded'] as num).toInt() * 1000),
        );
      }).toList();

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      logger.i('相机包名照片扫描完成: ${files.length} 张, 耗时: ${duration}ms');

      return files;
    } catch (e) {
      logger.e('相机包名照片扫描失败: $e');
      return [];
    }
  }

  /// 通过系统相机包名快速扫描视频（生活剪影优化版本）
  /// 速度快（约100-500ms），只返回系统相机应用创建的视频
  static Future<List<FileItem>> scanCameraPackageVideos() async {
    try {
      logger.i('开始通过相机包名扫描视频...');
      final startTime = DateTime.now();

      final List<dynamic> result =
          await _nativeCameraChannel.invokeMethod('scanCameraPackageVideos');

      final files = result.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return FileItem(
          path: map['path'] as String,
          name: map['name'] as String,
          size: (map['size'] as num).toInt(),
          isDirectory: false,
          modified: DateTime.fromMillisecondsSinceEpoch(
              (map['dateAdded'] as num).toInt() * 1000),
        );
      }).toList();

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      logger.i('相机包名视频扫描完成: ${files.length} 个, 耗时: ${duration}ms');

      return files;
    } catch (e) {
      logger.e('相机包名视频扫描失败: $e');
      return [];
    }
  }

  /// 扫描最近N天修改的应用文件
  ///
  /// 使用MediaStore的DATE_MODIFIED索引查询，避免遍历所有文件
  /// 适用于Android 11+（需要OWNER_PACKAGE_NAME字段）
  ///
  /// [packageName] 应用包名，如 'com.tencent.mm'
  /// [days] 天数，默认7天
  /// 返回最近修改的文件列表
  static Future<List<FileItem>> scanRecentAppFiles({
    required String packageName,
    int days = 7,
  }) async {
    try {
      logger.i('扫描最近修改的应用文件 - 包名: $packageName, 天数: $days');
      final startTime = DateTime.now();

      final List<dynamic> result = await _channel.invokeMethod(
        'scanRecentAppFiles',
        {
          'packageName': packageName,
          'days': days,
        },
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      logger.i(
          '扫描完成 - 包名: $packageName, 数量: ${result.length}, 耗时: ${duration.inMilliseconds}ms');

      final files = <FileItem>[];
      for (final item in result) {
        final map = Map<String, dynamic>.from(item as Map);
        files.add(FileItem(
          name: map['name'] as String,
          path: map['path'] as String,
          size: (map['size'] as num).toInt(),
          isDirectory: false,
          modified: DateTime.fromMillisecondsSinceEpoch(
            (map['modified'] as num).toInt(),
          ),
        ));
      }

      return files;
    } catch (e) {
      logger.e('扫描最近修改的应用文件失败 - 包名: $packageName, 错误: $e');
      return []; // 失败时返回空数组，不影响主流程
    }
  }
}
