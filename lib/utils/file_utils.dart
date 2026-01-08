import 'package:easyfile/core/config/app_config.dart';

/// 文件工具类
///
/// 提供文件类型判断、大小格式化等实用方法
///
/// 注意：文件类型判断方法已重构为委托给 FileTypesConfig
/// 所有扩展名列表统一由配置管理，支持远程更新和会员扩展
class FileUtils {
  // 懒加载配置引用
  static dynamic get _config => AppConfig.instance.fileTypes;

  // ==================== 文件类型判断方法 ====================

  /// 判断文件是否为图片类型
  static bool isImageFile(String fileName) => _config.isImageFile(fileName);

  /// 判断文件是否为视频类型
  static bool isVideoFile(String fileName) => _config.isVideoFile(fileName);

  /// 判断文件是否为音频类型
  static bool isAudioFile(String fileName) => _config.isAudioFile(fileName);

  /// 判断文件是否为PDF类型
  static bool isPdfFile(String fileName) => _config.isPdfFile(fileName);

  /// 判断文件是否为Word文档类型
  static bool isWordFile(String fileName) {
    final ext = getExtension(fileName);
    return _config.getWordExtensions().contains(ext);
  }

  /// 判断文件是否为Excel表格类型
  static bool isExcelFile(String fileName) {
    final ext = getExtension(fileName);
    return _config.getExcelExtensions().contains(ext);
  }

  /// 判断文件是否为PowerPoint演示文稿类型
  static bool isPowerPointFile(String fileName) {
    final ext = getExtension(fileName);
    return _config.getPptExtensions().contains(ext);
  }

  /// 判断文件是否为文本文件类型
  static bool isTextFile(String fileName) {
    final ext = getExtension(fileName);
    return _config.getTextExtensions().contains(ext);
  }

  /// 判断文件是否为压缩文件类型
  static bool isArchiveFile(String fileName) => _config.isArchiveFile(fileName);

  /// 判断文件是否为文档类型（PDF, Word, Excel, PPT）
  static bool isDocumentFile(String fileName) =>
      _config.isDocumentFile(fileName);

  // ==================== 文件大小格式化 ====================

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

  // ==================== MIME 类型获取 ====================

  /// 根据文件路径获取MIME类型
  ///
  /// 用于Android分享等需要精确MIME类型的场景
  static String getMimeType(String filePath) {
    return _config.getMimeType(filePath);
  }

  // ==================== 文件扩展名提取 ====================

  /// 从文件名中提取扩展名（小写，无点）
  ///
  /// 示例：
  /// - "photo.jpg" → "jpg"
  /// - "document.PDF" → "pdf"
  /// - "file" → ""
  static String getExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) {
      return '';
    }
    return fileName.substring(lastDot + 1).toLowerCase();
  }
}
