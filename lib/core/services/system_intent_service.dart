import 'package:flutter/services.dart';
import 'package:easyfile/core/logger.dart';

/// 系统意图服务
///
/// 用于调用Android系统意图，如打开应用详情页
class SystemIntentService {
  static const _channel = MethodChannel('com.easyfile/system_intent');

  /// 打开应用详情页
  ///
  /// 跳转到系统的应用详情页面，用户可以在这里清理缓存、卸载应用等
  Future<bool> openAppSettings(String packageName) async {
    try {
      logger.i('Opening app settings for: $packageName');

      final result = await _channel.invokeMethod<bool>(
        'openAppSettings',
        {'packageName': packageName},
      );

      return result ?? false;
    } on PlatformException catch (e) {
      logger.e('Platform exception opening app settings: ${e.message}');
      return false;
    } catch (e) {
      logger.e('Error opening app settings: $e');
      return false;
    }
  }

  /// 打开应用使用情况设置页
  ///
  /// 用于引导用户授予PACKAGE_USAGE_STATS权限
  Future<bool> openUsageStatsSettings() async {
    try {
      logger.i('Opening usage stats settings');

      final result = await _channel.invokeMethod<bool>(
        'openUsageStatsSettings',
      );

      return result ?? false;
    } on PlatformException catch (e) {
      logger.e('Platform exception opening usage stats settings: ${e.message}');
      return false;
    } catch (e) {
      logger.e('Error opening usage stats settings: $e');
      return false;
    }
  }
}
