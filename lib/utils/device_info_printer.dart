import 'package:easyfile/core/platform/device_info_channel.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 打印设备硬件环境信息到控制台
///
/// 使用方法：
/// ```dart
/// import 'package:easyfile/utils/device_info_printer.dart';
///
/// // 在 main() 或任何地方调用
/// await DeviceInfoPrinter.print();
/// ```
class DeviceInfoPrinter {
  /// 打印完整的设备信息
  static Future<void> print() async {
    try {
      debugPrint('========================================');
      debugPrint('        设备硬件环境统计');
      debugPrint('========================================\n');

      // 获取应用信息
      final packageInfo = await PackageInfo.fromPlatform();
      debugPrint('【应用信息】');
      debugPrint('  应用名称: ${packageInfo.appName}');
      debugPrint('  包名: ${packageInfo.packageName}');
      debugPrint('  版本: ${packageInfo.version} (${packageInfo.buildNumber})');
      debugPrint('');

      // 获取系统信息
      final systemInfo = await DeviceInfoChannel.getSystemInfo();
      final deviceInfo = systemInfo.deviceInfo;
      final platformInfo = systemInfo.platformInfo;

      debugPrint('【设备信息】');
      debugPrint('  制造商: ${deviceInfo.manufacturer}');
      debugPrint('  型号: ${deviceInfo.model}');
      debugPrint('  品牌: ${deviceInfo.brand}');
      debugPrint('  设备代号: ${deviceInfo.device}');
      debugPrint('');

      debugPrint('【系统信息】');
      debugPrint('  操作系统: ${platformInfo['operatingSystem']}');
      debugPrint('  系统版本: ${platformInfo['operatingSystemVersion']}');
      debugPrint('  Android SDK: API ${deviceInfo.sdkVersion}');
      debugPrint('  语言区域: ${platformInfo['localeName']}');
      debugPrint('');

      debugPrint('【处理器信息】');
      debugPrint('  CPU架构: ${deviceInfo.cpuAbi}');
      debugPrint('  CPU核心数: ${platformInfo['numberOfProcessors']}核');
      debugPrint('');

      debugPrint('【内存信息】');
      debugPrint('  总内存: ${deviceInfo.formatMemory(deviceInfo.totalMemory)}');
      debugPrint('  可用内存: ${deviceInfo.formatMemory(deviceInfo.availableMemory)}');
      debugPrint('  已用内存: ${deviceInfo.formatMemory(deviceInfo.totalMemory - deviceInfo.availableMemory)}');
      debugPrint('  使用率: ${deviceInfo.memoryUsagePercent.toStringAsFixed(1)}%');
      debugPrint('');

      debugPrint('【存储信息】');
      debugPrint('  总存储: ${deviceInfo.formatMemory(deviceInfo.totalStorage)}');
      debugPrint('  可用存储: ${deviceInfo.formatMemory(deviceInfo.availableStorage)}');
      debugPrint('  已用存储: ${deviceInfo.formatMemory(deviceInfo.totalStorage - deviceInfo.availableStorage)}');
      debugPrint('  使用率: ${deviceInfo.storageUsagePercent.toStringAsFixed(1)}%');
      debugPrint('');

      debugPrint('【屏幕信息】');
      debugPrint('  分辨率: ${deviceInfo.screenWidth} x ${deviceInfo.screenHeight}');
      debugPrint('  屏幕密度: ${deviceInfo.screenDensity} dpi');
      debugPrint('  屏幕等级: ${_getScreenDensityCategory(deviceInfo.screenDensity)}');
      debugPrint('');

      debugPrint('========================================');
      debugPrint('           统计完成');
      debugPrint('========================================\n');
    } catch (e) {
      debugPrint('❌ 获取设备信息失败: $e');
    }
  }

  /// 获取简要信息（一行）
  static Future<String> getOneLine() async {
    try {
      final systemInfo = await DeviceInfoChannel.getSystemInfo();
      final deviceInfo = systemInfo.deviceInfo;

      return '${deviceInfo.manufacturer} ${deviceInfo.model} | '
          'Android ${deviceInfo.sdkVersion} | '
          '${deviceInfo.cpuAbi} | '
          'RAM: ${deviceInfo.formatMemory(deviceInfo.totalMemory)} | '
          'Storage: ${deviceInfo.formatMemory(deviceInfo.totalStorage)}';
    } catch (e) {
      return '未知设备';
    }
  }

  static String _getScreenDensityCategory(int dpi) {
    if (dpi >= 640) return 'XXXHDPI';
    if (dpi >= 480) return 'XXHDPI';
    if (dpi >= 320) return 'XHDPI';
    if (dpi >= 240) return 'HDPI';
    if (dpi >= 160) return 'MDPI';
    return 'LDPI';
  }
}
