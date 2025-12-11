import 'dart:io';

import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/file_source.dart';

/// 新文件数据模型（轻量级索引）
class NewFileItem {
  final String path;
  final DateTime created;    // 文件创建/修改时间
  final DateTime discovered; // 发现时间（首次扫描到）
  final FileSource source;   // 自动识别的来源

  const NewFileItem({
    required this.path,
    required this.created,
    required this.discovered,
    required this.source,
  });

  /// 从 JSON 创建
  factory NewFileItem.fromJson(Map<String, dynamic> json) {
    return NewFileItem(
      path: json['path'] as String,
      created: DateTime.parse(json['created'] as String),
      discovered: DateTime.parse(json['discovered'] as String),
      source: FileSource.values[json['source'] as int],
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'created': created.toIso8601String(),
      'discovered': discovered.toIso8601String(),
      'source': source.index,
    };
  }

  /// 转换为 FileItem（从文件系统读取完整信息）
  FileItem? toFileItem() {
    try {
      final file = File(path);
      if (file.existsSync()) {
        return FileItem.fromEntity(file);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NewFileItem &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}
