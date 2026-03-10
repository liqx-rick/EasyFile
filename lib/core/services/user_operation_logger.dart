import 'dart:convert';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用户操作类型枚举
enum OperationType {
  trashEmpty, // 清空应用回收站
  duplicateClean, // 清理重复文件
  junkClean, // 清理垃圾文件
  systemTrashClean, // 清空系统回收站（全部）
  systemTrashDelete, // 从系统回收站删除选中文件
  largeFileClean, // 清理大文件
  privacyMoveIn, // 移入隐私空间
  privacyMoveOut, // 移出隐私空间
}

/// 用户操作日志数据
class UserOperationLog {
  final OperationType type;
  final DateTime timestamp;
  final int fileCount;
  final int sizeBytes;

  UserOperationLog({
    required this.type,
    required this.timestamp,
    required this.fileCount,
    required this.sizeBytes,
  });

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'fileCount': fileCount,
      'sizeBytes': sizeBytes,
    };
  }

  /// 从JSON创建
  factory UserOperationLog.fromJson(Map<String, dynamic> json) {
    return UserOperationLog(
      type: OperationType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => OperationType.trashEmpty,
      ),
      timestamp: DateTime.parse(json['timestamp']),
      fileCount: json['fileCount'] as int,
      sizeBytes: json['sizeBytes'] as int,
    );
  }

  /// 获取友好的描述文本
  String get description {
    final size = sizeFormatted;
    switch (type) {
      case OperationType.trashEmpty:
        return '清空了应用回收站，释放空间 $size';
      case OperationType.duplicateClean:
        return '清理了$fileCount个重复文件，节省空间 $size';
      case OperationType.junkClean:
        return '清理了垃圾文件，释放空间 $size';
      case OperationType.systemTrashClean:
        return '清空了系统回收站，释放空间 $size';
      case OperationType.systemTrashDelete:
        return '从系统回收站删除$fileCount个文件，释放空间 $size';
      case OperationType.largeFileClean:
        return '删除了$fileCount个大文件，节省空间 $size';
      case OperationType.privacyMoveIn:
        return '移入隐私空间$fileCount个文件 ($size)';
      case OperationType.privacyMoveOut:
        return '移出隐私空间$fileCount个文件 ($size)';
    }
  }

  /// 获取格式化的大小
  String get sizeFormatted => FileSizeFormatter.formatBytesWithSpace(sizeBytes);

  /// 获取相对时间描述
  String get timeDescription {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${timestamp.month}月${timestamp.day}日';
    }
  }
}

/// 轻量级用户操作日志服务
///
/// 使用 SharedPreferences 存储最近的操作记录
/// 第一阶段实现：只记录核心清理操作，最多保留10条
class UserOperationLogger {
  static const String _logsKey = 'user_operation_logs';
  static const int _maxLogs = 10;

  /// 记录用户操作
  ///
  /// [type] 操作类型
  /// [fileCount] 文件数量
  /// [sizeBytes] 文件大小（字节）
  static Future<void> log({
    required OperationType type,
    required int fileCount,
    required int sizeBytes,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logs = await _getLogs();

      // 创建新日志
      final newLog = UserOperationLog(
        type: type,
        timestamp: DateTime.now(),
        fileCount: fileCount,
        sizeBytes: sizeBytes,
      );

      // 插入到列表开头（最新的在前面）
      logs.insert(0, newLog);

      // 只保留最新的N条
      if (logs.length > _maxLogs) {
        logs.removeRange(_maxLogs, logs.length);
      }

      // 保存到 SharedPreferences
      final jsonList = logs.map((log) => log.toJson()).toList();
      await prefs.setString(_logsKey, jsonEncode(jsonList));

      logger.i('记录用户操作: ${newLog.description} (${newLog.sizeFormatted})');
    } catch (e) {
      logger.e('记录用户操作失败: $e');
    }
  }

  /// 获取最近的操作记录
  ///
  /// [limit] 最多返回的条数（默认5条）
  static Future<List<UserOperationLog>> getRecentLogs({int limit = 5}) async {
    try {
      final logs = await _getLogs();
      return logs.take(limit).toList();
    } catch (e) {
      logger.e('获取操作记录失败: $e');
      return [];
    }
  }

  /// 清空所有操作记录
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_logsKey);
      logger.i('已清空所有操作记录');
    } catch (e) {
      logger.e('清空操作记录失败: $e');
    }
  }

  /// 获取操作统计（本周数据）
  ///
  /// 返回 Map，包含：
  /// - totalOperations: 总操作次数
  /// - totalSize: 总节省空间（字节）
  /// - totalFiles: 总处理文件数
  static Future<Map<String, int>> getWeeklyStats() async {
    try {
      final logs = await _getLogs();
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));

      // 筛选本周的记录
      final weeklyLogs = logs.where((log) => log.timestamp.isAfter(weekAgo)).toList();

      int totalSize = 0;
      int totalFiles = 0;

      for (final log in weeklyLogs) {
        totalSize += log.sizeBytes;
        totalFiles += log.fileCount;
      }

      return {
        'totalOperations': weeklyLogs.length,
        'totalSize': totalSize,
        'totalFiles': totalFiles,
      };
    } catch (e) {
      logger.e('获取本周统计失败: $e');
      return {
        'totalOperations': 0,
        'totalSize': 0,
        'totalFiles': 0,
      };
    }
  }

  /// 从 SharedPreferences 读取日志列表
  static Future<List<UserOperationLog>> _getLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_logsKey);

      if (jsonStr == null || jsonStr.isEmpty) {
        return [];
      }

      final jsonList = jsonDecode(jsonStr) as List<dynamic>;
      return jsonList.map((json) => UserOperationLog.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      logger.e('读取操作日志失败: $e');
      return [];
    }
  }
}
