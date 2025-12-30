import 'package:flutter/foundation.dart';

/// 编译期配置（不可变，不需要存储）
/// 
/// 包含环境标识、应用信息等编译时确定的常量。
class BuildConfig {
  // ==================== 环境标识 ====================

  /// 是否为 Debug 模式
  bool get isDebug => kDebugMode;

  /// 是否为 Profile 模式
  bool get isProfile => kProfileMode;

  /// 是否为 Release 模式
  bool get isRelease => kReleaseMode;

  /// 当前环境
  Environment get environment {
    if (isDebug) return Environment.development;
    if (isProfile) return Environment.staging;
    return Environment.production;
  }

  // ==================== 应用标识 ====================

  /// 应用包名
  String get packageName => 'com.guangqi.easyfile';

  /// 应用名称
  String get appName => 'EasyFile';

  // ==================== 平台支持 ====================

  /// 是否支持 iOS（预留）
  bool get supportsIOS => false;

  /// 是否支持 Android
  bool get supportsAndroid => true;
}

/// 运行环境枚举
enum Environment {
  development,
  staging,
  production;

  bool get isDev => this == Environment.development;
  bool get isStaging => this == Environment.staging;
  bool get isProd => this == Environment.production;
}
