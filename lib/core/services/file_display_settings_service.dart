import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';

/// 文件显示设置服务
///
/// 管理文件列表的显示选项，如：
/// - 是否显示隐藏文件（以.开头的文件）
/// - 是否显示系统文件夹（Android、.thumbnails等）
/// - 是否隐藏空目录（快速访问菜单）
class FileDisplaySettingsService {
  static const String _keyShowHiddenFiles = 'show_hidden_files';
  static const String _keyShowSystemFiles = 'show_system_files';
  static const String _keyShowFullPath = 'show_full_path';
  static const String _keyMinFileSize = 'duplicate_scan_min_file_size';
  static const String _keyHideEmptyFolders = 'hide_empty_folders';

  // 默认最小文件大小：100KB
  static const int defaultMinFileSize = 100 * 1024; // 100KB

  // 最小文件大小范围
  static const int minFileSizeMin = 10 * 1024; // 10KB
  static const int minFileSizeMax = 10 * 1024 * 1024; // 10MB

  /// 获取是否显示隐藏文件
  Future<bool> getShowHiddenFiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyShowHiddenFiles) ?? false; // 默认不显示
    } catch (e) {
      logger.e('Error getting show hidden files setting: $e');
      return false;
    }
  }

  /// 设置是否显示隐藏文件
  Future<void> setShowHiddenFiles(bool show) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowHiddenFiles, show);
      logger.i('Show hidden files set to: $show');
    } catch (e) {
      logger.e('Error setting show hidden files: $e');
    }
  }

  /// 获取是否显示系统文件
  Future<bool> getShowSystemFiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyShowSystemFiles) ?? false; // 默认不显示
    } catch (e) {
      logger.e('Error getting show system files setting: $e');
      return false;
    }
  }

  /// 设置是否显示系统文件
  Future<void> setShowSystemFiles(bool show) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowSystemFiles, show);
      logger.i('Show system files set to: $show');
    } catch (e) {
      logger.e('Error setting show system files: $e');
    }
  }

  /// 获取是否显示完整路径
  Future<bool> getShowFullPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyShowFullPath) ?? false; // 默认不显示
    } catch (e) {
      logger.e('Error getting show full path setting: $e');
      return false;
    }
  }

  /// 设置是否显示完整路径
  Future<void> setShowFullPath(bool show) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowFullPath, show);
      logger.i('Show full path set to: $show');
    } catch (e) {
      logger.e('Error setting show full path: $e');
    }
  }

  /// 获取是否隐藏空文件夹（快速访问菜单）
  Future<bool> getHideEmptyFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyHideEmptyFolders) ?? true; // 默认开启隐藏空文件夹
    } catch (e) {
      logger.e('Error getting hide empty folders setting: $e');
      return true; // 出错时默认隐藏
    }
  }

  /// 设置是否隐藏空文件夹（快速访问菜单）
  Future<void> setHideEmptyFolders(bool hide) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyHideEmptyFolders, hide);
      logger.i('Hide empty folders set to: $hide');
    } catch (e) {
      logger.e('Error setting hide empty folders: $e');
    }
  }

  /// 获取重复文件扫描最小文件大小（字节）
  Future<int> getMinFileSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyMinFileSize) ?? defaultMinFileSize;
    } catch (e) {
      logger.e('Error getting min file size setting: $e');
      return defaultMinFileSize;
    }
  }

  /// 设置重复文件扫描最小文件大小（字节）
  Future<void> setMinFileSize(int size) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyMinFileSize, size);
      logger.i('Min file size set to: ${_formatFileSize(size)}');
    } catch (e) {
      logger.e('Error setting min file size: $e');
    }
  }

  /// 格式化文件大小显示
  static String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    } else {
      return '$bytes B';
    }
  }

  /// 格式化文件大小显示（公开方法，供UI使用）
  static String formatFileSize(int bytes) => _formatFileSize(bytes);

  /// 判断文件名是否为隐藏文件
  static bool isHiddenFile(String fileName) {
    return fileName.startsWith('.');
  }

  /// 判断是否为系统文件夹
  ///
  /// 注意：不再将 'android' 作为系统文件夹过滤，允许用户访问 Android/data 等目录
  /// 但删除、移动等操作仍然受 PathSecurity 保护
  static bool isSystemFolder(String folderName) {
    const systemFolders = [
      // 'android', // 已移除：允许用户浏览 Android 目录及其子目录（如 Android/data）
      'lost+found',
      '.thumbnails',
      '.cache',
      '.trash',
    ];
    return systemFolders.contains(folderName.toLowerCase());
  }

  /// 判断是否为系统文件
  static bool isSystemFile(String fileName) {
    const systemFiles = [
      '.nomedia',
      'thumbs.db',
      'desktop.ini',
      '.ds_store',
    ];
    return systemFiles.contains(fileName.toLowerCase());
  }
}
