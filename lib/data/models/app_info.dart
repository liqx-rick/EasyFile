import 'package:installed_apps/app_info.dart' as installed;
import 'dart:typed_data';
import 'package:easyfile/data/models/app_usage_stats.dart';

/// 应用信息模型
class EasyFileAppInfo {
  /// 应用名称
  final String name;

  /// 包名
  final String packageName;

  /// 版本名称
  final String versionName;

  /// 版本号
  final int versionCode;

  /// 应用图标（原始字节数据）
  final Uint8List? icon;

  /// 安装时间
  final DateTime? installTime;

  /// 更新时间
  final DateTime? updateTime;

  /// 是否为系统应用
  final bool isSystemApp;

  /// 应用存储信息（需要权限，可能为null）
  AppStorageInfo? storageInfo;

  /// 应用使用统计（需要权限，可能为null）
  AppUsageStats? usageStats;

  EasyFileAppInfo({
    required this.name,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    this.icon,
    this.installTime,
    this.updateTime,
    required this.isSystemApp,
    this.storageInfo,
    this.usageStats,
  });

  /// 从 installed_apps 包的 AppInfo 对象创建
  factory EasyFileAppInfo.fromInstalledApp(installed.AppInfo app) {
    // 智能检测时间戳单位（秒 vs 毫秒）
    // 如果时间戳小于 10000000000（2001年之前），则认为是秒，需要转换为毫秒
    final timestamp = app.installedTimestamp;
    final milliseconds = timestamp < 10000000000 ? timestamp * 1000 : timestamp;

    return EasyFileAppInfo(
      name: app.name,
      packageName: app.packageName,
      versionName: app.versionName,
      versionCode: app.versionCode,
      icon: app.icon, // 直接使用Uint8List
      installTime: DateTime.fromMillisecondsSinceEpoch(milliseconds),
      updateTime: null, // installed_apps 不提供更新时间
      isSystemApp: false, // 需要另外检查
    );
  }

  /// 从 JSON 创建
  factory EasyFileAppInfo.fromJson(Map<String, dynamic> json) {
    return EasyFileAppInfo(
      name: json['name'] as String,
      packageName: json['packageName'] as String,
      versionName: json['versionName'] as String,
      versionCode: json['versionCode'] as int,
      icon: null, // 不序列化图标数据
      installTime: json['installTime'] != null
          ? DateTime.parse(json['installTime'] as String)
          : null,
      updateTime: json['updateTime'] != null
          ? DateTime.parse(json['updateTime'] as String)
          : null,
      isSystemApp: json['isSystemApp'] as bool,
      storageInfo: json['storageInfo'] != null
          ? AppStorageInfo.fromJson(json['storageInfo'] as Map<String, dynamic>)
          : null,
      usageStats: json['usageStats'] != null
          ? AppUsageStats.fromJson(json['usageStats'] as Map<String, dynamic>)
          : null,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'packageName': packageName,
      'versionName': versionName,
      'versionCode': versionCode,
      // icon不序列化，缓存中不需要
      'installTime': installTime?.toIso8601String(),
      'updateTime': updateTime?.toIso8601String(),
      'isSystemApp': isSystemApp,
      'storageInfo': storageInfo?.toJson(),
      'usageStats': usageStats?.toJson(),
    };
  }

  /// 获取总占用空间
  int get totalSize => storageInfo?.totalSize ?? 0;

  /// 复制并更新字段
  EasyFileAppInfo copyWith({
    String? name,
    String? packageName,
    String? versionName,
    int? versionCode,
    Uint8List? icon,
    DateTime? installTime,
    DateTime? updateTime,
    bool? isSystemApp,
    AppStorageInfo? storageInfo,
    AppUsageStats? usageStats,
  }) {
    return EasyFileAppInfo(
      name: name ?? this.name,
      packageName: packageName ?? this.packageName,
      versionName: versionName ?? this.versionName,
      versionCode: versionCode ?? this.versionCode,
      icon: icon ?? this.icon,
      installTime: installTime ?? this.installTime,
      updateTime: updateTime ?? this.updateTime,
      isSystemApp: isSystemApp ?? this.isSystemApp,
      storageInfo: storageInfo ?? this.storageInfo,
      usageStats: usageStats ?? this.usageStats,
    );
  }

  @override
  String toString() {
    return 'AppInfo(name: $name, package: $packageName, size: ${totalSize > 0 ? totalSize : "unknown"})';
  }
}

/// 应用存储信息
class AppStorageInfo {
  /// 应用本身大小（字节）
  final int appSize;

  /// 数据大小（字节）
  final int dataSize;

  /// 缓存大小（字节）
  final int cacheSize;

  /// 缓存时间
  final DateTime cachedTime;

  AppStorageInfo({
    required this.appSize,
    required this.dataSize,
    required this.cacheSize,
    DateTime? cachedTime,
  }) : cachedTime = cachedTime ?? DateTime.now();

  /// 总大小
  ///
  /// 根据 Android StorageStats API 文档：
  /// - appBytes = APK + native libraries + OBB files
  /// - dataBytes = all data (INCLUDING cache)
  /// - cacheBytes = cache only (subset of dataBytes)
  ///
  /// 因此总大小 = appSize + dataSize (不能再加 cacheSize，否则会重复计算)
  /// cacheSize 仅用于单独显示缓存占用
  int get totalSize => appSize + dataSize;

  /// 从JSON创建
  factory AppStorageInfo.fromJson(Map<String, dynamic> json) {
    return AppStorageInfo(
      appSize: json['appSize'] as int,
      dataSize: json['dataSize'] as int,
      cacheSize: json['cacheSize'] as int,
      cachedTime: DateTime.parse(json['cachedTime'] as String),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'appSize': appSize,
      'dataSize': dataSize,
      'cacheSize': cacheSize,
      'cachedTime': cachedTime.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'AppStorageInfo(total: $totalSize, app: $appSize, data: $dataSize, cache: $cacheSize)';
  }
}
