import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/services/category_sort_service.dart';

/// 文件排序比较器工具类
///
/// 提供统一的文件排序逻辑，所有页面共享
/// 遵循文件管理器通用规则：文件夹始终排在文件前面
class FileComparatorUtil {
  /// 根据排序类型获取比较器
  ///
  /// 所有排序类型都遵循"文件夹优先"原则：
  /// 1. 文件夹始终排在文件前面
  /// 2. 文件夹内部按指定规则排序
  /// 3. 文件内部按指定规则排序
  static Comparator<FileItem> getComparator(SortType sortType) {
    switch (sortType) {
      case SortType.name:
        return _compareByName;
      case SortType.modifiedTime:
        return _compareByModifiedTime;
      case SortType.size:
        return _compareBySize;
      case SortType.fileType:
        return _compareByFileType;
    }
  }

  /// 按名称排序（文件夹优先）
  static int _compareByName(FileItem a, FileItem b) {
    // 文件夹优先
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    // 同类型按名称排序（不区分大小写）
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// 按修改时间排序（文件夹优先，新的在前）
  static int _compareByModifiedTime(FileItem a, FileItem b) {
    // 文件夹优先
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    // 同类型按修改时间排序（新的在前）
    return b.modified.compareTo(a.modified);
  }

  /// 按文件大小排序（文件夹优先，大的在前）
  static int _compareBySize(FileItem a, FileItem b) {
    // 文件夹优先
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    // 同类型按大小排序（大的在前）
    return b.size.compareTo(a.size);
  }

  /// 按文件类型排序（文件夹优先，然后按扩展名）
  static int _compareByFileType(FileItem a, FileItem b) {
    // 文件夹优先
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    // 获取文件扩展名
    final extA = _getFileExtension(a.name);
    final extB = _getFileExtension(b.name);

    // 没有扩展名的排在后面
    if (extA.isEmpty && extB.isNotEmpty) return 1;
    if (extA.isNotEmpty && extB.isEmpty) return -1;

    // 按扩展名排序
    final extCompare = extA.compareTo(extB);
    if (extCompare != 0) return extCompare;

    // 扩展名相同时按名称排序
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// 获取文件扩展名（小写）
  static String _getFileExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) return '';
    return fileName.substring(lastDot + 1).toLowerCase();
  }

  /// 对文件列表进行排序（返回新列表）
  static List<FileItem> sortFiles(List<FileItem> files, SortType sortType) {
    final result = List<FileItem>.from(files);
    result.sort(getComparator(sortType));
    return result;
  }

  /// 对文件列表进行原地排序
  static void sortFilesInPlace(List<FileItem> files, SortType sortType) {
    files.sort(getComparator(sortType));
  }
}
