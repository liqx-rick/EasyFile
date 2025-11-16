import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';

/// 全局视图模式服务
/// 管理应用级别的视图模式状态，所有页面共享同一个视图模式
class ViewModeService extends ChangeNotifier {
  static final ViewModeService _instance = ViewModeService._internal();
  factory ViewModeService() => _instance;
  
  ViewModeService._internal();

  static const String _viewModeKey = 'global_view_mode';
  ViewMode _viewMode = ViewMode.list;
  bool _initialized = false;

  /// 当前视图模式
  ViewMode get viewMode => _viewMode;

  /// 是否为网格视图
  bool get isGridView => _viewMode == ViewMode.grid;

  /// 是否为列表视图
  bool get isListView => _viewMode == ViewMode.list;

  /// 初始化，从本地存储加载视图模式
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_viewModeKey);
      
      if (savedMode != null) {
        _viewMode = savedMode == 'grid' ? ViewMode.grid : ViewMode.list;
      }
      
      _initialized = true;
      notifyListeners();
    } catch (e) {
      // 如果加载失败，使用默认值
      _viewMode = ViewMode.list;
      _initialized = true;
    }
  }

  /// 切换视图模式
  void toggleViewMode() {
    _viewMode = _viewMode == ViewMode.list ? ViewMode.grid : ViewMode.list;
    _saveViewMode();
    notifyListeners();
  }

  /// 设置视图模式
  void setViewMode(ViewMode mode) {
    if (_viewMode != mode) {
      _viewMode = mode;
      _saveViewMode();
      notifyListeners();
    }
  }

  /// 保存视图模式到本地
  Future<void> _saveViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _viewModeKey,
        _viewMode == ViewMode.grid ? 'grid' : 'list',
      );
    } catch (e) {
      // 忽略保存错误
    }
  }
}
