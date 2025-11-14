class FileUtils {
  /// 判断文件是否为图片类型
  static bool isImageFile(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
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
    return ['xls', 'xlsx'].contains(ext);
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
      'csv',
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
}
