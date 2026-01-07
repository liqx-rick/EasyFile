import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/preferences/system_trash_preferences.dart';
import 'package:easyfile/core/services/trash_file_service.dart';

/// 系统回收站缓存管理器
///
/// 负责管理系统回收站扫描结果的缓存，提供统一的缓存接口。
/// 与 [JunkFileCacheManager] 对称设计，但使用内存缓存而非持久化存储。
///
/// 缓存策略：
/// - 存储位置：内存（应用重启后失效）
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
  // ==================== 缓存字段 ====================

  /// 缓存的扫描结果
  TrashScanResult? _cachedScanResult;

  /// 缓存时间戳
  DateTime? _cacheTimestamp;

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
  /// cacheManager.saveCache(result);
  /// ```
  void saveCache(TrashScanResult result) {
    _cachedScanResult = result;
    _cacheTimestamp = DateTime.now();
    logger.i('系统回收站缓存已保存: ${result.allFiles.length} 个文件');
  }

  /// 获取缓存的扫描结果
  ///
  /// 返回：缓存的扫描结果，如果缓存无效或不存在则返回 null
  ///
  /// 注意：调用前应先使用 [isCacheValid] 检查缓存有效性
  ///
  /// 示例：
  /// ```dart
  /// if (cacheManager.isCacheValid()) {
  ///   final result = cacheManager.getCachedResult();
  ///   // 使用缓存结果
  /// }
  /// ```
  TrashScanResult? getCachedResult() {
    return _cachedScanResult;
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
  /// if (cacheManager.isCacheValid()) {
  ///   logger.d('使用缓存数据');
  /// } else {
  ///   logger.d('需要重新扫描');
  /// }
  /// ```
  bool isCacheValid() {
    if (_cachedScanResult == null || _cacheTimestamp == null) {
      return false;
    }

    final now = DateTime.now();
    final elapsed = now.difference(_cacheTimestamp!);
    final isValid = elapsed < _cacheExpiry;

    if (isValid) {
      logger
          .d('系统回收站缓存有效，剩余时间: ${_cacheExpiry.inMinutes - elapsed.inMinutes}分钟');
    }

    return isValid;
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
    _cachedScanResult = null;
    _cacheTimestamp = null;

    // 清理 SharedPreferences 中的相关数据
    try {
      // 总是清理扫描时间
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
  /// final info = cacheManager.getCacheInfo();
  /// logger.d('缓存信息: ${info.toString()}');
  /// ```
  Map<String, dynamic> getCacheInfo() {
    if (_cachedScanResult == null) {
      return {'cached': false};
    }

    final now = DateTime.now();
    final elapsed = now.difference(_cacheTimestamp!);

    return {
      'cached': true,
      'trashBinCount': _cachedScanResult!.trashBins.length,
      'fileCount': _cachedScanResult!.allFiles.length,
      'cacheAge': elapsed.inMinutes,
      'expiresIn': (_cacheExpiry.inMinutes - elapsed.inMinutes).clamp(0, 60),
      'isValid': isCacheValid(),
    };
  }
}
