import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/file_category.dart';

/// 文件类型统计信息
class FileTypeStats {
  final Map<FileCategory, int> counts;
  final int totalFileCount;
  final int totalDirectoryCount;

  FileTypeStats({
    required this.counts,
    required this.totalFileCount,
    required this.totalDirectoryCount,
  });

  /// 获取总数（文件+文件夹）
  int get totalCount => totalFileCount + totalDirectoryCount;

  /// 获取某个分类的数量
  int getCount(FileCategory category) {
    if (category == FileCategory.all) return totalCount;
    return counts[category] ?? 0;
  }

  /// 获取需要显示的分类列表（数量>0，按数量排序）
  List<FileCategory> getVisibleCategories({int maxCount = 6}) {
    final visibleCategories = counts.entries
        .where((entry) => entry.key != FileCategory.all && entry.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value)); // 按数量降序

    return visibleCategories.take(maxCount).map((e) => e.key).toList();
  }

  /// 是否有多个文件类型（是否需要显示Tab）
  bool get hasMultipleTypes {
    final nonZeroCategories = counts.entries.where((e) => e.value > 0).length;
    return nonZeroCategories > 1;
  }
}

/// 文件类型分析服务
class FileTypeAnalyzer {
  /// 分析文件列表，生成统计信息
  FileTypeStats analyze(List<FileItem> items) {
    final counts = <FileCategory, int>{};
    int fileCount = 0;
    int directoryCount = 0;

    for (final item in items) {
      if (item.isDirectory) {
        directoryCount++;
        continue;
      }

      fileCount++;
      final category = item.category;
      counts[category] = (counts[category] ?? 0) + 1;
    }

    return FileTypeStats(
      counts: counts,
      totalFileCount: fileCount,
      totalDirectoryCount: directoryCount,
    );
  }

  /// 根据分类筛选文件列表
  List<FileItem> filterByCategory(
    List<FileItem> items,
    FileCategory category, {
    bool hideFolders = false,
  }) {
    if (category == FileCategory.all) {
      // 创建新列表以避免与原列表共享引用
      return List<FileItem>.from(items);
    }

    return items.where((item) {
      // 需要隐藏文件夹时，直接过滤掉所有文件夹
      if (item.isDirectory && hideFolders) {
        return false;
      }
      // 文件夹显示（当不需要隐藏时）
      if (item.isDirectory) {
        return true;
      }
      // 文件按分类筛选
      return item.category == category;
    }).toList();
  }
}
