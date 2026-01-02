# 第二部分：详细实现

## 6. 存储层实现（核心）

### 6.1 ConfigStorage 抽象接口

```dart
// lib/core/config/storage/config_storage.dart

/// 配置存储抽象接口
/// 
/// 所有配置类都依赖此接口，不依赖具体实现（如 SharedPreferences）。
/// 这样可以：
/// 1. 轻松替换存储方式（本地 → 数据库 → 远程）
/// 2. 便于单元测试（注入 MockConfigStorage）
/// 3. 支持未来的远程配置、AB Test 等功能
abstract class ConfigStorage {
  // ==================== 读取方法 ====================

  /// 读取整数值
  int? getInt(String key);

  /// 读取浮点数值
  double? getDouble(String key);

  /// 读取布尔值
  bool? getBool(String key);

  /// 读取字符串值
  String? getString(String key);

  /// 读取字符串列表
  List<String>? getStringList(String key);

  // ==================== 写入方法 ====================

  /// 写入整数值
  Future<bool> setInt(String key, int value);

  /// 写入浮点数值
  Future<bool> setDouble(String key, double value);

  /// 写入布尔值
  Future<bool> setBool(String key, bool value);

  /// 写入字符串值
  Future<bool> setString(String key, String value);

  /// 写入字符串列表
  Future<bool> setStringList(String key, List<String> value);

  // ==================== 删除方法 ====================

  /// 删除指定键
  Future<bool> remove(String key);

  /// 清空所有数据
  Future<bool> clear();

  /// 检查键是否存在
  bool containsKey(String key);

  // ==================== 批量操作 ====================

  /// 批量写入（用于远程配置合并）
  /// 
  /// 支持 Map<String, dynamic>，自动根据值类型选择合适的写入方法
  Future<void> setAll(Map<String, dynamic> values);

  /// 获取所有键
  Set<String> getKeys();

  /// 获取所有键值对（调试用）
  Map<String, dynamic> getAll();
}
```

### 6.2 LocalConfigStorage 实现

```dart
// lib/core/config/storage/local_config_storage.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'config_storage.dart';

/// 本地配置存储实现（使用 SharedPreferences）
/// 
/// 优点：
/// - Android/iOS 都支持
/// - 文件存储，可靠性高
/// - 内存占用小
/// 
/// 缺点：
/// - 不支持复杂数据类型（但通过 setAll 的类型判断可解决）
/// - 读写性能一般（但对配置类足够）
class LocalConfigStorage implements ConfigStorage {
  final SharedPreferences _prefs;

  const LocalConfigStorage(this._prefs);

  /// 工厂方法：创建实例
  static Future<LocalConfigStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalConfigStorage(prefs);
  }

  // ==================== 读取实现 ====================

  @override
  int? getInt(String key) => _prefs.getInt(key);

  @override
  double? getDouble(String key) => _prefs.getDouble(key);

  @override
  bool? getBool(String key) => _prefs.getBool(key);

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  List<String>? getStringList(String key) => _prefs.getStringList(key);

  // ==================== 写入实现 ====================

  @override
  Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);

  @override
  Future<bool> setDouble(String key, double value) => 
      _prefs.setDouble(key, value);

  @override
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  Future<bool> setString(String key, String value) => 
      _prefs.setString(key, value);

  @override
  Future<bool> setStringList(String key, List<String> value) => 
      _prefs.setStringList(key, value);

  // ==================== 删除实现 ====================

  @override
  Future<bool> remove(String key) => _prefs.remove(key);

  @override
  Future<bool> clear() => _prefs.clear();

  @override
  bool containsKey(String key) => _prefs.containsKey(key);

  // ==================== 批量操作实现 ====================

  @override
  Future<void> setAll(Map<String, dynamic> values) async {
    for (final entry in values.entries) {
      final key = entry.key;
      final value = entry.value;

      // 根据值的类型自动选择合适的写入方法
      if (value is int) {
        await setInt(key, value);
      } else if (value is double) {
        await setDouble(key, value);
      } else if (value is bool) {
        await setBool(key, value);
      } else if (value is String) {
        await setString(key, value);
      } else if (value is List<String>) {
        await setStringList(key, value);
      } else {
        throw UnsupportedError(
          'Unsupported type for key "$key": ${value.runtimeType}. '
          'Supported types: int, double, bool, String, List<String>',
        );
      }
    }
  }

  @override
  Set<String> getKeys() => _prefs.getKeys();

  @override
  Map<String, dynamic> getAll() {
    final keys = getKeys();
    final result = <String, dynamic>{};
    
    for (final key in keys) {
      // 尝试按类型读取
      result[key] = getInt(key) ??
          getDouble(key) ??
          getBool(key) ??
          getString(key) ??
          getStringList(key);
    }
    
    return result;
  }
}
```

