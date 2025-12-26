/// 应用扫描配置
class AppConfig {
  /// 应用名称（中文）
  final String appName;

  /// 应用Key（英文标识，用于索引）
  final String appKey;

  /// 预配置包名列表（优先级1 - 最快最准确）
  /// 
  /// 多个包名支持应用的不同版本
  /// 例如：['com.tencent.mm'] - 微信
  final List<String> packageNames;

  /// 应用名称模糊匹配列表（优先级2 - 备选方案）
  /// 
  /// 当包名未知或可能变更时使用
  /// 例如：['微信', 'WeChat', 'weixin']
  /// 
  /// 注意：此功能需要查询所有已安装应用，性能较低，暂不推荐使用
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

  const AppConfig({
    required this.appName,
    required this.appKey,
    this.packageNames = const [],
    this.appLabelPatterns = const [],
    this.folderKeywords = const [],
    this.additionalPaths = const [],
    this.filePatterns = const [],
  });

  /// 验证配置是否有效
  bool get isValid {
    // 至少需要包名或文件夹关键字之一
    return packageNames.isNotEmpty || folderKeywords.isNotEmpty;
  }

  @override
  String toString() {
    return 'AppConfig(appName: $appName, appKey: $appKey, '
        'packageNames: $packageNames, folderKeywords: $folderKeywords)';
  }
}

/// 应用扫描配置中心
/// 
/// 集中管理所有预定义应用配置，便于扩充和修改
class AppScannerConfigs {
  /// 公共扫描基础路径
  /// 
  /// 这些是 Android 系统常见的公共存储目录
  static const List<String> basePaths = [
    '/storage/emulated/0/Download/',
    '/storage/emulated/0/Pictures/',
    '/storage/emulated/0/DCIM/',
    '/storage/emulated/0/Music/',
    '/storage/emulated/0/Movies/',
    '/storage/emulated/0/Documents/',
  ];

  /// 预定义应用配置映射表
  /// 
  /// 新增应用只需在此添加配置即可
  static final Map<String, AppConfig> appConfigs = {
    'wechat': _wechatConfig,
    'qq': _qqConfig,
    'telegram': _telegramConfig,
    'wps': _wpsConfig,
    'dingtalk': _dingtalkConfig,
    // 可继续添加其他应用...
  };

  // ========================================
  // 预定义应用配置（私有）
  // ========================================

  /// 微信配置
  static const _wechatConfig = AppConfig(
    appName: '微信',
    appKey: 'wechat',
    // 包名检测（快速）
    packageNames: ['com.tencent.mm'],
    // 备选：应用名称匹配
    appLabelPatterns: ['微信', 'WeChat', 'weixin'],
    // 文件夹关键字（用于动态查找）
    folderKeywords: ['WeiXin', 'weixin', 'Weixin'],
    // 文件名模式（微信相机和导出的图片）
    filePatterns: ['wx_camera_%', 'mmexport%'],
  );

  /// QQ配置
  static const _qqConfig = AppConfig(
    appName: 'QQ',
    appKey: 'qq',
    packageNames: ['com.tencent.mobileqq'],
    appLabelPatterns: ['QQ', 'qq'],
    folderKeywords: ['QQ', 'tencent'],
    filePatterns: [],
  );

  /// Telegram配置
  static const _telegramConfig = AppConfig(
    appName: 'Telegram',
    appKey: 'telegram',
    packageNames: ['org.telegram.messenger'],
    appLabelPatterns: ['Telegram'],
    folderKeywords: ['Telegram'],
    filePatterns: [],
  );

  /// WPS配置
  static const _wpsConfig = AppConfig(
    appName: 'WPS',
    appKey: 'wps',
    packageNames: ['cn.wps.moffice_eng', 'cn.wps.moffice'],
    appLabelPatterns: ['WPS', 'wps'],
    folderKeywords: ['WPS', 'kingsoft'],
    filePatterns: [],
  );

  /// 钉钉配置
  static const _dingtalkConfig = AppConfig(
    appName: '钉钉',
    appKey: 'dingtalk',
    packageNames: ['com.alibaba.android.rimet'],
    appLabelPatterns: ['钉钉', 'DingTalk', 'dingtalk'],
    folderKeywords: ['DingTalk', 'dingtalk'],
    filePatterns: [],
  );

  // ========================================
  // 工具方法
  // ========================================

  /// 获取应用配置
  /// 
  /// [appKey] 应用标识，如 'wechat'
  /// 返回对应的配置，如果不存在则返回 null
  static AppConfig? getConfig(String appKey) => appConfigs[appKey];

  /// 获取所有支持的应用Key列表
  static List<String> getAllAppKeys() => appConfigs.keys.toList();

  /// 检查是否支持某个应用
  static bool isSupported(String appKey) => appConfigs.containsKey(appKey);

  /// 添加自定义应用配置（运行时）
  /// 
  /// 允许用户在运行时动态添加应用配置
  static void addConfig(String appKey, AppConfig config) {
    if (appConfigs.containsKey(appKey)) {
      throw ArgumentError('应用配置已存在: $appKey');
    }
    appConfigs[appKey] = config;
  }

  /// 移除应用配置（运行时）
  static void removeConfig(String appKey) {
    appConfigs.remove(appKey);
  }
}
