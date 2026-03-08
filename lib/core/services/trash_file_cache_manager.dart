import 'dart:convert';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/preferences/system_trash_preferences.dart';
import 'package:easyfile/core/services/trash_file_service.dart';
import 'package:easyfile/data/models/trash_bin.dart';
import 'package:easyfile/data/models/trash_file_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 系统回收站缓存管理器
///
/// 负责管理系统回收站扫描结果的缓存，提供统一的缓存接口。
/// 与 [JunkFileCacheManager] 对称设计，使用 SharedPreferences 持久化存储。
///
/// 缓存策略：
/// - 存储位置：SharedPreferences（持久化）
/// - 缓存时长：1小时
/// - 额外数据：SharedPreferences 存储抑制期设置（由 SystemTrashPreferences 管理）
///
/// 使用场景：
/// ```dart
/// final cacheManager = TrashFileCacheManager();
///
/// // 保存缓存
/// cacheManager.saveCache(scanResult);
///
/// // 检查并获取缓存
/// if (cacheManager.isCacheValid()) {
///   final cached = cacheManager.getCachedResult();
/// }
///
/// // 清除缓存
/// await cacheManager.clearCache();
/// ```
class TrashFileCacheManager {
  // ==================== 缓存键 ====================

  static const String _cacheKeyTrashBins = 'trash_file_cache_bins';
  static const String _cacheKeyAllFiles = 'trash_file_cache_files';
  static const String _timestampKey = 'trash_file_cache_timestamp';

  /// 缓存有效期（1小时）
  static const Duration _cacheExpiry = Duration(hours: 1);

  // ==================== 缓存操作 ====================

