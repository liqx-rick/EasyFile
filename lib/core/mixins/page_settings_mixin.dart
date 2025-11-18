import 'package:flutter/material.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/services/category_sort_service.dart';

/// 页面设置Mixin
/// 为页面提供便捷的设置管理方法
mixin PageSettingsMixin<T extends StatefulWidget> on State<T> {
  /// 当前页面ID（子类必须实现）
  PageId get pageId;

  /// 页面设置服务
  late final PageSettingsService _settingsService = PageSettingsService();

  /// 是否已初始化页面设置
  bool _pageSettingsInitialized = false;

  /// 初始化页面设置
  @override
  void initState() {
    super.initState();
    _initializePageSettings();
  }

  /// 初始化页面设置并应用
  void _initializePageSettings() {
    if (_pageSettingsInitialized) return;

    // 设置当前页面
    _settingsService.setCurrentPage(pageId);

    // 应用页面设置到各个服务
    _applyPageSettings();

    // 监听设置变化
    _settingsService.addListener(_onSettingsChanged);

    _pageSettingsInitialized = true;
  }

  /// 应用页面设置
  void _applyPageSettings() {
    final settings = _settingsService.getPageSettings(pageId);

    // 应用视图模式
    if (settings.viewMode != null) {
      ViewModeService().setViewMode(settings.viewMode!);
    }

    // 应用排序类型
    if (settings.sortType != null) {
      CategorySortService().setSortType(settings.sortType!);
    }

    // 应用分组状态
    if (settings.groupEnabled != null) {
      CategoryGroupService().setGroupEnabled(settings.groupEnabled!);
    }
  }

  /// 设置变化回调
  void _onSettingsChanged() {
    if (_settingsService.currentPageId == pageId) {
      _applyPageSettings();
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _settingsService.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// 切换视图模式
  Future<void> toggleViewMode() async {
    await _settingsService.toggleViewMode(pageId);
  }

  /// 切换分组状态
  Future<void> toggleGroupEnabled() async {
    await _settingsService.toggleGroupEnabled(pageId);
  }

  /// 设置排序类型
  Future<void> setSortType(SortType sortType) async {
    await _settingsService.setSortType(pageId, sortType);
  }

  /// 获取当前视图模式
  ViewMode get currentViewMode => _settingsService.getViewMode(pageId);

  /// 获取当前排序类型
  SortType get currentSortType => _settingsService.getSortType(pageId);

  /// 获取当前分组状态
  bool get currentGroupEnabled => _settingsService.getGroupEnabled(pageId);

  /// 是否使用了自定义设置
  bool get hasCustomSettings => _settingsService.hasCustomSettings(pageId);
}

/// ViewMode 服务（兼容代码，实际从 PageSettingsService 读取）
class ViewModeService extends ChangeNotifier {
  static final ViewModeService _instance = ViewModeService._internal();
  factory ViewModeService() => _instance;
  ViewModeService._internal();

  ViewMode _viewMode = ViewMode.list;

  ViewMode get viewMode => _viewMode;
  bool get isGridView => _viewMode == ViewMode.grid;
  bool get isListView => _viewMode == ViewMode.list;

  Future<void> initialize() async {}

  void toggleViewMode() {
    _viewMode = _viewMode == ViewMode.list ? ViewMode.grid : ViewMode.list;
    notifyListeners();
  }

  void setViewMode(ViewMode mode) {
    if (_viewMode != mode) {
      _viewMode = mode;
      notifyListeners();
    }
  }
}

/// CategoryGroupService（兼容代码）
class CategoryGroupService extends ChangeNotifier {
  static final CategoryGroupService _instance =
      CategoryGroupService._internal();
  factory CategoryGroupService() => _instance;
  CategoryGroupService._internal();

  bool _groupEnabled = false;
  bool get isGroupEnabled => _groupEnabled;

  Future<void> initialize() async {}

  void toggleGroup() {
    _groupEnabled = !_groupEnabled;
    notifyListeners();
  }

  void setGroupEnabled(bool enabled) {
    if (_groupEnabled != enabled) {
      _groupEnabled = enabled;
      notifyListeners();
    }
  }
}
