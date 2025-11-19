/// 文件大小格式化工具类
///
/// 提供统一的文件大小和存储空间格式化方法
class FileSizeFormatter {
  FileSizeFormatter._();

  /// 格式化文件大小（字节）
  ///
  /// 将字节数转换为人类可读的格式：
  /// - < 1KB: 显示为 B
  /// - < 1MB: 显示为 KB (保留1位小数)
  /// - < 1GB: 显示为 MB (保留1位小数)
  /// - >= 1GB: 显示为 GB (保留1位小数)
  ///
  /// [bytes] 文件大小（字节）
  /// 返回格式化后的字符串，如 "1.5 MB"
  static String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
  }

  /// 格式化文件大小（字节）- 带空格版本
  ///
  /// 与 [formatBytes] 相同，但数字和单位之间有空格
  ///
  /// [bytes] 文件大小（字节）
  /// 返回格式化后的字符串，如 "1.5 MB"
  static String formatBytesWithSpace(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// 格式化存储空间大小（MB）
  ///
  /// 用于格式化存储空间，输入单位为MB（DiskSpacePlus返回的单位）
  /// - < 1GB: 显示为 MB (保留0位小数)
  /// - >= 1GB: 显示为 GB (保留1位小数)
  ///
  /// [sizeInMB] 存储空间大小（MB）
  /// [loadingText] 当值为null或0时显示的文本，默认为 "加载中"
  /// 返回格式化后的字符串，如 "256.5 GB"
  static String formatStorageSize(
    double? sizeInMB, {
    String loadingText = '加载中',
  }) {
    if (sizeInMB == null || sizeInMB == 0) {
      return loadingText;
    }

    final sizeInGB = sizeInMB / 1024;

    if (sizeInGB < 1) {
      return '${sizeInMB.toStringAsFixed(0)} MB';
    }
    return '${sizeInGB.toStringAsFixed(1)} GB';
  }

  /// 计算多个文件的总大小
  ///
  /// [sizes] 文件大小列表（字节）
  /// 返回总大小（字节）
  static int calculateTotalSize(List<int> sizes) {
    return sizes.fold<int>(0, (sum, size) => sum + size);
  }

  /// 格式化多个文件的总大小
  ///
  /// 便捷方法，结合了计算总大小和格式化
  ///
  /// [sizes] 文件大小列表（字节）
  /// [withSpace] 是否在数字和单位之间添加空格，默认为 false
  /// 返回格式化后的总大小字符串
  static String formatTotalSize(List<int> sizes, {bool withSpace = false}) {
    final totalSize = calculateTotalSize(sizes);
    return withSpace
        ? formatBytesWithSpace(totalSize)
        : formatBytes(totalSize);
  }
}
