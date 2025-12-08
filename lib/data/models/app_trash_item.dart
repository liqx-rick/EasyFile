import 'package:easyfile/utils/file_size_formatter.dart';

/// EasyFile回收站文件项
/// 
/// 用于存储从EasyFile删除的文件信息
/// 与系统回收站(TrashFileItem)区分
class AppTrashItem {
  /// 唯一标识符 (UUID)
  final String id;

  /// 回收站中的路径
  /// 示例: /data/data/com.example.easyfile/.trash/1733654321_photo.jpg
  final String trashPath;

  /// 原始文件路径
  /// 示例: /storage/emulated/0/DCIM/photo.jpg
  final String originalPath;

  /// 文件名（不含路径）
  /// 示例: photo.jpg
  final String fileName;

  /// 文件大小（字节）
  final int size;

  /// MIME类型
  /// 示例: image/jpeg, video/mp4
  final String mimeType;

  /// 删除时间
  final DateTime deletedAt;

  /// 缩略图路径（可选，用于图片/视频预览）
  final String? thumbnailPath;

  AppTrashItem({
    required this.id,
    required this.trashPath,
    required this.originalPath,
    required this.fileName,
    required this.size,
    required this.mimeType,
    required this.deletedAt,
    this.thumbnailPath,
  });

  /// 计算文件删除后的天数
  int get ageDays {
    return DateTime.now().difference(deletedAt).inDays;
  }

  /// 判断文件是否即将过期（距离自动清理少于3天）
  bool isExpiringSoon(int retentionDays) {
    return ageDays >= (retentionDays - 3) && ageDays < retentionDays;
  }

  /// 判断文件是否已过期
  bool isExpired(int retentionDays) {
    return ageDays >= retentionDays;
  }

  /// 格式化文件大小
  String get formattedSize {
    return FileSizeFormatter.formatBytes(size);
  }

  /// 获取文件类型（用于图标显示）
  FileTypeCategory get fileTypeCategory {
    final mimeType = this.mimeType.toLowerCase();
    
    if (mimeType.startsWith('image/')) {
      return FileTypeCategory.image;
    } else if (mimeType.startsWith('video/')) {
      return FileTypeCategory.video;
    } else if (mimeType.startsWith('audio/')) {
      return FileTypeCategory.audio;
    } else if (mimeType.contains('pdf') || 
               mimeType.contains('document') ||
               mimeType.contains('text/')) {
      return FileTypeCategory.document;
    } else if (mimeType.contains('zip') || 
               mimeType.contains('rar') ||
               mimeType.contains('7z')) {
      return FileTypeCategory.archive;
    } else {
      return FileTypeCategory.other;
    }
  }

  /// 从JSON反序列化
  factory AppTrashItem.fromJson(Map<String, dynamic> json) {
    return AppTrashItem(
      id: json['id'] as String,
      trashPath: json['trashPath'] as String,
      originalPath: json['originalPath'] as String,
      fileName: json['fileName'] as String,
      size: json['size'] as int,
      mimeType: json['mimeType'] as String,
      deletedAt: DateTime.fromMillisecondsSinceEpoch(json['deletedAt'] as int),
      thumbnailPath: json['thumbnailPath'] as String?,
    );
  }

  /// 序列化为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trashPath': trashPath,
      'originalPath': originalPath,
      'fileName': fileName,
      'size': size,
      'mimeType': mimeType,
      'deletedAt': deletedAt.millisecondsSinceEpoch,
      'thumbnailPath': thumbnailPath,
    };
  }

  /// 从数据库Map创建对象
  factory AppTrashItem.fromMap(Map<String, dynamic> map) {
    return AppTrashItem(
      id: map['id'] as String,
      trashPath: map['trash_path'] as String,
      originalPath: map['original_path'] as String,
      fileName: map['file_name'] as String,
      size: map['file_size'] as int,
      mimeType: map['mime_type'] as String,
      deletedAt: DateTime.fromMillisecondsSinceEpoch(map['deleted_at'] as int),
      thumbnailPath: map['thumbnail_path'] as String?,
    );
  }

  /// 转换为数据库Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'trash_path': trashPath,
      'original_path': originalPath,
      'file_name': fileName,
      'file_size': size,
      'mime_type': mimeType,
      'deleted_at': deletedAt.millisecondsSinceEpoch,
      'thumbnail_path': thumbnailPath,
    };
  }

  @override
  String toString() {
    return 'AppTrashItem(id: $id, fileName: $fileName, size: $formattedSize, ageDays: $ageDays)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppTrashItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// 文件类型分类（用于UI显示）
enum FileTypeCategory {
  image,    // 图片
  video,    // 视频
  audio,    // 音频
  document, // 文档
  archive,  // 压缩包
  other,    // 其他
}

/// 文件类型扩展方法
extension FileTypeCategoryExtension on FileTypeCategory {
  /// 获取显示名称
  String get displayName {
    switch (this) {
      case FileTypeCategory.image:
        return '图片';
      case FileTypeCategory.video:
        return '视频';
      case FileTypeCategory.audio:
        return '音频';
      case FileTypeCategory.document:
        return '文档';
      case FileTypeCategory.archive:
        return '压缩包';
      case FileTypeCategory.other:
        return '其他';
    }
  }

  /// 获取图标名称（Material Icons）
  String get iconName {
    switch (this) {
      case FileTypeCategory.image:
        return 'image';
      case FileTypeCategory.video:
        return 'videocam';
      case FileTypeCategory.audio:
        return 'audiotrack';
      case FileTypeCategory.document:
        return 'description';
      case FileTypeCategory.archive:
        return 'folder_zip';
      case FileTypeCategory.other:
        return 'insert_drive_file';
    }
  }
}