### 6.3 MockConfigStorage 实现（测试用）

```dart
// lib/core/config/storage/mock_config_storage.dart

import 'config_storage.dart';

/// Mock 配置存储（用于单元测试）
/// 
/// 完全内存实现，不涉及 SharedPreferences，
/// 使单元测试快速且不依赖设备存储。
class MockConfigStorage implements ConfigStorage {
  final Map<String, dynamic> _data = {};

  // ==================== 读取实现 ====================

  @override
  int? getInt(String key) => _data[key] as int?;

  @override
  double? getDouble(String key) => _data[key] as double?;

  @override
  bool? getBool(String key) => _data[key] as bool?;

  @override
  String? getString(String key) => _data[key] as String?;

  @override
  List<String>? getStringList(String key) => 
      _data[key] as List<String>?;

  // ==================== 写入实现 ====================

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = value;
    return true;
  }

  // ==================== 删除实现 ====================

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }

  @override
  bool containsKey(String key) => _data.containsKey(key);

  // ==================== 批量操作实现 ====================

  @override
  Future<void> setAll(Map<String, dynamic> values) async {
    _data.addAll(values);
  }

  @override
  Set<String> getKeys() => _data.keys.toSet();

  @override
  Map<String, dynamic> getAll() => Map.from(_data);

  /// 测试辅助方法：直接读取内存数据（绕过类型检查）
  dynamic getRaw(String key) => _data[key];
}
```

---

## 7. 配置类实现

### 7.1 AppConfig 统一入口

```dart
// lib/core/config/app_config.dart

import 'package:easyfile/core/logger.dart';
import 'storage/config_storage.dart';
import 'storage/local_config_storage.dart';
import 'build_config.dart';
import 'feature_config.dart';
import 'file_scan_config.dart';
import 'ui_config.dart';
import 'path_config.dart';
import 'debug_config.dart';

/// 应用配置统一入口
/// 
/// 单例模式，业务代码通过 AppConfig.instance 访问所有配置。
/// 
/// 使用示例：
/// ```dart
/// final maxSize = AppConfig.instance.fileScan.largeFileThreshold;
/// if (AppConfig.instance.feature.isNewFilesEnabled) { ... }
/// if (AppConfig.instance.build.isDebug) { ... }
/// ```
class AppConfig {
  static final AppConfig _instance = AppConfig._internal();

  /// 获取单例实例
  static AppConfig get instance => _instance;

  AppConfig._internal();

  // ==================== 配置模块（公开访问） ====================

  /// 编译期配置（环境、版本等）
  late final BuildConfig build = BuildConfig();

  /// 功能开关（可动态改变）
  late final FeatureConfig feature;

  /// 文件扫描配置（可动态改变）
  late final FileScanConfig fileScan;

  /// UI 参数配置（不可变）
  late final UiConfig ui = UiConfig();

  /// 系统路径配置（不可变）
  late final PathConfig paths = PathConfig();

  /// 调试与实验配置（Debug 时有效）
  late final DebugConfig debug = DebugConfig();

  // ==================== 存储实例（内部使用） ====================

  late ConfigStorage _storage;

  /// 获取存储实例（高级用途）
  ConfigStorage get storage => _storage;

  // ==================== 初始化方法 ====================

  /// 初始化配置系统
  /// 
  /// 【重要】需要在 main() 中尽早调用，通常在其他初始化之前。
  /// 
  /// 参数：
  /// - storage: 自定义存储实现。如果为 null，使用 LocalConfigStorage
  /// 
  /// 示例：
  /// ```dart
  /// void main() async {
  ///   // 方案一：使用默认存储（生产环境）
  ///   await AppConfig.instance.initialize();
  ///   
  ///   // 方案二：使用自定义存储（测试/特殊场景）
  ///   final mockStorage = MockConfigStorage();
  ///   await AppConfig.instance.initialize(storage: mockStorage);
  /// }
  /// ```
  Future<void> initialize({
    ConfigStorage? storage,
  }) async {
    try {
      logger.i('Initializing AppConfig...');

      // 1. 初始化存储层
      if (storage != null) {
        _storage = storage;
        logger.i('✓ Using custom storage: ${storage.runtimeType}');
      } else {
        _storage = await LocalConfigStorage.create();
        logger.i('✓ Using LocalConfigStorage (SharedPreferences)');
      }

      // 2. 初始化需要存储的配置模块
      feature = FeatureConfig(_storage);
      fileScan = FileScanConfig(_storage);
      logger.i('✓ FeatureConfig & FileScanConfig initialized');

      // 3. 应用调试配置覆盖
      debug.applyOverrides();
      logger.i('✓ DebugConfig applied');

      logger.i('✅ AppConfig initialization complete');
    } catch (e) {
      logger.e('❌ Failed to initialize AppConfig: $e');
      rethrow;
    }
  }

