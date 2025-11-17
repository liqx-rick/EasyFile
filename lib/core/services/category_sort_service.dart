import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/data/models/file_item.dart';

/// 排序类型
enum SortType {
  name,          // 按名称排序
  modifiedTime,  // 按修改时间排序
  size,          // 按文件大小排序
}

/// 全局类别文件排序服务
/// 管理所有类别页面的排序状态，一次设置，所有页面同步
class CategorySortService extends ChangeNotifier {
  static final CategorySortService _instance = CategorySortService._internal();
  factory CategorySortService() => _instance;
  
  CategorySortService._internal();

  static const String _sortTypeKey = 'category_sort_type';
  SortType _sortType = SortType.modifiedTime; // 默认按修改时间排序
  bool _initialized = false;

  /// 当前排序类型
  SortType get sortType => _sortType;

  /// 初始化，从本地存储加载排序类型
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedType = prefs.getString(_sortTypeKey);
      
      if (savedType != null) {
        _sortType = SortType.values.firstWhere(
          (e) => e.toString() == savedType,
          orElse: () => SortType.modifiedTime,
        );
      }
      
      _initialized = true;
      notifyListeners();
    } catch (e) {
      _sortType = SortType.modifiedTime;
      _initialized = true;
    }
  }

  /// 设置排序类型
  void setSortType(SortType type) {
    if (_sortType != type) {
      _sortType = type;
      _saveSortType();
      notifyListeners();
    }
  }

  /// 获取排序比较函数
  int Function(FileItem, FileItem) getComparator() {
    switch (_sortType) {
      case SortType.name:
        return (a, b) => a.name.compareTo(b.name);
      case SortType.modifiedTime:
        return (a, b) => b.modified.compareTo(a.modified); // 新的在前
      case SortType.size:
        return (a, b) => b.size.compareTo(a.size); // 大的在前
    }
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
    }
  }

  /// 保存排序类型到本地
  Future<void> _saveSortType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sortTypeKey, _sortType.toString());
    } catch (e) {
      // 忽略保存错误
    }
  }
}
