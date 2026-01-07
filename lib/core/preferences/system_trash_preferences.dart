import 'package:shared_preferences/shared_preferences.dart';

/// 系统回收站相关的SharedPreferences键管理
///
/// 统一管理系统回收站功能所需的所有SharedPreferences键，
/// 避免键名硬编码分散在多个文件中导致的维护问题。
///
/// 主要功能：
/// - 上次扫描时间管理（用于36小时缓存策略）
/// - 用户主动忽略时期管理（用户点击"不再提示"后的7天静默期）
/// - 清理抑制时期管理（清理后7天内不再扫描和提示）
class SystemTrashPreferences {
  // ==================== 私有键定义 ====================

  /// 上次扫描时间（毫秒时间戳）
  /// 用途：36小时内不重复扫描，避免频繁IO操作
  static const String _keyLastScanTime = 'system_trash_last_scan_time';

  /// 用户主动忽略的截止时间（毫秒时间戳）
  /// 用途：用户点击"不再提示"后，在此时间之前不再提示
  static const String _keyUserDismissedUntil =
      'system_trash_user_dismissed_until';

  /// 清理后的抑制截止时间（毫秒时间戳）
  /// 用途：清理回收站后，在此时间之前不再扫描和提示
  static const String _keyCleanedUntil = 'system_trash_cleaned_until';

  // ==================== 上次扫描时间管理 ====================