  // ==================== 重置方法（测试用） ====================

  /// 重置所有配置为默认值
  /// 
  /// 仅用于单元测试，生产环境禁用。
  Future<void> resetToDefaults() async {
    await feature.reset();
    await fileScan.reset();
    debug.reset();
    logger.i('🔄 All configs reset to defaults');
  }

  /// 打印配置状态（调试用）
  void printStatus() {
    if (!build.isDebug) return;

    print('╔════════════════════════════════════════╗');
    print('║         AppConfig Status Report        ║');
    print('╠════════════════════════════════════════╣');
    print('║ Environment: ${build.environment.name}');
    print('║ Storage: ${_storage.runtimeType}');
    print('║ Log Level: ${debug.logLevel}');
    print('║ Features Enabled: ${_countEnabledFeatures()}');
    print('╚════════════════════════════════════════╝');
  }

  int _countEnabledFeatures() {
    int count = 0;
    if (feature.isNewFilesEnabled) count++;
    if (feature.isLargeFilesEnabled) count++;
    if (feature.isDuplicateFilesEnabled) count++;
    if (feature.isJunkCleanupEnabled) count++;
    if (feature.isAppManagementEnabled) count++;
    if (feature.isTrashEnabled) count++;
    if (feature.isFavoritesEnabled) count++;
    return count;
  }
}
```

### 7.2 BuildConfig 编译期配置

```dart
// lib/core/config/build_config.dart

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 编译期配置（不可变）
/// 
/// 包含环境、版本、SDK 版本等信息。
/// 这些值在编译后就固定了，运行时不会改变。
class BuildConfig {
  // ==================== 环境标识 ====================

  /// 是否为 Debug 模式
  bool get isDebug => kDebugMode;

  /// 是否为 Profile 模式
  bool get isProfile => kProfileMode;

  /// 是否为 Release 模式
  bool get isRelease => kReleaseMode;

  /// 当前环境枚举值
  /// 
  /// 用于条件判断，比字符串判断更安全：
  /// ```dart
  /// switch (AppConfig.instance.build.environment) {
  ///   case Environment.development:
  ///     enableDetailedLogging();
  ///   case Environment.staging:
  ///     enableNetworkMocking();
  ///   case Environment.production:
  ///     disableDebugFeatures();
  /// }
  /// ```
  Environment get environment {
    if (isDebug) return Environment.development;
    if (isProfile) return Environment.staging;
    return Environment.production;
  }

  // ==================== 应用标识 ====================

  /// 应用包名
  String get packageName => 'com.guangqi.easyfile';

  /// 应用显示名称
  String get appName => 'EasyFile';

  /// 应用标签（用于日志、崩溃报告）
  String get appLabel => '$appName/$packageName';

  // ==================== SDK 版本要求 ====================

  /// 最低 Android SDK 版本（对应 Android 7.0）
  int get minSdkVersion => 24;

  /// 目标 Android SDK 版本（对应 Android 14）
  int get targetSdkVersion => 34;

  /// 最低 iOS 版本（预留）
  String? get minIOSVersion => null;

  // ==================== 平台支持 ====================

  /// 是否支持 iOS（预留，未来实现）
  bool get supportsIOS => false;

  /// 是否支持 Android
  bool get supportsAndroid => true;

  // ==================== 版本信息（异步） ====================

  /// 获取应用版本信息
  /// 
  /// 注意：这个方法是异步的，需要在使用前 await
  /// 
  /// 示例：
  /// ```dart
  /// final version = await AppConfig.instance.build.getVersion();
  /// print('App version: $version'); // 输出：App version: 1.0.0+123
  /// ```
  Future<AppVersion> getVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return AppVersion(
        version: info.version,
        buildNumber: info.buildNumber,
        fullVersion: '${info.version}+${info.buildNumber}',
      );
    } catch (e) {
      return const AppVersion(
        version: 'unknown',
        buildNumber: 'unknown',
        fullVersion: 'unknown',
      );
    }
  }
}

