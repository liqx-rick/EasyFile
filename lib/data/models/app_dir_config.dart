/// 应用目录配置
///
/// 用于配置需要扫描的应用目录信息
class AppDirConfig {
  /// 应用名称
  final String name;

  /// 主要路径
  final String path;

  /// 优先级（1=高, 2=中, 3=低）
  final int priority;

  /// 备选路径列表（如果主路径不存在，尝试这些路径）
  final List<String> alternativePaths;

  /// 图标名称（可选）
  final String? iconName;

  const AppDirConfig({
    required this.name,
    required this.path,
    required this.priority,
    this.alternativePaths = const [],
    this.iconName,
  });

  /// 是否是高优先级
  bool get isHighPriority => priority == 1;

  /// 是否是中优先级
  bool get isMediumPriority => priority == 2;

  /// 是否是低优先级
  bool get isLowPriority => priority == 3;

  @override
  String toString() {
    return 'AppDirConfig(name: $name, priority: $priority, path: $path)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppDirConfig &&
        other.name == name &&
        other.path == path &&
        other.priority == priority;
  }

  @override
  int get hashCode => name.hashCode ^ path.hashCode ^ priority.hashCode;
}

/// 预定义的应用目录配置
class AppDirConfigs {
  /// Tier 1 - 高优先级应用（必扫描）
  static const List<AppDirConfig> tier1Apps = [
    // 社交通讯 (7个)
    AppDirConfig(
      name: 'WhatsApp',
      path: '/storage/emulated/0/WhatsApp',
      priority: 1,
      iconName: 'whatsapp',
    ),
    AppDirConfig(
      name: 'WeChat',
      path: '/storage/emulated/0/tencent/MicroMsg',
      priority: 1,
      alternativePaths: ['/storage/emulated/0/WeChat'],
      iconName: 'wechat',
    ),
    AppDirConfig(
      name: 'Telegram',
      path: '/storage/emulated/0/Telegram',
      priority: 1,
      iconName: 'telegram',
    ),
    AppDirConfig(
      name: 'Facebook',
      path: '/storage/emulated/0/Facebook',
      priority: 1,
      iconName: 'facebook',
    ),
    AppDirConfig(
      name: 'Instagram',
      path: '/storage/emulated/0/Instagram',
      priority: 1,
      iconName: 'instagram',
    ),
    AppDirConfig(
      name: 'QQ',
      path: '/storage/emulated/0/tencent/QQfile_recv',
      priority: 1,
      alternativePaths: ['/storage/emulated/0/tencent/QQ_Files'],
      iconName: 'qq',
    ),
    AppDirConfig(
      name: 'TikTok',
      path: '/storage/emulated/0/TikTok',
      priority: 1,
      iconName: 'tiktok',
    ),

    // 媒体娱乐 (5个)
    AppDirConfig(
      name: 'Spotify',
      path: '/storage/emulated/0/Spotify',
      priority: 1,
      iconName: 'music',
    ),
    AppDirConfig(
      name: 'YouTube',
      path: '/storage/emulated/0/YouTube',
      priority: 1,
      iconName: 'videos',
    ),
    AppDirConfig(
      name: 'Netflix',
      path: '/storage/emulated/0/Netflix',
      priority: 1,
      iconName: 'videos',
    ),
    AppDirConfig(
      name: 'Snapchat',
      path: '/storage/emulated/0/Snapchat',
      priority: 1,
      iconName: 'pictures',
    ),
    AppDirConfig(
      name: '抖音',
      path: '/storage/emulated/0/douyin',
      priority: 1,
      alternativePaths: ['/storage/emulated/0/Douyin'],
      iconName: 'videos',
    ),

    // 工具类 (3个)
    AppDirConfig(
      name: 'Bluetooth',
      path: '/storage/emulated/0/bluetooth',
      priority: 1,
      iconName: 'storage',
    ),
    AppDirConfig(
      name: 'Screenshots',
      path: '/storage/emulated/0/Screenshots',
      priority: 1,
      alternativePaths: ['/storage/emulated/0/Pictures/Screenshots'],
      iconName: 'pictures',
    ),
    AppDirConfig(
      name: 'Screenrecorder',
      path: '/storage/emulated/0/Screenrecorder',
      priority: 1,
      alternativePaths: ['/storage/emulated/0/Movies/Screenrecorder'],
      iconName: 'videos',
    ),
  ];

