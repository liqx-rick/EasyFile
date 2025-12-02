/// 垃圾文件类型
enum JunkFileType {
  apk,
  tempFile,
  emptyFolder,
}

extension JunkFileTypeExtension on JunkFileType {
  /// 获取显示名称
  String get displayName {
    switch (this) {
      case JunkFileType.apk:
        return 'APK安装包';
      case JunkFileType.tempFile:
        return '临时文件';
      case JunkFileType.emptyFolder:
        return '空文件夹';
    }
  }

  /// 获取图标
  String get icon {
    switch (this) {
      case JunkFileType.apk:
        return '📦';
      case JunkFileType.tempFile:
        return '🗑️';
      case JunkFileType.emptyFolder:
        return '📂';
    }
  }

  /// 获取描述
  String get description {
    switch (this) {
      case JunkFileType.apk:
        return '已安装应用的安装包，可安全删除';
      case JunkFileType.tempFile:
        return '应用产生的临时文件，可安全删除';
      case JunkFileType.emptyFolder:
        return '空的文件夹，可安全删除';
    }
  }

  /// 从字符串转换
  static JunkFileType fromString(String value) {
    switch (value) {
      case 'apk':
        return JunkFileType.apk;
      case 'tempFile':
        return JunkFileType.tempFile;
      case 'emptyFolder':
        return JunkFileType.emptyFolder;
      default:
        throw ArgumentError('Unknown JunkFileType: $value');
    }
  }

  /// 转换为字符串
  String toStringValue() {
    switch (this) {
      case JunkFileType.apk:
        return 'apk';
      case JunkFileType.tempFile:
        return 'tempFile';
      case JunkFileType.emptyFolder:
        return 'emptyFolder';
    }
  }
}

/// 垃圾文件项
class JunkFileItem {
  /// 文件名
  final String name;

  /// 完整路径
  final String path;

  /// 文件大小（字节）
  final int size;

  /// 垃圾类型
  final JunkFileType type;

  /// 修改时间
  final DateTime modified;

  /// APK包名（仅APK类型）
  final String? packageName;

  /// 是否已安装（仅APK类型）
  final bool isInstalled;

  const JunkFileItem({
    required this.name,
    required this.path,
    required this.size,
    required this.type,
    required this.modified,
    this.packageName,
    this.isInstalled = false,
  });

  /// 从JSON创建
  factory JunkFileItem.fromJson(Map<String, dynamic> json) {
    return JunkFileItem(
      name: json['name'] as String,
      path: json['path'] as String,
      size: json['size'] as int,
      type: JunkFileTypeExtension.fromString(json['type'] as String),
      modified: DateTime.parse(json['modified'] as String),
      packageName: json['packageName'] as String?,
      isInstalled: json['isInstalled'] as bool? ?? false,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'size': size,
      'type': type.toStringValue(),
      'modified': modified.toIso8601String(),
      'packageName': packageName,
      'isInstalled': isInstalled,
    };
  }

  /// 获取父目录名称
  String get parentDirectoryName {
    // 统一使用正斜杠分割（兼容Windows和Android）
    final normalizedPath = path.replaceAll('\\', '/');
    final parts = normalizedPath.split('/');
    if (parts.length > 1) {
      // 返回倒数第二个部分（父目录名）
      final parentDir = parts[parts.length - 2];
      return parentDir.isNotEmpty ? parentDir : '';
    }
    return '';
  }

  /// 复制并修改属性
  JunkFileItem copyWith({
    String? name,
    String? path,
    int? size,
    JunkFileType? type,
    DateTime? modified,
    String? packageName,
    bool? isInstalled,
  }) {
    return JunkFileItem(
      name: name ?? this.name,
      path: path ?? this.path,
      size: size ?? this.size,
      type: type ?? this.type,
      modified: modified ?? this.modified,
      packageName: packageName ?? this.packageName,
      isInstalled: isInstalled ?? this.isInstalled,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is JunkFileItem &&
        other.path == path &&
        other.type == type &&
        other.size == size;
  }

  @override
  int get hashCode => path.hashCode ^ type.hashCode ^ size.hashCode;

  @override
  String toString() {
    return 'JunkFileItem(name: $name, type: ${type.displayName}, size: $size, path: $path)';
  }
}
