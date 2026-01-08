import 'dart:convert';
import 'package:easyfile/core/logger.dart';
import 'storage/config_storage.dart';

/// 应用配置数据模型
///
/// 描述需要被文件管理器扫描的应用的配置信息
class AppConfigData {
  /// 应用Key（英文标识，用于索引）
  final String appKey;

  /// 应用名称（中文）
  final String appName;

  /// 应用描述（说明为什么需要扫描此应用）
  final String? description;

  /// 预配置包名列表（优先级1 - 最快最准确）
  ///
  /// 多个包名支持应用的不同版本
  /// 例如：['com.tencent.mm'] - 微信
  final List<String> packageNames;

  /// 应用名称模糊匹配列表（优先级2 - 备选方案）
  ///
  /// 当包名未知或可能变更时使用
  /// 例如：['微信', 'WeChat', 'weixin']
  final List<String> appLabelPatterns;

  /// 文件夹关键字列表（用于动态查找应用目录）
  ///
  /// 在公共目录下搜索匹配的子文件夹
  /// 例如：['WeiXin', 'weixin', 'Weixin']
  final List<String> folderKeywords;

  /// 附加扫描路径列表
  ///
  /// 在基础路径之外的额外扫描路径
  /// 例如：['/storage/emulated/0/Android/data/com.tencent.mm/']
  final List<String> additionalPaths;

  /// 文件名模式列表（用于文件名匹配）
  ///
  /// 支持 SQL LIKE 语法，% 表示通配符
  /// 例如：['wx_camera_%', 'mmexport%'] - 微信相机和导出的图片
  final List<String> filePatterns;

  /// 优先级（1=最高，数字越大优先级越低）
  final int priority;

  /// 是否启用此应用扫描
  final bool enabled;

  const AppConfigData({
    required this.appKey,
    required this.appName,
    this.description,
    this.packageNames = const [],
    this.appLabelPatterns = const [],
    this.folderKeywords = const [],
    this.additionalPaths = const [],
    this.filePatterns = const [],
    this.priority = 99,
    this.enabled = true,
  });

  /// 验证配置是否有效
  bool get isValid {
    // 至少需要包名或文件夹关键字之一
    return packageNames.isNotEmpty || folderKeywords.isNotEmpty;
  }

