/// 回收站容器
/// 代表一个独立的回收站目录（如荣耀相册回收站、系统回收站等）
class TrashBin {
  /// 唯一标识（使用路径的哈希值）
  final String id;

  /// 完整路径
  final String path;

  /// 友好名称（如"荣耀相册回收站"）
  final String name;

  /// 回收站类型（用于分类和图标）
  final TrashBinType type;

  /// 文件数量
  final int fileCount;

  /// 总大小（字节）
  final int totalSize;

  /// 是否被选中（用于批量清空）
  bool isSelected;

  TrashBin({
    required this.id,
    required this.path,
    required this.name,
    required this.type,
    required this.fileCount,
    required this.totalSize,
    this.isSelected = false,
  });

  /// 从路径生成唯一ID
  static String generateId(String path) {
    return path.hashCode.abs().toString();
  }

  /// 根据路径智能生成友好名称
  static String generateFriendlyName(String path) {
    final lowerPath = path.toLowerCase();

    // 荣耀/华为相册回收站
    if (lowerPath.contains('.gallery2') && lowerPath.contains('recycle')) {
      return '荣耀相册回收站';
    }

    // 华为系统回收站
    if (lowerPath.contains('.recyclebinhw')) {
      return '华为系统回收站';
    }

    // 小米相册回收站
    if (lowerPath.contains('com.miui.gallery') && lowerPath.contains('trash')) {
      return '小米相册回收站';
    }

    // OPPO相册回收站
    if (lowerPath.contains('com.oppo.gallery') && lowerPath.contains('trash')) {
      return 'OPPO相册回收站';
    }

    // Vivo相册回收站
    if (lowerPath.contains('com.vivo.gallery') && lowerPath.contains('trash')) {
      return 'Vivo相册回收站';
    }

    // 荣耀相册回收站
    if (lowerPath.contains('com.hihonor.gallery') &&
        lowerPath.contains('trash')) {
      return '荣耀相册回收站';
    }

    // Google相册回收站
    if (lowerPath.contains('com.google.android.apps.photos') &&
        lowerPath.contains('trash')) {
      return 'Google相册回收站';
    }

    // 微信存储回收站
    if (lowerPath.contains('com.tencent.mm') && lowerPath.contains('trash')) {
      return '微信存储回收站';
    }

    // QQ回收站
    if (lowerPath.contains('com.tencent.mobileqq') &&
        lowerPath.contains('trash')) {
      return 'QQ回收站';
    }

    // 系统回收站（通用）
    if (lowerPath.contains('.trash') || lowerPath.contains('trash')) {
      return '系统回收站';
    }

    if (lowerPath.contains('.recycle') || lowerPath.contains('recycle')) {
      return '系统回收站';
    }

    // 文件管理器回收站
    if (lowerPath.contains('filemanager') ||
        lowerPath.contains('file_recycle')) {
      return '文件管理器回收站';
    }

    // 兜底方案：使用最后一级目录名
    final segments = path.split('/');
    final lastName = segments.isNotEmpty ? segments.last : 'Unknown';
    return '回收站 - $lastName';
  }

  /// 根据路径判断回收站类型
  static TrashBinType determineType(String path) {
    final lowerPath = path.toLowerCase();

    // 相册类回收站
    if (lowerPath.contains('gallery') ||
        lowerPath.contains('photos') ||
        lowerPath.contains('dcim') ||
        lowerPath.contains('.gallery2')) {
      return TrashBinType.gallery;
    }

    // 应用数据回收站
    if (lowerPath.contains('com.tencent.mm') ||
        lowerPath.contains('com.tencent.mobileqq') ||
        lowerPath.contains('android/data')) {
      return TrashBinType.app;
    }

    // 系统回收站
    return TrashBinType.system;
  }

  /// 复制并修改属性
  TrashBin copyWith({
    String? id,
    String? path,
    String? name,
    TrashBinType? type,
    int? fileCount,
    int? totalSize,
    bool? isSelected,
  }) {
    return TrashBin(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      type: type ?? this.type,
      fileCount: fileCount ?? this.fileCount,
      totalSize: totalSize ?? this.totalSize,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  String toString() {
    return 'TrashBin(name: $name, path: $path, files: $fileCount, size: $totalSize)';
  }
}

/// 回收站类型
enum TrashBinType {
  /// 系统回收站
  system,

  /// 相册/照片回收站
  gallery,

  /// 应用数据回收站
  app,
}
