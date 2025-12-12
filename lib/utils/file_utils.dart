class FileUtils {
  /// 判断文件是否为图片类型
  static bool isImageFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'bmp',
      'webp',
      'svg',
      'ico',
      'tiff',
      'tif',
      'heic',
      'heif'
    ].contains(ext);
  }

  /// 判断文件是否为视频类型
  static bool isVideoFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return [
      'mp4',
      'avi',
      'mkv',
      'mov',
      'flv',
      'wmv',
      'webm',
      '3gp',
      'm4v',
      'rmvb',
      'rm',
      'asf'
    ].contains(ext);
  }

  /// 判断文件是否为音频类型
  static bool isAudioFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return [
      'mp3',
      'wav',
      'flac',
      'aac',
      'm4a',
      'ogg',
      'wma',
      'opus',
      'aiff',
      'ape',
    ].contains(ext);
  }

  /// 判断文件是否为PDF类型
  static bool isPdfFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return ext == 'pdf';
  }

  /// 判断文件是否为Word文档类型
  static bool isWordFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return ['doc', 'docx'].contains(ext);
  }

  /// 判断文件是否为Excel表格类型
  static bool isExcelFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return ['xls', 'xlsx', 'csv'].contains(ext);
  }

  /// 判断文件是否为PowerPoint演示文稿类型
  static bool isPowerPointFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return ['ppt', 'pptx'].contains(ext);
  }

  /// 判断文件是否为文本文件类型
  static bool isTextFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return [
      'txt',
      'log',
      'md',
      'json',
      'xml',
      'html',
      'css',
      'js',
      'dart',
      'java',
      'py',
      'cpp',
      'c',
      'h',
    ].contains(ext);
  }

  /// 判断文件是否为压缩文件类型
  static bool isArchiveFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return ['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'].contains(ext);
  }

  /// 判断文件是否为文档类型（PDF, Word, Excel, PPT）
  static bool isDocumentFile(String fileName) {
    return isPdfFile(fileName) ||
        isWordFile(fileName) ||
        isExcelFile(fileName) ||
        isPowerPointFile(fileName);
  }

  /// 格式化文件大小
  ///
  /// 将字节数转换为人类可读的文件大小格式
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 根据文件路径获取MIME类型
  ///
  /// 用于Android分享等需要精确MIME类型的场景
  static String getMimeType(String filePath) {
    final ext = filePath.toLowerCase().split('.').last;

    // 图片类型
    if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
    if (ext == 'png') return 'image/png';
    if (ext == 'gif') return 'image/gif';
    if (ext == 'webp') return 'image/webp';
    if (ext == 'bmp') return 'image/bmp';
    if (ext == 'svg') return 'image/svg+xml';
    if (ext == 'heic') return 'image/heic';
    if (ext == 'heif') return 'image/heif';

    // 视频类型
    if (ext == 'mp4') return 'video/mp4';
    if (ext == 'avi') return 'video/x-msvideo';
    if (ext == 'mkv') return 'video/x-matroska';
    if (ext == 'mov') return 'video/quicktime';
    if (ext == 'wmv') return 'video/x-ms-wmv';
    if (ext == 'flv') return 'video/x-flv';
    if (ext == 'webm') return 'video/webm';
    if (ext == '3gp') return 'video/3gpp';

    // 音频类型
    if (ext == 'mp3') return 'audio/mpeg';
    if (ext == 'wav') return 'audio/wav';
    if (ext == 'flac') return 'audio/flac';
    if (ext == 'aac') return 'audio/aac';
    if (ext == 'm4a') return 'audio/mp4';
    if (ext == 'ogg') return 'audio/ogg';
    if (ext == 'opus') return 'audio/opus';

    // 文档类型
    if (ext == 'pdf') return 'application/pdf';
    if (ext == 'doc') return 'application/msword';
    if (ext == 'docx') {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (ext == 'xls') return 'application/vnd.ms-excel';
    if (ext == 'xlsx') {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (ext == 'ppt') return 'application/vnd.ms-powerpoint';
    if (ext == 'pptx') {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (ext == 'txt') return 'text/plain';

    // 压缩包类型
    if (ext == 'zip') return 'application/zip';
    if (ext == 'rar') return 'application/x-rar-compressed';
    if (ext == '7z') return 'application/x-7z-compressed';
    if (ext == 'tar') return 'application/x-tar';
    if (ext == 'gz') return 'application/gzip';

    // APK
    if (ext == 'apk') return 'application/vnd.android.package-archive';

    // 默认类型
    return '*/*';
  }
}
