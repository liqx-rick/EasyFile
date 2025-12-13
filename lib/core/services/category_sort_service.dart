import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/utils/file_utils.dart';

/// 排序类型
enum SortType {
  name, // 按名称排序
  modifiedTime, // 按修改时间排序
  size, // 按文件大小排序
  fileType, // 按文件类型排序
}

/// 全局类别文件排序服务
/// 管理所有类别页面的排序状态，一次设置，所有页面同步
class CategorySortService extends ChangeNotifier {
  static final CategorySortService _instance = CategorySortService._internal();
  factory CategorySortService() => _instance;

  CategorySortService._internal();

  static const String _sortTypeKey = 'category_sort_type';
  static const String _sortAscendingKey = 'category_sort_ascending';

  SortType _sortType = SortType.modifiedTime; // 默认按修改时间排序
  bool _isAscending = false; // 默认降序
  bool _initialized = false;

  /// 当前排序类型
  SortType get sortType => _sortType;

  /// 当前排序方向：true=升序，false=降序
  bool get isAscending => _isAscending;

  /// 初始化，从本地存储加载排序类型和方向
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedType = prefs.getString(_sortTypeKey);
      final savedAscending = prefs.getBool(_sortAscendingKey);

      if (savedType != null) {
        _sortType = SortType.values.firstWhere(
          (e) => e.toString() == savedType,
          orElse: () => SortType.modifiedTime,
        );
      }

      if (savedAscending != null) {
        _isAscending = savedAscending;
      }

      _initialized = true;
      notifyListeners();
    } catch (e) {
      _sortType = SortType.modifiedTime;
      _isAscending = false;
      _initialized = true;
    }
  }

  /// 设置排序类型
  void setSortType(SortType type) {
    if (_sortType != type) {
      _sortType = type;
      _isAscending = false; // 切换排序类型时重置为降序
      _saveSortSettings();
      notifyListeners();
    }
  }

  /// 切换排序方向
  void toggleSortDirection() {
    _isAscending = !_isAscending;
    _saveSortSettings();
    notifyListeners();
  }

  /// 设置排序方向
  void setSortDirection(bool ascending) {
    if (_isAscending != ascending) {
      _isAscending = ascending;
      _saveSortSettings();
      notifyListeners();
    }
  }

  /// 获取文件类型优先级（数字越小优先级越高）
  int _getFileTypePriority(FileItem file) {
    if (file.isDirectory) return 0; // 文件夹最优先

    final fileName = file.name;
    if (FileUtils.isImageFile(fileName)) return 1;
    if (FileUtils.isVideoFile(fileName)) return 2;
    if (FileUtils.isAudioFile(fileName)) return 3;
    if (FileUtils.isDocumentFile(fileName)) return 4;
    if (FileUtils.isTextFile(fileName)) return 5;
    if (FileUtils.isArchiveFile(fileName)) return 6;
    return 7; // 其他文件
  }

  /// 获取排序比较函数
  int Function(FileItem, FileItem) getComparator() {
    int Function(FileItem, FileItem) baseComparator;

    switch (_sortType) {
      case SortType.name:
        baseComparator = (a, b) => a.name.compareTo(b.name);
        break;
      case SortType.modifiedTime:
        baseComparator = (a, b) => b.modified.compareTo(a.modified); // 新的在前
        break;
      case SortType.size:
        baseComparator = (a, b) => b.size.compareTo(a.size); // 大的在前
        break;
      case SortType.fileType:
        baseComparator = (a, b) {
          final typeComparison =
              _getFileTypePriority(a) - _getFileTypePriority(b);
          if (typeComparison != 0) return typeComparison;
          return a.name.compareTo(b.name); // 同类型按名称排序
        };
        break;
    }

    // 如果是升序，反转比较结果
    if (_isAscending) {
      return (a, b) => -baseComparator(a, b);
    }
    return baseComparator;
  }

  /// 获取排序类型的显示名称
  String getSortTypeName() {
    switch (_sortType) {
      case SortType.name:
        return '按名称排序';
      case SortType.modifiedTime:
        return '按修改时间排序';
      case SortType.size:
        return '按文件大小排序';
      case SortType.fileType:
        return '按文件类型排序';
    }
  }

  /// 保存排序设置到本地
  Future<void> _saveSortSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sortTypeKey, _sortType.toString());
      await prefs.setBool(_sortAscendingKey, _isAscending);
    } catch (e) {
      // 忽略保存错误
    }
  }
}