  /// Tier 2 - 中优先级应用（条件扫描）
  static const List<AppDirConfig> tier2Apps = [
    // 社交媒体 (8个)
    AppDirConfig(
      name: 'Twitter',
      path: '/storage/emulated/0/Twitter',
      priority: 2,
      iconName: 'pictures',
    ),
    AppDirConfig(
      name: 'LinkedIn',
      path: '/storage/emulated/0/LinkedIn',
      priority: 2,
    ),
    AppDirConfig(
      name: 'Pinterest',
      path: '/storage/emulated/0/Pinterest',
      priority: 2,
      iconName: 'pictures',
    ),
    AppDirConfig(
      name: 'Reddit',
      path: '/storage/emulated/0/Reddit',
      priority: 2,
    ),
    AppDirConfig(
      name: 'Discord',
      path: '/storage/emulated/0/Discord',
      priority: 2,
    ),
    AppDirConfig(name: 'Viber', path: '/storage/emulated/0/Viber', priority: 2),
    AppDirConfig(name: 'Line', path: '/storage/emulated/0/Line', priority: 2),
    AppDirConfig(
      name: '微博',
      path: '/storage/emulated/0/weibo',
      priority: 2,
      alternativePaths: ['/storage/emulated/0/sina/weibo'],
    ),

    // 媒体编辑 (7个)
    AppDirConfig(
      name: 'Camera',
      path: '/storage/emulated/0/Camera',
      priority: 2,
      alternativePaths: ['/storage/emulated/0/DCIM/Camera'],
      iconName: 'pictures',
    ),
    AppDirConfig(
      name: 'PicsArt',
      path: '/storage/emulated/0/PicsArt',
      priority: 2,
      iconName: 'pictures',
    ),
    AppDirConfig(
      name: 'VSCO',
      path: '/storage/emulated/0/VSCO',
      priority: 2,
      iconName: 'pictures',
    ),
    AppDirConfig(
      name: 'Canva',
      path: '/storage/emulated/0/Canva',
      priority: 2,
      iconName: 'pictures',
    ),
    AppDirConfig(
      name: 'InShot',
      path: '/storage/emulated/0/InShot',
      priority: 2,
      iconName: 'videos',
    ),
    AppDirConfig(
      name: 'CapCut',
      path: '/storage/emulated/0/CapCut',
      priority: 2,
      iconName: 'videos',
    ),
    AppDirConfig(
      name: '剪映',
      path: '/storage/emulated/0/JianYing',
      priority: 2,
      alternativePaths: ['/storage/emulated/0/jianying'],
      iconName: 'videos',
    ),

    // 游戏平台 (3个)
    AppDirConfig(
      name: '游戏',
      path: '/storage/emulated/0/games',
      priority: 2,
      alternativePaths: ['/storage/emulated/0/Games'],
    ),
    AppDirConfig(
      name: '王者荣耀',
      path: '/storage/emulated/0/tencent/tmgp/sgame',
      priority: 2,
    ),
    AppDirConfig(
      name: '原神',
      path: '/storage/emulated/0/Android/data/com.miHoYo.GenshinImpact',
      priority: 2,
    ),

    // 云存储 (2个)
    AppDirConfig(
      name: 'GoogleDrive',
      path: '/storage/emulated/0/GoogleDrive',
      priority: 2,
      iconName: 'storage',
    ),
    AppDirConfig(
      name: 'Dropbox',
      path: '/storage/emulated/0/Dropbox',
      priority: 2,
      iconName: 'storage',
    ),
  ];

  /// Tier 3 - 低优先级应用（用户触发）
  static const List<AppDirConfig> tier3Apps = [
    // 办公协作
    AppDirConfig(name: 'Slack', path: '/storage/emulated/0/Slack', priority: 3),
    AppDirConfig(
      name: 'Notion',
      path: '/storage/emulated/0/Notion',
      priority: 3,
      iconName: 'documents',
    ),
    AppDirConfig(
      name: 'Evernote',
      path: '/storage/emulated/0/Evernote',
      priority: 3,
      iconName: 'documents',
    ),

    // 电商购物
    AppDirConfig(name: '淘宝', path: '/storage/emulated/0/taobao', priority: 3),
    AppDirConfig(name: '京东', path: '/storage/emulated/0/jd', priority: 3),
    AppDirConfig(
      name: '拼多多',
      path: '/storage/emulated/0/pinduoduo',
      priority: 3,
    ),

    // 阅读学习
    AppDirConfig(
      name: 'Kindle',
      path: '/storage/emulated/0/Kindle',
      priority: 3,
      iconName: 'documents',
    ),
    AppDirConfig(
      name: '微信读书',
      path: '/storage/emulated/0/WeChatRead',
      priority: 3,
      iconName: 'documents',
    ),
    AppDirConfig(
      name: '百度网盘',
      path: '/storage/emulated/0/baidu/netdisk',
      priority: 3,
      iconName: 'storage',
    ),

    // 其他
    AppDirConfig(name: 'Zoom', path: '/storage/emulated/0/Zoom', priority: 3),
    AppDirConfig(name: '支付宝', path: '/storage/emulated/0/alipay', priority: 3),
    AppDirConfig(name: '美团', path: '/storage/emulated/0/meituan', priority: 3),
    AppDirConfig(name: '高德地图', path: '/storage/emulated/0/amap', priority: 3),
    AppDirConfig(
      name: '网易云音乐',
      path: '/storage/emulated/0/netease/cloudmusic',
      priority: 3,
      iconName: 'music',
    ),
    AppDirConfig(
      name: 'QQ音乐',
      path: '/storage/emulated/0/qqmusic',
      priority: 3,
      iconName: 'music',
    ),
  ];

  /// 获取所有应用配置
  static List<AppDirConfig> get allApps => [
    ...tier1Apps,
    ...tier2Apps,
    ...tier3Apps,
  ];

  /// 根据优先级获取应用配置
  static List<AppDirConfig> getAppsByPriority(int priority) {
    return allApps.where((app) => app.priority == priority).toList();
  }

  /// 获取高优先级应用
  static List<AppDirConfig> get highPriorityApps => tier1Apps;

  /// 获取中高优先级应用
  static List<AppDirConfig> get mediumHighPriorityApps => [
    ...tier1Apps,
    ...tier2Apps,
  ];
}
