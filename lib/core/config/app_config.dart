import 'package:easyfile/core/logger.dart';
import 'storage/config_storage.dart';
import 'storage/local_config_storage.dart';
import 'build_config.dart';
import 'feature_config.dart';
import 'file_scan_config.dart';
import 'file_types_config.dart';
import 'app_scanner_config.dart';
import 'duplicate_files_recommendation_config.dart';

/// 应用配置统一入口
/// 
/// 单例模式，业务代码通过 AppConfig.instance 访问所有配置。
/// 
/// 设计原则：
/// 1. 不会被产品反复改的，不进
/// 2. 用户不可感知差异的，不进
/// 3. 必须和代码强一致的，不进
/// 
/// 强烈值得进Config：
/// 1. 功能是否存在（Feature Toggle）
/// 2. 策略阈值
/// 3. 推荐/排序/优先级规则
/// 4. 风险开关（止血用）
/// 5. 实验性体验参数
/// 
/// 使用示例：
/// ```dart
/// // 功能开关
/// if (AppConfig.instance.feature.isNewFilesEnabled) { ... }
/// 
/// // 策略阈值
/// final threshold = AppConfig.instance.fileScan.largeFileThreshold;
/// 
/// // 环境判断
/// if (AppConfig.instance.build.isDebug) { ... }
/// ```
class AppConfig {
  static final AppConfig _instance = AppConfig._internal();

  /// 获取单例实例
  static AppConfig get instance => _instance;

  AppConfig._internal();

  // ==================== 配置模块 ====================

  /// 编译期配置（环境、版本等，不存储）
  late final BuildConfig build = BuildConfig();

  /// 功能开关（Feature Toggle，可动态改变）
  FeatureConfig? _feature;
  FeatureConfig get feature => _feature!;

  /// 文件扫描配置（策略阈值，可动态改变）
  FileScanConfig? _fileScan;
  FileScanConfig get fileScan => _fileScan!;

  /// 文件类型配置（支持的扩展名，可动态扩展）
  FileTypesConfig? _fileTypes;
  FileTypesConfig get fileTypes => _fileTypes!;

  /// 应用扫描配置（应用列表、优先级、启用状态）
  AppScannerConfig? _appScanner;
  AppScannerConfig get appScanner => _appScanner!;

  /// 重复文件推荐配置（推荐算法的参数和权重）
  DuplicateFilesRecommendationConfig? _duplicateFilesRec;
  DuplicateFilesRecommendationConfig get duplicateFilesRec => _duplicateFilesRec!;

  // ==================== 存储实例 ====================

  ConfigStorage? _storage;

  /// 获取存储实例（高级用途）
  ConfigStorage get storage {
    if (_storage == null) {
      throw StateError('AppConfig not initialized. Call initialize() first.');
    }
    return _storage!;
  }

  // ==================== 初始化 ====================

  /// 初始化配置系统
  /// 
  /// 需要在 main() 中尽早调用。
  /// 
  /// 参数：
  /// - storage: 自定义存储实现。如果为 null，使用 LocalConfigStorage
  /// 
  /// 示例：
  /// ```dart
  /// void main() async {
  ///   // 生产环境：使用默认存储
  ///   await AppConfig.instance.initialize();
  ///   
  ///   // 测试环境：使用 Mock 存储
  ///   final mockStorage = MockConfigStorage();
  ///   await AppConfig.instance.initialize(storage: mockStorage);
  /// }
  /// ```
  Future<void> initialize({
    ConfigStorage? storage,
  }) async {
    try {
      logger.i('⚙️  Initializing AppConfig...');

      // 1. 初始化存储层
      if (storage != null) {
        _storage = storage;
        logger.i('✓ Using custom storage: ${storage.runtimeType}');
      } else {
        _storage = await LocalConfigStorage.create();
        logger.i('✓ Using LocalConfigStorage (SharedPreferences)');
      }

      // 2. 初始化需要存储的配置模块
      _feature = FeatureConfig(_storage!);
      _fileScan = FileScanConfig(_storage!);
      _fileTypes = FileTypesConfig(storage: _storage!);
      _appScanner = AppScannerConfig(_storage!);
      _duplicateFilesRec = DuplicateFilesRecommendationConfig(_storage!);
      logger.i('✓ FeatureConfig & FileScanConfig & FileTypesConfig & AppScannerConfig & DuplicateFilesRecommendationConfig initialized');

      logger.i('✅ AppConfig initialization complete');
      logger.i('build mode: {build.isProfile : ${build.isProfile}, build.isRelease: ${build.isRelease}}');

      // 3. 在 Debug 模式下打印配置状态
      if (build.isDebug) {
        _printStatus();
      }
    } catch (e) {
      logger.e('❌ Failed to initialize AppConfig: $e');
      rethrow;
    }
  }

  // ==================== 重置方法（测试用） ====================

  /// 重置所有配置为默认值
  /// 
  /// 仅用于单元测试。
  Future<void> resetToDefaults() async {
    await feature.reset();
    await fileScan.reset();
    await appScanner.resetAllAppConfigs();
    // fileTypes 无状态，不需要 reset
    logger.i('🔄 All configs reset to defaults');
  }

  // ==================== 调试辅助 ====================

  /// 打印配置状态（仅 Debug 模式）
  void _printStatus() {
    if (!build.isDebug) return;

    logger.i('╔════════════════════════════════════════╗');
    logger.i('║      AppConfig Status Report           ║');
    logger.i('╠════════════════════════════════════════╣');
    logger.i('║ Environment: ${build.environment.name.padRight(26)}║');
    logger.i('║ Storage: ${_storage.runtimeType.toString().padRight(30)}║');
    logger.i('║ Features Enabled: ${_countEnabledFeatures().toString().padRight(21)}║');
    logger.i('║ Debug Mode Enabled: ${build.isDebug.toString().padRight(19)}║');
    logger.i('╚════════════════════════════════════════╝');
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
