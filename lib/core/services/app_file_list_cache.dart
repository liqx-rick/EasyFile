import 'dart:convert';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用文件列表缓存服务
///
/// 缓存完整的应用文件列表到 SharedPreferences（JSON格式）
/// 用于应用重启后快速显示文件列表，避免重复扫描
///
/// 缓存策略：
/// - 存储：SharedPreferences (JSON序列化)
/// - 有效期：24小时
/// - 键格式：'app_file_list_{appKey}'
///
/// 使用场景：
/// - 用户点击微信卡片 -> 秒开显示缓存的文件列表
/// - 后台异步执行扫描更新
class AppFileListCache {
  /// SharedPreferences 实例
  SharedPreferences? _prefs;

  /// 缓存键前缀
  static const _cacheKeyPrefix = 'app_file_list_';

  /// 是否已初始化
  bool _initialized = false;

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
      logger.i('✓ AppFileListCache 初始化完成');
    } catch (e) {
      logger.e('AppFileListCache 初始化失败: $e');
      _initialized = true; // 即使失败也标记为已初始化
    }
  }

  /// 获取缓存的文件列表
  ///
  /// [appKey] 应用Key，如 'wechat'
  /// 返回缓存的文件列表，如果缓存不存在则返回 null
  /// 注意：缓存通过增量更新保持最新，不会自动过期
  Future<List<FileItem>?> getFileList(String appKey) async {
    if (!_initialized) await initialize();
    if (_prefs == null) return null;

    try {
      final key = '$_cacheKeyPrefix$appKey';
      final cacheJson = _prefs!.getString(key);

      if (cacheJson == null) {
        logger.d('无缓存: $appKey');
        return null;
      }

      final cacheData = json.decode(cacheJson) as Map<String, dynamic>;
      final timestamp = cacheData['timestamp'] as int;
      final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;

      // 解析文件列表（不检查过期，通过增量更新保持最新）
      final filesData = cacheData['files'] as List<dynamic>;
      final files = filesData.map((fileJson) {
        final map = fileJson as Map<String, dynamic>;
        return FileItem(
          name: map['name'] as String,
          path: map['path'] as String,
          isDirectory: false,
          size: map['size'] as int,
          modified: DateTime.fromMillisecondsSinceEpoch(map['modified'] as int),
        );
      }).toList();

      logger.i('✅ 从缓存加载文件列表: $appKey = ${files.length} 个文件 (${Duration(milliseconds: cacheAge).inMinutes}分钟前)');
      return files;
    } catch (e) {
      logger.e('读取缓存失败: $appKey, $e');
      return null;
    }
  }

  /// 保存文件列表到缓存
  ///
  /// [appKey] 应用Key
  /// [files] 文件列表
  Future<void> setFileList(String appKey, List<FileItem> files) async {
    if (!_initialized) await initialize();
    if (_prefs == null) return;

    try {
      final key = '$_cacheKeyPrefix$appKey';

      final cacheData = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'appKey': appKey,
        'files': files
            .map(
              (file) => {
                'name': file.name,
                'path': file.path,
                'size': file.size,
                'modified': file.modified.millisecondsSinceEpoch,
              },
            )
            .toList(),
      };

      await _prefs!.setString(key, json.encode(cacheData));
      logger.i('✅ 文件列表已缓存: $appKey = ${files.length} 个文件');
    } catch (e) {
      logger.e('保存缓存失败: $appKey, $e');
    }
  }

  /// 清除特定应用的缓存
  ///
  /// [appKey] 应用Key
  Future<void> clearFileList(String appKey) async {
    if (!_initialized) await initialize();
    if (_prefs == null) return;

    try {
      final key = '$_cacheKeyPrefix$appKey';
      await _prefs!.remove(key);
      logger.i('缓存已清除: $appKey');
    } catch (e) {
      logger.e('清除缓存失败: $appKey, $e');
    }
  }

  /// 清除所有应用的缓存
  Future<void> clearAllCache() async {
    if (!_initialized) await initialize();
    if (_prefs == null) return;

    try {
      final keys = _prefs!.getKeys();
      final appCacheKeys = keys.where((key) => key.startsWith(_cacheKeyPrefix));

      for (final key in appCacheKeys) {
        await _prefs!.remove(key);
      }

      logger.i('所有应用文件列表缓存已清除');
    } catch (e) {
      logger.e('清除所有缓存失败: $e');
    }
  }

  /// 获取缓存的年龄（分钟）
  ///
  /// [appKey] 应用Key
  /// 返回缓存的年龄（分钟），如果缓存不存在则返回 null
  Future<int?> getCacheAgeMinutes(String appKey) async {
    if (!_initialized) await initialize();
    if (_prefs == null) return null;

    try {
      final key = '$_cacheKeyPrefix$appKey';
      final cacheJson = _prefs!.getString(key);

      if (cacheJson == null) return null;

      final cacheData = json.decode(cacheJson) as Map<String, dynamic>;
      final timestamp = cacheData['timestamp'] as int;
      final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;

      return Duration(milliseconds: cacheAge).inMinutes;
    } catch (e) {
      logger.e('获取缓存年龄失败: $appKey, $e');
      return null;
    }
  }
}