  /// 从 JSON 创建
  factory AppConfigData.fromJson(Map<String, dynamic> json) {
    return AppConfigData(
      appKey: json['appKey'] as String,
      appName: json['appName'] as String,
      description: json['description'] as String?,
      packageNames: (json['packageNames'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      appLabelPatterns: (json['appLabelPatterns'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      folderKeywords: (json['folderKeywords'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      additionalPaths: (json['additionalPaths'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      filePatterns: (json['filePatterns'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      priority: json['priority'] as int? ?? 99,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'appKey': appKey,
      'appName': appName,
      if (description != null) 'description': description,
      'packageNames': packageNames,
      'appLabelPatterns': appLabelPatterns,
      'folderKeywords': folderKeywords,
      'additionalPaths': additionalPaths,
      'filePatterns': filePatterns,
      'priority': priority,
      'enabled': enabled,
    };
  }

  /// 复制并修改部分字段
  AppConfigData copyWith({
    String? appKey,
    String? appName,
    String? description,
    List<String>? packageNames,
    List<String>? appLabelPatterns,
    List<String>? folderKeywords,
    List<String>? additionalPaths,
    List<String>? filePatterns,
    int? priority,
    bool? enabled,
  }) {
    return AppConfigData(
      appKey: appKey ?? this.appKey,
      appName: appName ?? this.appName,
      description: description ?? this.description,
      packageNames: packageNames ?? this.packageNames,
      appLabelPatterns: appLabelPatterns ?? this.appLabelPatterns,
      folderKeywords: folderKeywords ?? this.folderKeywords,
      additionalPaths: additionalPaths ?? this.additionalPaths,
      filePatterns: filePatterns ?? this.filePatterns,
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  String toString() {
    return 'AppConfigData(appKey: $appKey, appName: $appName, '
        'priority: $priority, enabled: $enabled)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppConfigData && other.appKey == appKey;
  }

  @override
  int get hashCode => appKey.hashCode;
}

/// 应用扫描配置类
///
/// 符合"强烈值得进Config"原则：
/// - 原则3: 推荐/排序/优先级规则
/// - 原则4: 风险开关（可禁用某个应用）
///
/// 职责：
/// 1. 管理需要被文件管理器扫描的应用配置
/// 2. 支持运行时动态启用/禁用应用
/// 3. 支持远程配置热更新
/// 4. 支持用户自定义应用配置
class AppScannerConfig {
  final ConfigStorage _storage;
  static const String _keyPrefix = 'app_scanner_';

  AppScannerConfig(this._storage);

  // ==================== 默认应用配置 ====================

  /// 预定义应用配置（代码中定义的默认值）
  ///
  /// 这些是精心挑选的应用，其文件适合被文件管理器管理
  static final Map<String, AppConfigData> _defaultApps = {
    'wechat': const AppConfigData(
      appKey: 'wechat',
      appName: '微信',
      description: '社交聊天，文件、图片、视频多',
      packageNames: ['com.tencent.mm'],
      appLabelPatterns: ['微信', 'WeChat', 'weixin'],
      folderKeywords: ['WeiXin', 'weixin', 'Weixin'],
      filePatterns: ['wx_camera_%', 'mmexport%'],
      priority: 1,
      enabled: true,
    ),
    'qq': const AppConfigData(
      appKey: 'qq',
      appName: 'QQ',
      description: '社交聊天，文件传输频繁',
      packageNames: ['com.tencent.mobileqq'],
      appLabelPatterns: ['QQ', 'qq'],
      folderKeywords: ['QQ', 'tencent'],
      priority: 2,
      enabled: true,
    ),
    'telegram': const AppConfigData(
      appKey: 'telegram',
      appName: 'Telegram',
      description: '即时通讯，文档/媒体存储多',
      packageNames: ['org.telegram.messenger'],
      appLabelPatterns: ['Telegram'],
      folderKeywords: ['Telegram'],
      priority: 2,
      enabled: true,
    ),
    'wps': const AppConfigData(
      appKey: 'wps',
      appName: 'WPS',
      description: '办公软件，文档管理核心需求',
      packageNames: ['cn.wps.moffice_eng', 'cn.wps.moffice'],
      appLabelPatterns: ['WPS', 'wps'],
      folderKeywords: ['WPS', 'kingsoft'],
      priority: 1,
      enabled: true,
    ),
    'dingtalk': const AppConfigData(
      appKey: 'dingtalk',
      appName: '钉钉',
      description: '企业协作，文件/文档分享多',
      packageNames: ['com.alibaba.android.rimet'],
      appLabelPatterns: ['钉钉', 'DingTalk', 'dingtalk'],
      folderKeywords: ['DingTalk', 'dingtalk'],
      priority: 2,
      enabled: true,
    ),
  };

  // ==================== 读取配置 ====================

  /// 获取应用配置
  ///
  /// 优先从存储读取，不存在则返回默认值
  ///
  /// [appKey] 应用标识，如 'wechat'
  /// 返回对应的配置，如果不存在则返回 null
  Future<AppConfigData?> getAppConfig(String appKey) async {
    try {
      // 1. 尝试从存储读取
      final storedJson = _storage.getString('$_keyPrefix$appKey');
      if (storedJson != null) {
        final json = jsonDecode(storedJson) as Map<String, dynamic>;
        return AppConfigData.fromJson(json);
      }

      // 2. 返回默认配置
      return _defaultApps[appKey];
    } catch (e) {
      logger.e('Error getting app config for $appKey: $e');
      return _defaultApps[appKey];
    }
  }

  /// 获取所有预定义的应用Key列表
  List<String> getAllAppKeys() => _defaultApps.keys.toList();

  /// 检查是否支持某个应用
  bool isSupported(String appKey) => _defaultApps.containsKey(appKey);

  /// 获取所有启用的应用配置
  ///
  /// 返回按优先级排序的启用应用列表
  Future<List<AppConfigData>> getEnabledApps() async {
    final apps = <AppConfigData>[];

    try {
      for (final appKey in _defaultApps.keys) {
        final config = await getAppConfig(appKey);
        if (config != null && config.enabled) {
          apps.add(config);
        }
      }

      // 按优先级排序（数字小的优先级高）
      apps.sort((a, b) => a.priority.compareTo(b.priority));

      logger.d('Loaded ${apps.length} enabled apps');
    } catch (e) {
      logger.e('Error getting enabled apps: $e');
    }

    return apps;
  }

  /// 获取所有应用配置（包括禁用的）
  Future<List<AppConfigData>> getAllApps() async {
    final apps = <AppConfigData>[];

    try {
      for (final appKey in _defaultApps.keys) {
        final config = await getAppConfig(appKey);
        if (config != null) {
          apps.add(config);
        }
      }

      // 按优先级排序
      apps.sort((a, b) => a.priority.compareTo(b.priority));
    } catch (e) {
      logger.e('Error getting all apps: $e');
    }

    return apps;
  }

  // ==================== 修改配置 ====================

  /// 设置应用启用状态
  ///
  /// [appKey] 应用标识
  /// [enabled] 是否启用
  Future<void> setAppEnabled(String appKey, bool enabled) async {
    try {
      final config = await getAppConfig(appKey);
      if (config != null) {
        final updated = config.copyWith(enabled: enabled);
        await _storage.setString(
          '$_keyPrefix$appKey',
          jsonEncode(updated.toJson()),
        );
        logger.i('App $appKey enabled set to: $enabled');
      }
    } catch (e) {
      logger.e('Error setting app enabled for $appKey: $e');
      rethrow;
    }
  }

  /// 设置应用优先级
  ///
  /// [appKey] 应用标识
  /// [priority] 优先级（1=最高）
  Future<void> setAppPriority(String appKey, int priority) async {
    try {
      final config = await getAppConfig(appKey);
      if (config != null) {
        final updated = config.copyWith(priority: priority);
        await _storage.setString(
          '$_keyPrefix$appKey',
          jsonEncode(updated.toJson()),
        );
        logger.i('App $appKey priority set to: $priority');
      }
    } catch (e) {
      logger.e('Error setting app priority for $appKey: $e');
      rethrow;
    }
  }

  /// 更新应用配置
  ///
  /// [config] 新的应用配置
  Future<void> updateAppConfig(AppConfigData config) async {
    try {
      await _storage.setString(
        '$_keyPrefix${config.appKey}',
        jsonEncode(config.toJson()),
      );
      logger.i('App config updated: ${config.appKey}');
    } catch (e) {
      logger.e('Error updating app config: $e');
      rethrow;
    }
  }

  /// 添加自定义应用配置（运行时）
  ///
  /// 允许用户或远程配置添加新的应用
  ///
  /// [config] 应用配置
  Future<void> addCustomApp(AppConfigData config) async {
    try {
      // 检查是否已存在
      final existing = await getAppConfig(config.appKey);
      if (existing != null && _defaultApps.containsKey(config.appKey)) {
        throw ArgumentError('应用配置已存在: ${config.appKey}');
      }

      await _storage.setString(
        '$_keyPrefix${config.appKey}',
        jsonEncode(config.toJson()),
      );
      logger.i('Custom app added: ${config.appKey}');
    } catch (e) {
      logger.e('Error adding custom app: $e');
      rethrow;
    }
  }

  /// 移除自定义应用配置
  ///
  /// 只能移除自定义添加的应用，预定义应用只能禁用不能移除
  ///
  /// [appKey] 应用标识
  Future<void> removeCustomApp(String appKey) async {
    try {
      if (_defaultApps.containsKey(appKey)) {
        throw ArgumentError('不能移除预定义应用: $appKey，请使用 setAppEnabled() 禁用');
      }

      await _storage.remove('$_keyPrefix$appKey');
      logger.i('Custom app removed: $appKey');
    } catch (e) {
      logger.e('Error removing custom app: $e');
      rethrow;
    }
  }

  /// 重置应用配置为默认值
  ///
  /// [appKey] 应用标识
  Future<void> resetAppConfig(String appKey) async {
    try {
      await _storage.remove('$_keyPrefix$appKey');
      logger.i('App config reset to default: $appKey');
    } catch (e) {
      logger.e('Error resetting app config: $e');
      rethrow;
    }
  }

  /// 重置所有应用配置为默认值
  Future<void> resetAllAppConfigs() async {
    try {
      for (final appKey in _defaultApps.keys) {
        await _storage.remove('$_keyPrefix$appKey');
      }
      logger.i('All app configs reset to default');
    } catch (e) {
      logger.e('Error resetting all app configs: $e');
      rethrow;
    }
  }

  // ==================== 批量操作 ====================

  /// 从远程配置合并应用配置
  ///
  /// [remoteConfigs] 远程配置的 Map（appKey -> JSON）
  Future<void> mergeRemoteConfigs(Map<String, dynamic> remoteConfigs) async {
    try {
      int updatedCount = 0;

      for (final entry in remoteConfigs.entries) {
        try {
          final configJson = entry.value as Map<String, dynamic>;
          final config = AppConfigData.fromJson(configJson);

          await updateAppConfig(config);
          updatedCount++;
        } catch (e) {
          logger.w('Failed to merge config for ${entry.key}: $e');
        }
      }

      logger.i('Merged $updatedCount app configs from remote');
    } catch (e) {
      logger.e('Error merging remote configs: $e');
      rethrow;
    }
  }

  // ==================== 调试工具 ====================

  /// 获取配置状态摘要（用于调试）
  Future<String> getConfigSummary() async {
    final buffer = StringBuffer();
    buffer.writeln('=== App Scanner Config Summary ===');

    try {
      final apps = await getAllApps();
      buffer.writeln('Total apps: ${apps.length}');
      buffer.writeln('Enabled apps: ${apps.where((a) => a.enabled).length}');
      buffer.writeln('\nApp List:');

      for (final app in apps) {
        buffer.writeln('  - ${app.appName} (${app.appKey})');
        buffer.writeln('    Priority: ${app.priority}');
        buffer.writeln('    Enabled: ${app.enabled}');
        buffer.writeln('    Package: ${app.packageNames.join(", ")}');
        buffer.writeln('    Keywords: ${app.folderKeywords.join(", ")}');
      }
    } catch (e) {
      buffer.writeln('Error: $e');
    }

    return buffer.toString();
  }
}