  /// 获取上次扫描时间
  ///
  /// 返回：上次扫描的DateTime对象，如果从未扫描过则返回null
  static Future<DateTime?> getLastScanTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_keyLastScanTime);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// 设置上次扫描时间为当前时间
  ///
  /// 在每次完成扫描后调用，用于标记扫描时间点
  static Future<void> setLastScanTimeNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastScanTime, DateTime.now().millisecondsSinceEpoch);
  }

  /// 清除上次扫描时间
  ///
  /// 在清除缓存或重置状态时调用
  static Future<void> clearLastScanTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastScanTime);
  }

  /// 检查距离上次扫描是否已超过指定时长
  ///
  /// [duration] 需要检查的时长（如：Duration(hours: 36)）
  /// 返回：true表示已超过指定时长或从未扫描，false表示未超过
  ///
  /// 示例：
  /// ```dart
  /// // 检查是否超过36小时
  /// final shouldScan = await SystemTrashPreferences.isLastScanOlderThan(
  ///   const Duration(hours: 36)
  /// );
  /// ```
  static Future<bool> isLastScanOlderThan(Duration duration) async {
    final lastScanTime = await getLastScanTime();
    if (lastScanTime == null) return true; // 从未扫描，需要扫描

    final now = DateTime.now();
    final elapsedTime = now.difference(lastScanTime);
    return elapsedTime > duration;
  }

  // ==================== 用户主动忽略时期管理 ====================

  /// 获取用户主动忽略的截止时间
  ///
  /// 返回：截止时间的DateTime对象，如果用户未设置忽略则返回null
  static Future<DateTime?> getUserDismissedUntil() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_keyUserDismissedUntil);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// 设置用户主动忽略时期
  ///
  /// [duration] 忽略的时长（如：Duration(days: 7)）
  /// 从当前时间开始计算，设置截止时间
  ///
  /// 示例：
  /// ```dart
  /// // 用户点击"7天内不再提示"
  /// await SystemTrashPreferences.setUserDismissedPeriod(
  ///   const Duration(days: 7)
  /// );
  /// ```
  static Future<void> setUserDismissedPeriod(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(duration);
    await prefs.setInt(_keyUserDismissedUntil, until.millisecondsSinceEpoch);
  }

  /// 清除用户主动忽略时期
  ///
  /// 在用户取消忽略或清除所有抑制时调用
  static Future<void> clearUserDismissedPeriod() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserDismissedUntil);
  }

  /// 检查当前是否处于用户主动忽略时期内
  ///
  /// 返回：true表示在忽略期内，false表示不在或从未设置
  ///
  /// 示例：
  /// ```dart
  /// if (await SystemTrashPreferences.isInUserDismissedPeriod()) {
  ///   // 用户选择了不再提示，跳过提示逻辑
  ///   return;
  /// }
  /// ```
  static Future<bool> isInUserDismissedPeriod() async {
    final until = await getUserDismissedUntil();
    if (until == null) return false;

    final now = DateTime.now();
    return now.isBefore(until);
  }

  // ==================== 清理抑制时期管理 ====================

  /// 获取清理后的抑制截止时间
  ///
  /// 返回：截止时间的DateTime对象，如果从未清理则返回null
  static Future<DateTime?> getCleanedUntil() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_keyCleanedUntil);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// 设置清理抑制时期
  ///
  /// [duration] 抑制的时长（如：Duration(days: 7)）
  /// 从当前时间开始计算，设置截止时间
  ///
  /// 应在以下情况调用：
  /// - 用户完成清空回收站操作后
  /// - 用户删除部分回收站文件后
  ///
  /// 示例：
  /// ```dart
  /// // 清理完成后，设置7天抑制期
  /// await SystemTrashPreferences.setCleanedSuppressionPeriod(
  ///   const Duration(days: 7)
  /// );
  /// ```
  static Future<void> setCleanedSuppressionPeriod(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(duration);
    await prefs.setInt(_keyCleanedUntil, until.millisecondsSinceEpoch);
  }

  /// 清除清理抑制时期
  ///
  /// 在清除所有抑制或重置状态时调用
  static Future<void> clearCleanedSuppressionPeriod() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCleanedUntil);
  }

  /// 检查当前是否处于清理抑制时期内
  ///
  /// 返回：true表示在抑制期内，false表示不在或从未清理
  ///
  /// 示例：
  /// ```dart
  /// if (await SystemTrashPreferences.isInCleanedSuppressionPeriod()) {
  ///   // 刚清理过，跳过扫描和提示
  ///   return;
  /// }
  /// ```
  static Future<bool> isInCleanedSuppressionPeriod() async {
    final until = await getCleanedUntil();
    if (until == null) return false;

    final now = DateTime.now();
    return now.isBefore(until);
  }

  // ==================== 批量操作 ====================

  /// 清除所有抑制时期设置（保留扫描时间）
  ///
  /// 会清除：
  /// - 用户主动忽略时期
  /// - 清理抑制时期
  ///
  /// 不会清除：
  /// - 上次扫描时间（缓存策略仍然有效）
  ///
  /// 应用场景：
  /// - 用户在设置中点击"重置提示状态"
  /// - 强制允许扫描和提示
  static Future<void> clearAllSuppressionPeriods() async {
    await Future.wait([
      clearUserDismissedPeriod(),
      clearCleanedSuppressionPeriod(),
    ]);
  }

  /// 完全重置所有系统回收站相关设置
  ///
  /// 会清除所有键值，包括：
  /// - 上次扫描时间
  /// - 用户主动忽略时期
  /// - 清理抑制时期
  ///
  /// 应用场景：
  /// - 应用重置
  /// - 调试/测试
  /// - 用户要求完全重新开始
  static Future<void> resetAll() async {
    await Future.wait([
      clearLastScanTime(),
      clearUserDismissedPeriod(),
      clearCleanedSuppressionPeriod(),
    ]);
  }

  // ==================== 调试辅助 ====================

  /// 获取所有系统回收站相关的偏好设置（用于调试）
  ///
  /// 返回：包含所有设置的Map，键为易读的名称，值为格式化的字符串
  ///
  /// 示例输出：
  /// ```
  /// {
  ///   'lastScanTime': '2026-01-07 14:30:00',
  ///   'userDismissedUntil': '2026-01-14 10:20:00',
  ///   'cleanedUntil': 'null'
  /// }
  /// ```
  static Future<Map<String, String>> getDebugInfo() async {
    final lastScan = await getLastScanTime();
    final dismissed = await getUserDismissedUntil();
    final cleaned = await getCleanedUntil();

    return {
      'lastScanTime': lastScan?.toString() ?? 'null',
      'userDismissedUntil': dismissed?.toString() ?? 'null',
      'cleanedUntil': cleaned?.toString() ?? 'null',
      'isInUserDismissedPeriod': (await isInUserDismissedPeriod()).toString(),
      'isInCleanedSuppressionPeriod':
          (await isInCleanedSuppressionPeriod()).toString(),
    };
  }
}
