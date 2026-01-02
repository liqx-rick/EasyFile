/// 文件类型分类枚举
enum FileCategory {
  all, // 全部
  image, // 图片
  video, // 视频
  audio, // 音频
  document, // 文档
  archive, // 压缩包
  apk, // APK安装包
  other, // 其他
}

/// 文件类型分类扩展
extension FileCategoryExtension on FileCategory {
  /// 获取分类显示名称
  String get displayName {
    switch (this) {
      case FileCategory.all:
        return '全部';
      case FileCategory.image:
        return '图片';
      case FileCategory.video:
        return '视频';
      case FileCategory.audio:
        return '音频';
      case FileCategory.document:
        return '文档';
      case FileCategory.archive:
        return '压缩包';
      case FileCategory.apk:
        return 'APK';
      case FileCategory.other:
        return '其他';
    }
  }

  /// 获取分类图标名称
  String get iconName {
    switch (this) {
      case FileCategory.all:
        return 'folder';
      case FileCategory.image:
        return 'image';
      case FileCategory.video:
        return 'video';
      case FileCategory.audio:
        return 'audio';
      case FileCategory.document:
        return 'document';
      case FileCategory.archive:
        return 'archive';
      case FileCategory.apk:
        return 'apk';
      case FileCategory.other:
        return 'file';
    }
  }
}
