import 'package:flutter/material.dart';
import '../../utils/file_comparator_util.dart';
import '../../data/models/file_item.dart';
import '../../core/services/category_sort_service.dart';

/// 分类页面及其他文件聚合页面的通用 Mixin
///
/// 提供统一的：
/// - 搜索、筛选、排序状态管理
/// - 过滤文件列表的计算属性
/// - 排序逻辑调用
///
/// 子类必须实现：
/// - [searchQuery] getter：当前搜索查询
/// - [filterFile] 方法：文件筛选谓词
/// - [selectionController] getter (来自 EditModeMixin)
///
/// 示例：
/// ```dart
/// class MyPage extends State with CategoryLikePageMixin {
///   String get searchQuery => _searchController.text;
///
///   bool filterFile(FileItem file) {
///     // 返回 true 表示该文件应包含在结果中
///     return file.name.endsWith('.zip');
///   }
/// }
/// ```
mixin CategoryLikePageMixin<T extends StatefulWidget> on State<T> {
  /// 所有文件列表（原始，未过滤）
  ///
  /// 子类应在加载数据后直接赋值
  @protected
  List<FileItem> allFiles = [];

  /// 当前搜索查询
  ///
  /// 子类应通过 getter 实现，通常来自 TextEditingController
  @protected
  String get searchQuery;

  /// 文件筛选谓词
  ///
  /// 子类覆盖此方法以实现特定的文件筛选逻辑
  /// 例如：按格式筛选、按类型筛选等
  @protected
  bool filterFile(FileItem file) => true;

  /// 过滤后的文件列表
  ///
  /// 应用了文件筛选和搜索过滤的文件列表
  /// 这是一个计算属性，会自动重新计算
  @protected
  List<FileItem> get filteredFiles {
    var result = allFiles;

    // 第一步：应用文件筛选
    result = result.where(filterFile).toList();

    // 第二步：应用搜索过滤
    if (searchQuery.isNotEmpty) {
      result = result.where((f) {
        return f.name.toLowerCase().contains(searchQuery.toLowerCase());
      }).toList();
    }

    return result;
  }

  /// 应用排序到文件列表
  ///
  /// 这是一个工具方法，使用 FileComparatorUtil 进行排序
  /// 子类应在 setState() 中调用此方法
  ///
  /// 示例：
  /// ```dart
  /// setState(() {
  ///   applySorting(allFiles, SortType.name, ascending: true);
  /// });
  /// ```
  @protected
  void applySorting(
    List<FileItem> files,
    SortType sortType, {
    bool ascending = true,
  }) {
    FileComparatorUtil.sortFilesInPlace(
      files,
      sortType,
      ascending: ascending,
    );
  }

  /// 按文件名搜索和排序
  ///
  /// 这是一个便捷方法，结合了搜索、筛选、排序
  /// 适用于简单场景
  @protected
  List<FileItem> getFilteredAndSortedFiles(SortType sortType,
      {bool ascending = true}) {
    var result = filteredFiles;
    applySorting(result, sortType, ascending: ascending);
    return result;
  }
}
