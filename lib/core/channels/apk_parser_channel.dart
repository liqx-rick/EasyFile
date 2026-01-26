import 'package:flutter/services.dart';

import '../../data/models/apk_info.dart';
import '../logger.dart';

/// APK解析器Platform Channel
class ApkParserChannel {
  static const MethodChannel _channel = MethodChannel('com.easyfile.apk_parser');

  /// 解析单个APK文件
  ///
  /// 返回包含APK基本信息的ApkInfo对象（不含安装状态）
  static Future<ApkInfo?> parseApk(String filePath) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('parseApk', {'filePath': filePath});

      if (result == null) {
        return null;
      }

      final json = Map<String, dynamic>.from(result);
      return ApkInfo.fromJson(json);
    } on PlatformException catch (e) {
      logger.e('APK解析失败: ${e.message}');
      return null;
    }
  }

  /// 批量解析APK文件
  ///
  /// 高效批量解析，返回成功解析的APK列表
  static Future<List<ApkInfo>> parseApkBatch(List<String> filePaths) async {
    try {
      final List<dynamic>? results = await _channel.invokeMethod('parseApkBatch', {'filePaths': filePaths});

      if (results == null) {
        return [];
      }

      return results.map((e) => ApkInfo.fromJson(Map<String, dynamic>.from(e))).toList();
    } on PlatformException catch (e) {
      logger.e('批量APK解析失败: ${e.message}');
      return [];
    }
  }

  /// 检查APK安装状态
  ///
  /// 返回安装状态枚举值
  static Future<ApkInstallStatus> checkInstallStatus(
    String packageName,
    int versionCode,
  ) async {
    try {
      final String? result = await _channel.invokeMethod(
        'checkInstallStatus',
        {
          'packageName': packageName,
          'versionCode': versionCode,
        },
      );

      if (result == null) {
        return ApkInstallStatus.unknown;
      }

      return ApkInstallStatus.values.firstWhere(
        (e) => e.name == result,
        orElse: () => ApkInstallStatus.unknown,
      );
    } on PlatformException catch (e) {
      logger.e('检查安装状态失败: ${e.message}');
      return ApkInstallStatus.unknown;
    }
  }

  /// 批量检查APK安装状态
  ///
  /// 返回Map<包名, ApkInstallStatus>
  static Future<Map<String, ApkInstallStatus>> checkInstallStatusBatch(
    List<Map<String, dynamic>> apkInfoList,
  ) async {
    try {
      final Map<dynamic, dynamic>? results = await _channel.invokeMethod(
        'checkInstallStatusBatch',
        {'apkInfoList': apkInfoList},
      );

      if (results == null) {
        return {};
      }

      return results.map((key, value) {
        final status = ApkInstallStatus.values.firstWhere(
          (e) => e.name == value,
          orElse: () => ApkInstallStatus.unknown,
        );
        return MapEntry(key.toString(), status);
      });
    } on PlatformException catch (e) {
      logger.e('批量检查安装状态失败: ${e.message}');
      return {};
    }
  }

  /// 跳转系统安装页面
  ///
  /// Android 8.0+直接跳转安装
  static Future<bool> launchInstall(String filePath) async {
    try {
      final bool? result = await _channel.invokeMethod('launchInstall', {'filePath': filePath});
      return result ?? false;
    } on PlatformException catch (e) {
      logger.e('跳转安装失败: ${e.message}');
      return false;
    }
  }

  /// 跳转应用详情页
  ///
  /// 已安装应用可查看详情或卸载
  static Future<bool> launchAppSettings(String packageName) async {
    try {
      final bool? result = await _channel.invokeMethod('launchAppSettings', {'packageName': packageName});
      return result ?? false;
    } on PlatformException catch (e) {
      logger.e('跳转应用详情失败: ${e.message}');
      return false;
    }
  }

  /// 开始监听应用安装/卸载事件
  static Future<void> startPackageListener() async {
    try {
      await _channel.invokeMethod('startPackageListener');
      logger.i('已开启应用包监听');
    } on PlatformException catch (e) {
      logger.e('开启包监听失败: ${e.message}');
    }
  }

  /// 停止监听应用安装/卸载事件
  static Future<void> stopPackageListener() async {
    try {
      await _channel.invokeMethod('stopPackageListener');
      logger.i('已关闭应用包监听');
    } on PlatformException catch (e) {
      logger.e('关闭包监听失败: ${e.message}');
    }
  }

  /// 设置应用包变化回调
  static void setPackageChangeCallback(Function(String packageName, String action) callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPackageChanged') {
        final packageName = call.arguments['packageName'] as String;
        final action = call.arguments['action'] as String;
        callback(packageName, action);
      }
    });
  }
}
