import 'dart:io';
import 'package:flutter/services.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/trash_file_item.dart';

/// MediaStore回收站平台通道
///
/// 通过Method Channel调用Android原生代码查询和删除系统回收站文件
class MediaStoreTrashChannel {
  static const MethodChannel _channel =
      MethodChannel('com.example.easyfile/trash');

  /// 检查当前平台是否支持MediaStore Trash
  ///
  /// 返回true表示支持（Android 11+）
  static Future<bool> isSupported() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final bool supported = await _channel.invokeMethod('isSupported');
      logger.i('MediaStore Trash支持状态: $supported');
      return supported;
    } catch (e) {
      logger.e('检查MediaStore Trash支持状态失败: $e');
      return false;
    }
  }

  /// 查询回收站中的文件
  ///
  /// 返回回收站文件列表
  static Future<List<TrashFileItem>> queryTrashedFiles() async {
    try {
      logger.i('开始查询MediaStore回收站文件');

      final List<dynamic> result =
          await _channel.invokeMethod('queryTrashedFiles');

      final files = result.map((item) {
        final map = Map<String, dynamic>.from(item as Map);

        return TrashFileItem(
          name: map['name'] as String,
          path: map['path'] as String? ?? '',
          size: (map['size'] as num).toInt(),
          modified: DateTime.fromMillisecondsSinceEpoch(
            (map['modified'] as num).toInt(),
          ),
          trashedTime: DateTime.fromMillisecondsSinceEpoch(
            (map['modified'] as num).toInt(),
          ),
          isDirectory: false,
          // 存储MediaStore ID，用于删除
          mediaStoreId: (map['id'] as num).toInt(),
          // MediaStore查询的文件通过扩展名推断MIME类型
          mimeTypeVerified: false,
        );
      }).toList();

      logger.i('查询到 ${files.length} 个回收站文件');
      return files;
    } catch (e) {
      logger.e('查询MediaStore回收站文件失败: $e');
      rethrow;
    }
  }

  /// 删除单个回收站文件
  ///
  /// [fileId] MediaStore文件ID
  /// 返回删除是否成功
  static Future<bool> deleteTrashedFile(int fileId) async {
    try {
      logger.d('删除MediaStore回收站文件，ID: $fileId');

      final bool success = await _channel.invokeMethod(
        'deleteTrashedFile',
        {'fileId': fileId},
      );

      if (success) {
        logger.i('文件删除成功，ID: $fileId');
      } else {
        logger.w('文件删除失败，ID: $fileId');
      }

      return success;
    } catch (e) {
      logger.e('删除MediaStore回收站文件异常，ID: $fileId, 错误: $e');
      return false;
    }
  }

  /// 批量删除回收站文件
  ///
  /// [fileIds] 文件ID列表
  /// 返回删除结果统计
  static Future<Map<String, int>> deleteMultipleTrashedFiles(
      List<int> fileIds) async {
    try {
      logger.i('批量删除 ${fileIds.length} 个MediaStore回收站文件');

      final Map<dynamic, dynamic> result = await _channel.invokeMethod(
        'deleteMultipleTrashedFiles',
        {'fileIds': fileIds},
      );

      final resultMap = {
        'success': result['success'] as int,
        'failed': result['failed'] as int,
      };

      logger.i('批量删除完成: 成功 ${resultMap['success']}, 失败 ${resultMap['failed']}');

      return resultMap;
    } catch (e) {
      logger.e('批量删除MediaStore回收站文件失败: $e');
      rethrow;
    }
  }

  /// 清空整个回收站
  ///
  /// 返回删除结果统计
  static Future<Map<String, int>> emptyTrash() async {
    try {
      logger.i('清空MediaStore回收站');

      final Map<dynamic, dynamic> result =
          await _channel.invokeMethod('emptyTrash');

      final resultMap = {
        'success': result['success'] as int,
        'failed': result['failed'] as int,
      };

      logger
          .i('清空回收站完成: 成功 ${resultMap['success']}, 失败 ${resultMap['failed']}');

      return resultMap;
    } catch (e) {
      logger.e('清空MediaStore回收站失败: $e');
      rethrow;
    }
  }
}
