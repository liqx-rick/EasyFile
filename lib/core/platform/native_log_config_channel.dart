import 'package:flutter/services.dart';
import 'package:easyfile/core/logger.dart';

/// 原生日志配置通道
/// 
/// 用于将 Flutter 端的日志级别配置同步到原生端（Android/iOS）
/// 确保 Flutter 和原生日志使用统一的日志级别策略
/// 
/// 使用示例：
/// ```dart
/// await NativeLogConfigChannel.setLogLevel(LogLevel.warn);
/// ```
class NativeLogConfigChannel {
  static const _channel = MethodChannel('easyfile/log_config');

  /// 设置原生端日志级别（与 Flutter 端同步）
  /// 
  /// [level] - Flutter 的 LogLevel 枚举
  /// 
  /// 返回：设置是否成功
  static Future<bool> setLogLevel(LogLevel level) async {
    try {
      logger.d('设置原生日志级别: ${level.name}');
      
      final result = await _channel.invokeMethod<bool>(
        'setLogLevel',
        {'level': level.name},
      );
      
      if (result == true) {
        logger.i('✓ 原生日志级别已同步: ${level.name}');
      } else {
        logger.w('原生日志级别设置失败（可能在非 Android 平台）');
      }
      
      return result ?? false;
    } catch (e) {
      // 非 Android 平台会抛出异常，这是正常的
      logger.d('原生日志配置通道不可用（可能在非 Android 平台）: $e');
      return false;
    }
  }

  /// 获取当前原生端日志级别
  /// 
  /// 返回：当前日志级别字符串（debug/info/warn/error）
  static Future<String?> getLogLevel() async {
    try {
      final result = await _channel.invokeMethod<String>('getLogLevel');
      return result;
    } catch (e) {
      logger.d('获取原生日志级别失败: $e');
      return null;
    }
  }

  /// 启用/禁用原生端日志
  /// 
  /// [enabled] - true 启用，false 禁用
  static Future<bool> setLogEnabled(bool enabled) async {
    try {
      logger.d('设置原生日志输出: ${enabled ? "启用" : "禁用"}');
      
      final result = await _channel.invokeMethod<bool>(
        'setLogEnabled',
        {'enabled': enabled},
      );
      
      if (result == true) {
        logger.i('✓ 原生日志已${enabled ? "启用" : "禁用"}');
      }
      
      return result ?? false;
    } catch (e) {
      logger.d('设置原生日志启用状态失败: $e');
      return false;
    }
  }

  /// 同步 Flutter 日志配置到原生端
  /// 
  /// 在应用启动时调用，确保 Flutter 和原生使用相同的日志策略
  /// 
  /// [level] - Flutter 当前的日志级别
  /// [enabled] - 是否启用日志（可选，默认 true）
  static Future<void> syncLogConfig({
    required LogLevel level,
    bool enabled = true,
  }) async {
    logger.i('🔄 开始同步日志配置到原生端...');
    
    try {
      // 设置日志级别
      final levelSynced = await setLogLevel(level);
      
      // 设置启用状态
      final enabledSynced = await setLogEnabled(enabled);
      
      if (levelSynced && enabledSynced) {
        logger.i('✅ 日志配置同步完成: ${level.name}, ${enabled ? "启用" : "禁用"}');
      } else {
        logger.w('⚠️  日志配置部分同步失败（可能在非 Android 平台）');
      }
    } catch (e) {
      logger.e('日志配置同步失败: $e');
    }
  }
}
