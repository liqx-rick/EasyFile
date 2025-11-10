import 'dart:io';

import 'package:easyfile/data/models/file_item.dart';

/// 最近访问文件模型
class RecentFileItem {
  final String id;
  final String path;
  final String name;
  final bool isDirectory;
  final DateTime accessedAt;
  final int accessCount;

  const RecentFileItem({
    required this.id,
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.accessedAt,
    required this.accessCount,
  });

  /// 从FileItem创建RecentFileItem
  factory RecentFileItem.fromFileItem(FileItem fileItem) {
    return RecentFileItem(
      id: fileItem.path.hashCode.toString(),
      path: fileItem.path,
      name: fileItem.name,
      isDirectory: fileItem.isDirectory,
      accessedAt: DateTime.now(),
      accessCount: 1,
    );
  }

  /// 从 JSON 创建 RecentFileItem
  factory RecentFileItem.fromJson(Map<String, dynamic> json) {
    return RecentFileItem(
      id: json['id'] as String,
      path: json['path'] as String,
      name: json['name'] as String,
      isDirectory: json['isDirectory'] as bool,
      accessedAt: DateTime.parse(json['accessedAt'] as String),
      accessCount: json['accessCount'] as int? ?? 1,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'name': name,
      'isDirectory': isDirectory,
      'accessedAt': accessedAt.toIso8601String(),
      'accessCount': accessCount,
    };
  }

  /// 复制并更新访问时间和次数
  RecentFileItem copyWithAccess() {
    return RecentFileItem(
      id: id,
      path: path,
      name: name,
      isDirectory: isDirectory,
      accessedAt: DateTime.now(),
      accessCount: accessCount + 1,
    );
  }

  /// 转换为FileItem (用于显示)
  FileItem toFileItem() {
    try {
      final entity = isDirectory ? Directory(path) : File(path);
      if (entity.existsSync()) {
        return FileItem.fromEntity(entity);
      }
    } catch (_) {}
    
    // 如果文件不存在，创建一个基本的FileItem
    return FileItem(
      name: name,
      path: path,
      isDirectory: isDirectory,
      size: 0,
      modified: accessedAt,
    );
  }

  @override
  String toString() {
    return 'RecentFileItem(name: $name, path: $path, accessedAt: $accessedAt, accessCount: $accessCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecentFileItem &&
        other.path == path;
  }

  @override
  int get hashCode => path.hashCode;
}