/// 运行环境枚举
enum Environment {
  /// 开发环境（Debug 模式）
  development,

  /// 测试环境（Profile 模式）
  staging,

  /// 生产环境（Release 模式）
  production;

  /// 是否为开发环境
  bool get isDev => this == Environment.development;

  /// 是否为测试环境
  bool get isStaging => this == Environment.staging;

  /// 是否为生产环境
  bool get isProd => this == Environment.production;
}

/// 应用版本信息
class AppVersion {
  /// 应用版本号（语义化版本，如 1.0.0）
  final String version;

  /// 构建号（整数，用于区分同版本的不同构建）
  final String buildNumber;

  /// 完整版本号（version + buildNumber，如 1.0.0+123）
  final String fullVersion;

  const AppVersion({
    required this.version,
    required this.buildNumber,
    required this.fullVersion,
  });

  @override
  String toString() => fullVersion;
}
```

### 7.3 FeatureConfig 功能开关（改进版）

```dart
// lib/core/config/feature_config.dart

import 'package:easyfile/core/logger.dart';
import 'storage/config_storage.dart';

/// 功能开关配置
/// 
/// 控制应用各功能模块的启用/禁用状态。
/// 支持动态改变和远程配置覆盖，适合灰度发布和 AB Test。
/// 
/// 注意：
/// - 此类依赖 ConfigStorage 抽象，而非 SharedPreferences
/// - 默认值为 true，即功能默认启用
/// - 远程配置可以覆盖本地配置
class FeatureConfig {
  final ConfigStorage _storage;

  // ==================== 存储键前缀 ====================
  static const String _keyPrefix = 'feature_';

  FeatureConfig(this._storage);

  // ==================== 核心功能开关 ====================

  /// 新文件扫描功能
  /// 
  /// 用于首页的"新文件"Tab，显示最近 7 天内新增的文件。
  /// 默认启用。
  bool get isNewFilesEnabled => _getBool('new_files', defaultValue: true);

  /// 大文件扫描功能
  /// 
  /// 用于查找占用空间过多的文件（默认 >50MB）。
  /// 默认启用。
  bool get isLargeFilesEnabled => _getBool('large_files', defaultValue: true);

  /// 重复文件扫描功能
  /// 
  /// 用于发现重复的文件副本。
  /// 默认启用。
  bool get isDuplicateFilesEnabled => 
      _getBool('duplicate_files', defaultValue: true);

  /// 垃圾文件清理功能
  /// 
  /// 用于清理临时文件、空文件夹等。
  /// 默认启用。
  bool get isJunkCleanupEnabled => _getBool('junk_cleanup', defaultValue: true);

  /// 应用管理功能
  /// 
  /// 用于查看和卸载已安装的应用。
  /// 默认启用。
  bool get isAppManagementEnabled => 
      _getBool('app_management', defaultValue: true);

  /// 回收站功能
  /// 
  /// 用于恢复误删的文件（7 天内）。
  /// 默认启用。
  bool get isTrashEnabled => _getBool('trash', defaultValue: true);

  /// 收藏功能
  /// 
  /// 用于快速访问常用文件和文件夹。
  /// 默认启用。
  bool get isFavoritesEnabled => _getBool('favorites', defaultValue: true);

  // ==================== 高级功能开关 ====================

  /// 视频缩略图生成
  /// 
  /// 在列表/网格中显示视频的第一帧作为缩略图。
  /// 消耗 CPU 但提升用户体验，默认启用。
  bool get isVideoThumbnailEnabled => 
      _getBool('video_thumbnail', defaultValue: true);

  /// 媒体信息详情展示
  /// 
  /// 在详情页中显示图片/视频的详细元数据（分辨率、拍摄时间等）。
  /// 默认启用。
  bool get isMediaInfoEnabled => _getBool('media_info', defaultValue: true);

  /// 文件预览功能
  /// 
  /// 支持在应用内预览图片、视频等多媒体文件。
  /// 默认启用。
  bool get isFilePreviewEnabled => _getBool('file_preview', defaultValue: true);

  /// 音频播放器
  /// 
  /// 在应用内播放音乐文件。
  /// 默认启用。
  bool get isAudioPlayerEnabled => _getBool('audio_player', defaultValue: true);

  // ==================== 实验性功能（预留，默认禁用） ====================

