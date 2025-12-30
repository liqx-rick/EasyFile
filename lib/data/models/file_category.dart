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

  /// 根据文件扩展名判断分类
  /// 
  /// ⚠️ 已弃用：请使用 AppConfig.instance.fileTypes.getCategoryByExtension()
  @Deprecated('Use AppConfig.instance.fileTypes.getCategoryByExtension() instead')
  static FileCategory fromExtension(String extension) {
    final ext = extension.toLowerCase();

    // 图片
    if ([
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
      'svg',
      'ico',
      'heic',
      'heif',
    ].contains(ext)) {
      return FileCategory.image;
    }

    // 视频
    if ([
      'mp4',
      'avi',
      'mkv',
      'mov',
      'wmv',
      'flv',
      'webm',
      '3gp',
      'm4v',
      'mpg',
      'mpeg',
    ].contains(ext)) {
      return FileCategory.video;
    }

    // 音频
    if ([
      'mp3',
      'flac',
      'wav',
      'aac',
      'm4a',
      'ogg',
      'wma',
      'ape',
      'alac',
      'opus',
    ].contains(ext)) {
      return FileCategory.audio;
    }

    // 文档
    if ([
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
      'rtf',
      'odt',
      'ods',
      'odp',
      'csv',
      'md',
    ].contains(ext)) {
      return FileCategory.document;
    }

    // 压缩包
    if ([
      'zip',
      'rar',
      '7z',
      'tar',
      'gz',
      'bz2',
      'xz',
      'z',
      'lz',
      'lzma',
      'tgz',
      'tbz2',
    ].contains(ext)) {
      return FileCategory.archive;
    }

    // APK
    if (ext == 'apk') {
      return FileCategory.apk;
    }

    // 其他
    return FileCategory.other;
  }

  /// 根据文件名判断分类
  /// 
  /// ⚠️ 已弃用：请使用 AppConfig.instance.fileTypes.getCategoryByExtension()
  @Deprecated('Use AppConfig.instance.fileTypes.getCategoryByExtension() instead')
  static FileCategory fromFileName(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) {
      return FileCategory.other;
    }

    final extension = fileName.substring(lastDot + 1);
    return fromExtension(extension);
  }
}
