import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/services/category_sort_service.dart';

/// 页面设置管理服务
/// 管理各页面的视图模式、排序、分组设置
class PageSettingsService extends ChangeNotifier {
  static final PageSettingsService _instance = PageSettingsService._internal();
  factory PageSettingsService() => _instance;

  PageSettingsService._internal();

  static const String _userSettingsKey = 'page_user_settings';
  static const String _gridShowFileInfoKey = 'grid_show_file_info';
  static const String _settingsVersionKey = 'page_settings_version';
  static const int _currentSettingsVersion = 3; // 版本3: 强制重置压缩包页面排序
  bool _initialized = false;

  /// 用户自定义的设置（覆盖默认值）
  Map<PageId, PageSettings> _userSettings = {};

  /// 网格模式是否显示文件信息（文件名和大小）
  /// 默认：图片和视频分类为false（简洁模式），其他为true
  bool? _gridShowFileInfo;

  /// 当前活动的页面ID
  PageId? _currentPageId;

  /// 获取当前页面ID
  PageId? get currentPageId => _currentPageId;

  /// 初始化
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 检查设置版本
      final savedVersion = prefs.getInt(_settingsVersionKey) ?? 1;
      
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
      
      
      // 版本迁移：修复压缩包页面的默认排序
      if (savedVersion < 3) {
        debugPrint('[PageSettings] Migration: Upgrading from version $savedVersion to $_currentSettingsVersion');
        debugPrint('[PageSettings] Migration: Force resetting archiveManagement to default sort');
        // 强制设置压缩包页面为默认排序（按时间降序）
        _userSettings.remove(PageId.archiveManagement);
        await _saveUserSettings();
        await prefs.setInt(_settingsVersionKey, _currentSettingsVersion);
        debugPrint('[PageSettings] Migration: Completed, archiveManagement will use default: SortType.modifiedTime, ascending=false');
      } else {
        debugPrint('[PageSettings] Current version: $savedVersion (up to date)');
      }

      // 加载网格文件信息显示偏好
      _gridShowFileInfo = prefs.getBool(_gridShowFileInfoKey);

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
      sortAscending: userSettings?.sortAscending ?? defaults.sortAscending,
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

  /// 获取当前页面的排序方向
  bool getSortAscending(PageId pageId) {
    return getPageSettings(pageId).sortAscending ?? false;
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
    _userSettings[pageId] = current.copyWith(
      sortType: sortType,
      sortAscending: false, // 切换排序类型时重置为降序
    );
    await _saveUserSettings();
    notifyListeners();
  }

  /// 设置页面的排序方向
  Future<void> setSortAscending(PageId pageId, bool ascending) async {
    final current = _userSettings[pageId] ?? const PageSettings();
    _userSettings[pageId] = current.copyWith(sortAscending: ascending);
    await _saveUserSettings();
    notifyListeners();
  }

  /// 切换页面的排序方向
  Future<void> toggleSortDirection(PageId pageId) async {
    final current = getSortAscending(pageId);
    await setSortAscending(pageId, !current);
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
    // 清理图片缓存，减少内存占用
    try {
      final imageCache = PaintingBinding.instance.imageCache;
      imageCache.clear();
      imageCache.clearLiveImages();
    } catch (e) {
      // 忽略清理错误
    }

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

  /// 恢复推荐页面设置
  Future<void> resetRecommendSettings() async {
    _userSettings.removeWhere((pageId, _) =>
        pageId == PageId.recommendApplication ||
        pageId == PageId.recommendContent ||
        pageId == PageId.recommendCleanup);

    // 保存设置
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonMap = _userSettings.map(
        (key, value) => MapEntry(key.key, value.toJson()),
      );
      await prefs.setString(_userSettingsKey, json.encode(jsonMap));
    } catch (e) {
      // 忽略保存错误
    }

    notifyListeners();
  }

  /// 获取网格模式是否显示文件信息
  /// [pageId] 页面ID（保留用于兼容性，实际未使用）
  /// 返回：true=显示文件名和大小，false=仅显示缩略图
  bool getGridShowFileInfo(PageId pageId) {
    // 如果用户设置过，使用用户设置
    if (_gridShowFileInfo != null) {
      return _gridShowFileInfo!;
    }

    // 默认行为：图片和视频默认不显示文件信息（简洁模式）
    // 此方法只在判断图片/视频文件时被调用，不影响其他文件类型
    return false;
  }

  /// 设置网格模式是否显示文件信息
  Future<void> setGridShowFileInfo(bool show) async {
    _gridShowFileInfo = show;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_gridShowFileInfoKey, show);
      notifyListeners();
    } catch (e) {
      // 忽略保存错误
    }
  }
}