  /// 云同步功能（未来）
  /// 
  /// 将文件操作同步到云端。
  /// 当前不可用，默认禁用。
  bool get isCloudSyncEnabled => _getBool('cloud_sync', defaultValue: false);

  /// 会员功能（未来）
  /// 
  /// 控制高级功能的访问权限。
  /// 当前不可用，默认禁用。
  bool get isPremiumEnabled => _getBool('premium', defaultValue: false);

  /// AI 推荐功能（未来）
  /// 
  /// 基于用户行为的智能推荐。
  /// 当前不可用，默认禁用。
  bool get isAIRecommendEnabled => _getBool('ai_recommend', defaultValue: false);

  // ==================== 内部实现 ====================

  /// 读取布尔值，带默认值
  bool _getBool(String key, {required bool defaultValue}) {
    final fullKey = '$_keyPrefix$key';
    return _storage.getBool(fullKey) ?? defaultValue;
  }

  /// 写入布尔值
  Future<void> _setBool(String key, bool value) async {
    final fullKey = '$_keyPrefix$key';
    await _storage.setBool(fullKey, value);
  }

  // ==================== 公开接口 ====================

  /// 动态设置功能开关
  /// 
  /// 用于灰度发布或 AB Test：
  /// ```dart
  /// await AppConfig.instance.feature.setFeature('new_ui', enabled: true);
  /// ```
  Future<void> setFeature(String key, {required bool enabled}) async {
    try {
      await _setBool(key, enabled);
      logger.i('Feature "$key" set to $enabled');
    } catch (e) {
      logger.e('Failed to set feature "$key": $e');
      rethrow;
    }
  }

  /// 批量更新功能开关（用于远程配置）
  /// 
  /// 示例：
  /// ```dart
  /// final remoteFlags = {
  ///   'new_files': false,
  ///   'premium': true,
  /// };
  /// await AppConfig.instance.feature.mergeWith(remoteFlags);
  /// ```
  Future<void> mergeWith(Map<String, bool> remoteFlags) async {
    try {
      final prefixedData = remoteFlags.map(
        (key, value) => MapEntry('$_keyPrefix$key', value),
      );
      await _storage.setAll(prefixedData);
      logger.i('Merged ${remoteFlags.length} feature flags from remote');
    } catch (e) {
      logger.e('Failed to merge feature flags: $e');
      rethrow;
    }
  }

  /// 重置所有功能开关为默认值
  /// 
  /// 仅用于测试，生产环境慎用。
  Future<void> reset() async {
    try {
      final keys = _storage.getKeys()
          .where((key) => key.startsWith(_keyPrefix))
          .toList();
      
      for (final key in keys) {
        await _storage.remove(key);
      }
      logger.i('Reset all feature flags to defaults');
    } catch (e) {
      logger.e('Failed to reset feature flags: $e');
      rethrow;
    }
  }

  /// 获取所有已启用的功能列表（调试用）
  List<String> getEnabledFeatures() {
    final enabled = <String>[];
    if (isNewFilesEnabled) enabled.add('new_files');
    if (isLargeFilesEnabled) enabled.add('large_files');
    if (isDuplicateFilesEnabled) enabled.add('duplicate_files');
    if (isJunkCleanupEnabled) enabled.add('junk_cleanup');
    if (isAppManagementEnabled) enabled.add('app_management');
    if (isTrashEnabled) enabled.add('trash');
    if (isFavoritesEnabled) enabled.add('favorites');
    if (isVideoThumbnailEnabled) enabled.add('video_thumbnail');
    if (isMediaInfoEnabled) enabled.add('media_info');
    if (isFilePreviewEnabled) enabled.add('file_preview');
    if (isAudioPlayerEnabled) enabled.add('audio_player');
    if (isCloudSyncEnabled) enabled.add('cloud_sync');
    if (isPremiumEnabled) enabled.add('premium');
    if (isAIRecommendEnabled) enabled.add('ai_recommend');
    return enabled;
  }
}
```

---

这是第二部分的代码实现，包含了：
✅ ConfigStorage 完整抽象接口  
✅ LocalConfigStorage 实现（SharedPreferences）  
✅ MockConfigStorage 实现（单元测试）  
✅ AppConfig 统一入口  
✅ BuildConfig 编译期配置  
✅ FeatureConfig 功能开关（改进版）  

篇幅限制，DebugConfig、FileScanConfig、UiConfig、PathConfig 在下一个文件中继续。
