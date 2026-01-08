import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/core/config/app_config.dart';

/// 数据源辅助工具类（简化版）
///
/// 提供通用的文件过滤功能，避免在各数据源中重复实现
///
/// 注意：此类仅包含真正需要的功能，避免过度设计
class DataSourceHelpers {
  DataSourceHelpers._();

  /// 按支持的文件类型过滤（使用 FileTypesConfig）
  ///
  /// 过滤掉不支持的文件类型，确保只显示 FileTypesConfig 中定义的文件
  ///
  /// 参数：
  /// - files: 文件列表
  ///
  /// 返回：只包含支持类型的文件列表
  ///
  /// 示例：
  /// ```dart
  /// final supported = DataSourceHelpers.filterBySupportedTypes(allFiles);
  /// ```
  static List<FileItem> filterBySupportedTypes(List<FileItem> files) {
    final fileTypes = AppConfig.instance.fileTypes;

    return files.where((file) {
      final fileName = file.name;
      return fileTypes.isImageFile(fileName) ||
          fileTypes.isVideoFile(fileName) ||
          fileTypes.isAudioFile(fileName) ||
          fileTypes.isDocumentFile(fileName) ||
          fileTypes.isArchiveFile(fileName) ||
          fileTypes.isApkFile(fileName);
    }).toList();
  }

  /// 按文件类型过滤（用于 AppFilesDataSource 的 Tab 功能）
  ///
  /// 参数：
  /// - files: 文件列表
  /// - fileTypes: 文件扩展名列表（如 ['jpg', 'png', 'gif']）
  ///
  /// 返回：符合类型的文件列表
  ///
  /// 示例：
  /// ```dart
  /// final images = DataSourceHelpers.filterByFileTypes(
  ///   files,
  ///   fileTypes: ['jpg', 'png', 'gif'],
  /// );
  /// ```
  static List<FileItem> filterByFileTypes(
    List<FileItem> files, {
    required List<String> fileTypes,
  }) {
    if (fileTypes.isEmpty) return files;

    final lowerFileTypes = fileTypes.map((t) => t.toLowerCase()).toSet();

    return files.where((file) {
      final ext = FileUtils.getExtension(file.name);
      return lowerFileTypes.contains(ext);
    }).toList();
  }

  /// 按大小过滤（用于 LargeFilesDataSource）
  ///
  /// 参数：
  /// - files: 文件列表
  /// - minSize: 最小文件大小（字节），可选
  /// - maxSize: 最大文件大小（字节），可选
  ///
  /// 返回：符合大小范围的文件列表
  ///
  /// 示例：
  /// ```dart
  /// // 大于 100MB 的文件
  /// final largeFiles = DataSourceHelpers.filterBySize(
  ///   files,
  ///   minSize: 100 * 1024 * 1024,
  /// );
  /// ```
  static List<FileItem> filterBySize(
    List<FileItem> files, {
    int? minSize,
    int? maxSize,
  }) {
    return files.where((file) {
      if (minSize != null && file.size < minSize) return false;
      if (maxSize != null && file.size > maxSize) return false;
      return true;
    }).toList();
  }

  /// 按大小排序（用于 LargeFilesDataSource）
  ///
  /// 参数：
  /// - files: 文件列表（会被修改）
  /// - descending: 是否降序（默认 true，大文件在前）
  ///
  /// 示例：
  /// ```dart
  /// DataSourceHelpers.sortFilesBySize(largeFiles, descending: true);
  /// ```
  static void sortFilesBySize(
    List<FileItem> files, {
    bool descending = true,
  }) {
    files.sort((a, b) {
      final result = a.size.compareTo(b.size);
      return descending ? -result : result;
    });
  }

  /// 格式化文件大小（用于 LargeFilesDataSource 日志）
  ///
  /// 参数：
  /// - bytes: 字节数
  ///
  /// 返回：可读的大小字符串（如 "1.5 GB"）
  ///
  /// 示例：
  /// ```dart
  /// final sizeStr = DataSourceHelpers.formatSize(1536 * 1024 * 1024); // "1.50 GB"
  /// ```
  static String formatSize(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)}KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
    }
  }
}
