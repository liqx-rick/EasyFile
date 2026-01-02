import 'dart:io';

import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/data/models/file_category.dart';

class FileItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;
  final DateTime? accessedAt; // 访问时间（可选，用于最近文件列表）
  final DateTime? addedTime; // 加入收藏的时间（可选，用于收藏列表）

  FileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
    this.accessedAt,
    this.addedTime,
  });

  /// 获取文件类型分类
  FileCategory get category {
    if (isDirectory) return FileCategory.all;
    return AppConfig.instance.fileTypes.getCategoryByExtension(name);
  }

  factory FileItem.fromEntity(FileSystemEntity entity) {
    final stat = entity.statSync();

    // 正确提取文件/文件夹名称
    String name = '';
    final pathSegments = entity.uri.pathSegments;

    if (pathSegments.isNotEmpty) {
      // 如果最后一个段是空的（比如目录路径以/结尾），则取倒数第二个
      name = pathSegments.last.isEmpty && pathSegments.length > 1
          ? pathSegments[pathSegments.length - 2]
          : pathSegments.last;
    }

    // 如果还是空的，从路径中提取
    if (name.isEmpty) {
      final pathParts = entity.path.split(Platform.pathSeparator);
      name = pathParts.lastWhere(
        (part) => part.isNotEmpty,
        orElse: () => 'Unknown',
      );
    }

    return FileItem(
      name: name,
      path: entity.path,
      isDirectory: entity is Directory,
      size: stat.size,
      modified: stat.modified,
    );
  }

  /// 从 JSON 创建 FileItem（用于缓存反序列化）
  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      name: json['name'] as String,
      path: json['path'] as String,
      isDirectory: json['isDirectory'] as bool,
      size: json['size'] as int,
      modified: DateTime.fromMillisecondsSinceEpoch(json['modified'] as int),
      accessedAt: json['accessedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['accessedAt'] as int)
          : null,
      addedTime: json['addedTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['addedTime'] as int)
          : null,
    );
  }

  /// 转换为 JSON（用于缓存序列化）
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'isDirectory': isDirectory,
      'size': size,
      'modified': modified.millisecondsSinceEpoch,
      'accessedAt': accessedAt?.millisecondsSinceEpoch,
      'addedTime': addedTime?.millisecondsSinceEpoch,
    };
  }
}
