import 'package:flutter/material.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/favorite_item.dart';

/// Tab 视图类型
enum TabView {
  recent, // 最近访问
  browse, // 文件浏览
}

/// 视图模式
enum ViewMode {
  list, // 列表视图
  grid, // 网格视图
}

class FileViewModel extends ChangeNotifier {
  bool _isLoading = false;
  List<FileItem> _files = [];
  String _currentPath = '';
  String _rootPath = ''; // 导航起始路径（收藏夹根路径或最近文件模式的空路径）
  bool _isSearchMode = false;
  String _searchQuery = '';
  bool _isRecentFilesMode = false;

  // 应用级状态
  List<FavoriteItem> _favorites = [];
  ThemeMode _themeMode = ThemeMode.system;
  TabView _currentTab = TabView.recent;
  ViewMode _viewMode = ViewMode.list;

  // 基础状态的 getters
  bool get isLoading => _isLoading;
  List<FileItem> get files => _files;
  String get currentPath => _currentPath;
  String get rootPath => _rootPath; // 获取根路径
  bool get isSearchMode => _isSearchMode;
  String get searchQuery => _searchQuery;
  bool get isRecentFilesMode => _isRecentFilesMode;

  // 应用级状态的 getters
  List<FavoriteItem> get favorites => _favorites;
  ThemeMode get themeMode => _themeMode;
  TabView get currentTab => _currentTab;
  ViewMode get viewMode => _viewMode;

  /// 获取当前路径的显示名称
  String get currentPathName {
    if (_currentPath.isEmpty) return '正在加载...';

    final segments = _currentPath.split(RegExp(r'[/\\]'));
    final lastSegment = segments.last;

    if (lastSegment.isEmpty && segments.length > 1) {
      return segments[segments.length - 2];
    }

    return lastSegment.isEmpty ? '根目录' : lastSegment;
  }

  void setLoading(bool value) {
    logger.d('Setting loading state: $value');
    _isLoading = value;
    notifyListeners();
  }

  void setFiles(List<FileItem> files) {
    logger.d('Setting files list: ${files.length} items');
    _files = files;
    notifyListeners();
  }

  void setCurrentPath(String path) {
    logger.d('Setting current path: $path');
    _currentPath = path;
    notifyListeners();
  }

  void setRootPath(String path) {
    logger.d('Setting root path: $path');
    _rootPath = path;
    notifyListeners();
  }

  void setSearchMode(bool value) {
    logger.d('Setting search mode: $value');
    _isSearchMode = value;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    logger.d('Setting search query: $query');
    _searchQuery = query;
    notifyListeners();
  }

  // 收藏夹相关方法
  void setFavorites(List<FavoriteItem> favorites) {
    logger.d('Setting favorites list: ${favorites.length} items');
    _favorites = _sortedFavorites(favorites);
    notifyListeners();
  }

  void addFavorite(FavoriteItem favorite) {
    logger.d('Adding favorite: ${favorite.name}');
    if (!_favorites.any((f) => f.path == favorite.path)) {
      _favorites.add(favorite);
      _favorites = _sortedFavorites(_favorites);
      notifyListeners();
    }
  }

  void removeFavorite(String id) {
    logger.d('Removing favorite with id: $id');
    _favorites.removeWhere((f) => f.id == id);
    notifyListeners();
  }

  void updateFavorite(FavoriteItem updatedFavorite) {
    logger.d('Updating favorite: ${updatedFavorite.name}');
    final index = _favorites.indexWhere((f) => f.id == updatedFavorite.id);
    if (index != -1) {
      _favorites[index] = updatedFavorite;
      _favorites = _sortedFavorites(_favorites);
      notifyListeners();
    }
  }

  // 统一的收藏排序：置顶优先，其次名称 A-Z
  List<FavoriteItem> _sortedFavorites(List<FavoriteItem> list) {
    final copy = [...list];
    copy.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return copy;
  }

  // 主题相关方法
  void setThemeMode(ThemeMode mode) {
    logger.d('Setting theme mode: $mode');
    _themeMode = mode;
    notifyListeners();
  }

  void toggleTheme() {
    logger.d('Toggling theme from $_themeMode');
    // 三模式循环：light → dark → system → light
    switch (_themeMode) {
      case ThemeMode.light:
        _themeMode = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        _themeMode = ThemeMode.system;
        break;
      case ThemeMode.system:
        _themeMode = ThemeMode.light;
        break;
    }
    notifyListeners();
  }

  // 搜索相关方法
  void toggleSearchMode() {
    logger.d('Toggling search mode from $_isSearchMode');
    _isSearchMode = !_isSearchMode;
    if (!_isSearchMode) {
      _searchQuery = '';
    }
    notifyListeners();
  }

  void clearSearch() {
    logger.d('Clearing search mode');
    _isSearchMode = false;
    _searchQuery = '';
    notifyListeners();
  }

  void setIsRecentFilesMode(bool isRecent) {
    logger.d('Setting recent files mode: $isRecent');
    _isRecentFilesMode = isRecent;
    notifyListeners();
  }

  /// 设置错误信息
  void setError(String message) {
    logger.e('ViewModel error: $message');
    // 可以在这里添加错误状态的处理
  }

  // Tab 和视图模式相关方法
  void setCurrentTab(TabView tab) {
    logger.d('Setting current tab: $tab');
    _currentTab = tab;
    notifyListeners();
  }

  void setViewMode(ViewMode mode) {
    logger.d('Setting view mode: $mode');
    _viewMode = mode;
    notifyListeners();
  }

  void toggleViewMode() {
    logger.d('Toggling view mode from $_viewMode');
    _viewMode = _viewMode == ViewMode.list ? ViewMode.grid : ViewMode.list;
    notifyListeners();
  }
}
