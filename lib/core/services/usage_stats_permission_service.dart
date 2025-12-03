import 'package:flutter/services.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/services/system_intent_service.dart';

/// 使用统计权限服务
///
/// 用于管理 PACKAGE_USAGE_STATS 权限，该权限用于：
/// 1. 查询应用精确的存储占用信息
/// 2. 查询应用最后使用时间
class UsageStatsPermissionService {
  final _intentService = locator<SystemIntentService>();
  static const MethodChannel _channel =
      MethodChannel('com.easyfile/permission');

  /// 检查是否已授予使用统计权限
  Future<bool> isGranted() async {
    try {
      logger.d('Checking PACKAGE_USAGE_STATS permission');
      final granted =
          await _channel.invokeMethod<bool>('hasUsageStatsPermission');
      logger.i('PACKAGE_USAGE_STATS permission: ${granted ?? false}');
      return granted ?? false;
    } catch (e) {
      logger.e('Error checking PACKAGE_USAGE_STATS permission: $e');
      return false;
    }
  }

  /// 请求使用统计权限
  ///
  /// 注意：这是一个特殊权限，无法通过运行时权限弹窗授予
  /// 必须引导用户跳转到系统设置页面手动开启
  Future<bool> request() async {
    try {
      logger.i('Requesting PACKAGE_USAGE_STATS permission');

      // 直接打开使用统计设置页
      await _intentService.openUsageStatsSettings();

      // 等待用户操作后返回
      await Future.delayed(const Duration(milliseconds: 500));

      // 返回false，提示用户需要手动授予
      return false;
    } catch (e) {
      logger.e('Error requesting PACKAGE_USAGE_STATS permission: $e');
      return false;
    }
  }

  /// 打开应用使用统计设置页面
  Future<bool> openAppSettings() async {
    try {
      logger.i('Opening usage stats settings');
      return await _intentService.openUsageStatsSettings();
    } catch (e) {
      logger.e('Error opening usage stats settings: $e');
      return false;
    }
  }
}
