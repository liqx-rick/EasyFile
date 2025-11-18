import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/services/category_sort_service.dart';

/// 页面设置管理服务
/// 管理各页面的视图模式、排序、分组设置
class PageSettingsService extends ChangeNotifier {
  static final PageSettingsService _instance =
      PageSettingsService._internal();
  factory PageSettingsService() => _instance;

  PageSettingsService._internal();

  static const String _userSettingsKey = 'page_user_settings';
  bool _initialized = false;

  /// 用户自定义的设置（覆盖默认值）
  Map<PageId, PageSettings> _userSettings = {};

  /// 当前活动的页面ID
  PageId? _currentPageId;

  /// 获取当前页面ID
  PageId? get currentPageId => _currentPageId;

  /// 初始化
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_userSettingsKey);

      if (jsonString != null) {
        final Map<String, dynamic> jsonMap = json.decode(jsonString);
        _userSettings = jsonMap.map(
          (key, value) => MapEntry(
            PageId.values.firstWhere((e) => e.key == key),
            PageSettings.fromJson(value as Map<String, dynamic>),
          ),
        );
      }

      _initialized = true;
    } catch (e) {
      _userSettings = {};
      _initialized = true;
    }
  }

  /// 设置当前页面
  void setCurrentPage(PageId pageId) {
    if (_currentPageId != pageId) {
      _currentPageId = pageId;
      notifyListeners();
    }
  }

  /// 获取页面的实际设置（用户设置 > 默认设置）
  PageSettings getPageSettings(PageId pageId) {
    final userSettings = _userSettings[pageId];
    final defaults = PageDefaultSettings.getDefaults(pageId);

    return PageSettings(
      viewMode: userSettings?.viewMode ?? defaults.viewMode,
      sortType: userSettings?.sortType ?? defaults.sortType,
      groupEnabled: userSettings?.groupEnabled ?? defaults.groupEnabled,
    );
  }

  /// 获取当前页面的视图模式
  ViewMode getViewMode(PageId pageId) {
    return getPageSettings(pageId).viewMode ?? ViewMode.list;
  }

  /// 获取当前页面的排序类型
  SortType getSortType(PageId pageId) {
    return getPageSettings(pageId).sortType ?? SortType.modifiedTime;
  }

  /// 获取当前页面的分组状态
  bool getGroupEnabled(PageId pageId) {
    return getPageSettings(pageId).groupEnabled ?? false;
  }

  /// 设置页面的视图模式
  Future<void> setViewMode(PageId pageId, ViewMode viewMode) async {
    final current = _userSettings[pageId] ?? const PageSettings();
    _userSettings[pageId] = current.copyWith(viewMode: viewMode);
    await _saveUserSettings();
    notifyListeners();
  }

  /// 设置页面的排序类型
  Future<void> setSortType(PageId pageId, SortType sortType) async {
    final current = _userSettings[pageId] ?? const PageSettings();
    _userSettings[pageId] = current.copyWith(sortType: sortType);
    await _saveUserSettings();
    notifyListeners();
  }

  /// 设置页面的分组状态
  Future<void> setGroupEnabled(PageId pageId, bool enabled) async {
    final current = _userSettings[pageId] ?? const PageSettings();
    _userSettings[pageId] = current.copyWith(groupEnabled: enabled);
    await _saveUserSettings();
    notifyListeners();
  }

  /// 切换页面的视图模式
  Future<void> toggleViewMode(PageId pageId) async {
    final current = getViewMode(pageId);
    final newMode = current == ViewMode.list ? ViewMode.grid : ViewMode.list;
    await setViewMode(pageId, newMode);
  }

  /// 切换页面的分组状态
  Future<void> toggleGroupEnabled(PageId pageId) async {
    final current = getGroupEnabled(pageId);
    await setGroupEnabled(pageId, !current);
  }

  /// 恢复所有页面为推荐设置
  Future<void> resetToDefaults() async {
    _userSettings.clear();
    await _saveUserSettings();
    notifyListeners();
  }

  /// 恢复单个页面为推荐设置
  Future<void> resetPage(PageId pageId) async {
    _userSettings.remove(pageId);
    await _saveUserSettings();
    notifyListeners();
  }

  /// 检查页面是否使用了自定义设置
  bool hasCustomSettings(PageId pageId) {
    return _userSettings.containsKey(pageId);
  }

  /// 保存用户设置到本地
  Future<void> _saveUserSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonMap = _userSettings.map(
        (key, value) => MapEntry(key.key, value.toJson()),
      );
      await prefs.setString(_userSettingsKey, json.encode(jsonMap));
    } catch (e) {
      // 忽略保存错误
    }
  }

  /// 获取所有页面的设置（用于设置页面展示）
  Map<PageId, PageSettings> getAllPageSettings() {
    return Map.fromEntries(
      PageId.values.map((pageId) => MapEntry(pageId, getPageSettings(pageId))),
    );
  }
}
