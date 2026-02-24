import 'dart:io';

import 'package:easyfile/core/logger.dart';
import 'package:flutter/services.dart';

/// 设备硬件信息通道
/// 用于获取设备的硬件环境信息
class DeviceInfoChannel {
  static const _channel = MethodChannel('easyfile/native_camera_test');

  /// 获取设备硬件信息
  static Future<DeviceInfo> getDeviceInfo() async {
    try {
      logger.i('获取设备硬件信息...');

      final Map<dynamic, dynamic> result = await _channel.invokeMethod('getDeviceInfo');
      final info = Map<String, dynamic>.from(result);

      return DeviceInfo.fromMap(info);
    } catch (e) {
      logger.e('获取设备硬件信息失败: $e');
      return DeviceInfo.empty();
    }
  }

  /// 获取完整的系统信息
  static Future<SystemInfo> getSystemInfo() async {
    try {
      logger.i('获取系统完整信息...');

      final deviceInfo = await getDeviceInfo();

      // Dart 端可以获取的额外信息
      final platformInfo = {
        'operatingSystem': Platform.operatingSystem,
        'operatingSystemVersion': Platform.operatingSystemVersion,
        'numberOfProcessors': Platform.numberOfProcessors,
        'localeName': Platform.localeName,
      };

      return SystemInfo(
        deviceInfo: deviceInfo,
        platformInfo: platformInfo,
      );
    } catch (e) {
      logger.e('获取系统完整信息失败: $e');
      rethrow;
    }
  }
}

/// 设备硬件信息数据模型
class DeviceInfo {
  /// 设备制造商 (e.g., "Samsung", "Xiaomi")
  final String manufacturer;

  /// 设备型号 (e.g., "SM-G973F", "Mi 10")
  final String model;

  /// Android 版本号 (e.g., 13)
  final int androidVersion;

  /// Android SDK 版本 (e.g., 33)
  final int sdkVersion;

  /// 设备品牌 (e.g., "samsung", "xiaomi")
  final String brand;

  /// 设备名称 (e.g., "beyond1")
  final String device;

  /// 处理器架构 (e.g., "arm64-v8a")
  final String cpuAbi;

  /// 总内存 (字节)
  final int totalMemory;

  /// 可用内存 (字节)
  final int availableMemory;

  /// 总存储空间 (字节)
  final int totalStorage;

  /// 可用存储空间 (字节)
  final int availableStorage;

  /// 屏幕宽度 (像素)
  final int screenWidth;

  /// 屏幕高度 (像素)
  final int screenHeight;

  /// 屏幕密度 DPI
  final int screenDensity;

  DeviceInfo({
    required this.manufacturer,
    required this.model,
    required this.androidVersion,
    required this.sdkVersion,
    required this.brand,
    required this.device,
    required this.cpuAbi,
    required this.totalMemory,
    required this.availableMemory,
    required this.totalStorage,
    required this.availableStorage,
    required this.screenWidth,
    required this.screenHeight,
    required this.screenDensity,
  });

  factory DeviceInfo.fromMap(Map<String, dynamic> map) {
    return DeviceInfo(
      manufacturer: map['make'] as String? ?? 'Unknown',
      model: map['model'] as String? ?? 'Unknown',
      androidVersion: map['androidVersion'] as int? ?? 0,
      sdkVersion: map['sdkVersion'] as int? ?? 0,
      brand: map['brand'] as String? ?? 'Unknown',
      device: map['device'] as String? ?? 'Unknown',
      cpuAbi: map['cpuAbi'] as String? ?? 'Unknown',
      totalMemory: (map['totalMemory'] as num?)?.toInt() ?? 0,
      availableMemory: (map['availableMemory'] as num?)?.toInt() ?? 0,
      totalStorage: (map['totalStorage'] as num?)?.toInt() ?? 0,
      availableStorage: (map['availableStorage'] as num?)?.toInt() ?? 0,
      screenWidth: map['screenWidth'] as int? ?? 0,
      screenHeight: map['screenHeight'] as int? ?? 0,
      screenDensity: map['screenDensity'] as int? ?? 0,
    );
  }

  factory DeviceInfo.empty() {
    return DeviceInfo(
      manufacturer: 'Unknown',
      model: 'Unknown',
      androidVersion: 0,
      sdkVersion: 0,
      brand: 'Unknown',
      device: 'Unknown',
      cpuAbi: 'Unknown',
      totalMemory: 0,
      availableMemory: 0,
      totalStorage: 0,
      availableStorage: 0,
      screenWidth: 0,
      screenHeight: 0,
      screenDensity: 0,
    );
  }

  /// 格式化内存大小
  String formatMemory(int bytes) {
    if (bytes == 0) return '未知';

    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return '${size.toStringAsFixed(2)} ${units[unitIndex]}';
  }

  /// 获取内存使用率
  double get memoryUsagePercent {
    if (totalMemory == 0) return 0;
    return ((totalMemory - availableMemory) / totalMemory * 100);
  }

  /// 获取存储使用率
  double get storageUsagePercent {
    if (totalStorage == 0) return 0;
    return ((totalStorage - availableStorage) / totalStorage * 100);
  }

  @override
  String toString() {
    return '''
设备信息:
- 制造商: $manufacturer
- 型号: $model
- 品牌: $brand
- 设备代号: $device
- Android版本: $androidVersion (SDK $sdkVersion)
- CPU架构: $cpuAbi
- 总内存: ${formatMemory(totalMemory)}
- 可用内存: ${formatMemory(availableMemory)} (${(100 - memoryUsagePercent).toStringAsFixed(1)}%)
- 总存储: ${formatMemory(totalStorage)}
- 可用存储: ${formatMemory(availableStorage)} (${(100 - storageUsagePercent).toStringAsFixed(1)}%)
- 屏幕分辨率: ${screenWidth}x$screenHeight
- 屏幕密度: ${screenDensity}dpi
''';
  }
}

/// 系统完整信息
class SystemInfo {
  final DeviceInfo deviceInfo;
  final Map<String, dynamic> platformInfo;

  SystemInfo({
    required this.deviceInfo,
    required this.platformInfo,
  });

  @override
  String toString() {
    return '''
${deviceInfo.toString()}
系统信息:
- 操作系统: ${platformInfo['operatingSystem']}
- 系统版本: ${platformInfo['operatingSystemVersion']}
- CPU核心数: ${platformInfo['numberOfProcessors']}
- 语言区域: ${platformInfo['localeName']}
''';
  }
}
