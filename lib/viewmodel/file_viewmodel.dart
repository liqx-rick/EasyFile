import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/favorite_item.dart';
import 'package:easyfile/data/models/favorite_file_item.dart';
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/data/services/file_type_analyzer.dart';

/// Tab 视图类型
enum TabView {
  recent, // 最近访问
  favorite, // 收藏文件
  browse, // 文件浏览
  appManagement, // 应用管理
}

/// 视图模式
enum ViewMode {
  list, // 列表视图
  grid, // 网格视图
}

class FileViewModel extends ChangeNotifier {
  bool _isLoading = false;
  List<FileItem> _files = [];
  List<FileItem> _allFiles = []; // 保存所有文件（未筛选）
  String _currentPath = '';
  String _rootPath = ''; // 导航起始路径（收藏夹根路径或最近文件模式的空路径）
  bool _isSearchMode = false;
  String _searchQuery = '';
  bool _isRecentFilesMode = false;
  String? _errorMessage; // 错误消息

  // 文件更新跟踪（用于页面同步更新）
  String? _lastUpdatedOldPath;
  FileItem? _lastUpdatedNewFile;

  // 文件类型筛选
  FileCategory _selectedCategory = FileCategory.all;
  final FileTypeAnalyzer _fileTypeAnalyzer = FileTypeAnalyzer();

  // 应用级状态
  List<FavoriteItem> _favorites = [];
  List<FavoriteFileItem> _favoriteFiles = []; // 收藏文件列表
  ThemeMode _themeMode = ThemeMode.system;
  TabView _currentTab = TabView.recent;
  ViewMode _viewMode = ViewMode.list;
  String? _lastBrowsePath; // 保存浏览模式下的最后路径

  // SharedPreferences keys
  static const String _keyCurrentTab = 'current_tab';
  static const String _keyLastBrowsePath = 'last_browse_path';
  static const String _keyThemeMode = 'theme_mode';

  FileViewModel() {
    _loadSavedState();
  }

  /// 从 SharedPreferences 加载保存的状态
  Future<void> _loadSavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载上次的 tab
      final savedTab = prefs.getString(_keyCurrentTab);
      if (savedTab != null) {
        _currentTab = TabView.values.firstWhere(
          (e) => e.toString() == savedTab,
          orElse: () => TabView.recent,
        );
        logger.d('Restored current tab: $_currentTab');
      }

      // 加载上次浏览的路径
      _lastBrowsePath = prefs.getString(_keyLastBrowsePath);
      if (_lastBrowsePath != null) {
        logger.d('Restored last browse path: $_lastBrowsePath');
      }

