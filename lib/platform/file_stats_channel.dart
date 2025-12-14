import 'package:flutter/services.dart';
import 'package:easyfile/core/logger.dart';

/// 文件统计信息原生通道
///
/// 提供获取文件创建时间等原生文件系统信息
class FileStatsChannel {
  static const MethodChannel _channel =
      MethodChannel('com.easyfile/file_stats');

  /// 获取单个文件的创建时间
  ///
  /// 返回时间戳（毫秒），如果文件不存在或出错返回null
  static Future<DateTime?> getFileCreationTime(String filePath) async {
    try {
      final timestamp = await _channel.invokeMethod<int>(
        'getFileCreationTime',
        {'filePath': filePath},
      );

      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      return null;
    } catch (e) {
      logger.w('Error getting file creation time for $filePath: $e');
      return null;
    }
  }

  /// 批量获取文件的创建时间
  ///
  /// 返回 `Map<filePath, DateTime?>`
  static Future<Map<String, DateTime?>> getFilesCreationTimes(
      List<String> filePaths) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getFilesCreationTimes',
        {'filePaths': filePaths},
      );

      if (result == null) return {};

      final times = <String, DateTime?>{};
      result.forEach((key, value) {
        if (key is String) {
          times[key] = value != null
              ? DateTime.fromMillisecondsSinceEpoch(value as int)
              : null;
        }
      });

      return times;
    } catch (e) {
      logger.e('Error getting files creation times: $e');
      return {};
    }
  }
}
