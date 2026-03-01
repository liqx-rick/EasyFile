import 'package:flutter/material.dart';

/// 智能任务卡片类型
enum TaskType {
  /// 重复文件清理
  duplicateFiles,

  /// 大文件清理
  largeFiles,

  /// 系统回收站清理
  systemTrash,

  /// 安装包清理
  apkFiles,

  /// 应用缓存提醒
  appCache,

  /// 垃圾文件清理
  junkFiles,
}

/// 智能任务卡片模型
class TaskCard {
  /// 任务类型
  final TaskType type;

  /// 优先级（数值越大优先级越高，用于排序）
  final int priority;

  /// 任务标题
  final String title;

  /// 任务副标题/描述
  final String subtitle;

  /// 可节省的空间大小（字节）
  final int? savableSize;

  /// 文件数量
  final int? fileCount;

  /// 主操作回调
  final VoidCallback onAction;

  /// 是否可以忽略
  final bool dismissible;

  /// 忽略回调
  final VoidCallback? onDismiss;

  const TaskCard({
    required this.type,
    required this.priority,
    required this.title,
    required this.subtitle,
    this.savableSize,
    this.fileCount,
    required this.onAction,
    this.dismissible = true,
    this.onDismiss,
  });

  /// 获取任务图标
  IconData get icon {
    switch (type) {
      case TaskType.duplicateFiles:
        return Icons.content_copy;
      case TaskType.largeFiles:
        return Icons.storage;
      case TaskType.systemTrash:
        return Icons.delete_outline;
      case TaskType.apkFiles:
        return Icons.android;
      case TaskType.appCache:
        return Icons.cached;
      case TaskType.junkFiles:
        return Icons.cleaning_services;
    }
  }

  /// 获取任务颜色
  Color get color {
    switch (type) {
      case TaskType.duplicateFiles:
        return Colors.orange;
      case TaskType.largeFiles:
        return Colors.blue;
      case TaskType.systemTrash:
        return Colors.red;
      case TaskType.apkFiles:
        return Colors.green;
      case TaskType.appCache:
        return Colors.purple;
      case TaskType.junkFiles:
        return Colors.brown;
    }
  }

  /// 获取主操作按钮文本
  String get actionText {
    switch (type) {
      case TaskType.duplicateFiles:
      case TaskType.largeFiles:
      case TaskType.systemTrash:
      case TaskType.apkFiles:
      case TaskType.junkFiles:
        return '立即清理';
      case TaskType.appCache:
        return '查看详情';
    }
  }

  /// 复制并修改部分字段
  TaskCard copyWith({
    TaskType? type,
    int? priority,
    String? title,
    String? subtitle,
    int? savableSize,
    int? fileCount,
    VoidCallback? onAction,
    bool? dismissible,
    VoidCallback? onDismiss,
  }) {
    return TaskCard(
      type: type ?? this.type,
      priority: priority ?? this.priority,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      savableSize: savableSize ?? this.savableSize,
      fileCount: fileCount ?? this.fileCount,
      onAction: onAction ?? this.onAction,
      dismissible: dismissible ?? this.dismissible,
      onDismiss: onDismiss ?? this.onDismiss,
    );
  }
}