      // 加载主题模式
      final savedThemeMode = prefs.getString(_keyThemeMode);
      if (savedThemeMode != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (e) => e.toString() == savedThemeMode,
          orElse: () => ThemeMode.system,
        );
        logger.d('Restored theme mode: $_themeMode');
      }
    } catch (e) {
      logger.e('Error loading saved state: $e');
    }
  }

  /// 保存当前状态
  Future<void> _saveCurrentState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCurrentTab, _currentTab.toString());
      await prefs.setString(_keyThemeMode, _themeMode.toString());

      if (_currentTab == TabView.browse && _currentPath.isNotEmpty) {
        await prefs.setString(_keyLastBrowsePath, _currentPath);
      }

      logger.d(
          'Saved current state: tab=$_currentTab, path=$_currentPath, theme=$_themeMode');
    } catch (e) {
      logger.e('Error saving current state: $e');
    }
  }

  /// 重置到默认状态（新启动时使用）
  void resetToDefault() {
    logger.i('Resetting FileViewModel to default state');
    _currentTab = TabView.recent;
    _lastBrowsePath = null;
    _currentPath = '';
    _rootPath = '';
    _isRecentFilesMode = false;
    notifyListeners();
  }

  // 基础状态的 getters
  bool get isLoading => _isLoading;
  List<FileItem> get files => _files;
  String get currentPath => _currentPath;
  String get rootPath => _rootPath; // 获取根路径
  bool get isSearchMode => _isSearchMode;
  String get searchQuery => _searchQuery;
  bool get isRecentFilesMode => _isRecentFilesMode;

  // 文件更新跟踪的 getters
  String? get lastUpdatedOldPath => _lastUpdatedOldPath;
  FileItem? get lastUpdatedNewFile => _lastUpdatedNewFile;

  // 文件类型筛选的 getters
  FileCategory get selectedCategory => _selectedCategory;
  FileTypeStats get fileTypeStats => _fileTypeAnalyzer.analyze(_allFiles);
  FileTypeAnalyzer get fileTypeAnalyzer => _fileTypeAnalyzer;

  // 应用级状态的 getters
  List<FavoriteItem> get favorites => _favorites;
  List<FavoriteFileItem> get favoriteFiles => _favoriteFiles;
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
    logger.d('Setting files list: ${files.length} items for tab: $_currentTab');
    if (files.isNotEmpty) {
      logger.d('First 3 files: ${files.take(3).map((f) => f.name).join(", ")}');
    }
    _allFiles = files;
    _applyFilters();
  }

  /// 更新单个文件信息（用于重命名等操作后即时更新UI，无需重新加载列表）
  void updateFileInList(String oldPath, FileItem updatedFile) {
    logger.d('Updating file in list: $oldPath -> ${updatedFile.path}');

    // 记录本次更新，供页面监听器使用
    _lastUpdatedOldPath = oldPath;
    _lastUpdatedNewFile = updatedFile;

    // 更新 _allFiles
    final allIndex = _allFiles.indexWhere((f) => f.path == oldPath);
    if (allIndex != -1) {
      _allFiles[allIndex] = updatedFile;
      logger.d('Updated file in _allFiles at index $allIndex');
    }

    // 更新 _files
    final index = _files.indexWhere((f) => f.path == oldPath);
    if (index != -1) {
      _files[index] = updatedFile;
      logger.d('Updated file in _files at index $index');
      notifyListeners();
    } else {
      // 如果在过滤后的列表中找不到，可能是因为筛选条件，重新应用筛选
      _applyFilters();
    }
  }

  /// 添加文件到列表（用于复制操作后即时更新UI）
  void addFileToList(FileItem newFile) {
    logger.d('Adding file to list: ${newFile.path}');

    // 添加到 _allFiles 和 _files
    _allFiles.add(newFile);
    _files.add(newFile);

    // 按当前排序方式重新排序（文件夹优先，然后按名称）
    _files.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    _allFiles.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    logger.d('Added and sorted file in list');
    notifyListeners();
  }

  /// 从列表中移除文件（用于删除操作后即时更新UI）
  void removeFileFromList(String filePath) {
    logger.d('Removing file from list: $filePath');

    _allFiles.removeWhere((f) => f.path == filePath);
    _files.removeWhere((f) => f.path == filePath);

    logger.d('File removed, remaining: ${_files.length} items');
    notifyListeners();
  }

  /// 应用筛选条件
  void _applyFilters() {
    _files = _fileTypeAnalyzer.filterByCategory(_allFiles, _selectedCategory);
    logger.d(
        'After filters applied: ${_files.length} items (from ${_allFiles.length} total)');
    notifyListeners();
  }

  /// 设置选中的文件类型分类
  void setSelectedCategory(FileCategory category) {
    logger.d('Setting selected category: ${category.displayName}');
    if (_selectedCategory != category) {
      _selectedCategory = category;
      _applyFilters();
    }
  }

  /// 重置文件类型筛选
  void resetCategoryFilter() {
    if (_selectedCategory != FileCategory.all) {
      _selectedCategory = FileCategory.all;
      _applyFilters();
    }
  }

  void setCurrentPath(String path) {
    logger.d('Setting current path: $path');
    _currentPath = path;

    // 如果在浏览模式，保存当前路径
    if (_currentTab == TabView.browse && path.isNotEmpty) {
      _lastBrowsePath = path;
      _saveCurrentState();
    }

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

  // 收藏文件相关方法
  void setFavoriteFiles(List<FavoriteFileItem> favoriteFiles) {
    logger.d('Setting favorite files list: ${favoriteFiles.length} items');
    _favoriteFiles = _sortedFavoriteFiles(favoriteFiles);
    logger.d(
        'Favorite files after sorting: ${_favoriteFiles.map((f) => f.filePath).join(", ")}');
    notifyListeners();
  }

  void addFavoriteFile(FavoriteFileItem favoriteFile) {
    logger.d('Adding favorite file: ${favoriteFile.filePath}');
    if (!_favoriteFiles.any((f) => f.filePath == favoriteFile.filePath)) {
      _favoriteFiles.add(favoriteFile);
      _favoriteFiles = _sortedFavoriteFiles(_favoriteFiles);
      logger.i('Favorite file added. Total count: ${_favoriteFiles.length}');
      notifyListeners();
    } else {
      logger.w('Favorite file already exists: ${favoriteFile.filePath}');
    }
  }

  /// 批量添加收藏文件（只通知一次）
  void batchAddFavoriteFiles(List<FavoriteFileItem> favoriteFiles) {
    logger.d('Batch adding ${favoriteFiles.length} favorite files');
    int addedCount = 0;
    for (final favoriteFile in favoriteFiles) {
      if (!_favoriteFiles.any((f) => f.filePath == favoriteFile.filePath)) {
        _favoriteFiles.add(favoriteFile);
        addedCount++;
      }
    }
    if (addedCount > 0) {
      _favoriteFiles = _sortedFavoriteFiles(_favoriteFiles);
      logger.i('Batch added $addedCount favorite files. Total count: ${_favoriteFiles.length}');
      // 延迟通知，确保PopupMenu等UI组件有时间关闭，避免"deactivated widget's ancestor"错误
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  void removeFavoriteFile(String filePath) {
    logger.d('Removing favorite file: $filePath');
    final beforeCount = _favoriteFiles.length;
    _favoriteFiles.removeWhere((f) => f.filePath == filePath);
    final afterCount = _favoriteFiles.length;
    logger.i('Favorite file removed. Count: $beforeCount -> $afterCount');
    notifyListeners();
  }

  /// 批量移除收藏文件（只通知一次）
  void batchRemoveFavoriteFiles(List<String> filePaths) {
    logger.d('Batch removing ${filePaths.length} favorite files');
    int removedCount = 0;
    for (final filePath in filePaths) {
      final beforeCount = _favoriteFiles.length;
      _favoriteFiles.removeWhere((f) => f.filePath == filePath);
      if (_favoriteFiles.length < beforeCount) {
        removedCount++;
      }
    }
    if (removedCount > 0) {
      logger.i('Batch removed $removedCount favorite files. Total count: ${_favoriteFiles.length}');
      // 延迟通知，确保PopupMenu等UI组件有时间关闭，避免"deactivated widget's ancestor"错误
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  void updateFavoriteFile(FavoriteFileItem updatedFavoriteFile) {
    logger.d('Updating favorite file: ${updatedFavoriteFile.filePath}');
    final index = _favoriteFiles.indexWhere(
      (f) => f.filePath == updatedFavoriteFile.filePath,
    );
    if (index != -1) {
      _favoriteFiles[index] = updatedFavoriteFile;
      _favoriteFiles = _sortedFavoriteFiles(_favoriteFiles);
      notifyListeners();
    }
  }

  bool isFavoriteFile(String filePath) {
    return _favoriteFiles.any((f) => f.filePath == filePath);
  }

  // 统一的收藏文件排序：按收藏时间倒序（最新的在前面）
  List<FavoriteFileItem> _sortedFavoriteFiles(List<FavoriteFileItem> list) {
    final copy = [...list];
    copy.sort((a, b) => b.addedTime.compareTo(a.addedTime));
    return copy;
  }

  // 主题相关方法
  void setThemeMode(ThemeMode mode) {
    logger.i('Setting theme mode: $mode');
    _themeMode = mode;
    _saveCurrentState(); // 保存主题模式
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
    _saveCurrentState(); // 保存主题模式
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
    _errorMessage = message;
    notifyListeners();
  }

  /// 清除错误信息
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// 获取错误信息
  String? get errorMessage => _errorMessage;

  // Tab 和视图模式相关方法
  void setCurrentTab(TabView tab) {
    logger.d('Setting current tab: $tab');
    _currentTab = tab;
    _saveCurrentState(); // 保存状态
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

  /// Getter for last browse path (for restoring state)
  String? get lastBrowsePath => _lastBrowsePath;
}
