import 'package:flutter/services.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/new_file_item.dart';
import 'package:easyfile/data/sources/file_source_detector.dart';

/// 新文件原生扫描通道
/// 
/// 性能优化版本：
/// - 使用原生 MediaStore 索引查询（快速）
/// - 使用协程避免阻塞UI（流畅）
/// - 一级目录扫描补充（完整）
/// 
/// 性能对比：
/// - 优化前：10-15秒（Dart递归扫描）
/// - 优化后：2-3秒（原生索引查询）
class NewFilesNativeChannel {
  static const _channel = MethodChannel('easyfile/new_files');
  
  /// 扫描最近的新文件（原生优化版）
  /// 
  /// 参数：
  /// - [days] 保留天数，默认7天
  /// 
  /// 返回：
  /// - 新文件列表，按创建时间倒序排序
  /// 
  /// 异常：
  /// - 如果原生扫描失败，抛出 PlatformException
  static Future<List<NewFileItem>> scanRecentFiles(int days) async {
    try {
      logger.i('NewFilesNativeChannel: 开始扫描最近 $days 天的文件');
      final startTime = DateTime.now();
      
      // 调用原生方法
      final List<dynamic> results = await _channel.invokeMethod(
        'scanRecentFiles',
        {'days': days},
      );
      
      final duration = DateTime.now().difference(startTime);
      logger.i('NewFilesNativeChannel: 原生扫描完成，耗时 ${duration.inMilliseconds}ms');
      
      // 转换为 NewFileItem
      final items = results.map((json) {
        final map = json as Map<dynamic, dynamic>;
        return NewFileItem(
          path: map['path'] as String,
          created: DateTime.fromMillisecondsSinceEpoch(
            (map['dateAdded'] as int) * 1000,
          ),
          discovered: DateTime.now(),
          displayName: FileSourceDetector.detectSource(map['path'] as String),
        );
      }).toList();
      
      logger.i('NewFilesNativeChannel: 找到 ${items.length} 个新文件');
      return items;
      
    } on PlatformException catch (e) {
      logger.e('NewFilesNativeChannel: 原生扫描失败 - ${e.code}: ${e.message}');
      rethrow;
    } catch (e) {
      logger.e('NewFilesNativeChannel: 扫描出错: $e');
      rethrow;
    }
  }
  
  /// 检查原生扫描是否可用
  /// 
  /// 返回：
  /// - true: 原生扫描可用
  /// - false: 需要降级到Dart扫描
  static Future<bool> isAvailable() async {
    try {
      // 尝试调用一次扫描（0天 = 快速测试）
      await _channel.invokeMethod('scanRecentFiles', {'days': 0});
      return true;
    } catch (e) {
      logger.w('NewFilesNativeChannel: 原生扫描不可用，将使用降级方案');
      return false;
    }
  }
}
