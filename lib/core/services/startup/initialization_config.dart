import 'package:shared_preferences/shared_preferences.dart';

/// 应用初始化配置
///
/// 控制首次安装时各阶段的执行
///
/// **默认策略（quickStart模式）**：
/// - P1.1分类扫描：关闭（按需加载，用户进入时才扫描）
/// - P1.2应用扫描：开启（首页秒开体验）
/// - 原因：平衡启动速度和功能体验
class InitializationConfig {
  /// SharedPreferences 存储键
  static const String _keyEnableP1CategoryScan = 'init_enable_p1_category_scan';
  static const String _keyEnableP1AppScan = 'init_enable_p1_app_scan';

  // ========== P0 阶段 ==========

  /// 基础资源加载（快速访问、收藏夹）
  /// ⚠️ 不建议关闭，是核心功能
  final bool enableP0BasicResources = true;

  // ========== P1 阶段 ==========

  /// P1.1: 分类文件扫描总开关
  ///
  /// 控制所有分类扫描（images, video, music, documents, downloads, apk, archive）
  ///
  /// **开启时（默认）**:
  /// - 初始化时扫描所有分类
  /// - 缓存文件列表到 SharedPreferences
  /// - 用户进入分类页时秒开（直接显示缓存）
  /// - 初始化耗时: +30-50秒
  ///
  /// **关闭时**:
  /// - 初始化时跳过分类扫描
  /// - 用户首次进入分类页时才扫描（两阶段扫描）
  ///   - 阶段1: MediaStore快速显示（200-500ms）
  ///   - 阶段2: 后台路径验证（2-5秒）
  /// - 初始化耗时: -30-50秒
  ///
  /// **适用场景**:
  /// - 关闭: 追求极致启动速度
  /// - 开启: 追求分类页面秒开体验
  final bool enableP1CategoryScan;

  /// P1.2: 应用扫描开关
  ///
  /// 控制推荐应用的文件扫描（微信、QQ、WPS、钉钉等）
  ///
  /// **开启时（默认）**:
  /// - 初始化时扫描已安装应用
  /// - 缓存文件数量和列表
  /// - 用户进入首页时秒开（直接显示推荐卡片）
  /// - 初始化耗时: +15-20秒
  ///
  /// **关闭时**:
  /// - 初始化时跳过应用扫描
  /// - 用户首次进入首页时才扫描（1-2秒加载）
  /// - 仍然检测应用是否安装（不扫描文件）
  /// - 初始化耗时: -15-20秒
  ///
  /// **适用场景**:
  /// - 关闭: 追求极致启动速度
  /// - 开启: 追求首页秒开体验
  final bool enableP1AppScan;

  // ========== P2 阶段 ==========

  /// 文件夹检测（快速访问文件夹）
  /// ⚠️ 不建议关闭，是核心功能
  final bool enableP2FolderDetection = true;

  // ========== 性能优化模式 ==========

  /// 快速启动模式：跳过所有可延迟任务
  /// - 跳过 P1.1 分类扫描（-30-50秒）
  /// - 跳过 P1.2 应用扫描（-15-20秒）
  /// - 保留 P0 和 P2（核心功能）
  /// - 总节省: 45-70秒
  bool get quickStartMode => !enableP1CategoryScan && !enableP1AppScan;

  /// 构造函数
  InitializationConfig({
    this.enableP1CategoryScan = true,
    this.enableP1AppScan = true,
  });

  /// 从 SharedPreferences 加载配置
  static Future<InitializationConfig> load() async {
    final prefs = await SharedPreferences.getInstance();

    return InitializationConfig(
      enableP1CategoryScan: prefs.getBool(_keyEnableP1CategoryScan) ?? true,
      enableP1AppScan: prefs.getBool(_keyEnableP1AppScan) ?? true,
    );
  }

  /// 保存配置到 SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_keyEnableP1CategoryScan, enableP1CategoryScan);
    await prefs.setBool(_keyEnableP1AppScan, enableP1AppScan);
  }

  /// 创建快速启动配置（首次安装默认模式）
  ///
  /// P1.1分类扫描：关闭 - 节省35秒，按需加载
  /// P1.2应用扫描：开启 - 保留首页秒开体验
  factory InitializationConfig.quickStart() {
    return InitializationConfig(
      enableP1CategoryScan: false,
      enableP1AppScan: true,
    );
  }

  /// 创建完整初始化配置（所有阶段开启）
  factory InitializationConfig.full() {
    return InitializationConfig(
      enableP1CategoryScan: true,
      enableP1AppScan: true,
    );
  }

  /// 复制配置并修改部分值
  InitializationConfig copyWith({
    bool? enableP1CategoryScan,
    bool? enableP1AppScan,
  }) {
    return InitializationConfig(
      enableP1CategoryScan: enableP1CategoryScan ?? this.enableP1CategoryScan,
      enableP1AppScan: enableP1AppScan ?? this.enableP1AppScan,
    );
  }

  @override
  String toString() {
    return 'InitializationConfig('
        'P0: ✓, '
        'P1.1: ${enableP1CategoryScan ? "✓" : "✗"}, '
        'P1.2: ${enableP1AppScan ? "✓" : "✗"}, '
        'P2: ✓, '
        'quickMode: ${quickStartMode ? "✓" : "✗"}'
        ')';
  }
}
