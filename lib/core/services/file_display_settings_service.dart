import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';

/// 文件显示设置服务
///
/// 管理文件列表的显示选项，如：
/// - 是否显示隐藏文件（以.开头的文件）
/// - 是否显示系统文件夹（Android、.thumbnails等）
class FileDisplaySettingsService {
  static const String _keyShowHiddenFiles = 'show_hidden_files';
  static const String _keyShowSystemFiles = 'show_system_files';
  static const String _keyShowFullPath = 'show_full_path';

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

  /// 判断文件名是否为隐藏文件
  static bool isHiddenFile(String fileName) {
    return fileName.startsWith('.');
  }

  /// 判断是否为系统文件夹
  static bool isSystemFolder(String folderName) {
    const systemFolders = [
      'android',
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
