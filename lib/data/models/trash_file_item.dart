/// 回收站文件项
class TrashFileItem {
  /// 文件名
  final String name;

  /// 完整路径
  final String path;

  /// 文件大小（字节）
  final int size;

  /// 修改时间
  final DateTime modified;

  /// 删除时间（回收站中的时间）
  final DateTime? trashedTime;

  /// 原始路径（如果可以获取）
  final String? originalPath;

  /// 是否为文件夹
  final bool isDirectory;

  /// MediaStore文件ID（用于Android 11+删除）
  final int? mediaStoreId;

  /// MIME类型（用于分类）
  final String mimeType;

  /// MIME类型是否已通过文件头验证（true=文件头检测，false=扩展名推断）
  final bool mimeTypeVerified;

  /// 所属回收站ID（用于分组和过滤）
  final String? trashBinId;

  TrashFileItem({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
    this.trashedTime,
    this.originalPath,
    this.isDirectory = false,
    this.mediaStoreId,
    String? mimeType,
    this.mimeTypeVerified = false,
    this.trashBinId,
  }) : mimeType = mimeType ?? _inferMimeType(name);

  /// 根据文件名推断MIME类型
  static String _inferMimeType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    
    // 荣耀/华为相册回收站特殊扩展名 (.hndgp)
    // 需要根据文件内容判断真实类型，这里先标记为图片类型
    if (ext == 'hndgp') {
      return 'image/unknown'; // 将在扫描时根据文件头更新
    }
    
    // 图片
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif'].contains(ext)) {
      return 'image/$ext';
    }
    // 视频
    if (['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', '3gp', 'webm', 'm4v'].contains(ext)) {
      return 'video/$ext';
    }
    // 音频
    if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma'].contains(ext)) {
      return 'audio/$ext';
    }
    // 文档
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'].contains(ext)) {
      return 'application/$ext';
    }
    // 压缩文件
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return 'application/$ext';
    }
    
    return 'application/octet-stream';
  }

  /// 从JSON创建
  factory TrashFileItem.fromJson(Map<String, dynamic> json) {
    return TrashFileItem(
      name: json['name'] as String,
      path: json['path'] as String,
      size: json['size'] as int,
      modified: DateTime.parse(json['modified'] as String),
      trashedTime: json['trashedTime'] != null
          ? DateTime.parse(json['trashedTime'] as String)
          : null,
      originalPath: json['originalPath'] as String?,
      isDirectory: json['isDirectory'] as bool? ?? false,
      mediaStoreId: json['mediaStoreId'] as int?,
      mimeType: json['mimeType'] as String?,
      mimeTypeVerified: json['mimeTypeVerified'] as bool? ?? false,
      trashBinId: json['trashBinId'] as String?,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'size': size,
      'modified': modified.toIso8601String(),
      'trashedTime': trashedTime?.toIso8601String(),
      'originalPath': originalPath,
      'isDirectory': isDirectory,
      'mediaStoreId': mediaStoreId,
      'mimeType': mimeType,
      'mimeTypeVerified': mimeTypeVerified,
      'trashBinId': trashBinId,
    };
  }

  /// 获取回收站目录名称
  String get trashDirectoryName {
    final normalizedPath = path.replaceAll('\\', '/');
    if (normalizedPath.contains('/.Trash/')) {
      return '.Trash';
    } else if (normalizedPath.contains('/.Trash-')) {
      final match = RegExp(r'\.Trash-\d+').firstMatch(normalizedPath);
      return match?.group(0) ?? '.Trash';
    }
    return '回收站';
  }

  /// 复制并修改属性
  TrashFileItem copyWith({
    String? name,
    String? path,
    int? size,
    DateTime? modified,
    DateTime? trashedTime,
    String? originalPath,
    bool? isDirectory,
    int? mediaStoreId,
    String? mimeType,
    bool? mimeTypeVerified,
    String? trashBinId,
  }) {
    return TrashFileItem(
      name: name ?? this.name,
      path: path ?? this.path,
      size: size ?? this.size,
      modified: modified ?? this.modified,
      trashedTime: trashedTime ?? this.trashedTime,
      originalPath: originalPath ?? this.originalPath,
      isDirectory: isDirectory ?? this.isDirectory,
      mediaStoreId: mediaStoreId ?? this.mediaStoreId,
      mimeType: mimeType ?? this.mimeType,
      mimeTypeVerified: mimeTypeVerified ?? this.mimeTypeVerified,
      trashBinId: trashBinId ?? this.trashBinId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TrashFileItem &&
        other.path == path &&
        other.size == size;
  }

  @override
  int get hashCode => path.hashCode ^ size.hashCode;

  @override
  String toString() {
    return 'TrashFileItem(name: $name, size: $size, path: $path, trashed: $trashedTime)';
  }
}
