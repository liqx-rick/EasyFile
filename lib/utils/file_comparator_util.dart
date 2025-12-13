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
  ///
  /// [sortType] 排序类型
  /// [ascending] 排序方向：true=升序，false=降序（默认）
  ///
  /// 标准的排序定义：
  /// - 升序（↑）：A→Z, 小→大, 旧→新（数值递增）
  /// - 降序（↓）：Z→A, 大→小, 新→旧（数值递减）
  ///
  /// 各排序类型的默认值（ascending=false）：
  /// - 按名称：默认升序 A-Z（文件管理器习惯）
  /// - 按时间：默认降序 新的在前（文件管理器习惯）
  /// - 按大小：默认降序 大的在前（文件管理器习惯）
  static Comparator<FileItem> getComparator(SortType sortType,
      {bool ascending = false}) {
    switch (sortType) {
      case SortType.name:
        // 按名称：默认A-Z（升序），切换后Z-A（降序）
        return ascending
            ? (a, b) => _compareByNameDescending(a, b)
            : (a, b) => _compareByNameAscending(a, b);
      case SortType.modifiedTime:
        // 按时间：默认新的在前（降序），切换后旧的在前（升序）
        return ascending
            ? (a, b) => _compareByModifiedTimeAscending(a, b)
            : (a, b) => _compareByModifiedTimeDescending(a, b);
      case SortType.size:
        // 按大小：默认大的在前（降序），切换后小的在前（升序）
        return ascending
            ? (a, b) => _compareBySizeAscending(a, b)
            : (a, b) => _compareBySizeDescending(a, b);
      case SortType.fileType:
        // 按类型：默认A-Z（升序），切换后Z-A（降序）
        return ascending
            ? (a, b) => _compareByFileTypeDescending(a, b)
            : (a, b) => _compareByFileTypeAscending(a, b);
    }
  }

  /// 按名称升序排序（A-Z，文件夹优先）
  static int _compareByNameAscending(FileItem a, FileItem b) {
    // 文件夹优先
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    // 同类型按名称排序，使用 compareTo 比较 Unicode（支持中文）
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// 按名称降序排序（Z-A，文件夹优先）
  static int _compareByNameDescending(FileItem a, FileItem b) {
    // 文件夹优先
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    // 同类型按名称降序排序
    return b.name.toLowerCase().compareTo(a.name.toLowerCase());
  }

  /// 按修改时间降序排序（文件夹优先，新的在前）
  static int _compareByModifiedTimeDescending(FileItem a, FileItem b) {
    // 文件夹优先
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    // 同类型按修改时间排序（新的在前）
    return b.modified.compareTo(a.modified);
  }

  /// 按修改时间升序排序（文件夹优先，旧的在前）
  static int _compareByModifiedTimeAscending(FileItem a, FileItem b) {
    // 文件夹优先
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    // 同类型按修改时间排序（旧的在前）
    return a.modified.compareTo(b.modified);
  }

  /// 按文件大小降序排序（文件夹优先，大的在前）
  static int _compareBySizeDescending(FileItem a, FileItem b) {
    // 文件夹优先
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    // 同类型按大小排序（大的在前）
    return b.size.compareTo(a.size);
  }

  /// 按文件大小升序排序（文件夹优先，小的在前）
  static int _compareBySizeAscending(FileItem a, FileItem b) {
    // 文件夹优先
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    // 同类型按大小排序（小的在前）
    return a.size.compareTo(b.size);
  }

  /// 按文件类型升序排序（文件夹优先，然后按扩展名A-Z）
  static int _compareByFileTypeAscending(FileItem a, FileItem b) {
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

  /// 按文件类型降序排序（文件夹优先，然后按扩展名Z-A）
  static int _compareByFileTypeDescending(FileItem a, FileItem b) {
    // 文件夹优先
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    // 获取文件扩展名
    final extA = _getFileExtension(a.name);
    final extB = _getFileExtension(b.name);

    // 没有扩展名的排在后面
    if (extA.isEmpty && extB.isNotEmpty) return 1;
    if (extA.isNotEmpty && extB.isEmpty) return -1;

    // 按扩展名降序排序
    final extCompare = extB.compareTo(extA);
    if (extCompare != 0) return extCompare;

    // 扩展名相同时按名称降序排序
    return b.name.toLowerCase().compareTo(a.name.toLowerCase());
  }

  /// 获取文件扩展名（小写）
  static String _getFileExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) return '';
    return fileName.substring(lastDot + 1).toLowerCase();
  }

  /// 对文件列表进行排序（返回新列表）
  ///
  /// [files] 待排序的文件列表
  /// [sortType] 排序类型
  /// [ascending] 排序方向：true=升序，false=降序（默认）
  static List<FileItem> sortFiles(List<FileItem> files, SortType sortType,
      {bool ascending = false}) {
    final result = List<FileItem>.from(files);
    result.sort(getComparator(sortType, ascending: ascending));
    return result;
  }

  /// 对文件列表进行原地排序
  ///
  /// [files] 待排序的文件列表
  /// [sortType] 排序类型
  /// [ascending] 排序方向：true=升序，false=降序（默认）
  static void sortFilesInPlace(List<FileItem> files, SortType sortType,
      {bool ascending = false}) {
    files.sort(getComparator(sortType, ascending: ascending));
  }
}
