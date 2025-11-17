import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局类别文件分组服务
/// 管理所有类别页面的分组状态，一次设置，所有页面同步
class CategoryGroupService extends ChangeNotifier {
  static final CategoryGroupService _instance = CategoryGroupService._internal();
  factory CategoryGroupService() => _instance;
  
  CategoryGroupService._internal();

  static const String _groupEnabledKey = 'category_group_enabled';
  bool _groupEnabled = false; // 默认不分组
  bool _initialized = false;

  /// 当前是否启用分组
  bool get isGroupEnabled => _groupEnabled;

  /// 初始化，从本地存储加载分组状态
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _groupEnabled = prefs.getBool(_groupEnabledKey) ?? false;
      
      _initialized = true;
      notifyListeners();
    } catch (e) {
      _groupEnabled = false;
      _initialized = true;
    }
  }

  /// 切换分组状态
  void toggleGroup() {
    _groupEnabled = !_groupEnabled;
    _saveGroupState();
    notifyListeners();
  }

  /// 设置分组状态
  void setGroupEnabled(bool enabled) {
    if (_groupEnabled != enabled) {
      _groupEnabled = enabled;
      _saveGroupState();
      notifyListeners();
    }
  }

  /// 保存分组状态到本地
  Future<void> _saveGroupState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_groupEnabledKey, _groupEnabled);
    } catch (e) {
      // 忽略保存错误
    }
  }
}