  /// 保存缓存
  ///
  /// [result] 扫描结果对象，包含回收站列表和文件列表
  ///
  /// 示例：
  /// ```dart
  /// final result = TrashScanResult(
  ///   trashBins: bins,
  ///   allFiles: files,
  /// );
  /// await cacheManager.saveCache(result);
  /// ```
  Future<void> saveCache(TrashScanResult result) async {
    try {
      logger.d('准备保存系统回收站缓存: ${result.allFiles.length}个文件');
      final prefs = await SharedPreferences.getInstance();

      // 保存回收站列表
      final binsJson = result.trashBins
          .map((bin) => {
                'id': bin.id,
                'name': bin.name,
                'path': bin.path,
                'type': bin.type.name,
                'fileCount': bin.fileCount,
                'totalSize': bin.totalSize,
              })
          .toList();

      // 保存文件列表
      final filesJson = result.allFiles
          .map((file) => {
                'name': file.name,
                'path': file.path,
                'size': file.size,
                'modified': file.modified.millisecondsSinceEpoch,
                'trashedTime': file.trashedTime?.millisecondsSinceEpoch,
                'trashBinId': file.trashBinId,
                'mimeType': file.mimeType,
                'mimeTypeVerified': file.mimeTypeVerified,
              })
          .toList();

      await prefs.setString(_cacheKeyTrashBins, jsonEncode(binsJson));
      await prefs.setString(_cacheKeyAllFiles, jsonEncode(filesJson));
      await prefs.setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch);

      logger.i('✅ 系统回收站缓存已保存: ${result.allFiles.length}个文件');
    } catch (e, stackTrace) {
      logger.e('保存系统回收站缓存失败: $e\n$stackTrace');
    }
  }

  /// 获取缓存的扫描结果
  ///
  /// 返回：缓存的扫描结果，如果缓存无效或不存在则返回 null
  ///
  /// 注意：调用前应先使用 [isCacheValid] 检查缓存有效性
  ///
  /// 示例：
  /// ```dart
  /// if (await cacheManager.isCacheValid()) {
  ///   final result = await cacheManager.getCachedResult();
  ///   // 使用缓存结果
  /// }
  /// ```
  Future<TrashScanResult?> getCachedResult() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final binsJson = prefs.getString(_cacheKeyTrashBins);
      final filesJson = prefs.getString(_cacheKeyAllFiles);
      final timestamp = prefs.getInt(_timestampKey);

      if (binsJson == null || filesJson == null || timestamp == null) {
        logger.d('系统回收站缓存不完整');
        return null;
      }

      // 检查是否过期
      final scanTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final age = DateTime.now().difference(scanTime);

      if (age > _cacheExpiry) {
        logger.d('系统回收站缓存已过期 (age: ${age.inMinutes}分钟)');
        await clearCache();
        return null;
      }

      // 解析回收站列表
      final binsList = (jsonDecode(binsJson) as List)
          .map((json) => TrashBin(
                id: json['id'] as String,
                name: json['name'] as String,
                path: json['path'] as String,
                type: TrashBinType.values.firstWhere(
                  (e) => e.name == json['type'],
                  orElse: () => TrashBinType.system,
                ),
                fileCount: json['fileCount'] as int,
                totalSize: json['totalSize'] as int,
              ))
          .toList();

      // 解析文件列表
      final filesList = (jsonDecode(filesJson) as List)
          .map((json) => TrashFileItem(
                name: json['name'] as String,
                path: json['path'] as String,
                size: json['size'] as int,
                modified: DateTime.fromMillisecondsSinceEpoch(json['modified'] as int),
                trashedTime: json['trashedTime'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(json['trashedTime'] as int)
                    : null,
                trashBinId: json['trashBinId'] as String?,
                mimeType: json['mimeType'] as String?,
                mimeTypeVerified: json['mimeTypeVerified'] as bool? ?? false,
              ))
          .toList();

      logger.d('✅ 系统回收站缓存加载成功: ${filesList.length}个文件, 年龄: ${age.inMinutes}分钟');

      return TrashScanResult(
        trashBins: binsList,
        allFiles: filesList,
      );
    } catch (e, stackTrace) {
      logger.e('加载系统回收站缓存失败: $e\n$stackTrace');
      return null;
    }
  }

  /// 检查缓存是否有效
  ///
  /// 返回：true 表示缓存存在且未过期，false 表示缓存无效或不存在
  ///
  /// 判断标准：
  /// - 缓存结果和时间戳都存在
  /// - 距离缓存时间未超过1小时
  ///
  /// 示例：
  /// ```dart
  /// if (await cacheManager.isCacheValid()) {
  ///   logger.d('使用缓存数据');
  /// } else {
  ///   logger.d('需要重新扫描');
  /// }
  /// ```
  Future<bool> isCacheValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final binsJson = prefs.getString(_cacheKeyTrashBins);
      final filesJson = prefs.getString(_cacheKeyAllFiles);
      final timestamp = prefs.getInt(_timestampKey);

      if (binsJson == null || filesJson == null || timestamp == null) {
        logger.d('系统回收站缓存不存在');
        return false;
      }

      final scanTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final age = DateTime.now().difference(scanTime);
      final isValid = age < _cacheExpiry;

      if (isValid) {
        logger.d('系统回收站缓存有效，年龄: ${age.inMinutes}分钟, 剩余: ${_cacheExpiry.inMinutes - age.inMinutes}分钟');
      } else {
        logger.d('系统回收站缓存已过期，年龄: ${age.inMinutes}分钟');
      }

      return isValid;
    } catch (e) {
      logger.e('检查系统回收站缓存有效性失败: $e');
      return false;
    }
  }

  /// 清除缓存
  ///
  /// [keepSuppressionPeriods] 是否保留抑制期设置
  /// - true: 仅清除缓存数据，保留用户设置的忽略期和清理抑制期
  /// - false: 清除缓存数据和所有抑制期设置
  ///
  /// 应用场景：
  /// - 文件删除后：调用 `clearCache(keepSuppressionPeriods: false)` 完全清理
  /// - 强制刷新：调用 `clearCache(keepSuppressionPeriods: true)` 保留用户设置
  /// - 用户重置：调用 `clearCache(keepSuppressionPeriods: false)` 恢复初始状态
  ///
  /// 示例：
  /// ```dart
  /// // 删除文件后，完全清除缓存和抑制期
  /// await cacheManager.clearCache(keepSuppressionPeriods: false);
  ///
  /// // 强制刷新，但保留用户"不再提示"设置
  /// await cacheManager.clearCache(keepSuppressionPeriods: true);
  /// ```
  Future<void> clearCache({bool keepSuppressionPeriods = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 清除缓存数据
      await prefs.remove(_cacheKeyTrashBins);
      await prefs.remove(_cacheKeyAllFiles);
      await prefs.remove(_timestampKey);

      // 清理 SharedPreferences 中的相关数据
      await SystemTrashPreferences.clearLastScanTime();

      // 根据参数决定是否清理抑制期设置
      if (!keepSuppressionPeriods) {
        await SystemTrashPreferences.clearAllSuppressionPeriods();
        logger.i('系统回收站缓存及所有相关设置已清除');
      } else {
        logger.i('系统回收站缓存已清除（保留抑制期设置）');
      }
    } catch (e) {
      logger.e('清理系统回收站缓存失败: $e');
    }
  }

  // ==================== 调试支持 ====================

  /// 获取缓存信息（用于调试和监控）
  ///
  /// 返回：包含缓存状态的Map，包括：
  /// - cached: 是否有缓存
  /// - trashBinCount: 回收站数量
  /// - fileCount: 文件总数
  /// - cacheAge: 缓存年龄（分钟）
  /// - expiresIn: 剩余有效时间（分钟）
  /// - isValid: 缓存是否有效
  ///
  /// 示例：
  /// ```dart
  /// final info = await cacheManager.getCacheInfo();
  /// logger.d('缓存信息: ${info.toString()}');
  /// ```
  Future<Map<String, dynamic>> getCacheInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_timestampKey);
    final binsJson = prefs.getString(_cacheKeyTrashBins);
    final filesJson = prefs.getString(_cacheKeyAllFiles);

    if (timestamp == null || binsJson == null || filesJson == null) {
      return {'cached': false};
    }

    final now = DateTime.now();
    final scanTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final elapsed = now.difference(scanTime);

    final binsList = jsonDecode(binsJson) as List;
    final filesList = jsonDecode(filesJson) as List;

    return {
      'cached': true,
      'trashBinCount': binsList.length,
      'fileCount': filesList.length,
      'cacheAge': elapsed.inMinutes,
      'expiresIn': (_cacheExpiry.inMinutes - elapsed.inMinutes).clamp(0, 60),
      'isValid': await isCacheValid(),
    };
  }
}
