import 'package:flutter/foundation.dart';
import 'package:easyfile/core/constants/system_folders_config.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';

/// 快速访问视图模型
class QuickAccessViewModel extends ChangeNotifier {
  List<QuickAccessFolder> _folders = [];
  bool _isLoading = false;
  bool _isScanning = false;
  String? _errorMessage;

  // v2.0: 系统目录展开状态管理（key: 系统目录根路径，value: 是否展开）
  final Map<String, bool> _expandedSystemFolders = {};

  // 新增文件夹ID集合（会话级，关闭应用后自动清除）
  final Set<String> _newFolderIds = {};

  // Getters
  List<QuickAccessFolder> get folders => _folders;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  String? get errorMessage => _errorMessage;

  /// 获取系统目录（按预定义顺序排序，显示条件：有效、非空、不隐藏）
  List<QuickAccessFolder> get systemFolders {
    final filtered = _folders
        .where((f) => f.type == QuickAccessFolderType.system && !f.isHidden)
        .toList();

    // 按系统目录的预定义顺序排序（仅根目录）
    final rootFolders = filtered.where((f) => !f.isSystemSubfolder).toList();
    rootFolders.sort((a, b) {
      final aIndex = SystemFoldersConfig.systemPaths.indexOf(a.path);
      final bIndex = SystemFoldersConfig.systemPaths.indexOf(b.path);
      return aIndex.compareTo(bIndex);
    });

    return rootFolders;
  }

  /// 获取系统文件夹总数（包括所有子文件夹）
  int get systemFoldersTotalCount {
    return _folders
        .where((f) => f.type == QuickAccessFolderType.system && !f.isHidden)
        .length;
  }

  /// 获取其他目录（应用、用户自定义等，按名称排序，显示条件：有效、非空、不隐藏）
  List<QuickAccessFolder> get otherFolders {
    final filtered = _folders
        .where((f) => f.type == QuickAccessFolderType.other && !f.isHidden)
        // 额外过滤：排除所有具有 parentPath 的文件夹（这些是系统目录的子文件夹，不应该在这里显示）
        .where((f) => f.parentPath == null)
        // 额外过滤：排除系统文件夹（处理历史数据库中错误分类的记录）
        .where((f) => !SystemFoldersConfig.isSystemFolder(f.path))
        .toList();

    // 按显示名称排序
    filtered.sort((a, b) => a.displayName.compareTo(b.displayName));

    return filtered;
  }

  /// @deprecated 改为 otherFolders
  List<QuickAccessFolder> get appRootFolders => otherFolders;

  /// @deprecated 改为 otherFolders
  List<QuickAccessFolder> get appSubfolders => otherFolders;

  /// @deprecated 改为 otherFolders
  List<QuickAccessFolder> get userCustomFolders => otherFolders;

  /// @deprecated 首页推荐已移除
  List<QuickAccessFolder> get pinnedFolders => [];

  /// 设置文件夹列表
  void setFolders(List<QuickAccessFolder> folders) {
    _folders = folders;
    _errorMessage = null;
    notifyListeners();
  }

  /// 设置加载状态
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// 设置扫描状态
  void setScanning(bool scanning) {
    _isScanning = scanning;
    notifyListeners();
  }

  /// 设置错误信息
  void setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  /// 清除错误信息
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// 添加文件夹
  void addFolder(QuickAccessFolder folder) {
    if (!_folders.any((f) => f.path == folder.path)) {
      _folders.add(folder);
      notifyListeners();
    }
  }

  /// 删除文件夹
  void removeFolder(String path) {
    _folders.removeWhere((f) => f.path == path);
    notifyListeners();
  }

  /// 更新文件夹
  void updateFolder(QuickAccessFolder updatedFolder) {
    final index = _folders.indexWhere((f) => f.path == updatedFolder.path);
    if (index != -1) {
      _folders[index] = updatedFolder;
      notifyListeners();
    }
  }

  /// 批量删除文件夹
  void removeFolders(List<String> paths) {
    _folders.removeWhere((f) => paths.contains(f.path));
    notifyListeners();
  }

  /// 获取指定路径的文件夹
  QuickAccessFolder? getFolderByPath(String path) {
    try {
      return _folders.firstWhere((f) => f.path == path);
    } catch (e) {
      return null;
    }
  }

  /// 检查路径是否已存在
  bool pathExists(String path) {
    return _folders.any((f) => f.path == path);
  }

  // ========== v2.0 新增方法 ==========

  /// 获取系统目录的子文件夹（从文件系统读取）
  /// 获取某个路径的所有子文件夹（从数据库）
  ///
  /// 返回所有 parentPath 匹配的文件夹记录，按名称排序
  /// 这些都是已加入快速访问的子文件夹
  List<QuickAccessFolder> getSubfoldersFromDatabase(String parentPath) {
    final subfolders = _folders
        .where((f) => f.parentPath == parentPath && !f.isHidden)
        .toList();

    // 按显示名称排序
    subfolders.sort((a, b) => a.displayName.compareTo(b.displayName));

    return subfolders;
  }

  /// 检查某个路径是否有子文件夹
  ///
  /// 返回 true 如果存在至少一个 parentPath 匹配且未隐藏的子文件夹
  /// 用于决定是否显示展开图标
  bool hasSubfolders(String parentPath) {
    return _folders.any((f) => f.parentPath == parentPath && !f.isHidden);
  }

  /// 获取系统目录是否已展开
  bool isSystemFolderExpanded(String rootPath) {
    return _expandedSystemFolders[rootPath] ?? false;
  }

  /// 设置系统目录展开状态
  void setSystemFolderExpanded(String rootPath, bool expanded) {
    _expandedSystemFolders[rootPath] = expanded;
    notifyListeners();
  }

  /// 切换系统目录展开状态
  void toggleSystemFolderExpanded(String rootPath) {
    final currentState = _expandedSystemFolders[rootPath] ?? false;
    _expandedSystemFolders[rootPath] = !currentState;
    notifyListeners();
  }

  /// 清除所有展开状态（如重新扫描时）
  void clearExpandedStates() {
    _expandedSystemFolders.clear();
    notifyListeners();
  }

  /// 检查文件夹是否是新增的
  bool isNewFolder(String folderId) => _newFolderIds.contains(folderId);

  /// 检查父目录是否有新增的子文件夹
  bool hasNewSubfolders(String parentPath) {
    return _folders.any((folder) =>
        folder.parentPath == parentPath && _newFolderIds.contains(folder.id));
  }

  /// 标记新增的文件夹
  void markAsNew(List<String> folderIds) {
    _newFolderIds.addAll(folderIds);
    notifyListeners();
  }
}
