import 'package:flutter/foundation.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';

/// 快速访问视图模型
class QuickAccessViewModel extends ChangeNotifier {
  List<QuickAccessFolder> _folders = [];
  bool _isLoading = false;
  bool _isScanning = false;
  String? _errorMessage;

  // Getters
  List<QuickAccessFolder> get folders => _folders;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  String? get errorMessage => _errorMessage;

  /// 获取系统目录
  List<QuickAccessFolder> get systemFolders => _folders
      .where((f) => f.type == QuickAccessFolderType.system && !f.isHidden)
      .toList();

  /// 获取应用根目录
  List<QuickAccessFolder> get appRootFolders => _folders
      .where((f) => f.type == QuickAccessFolderType.appRoot && !f.isHidden)
      .toList();

  /// 获取应用子目录
  List<QuickAccessFolder> get appSubfolders => _folders
      .where((f) => f.type == QuickAccessFolderType.appSubfolder && !f.isHidden)
      .toList();

  /// 获取用户自定义目录
  List<QuickAccessFolder> get userCustomFolders => _folders
      .where((f) => f.type == QuickAccessFolderType.userCustom && !f.isHidden)
      .toList();

  /// 获取置顶的文件夹
  List<QuickAccessFolder> get pinnedFolders =>
      _folders.where((f) => f.pinned).toList();

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
}
