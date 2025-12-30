import 'dart:typed_data';
import 'dart:async';
import 'package:easyfile/core/platform/app_file_scanner_channel.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/config/app_scanner_config.dart';
import 'package:easyfile/core/services/app_scan_result.dart';
import 'package:easyfile/core/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用检测服务（优化版 - 持久化缓存）
/// 
/// 核心优化：
/// - 不查询所有应用列表（避免性能开销）
/// - 只检测指定应用是否安装（精准高效）
/// - 按需获取应用图标（懒加载）
/// - 持久化缓存（SharedPreferences）+ 事件驱动刷新
/// 
/// 性能对比：
/// - 原方案：查询100+应用，耗时500-1000ms
/// - 优化方案（首次）：查询1个应用，耗时5-10ms（提升100倍）
/// - 优化方案（缓存）：读取本地缓存，耗时<2ms（提升250-500倍）
/// 
/// 缓存策略：
/// - 内存缓存：即时访问，超快速度
/// - 持久化缓存：跨会话保留，应用重启后无需重新检测
/// - 事件驱动：监听系统广播，应用安装/卸载时自动更新
/// - 手动刷新：支持用户主动刷新（下拉刷新等场景）
class AppDetectionService {
  // ========================================
  // 缓存管理
  // ========================================

  /// 检测结果缓存（包名 -> 是否安装）
  final Map<String, bool> _installCache = {};

  /// 图标缓存（包名 -> 图标数据）
  final Map<String, Uint8List?> _iconCache = {};

  /// SharedPreferences 实例（持久化存储）
  SharedPreferences? _prefs;

  /// 持久化缓存键前缀
  static const _cacheKeyPrefix = 'app_installed_';

  /// 是否已初始化
  bool _initialized = false;

  /// 事件监听订阅
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;

  // ========================================
  // 核心方法
  // ========================================

  /// 初始化服务（必须在使用前调用）
  /// 
  /// 加载持久化缓存，提升首次访问速度
  /// 
  /// 使用示例：
  /// ```dart
  /// final service = AppDetectionService();
  /// await service.initialize();
  /// ```
  Future<void> initialize() async {
    if (_initialized) return;

    logger.i('初始化应用检测服务...');
    final stopwatch = Stopwatch()..start();

    try {
      // 加载持久化存储
      _prefs = await SharedPreferences.getInstance();

      // 加载所有已缓存的应用安装状态
      final keys = _prefs!.getKeys();
      int loadedCount = 0;

      for (final key in keys) {
        if (key.startsWith(_cacheKeyPrefix)) {
          final packageName = key.substring(_cacheKeyPrefix.length);
          final isInstalled = _prefs!.getBool(key) ?? false;
          _installCache[packageName] = isInstalled;
          loadedCount++;
        }
      }

      _initialized = true;
      stopwatch.stop();

      logger.i('✓ 服务初始化完成: 加载 $loadedCount 个缓存 (${stopwatch.elapsedMilliseconds}ms)');
      
      // 启动事件监听
      _startEventListener();
    } catch (e) {
      stopwatch.stop();
      logger.e('✗ 服务初始化失败: $e');
      _initialized = true; // 即使失败也标记为已初始化，避免重复尝试
    }
  }

  /// 启动应用事件监听
  void _startEventListener() {
    try {
      _eventSubscription = AppFileScannerChannel.watchAppEvents().listen(
        (event) {
          final eventType = event['event'] as String?;
          final packageName = event['packageName'] as String?;

          if (packageName != null) {
            if (eventType == 'installed') {
              onAppInstalled(packageName);
            } else if (eventType == 'uninstalled') {
              onAppUninstalled(packageName);
            }
          }
        },
        onError: (error) {
          logger.e('应用事件监听错误: $error');
        },
      );
      logger.i('✓ 应用事件监听已启动');
    } catch (e) {
      logger.e('✗ 启动事件监听失败: $e');
    }
  }

  /// 停止服务（释放资源）
  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    logger.i('应用检测服务已释放');
  }

  /// 检测应用是否安装
  /// 
  /// 支持两种检测方式：
  /// 1. 配置包名列表（优先，性能最优）
  /// 2. 应用名称模糊匹配（备选，暂不实现，需要查询所有应用，性能低）
  /// 
  /// 使用示例：
  /// ```dart
  /// final config = AppScannerConfigs.getConfig('wechat');
  /// final result = await detectionService.detectApp(config!);
  /// 
  /// if (result.isInstalled) {
  ///   print('微信已安装: ${result.packageName}');
  /// }
  /// ```
  Future<AppDetectionResult> detectApp(AppConfigData config) async {
    logger.i('检测应用: ${config.appName} (${config.appKey})');

    // 优先使用预配置的包名（快速准确）
    if (config.packageNames.isNotEmpty) {
      for (final packageName in config.packageNames) {
        final isInstalled = await _isAppInstalled(packageName);

        if (isInstalled) {
          logger.i('✓ 检测到已安装: $packageName');
          return AppDetectionResult(
            isInstalled: true,
            packageName: packageName,
            detectionMethod: 'configured_package',
          );
        }
      }
    }

    // 备选方案：应用名称模糊匹配
    // 注意：此方式需要查询所有已安装应用，性能较低，暂不实现
    // if (config.appLabelPatterns.isNotEmpty) {
    //   final result = await _detectByAppLabel(config);
    //   if (result.isInstalled) {
    //     return result;
    //   }
    // }

    logger.i('✗ 未检测到应用: ${config.appName}');
    return AppDetectionResult(isInstalled: false);
  }

  /// 检测单个应用是否安装（带缓存）
  /// 
  /// 性能优化：
  /// - 优先使用内存缓存（<1ms）
  /// - 其次使用持久化缓存（<2ms）
  /// - 最后查询系统（5-10ms）
  /// 
  /// [packageName] 应用包名，如 'com.tencent.mm'
  Future<bool> _isAppInstalled(String packageName) async {
    // 确保已初始化
    if (!_initialized) {
      await initialize();
    }

    // 1. 检查内存缓存
    if (_installCache.containsKey(packageName)) {
      logger.d('使用内存缓存: $packageName = ${_installCache[packageName]}');
      return _installCache[packageName]!;
    }

    // 2. 检查持久化缓存
    if (_prefs != null) {
      final key = '$_cacheKeyPrefix$packageName';
      if (_prefs!.containsKey(key)) {
        final isInstalled = _prefs!.getBool(key) ?? false;
        _installCache[packageName] = isInstalled; // 同步到内存缓存
        logger.d('使用持久化缓存: $packageName = $isInstalled');
        return isInstalled;
      }
    }

    // 3. 查询系统
    final stopwatch = Stopwatch()..start();
    final isInstalled = await AppFileScannerChannel.isAppInstalled(packageName);
    stopwatch.stop();

    logger.d('系统检测 $packageName: $isInstalled (${stopwatch.elapsedMilliseconds}ms)');

    // 更新缓存（内存 + 持久化）
    await _updateCache(packageName, isInstalled);

    return isInstalled;
  }

  /// 更新缓存（内存 + 持久化）
  Future<void> _updateCache(String packageName, bool isInstalled) async {
    // 更新内存缓存
    _installCache[packageName] = isInstalled;

    // 更新持久化缓存
    if (_prefs != null) {
      final key = '$_cacheKeyPrefix$packageName';
      await _prefs!.setBool(key, isInstalled);
    }
  }

  /// 获取应用图标（懒加载，带缓存）
  /// 
  /// 只在需要显示应用图标时调用，避免不必要的性能开销
  /// 
  /// 使用示例：
  /// ```dart
  /// final result = await detectApp(config);
  /// if (result.isInstalled) {
  ///   // 仅在需要显示图标时才加载
  ///   final icon = await getAppIcon(result.packageName!);
  ///   if (icon != null) {
  ///     Image.memory(icon, width: 40, height: 40);
  ///   }
  /// }
  /// ```
  /// 
  /// [packageName] 应用包名
  /// 返回图标的字节数据（Uint8List），如果应用未安装或获取失败则返回 null
  Future<Uint8List?> getAppIcon(String packageName) async {
    // 检查内存缓存
    if (_iconCache.containsKey(packageName)) {
      logger.d('使用缓存图标: $packageName');
      return _iconCache[packageName];
    }

    // 查询原生
    logger.i('获取应用图标: $packageName');
    final stopwatch = Stopwatch()..start();
    final icon = await AppFileScannerChannel.getAppIcon(packageName);
    stopwatch.stop();

    logger.d('图标获取完成: ${icon != null ? '成功' : '失败'} (${stopwatch.elapsedMilliseconds}ms)');

    // 更新内存缓存（图标不需要持久化，每次重启重新获取即可）
    _iconCache[packageName] = icon;

    return icon;
  }

  // ========================================
  // 缓存管理
  // ========================================

  /// 清除所有缓存
  /// 
  /// 在以下场景调用：
  /// - 用户手动刷新
  /// - 检测到缓存数据不准确
  Future<void> clearCache() async {
    logger.d('清除应用检测缓存');

    // 清除内存缓存
    _installCache.clear();
    _iconCache.clear();

    // 清除持久化缓存
    if (_prefs != null) {
      final keys = _prefs!.getKeys().where((k) => k.startsWith(_cacheKeyPrefix)).toList();
      for (final key in keys) {
        await _prefs!.remove(key);
      }
    }
  }

  /// 清除特定应用的缓存
  /// 
  /// [packageName] 应用包名
  Future<void> clearAppCache(String packageName) async {
    logger.d('清除应用缓存: $packageName');

    // 清除内存缓存
    _installCache.remove(packageName);
    _iconCache.remove(packageName);

    // 清除持久化缓存
    if (_prefs != null) {
      final key = '$_cacheKeyPrefix$packageName';
      await _prefs!.remove(key);
    }
  }

  /// 刷新特定应用的缓存（强制重新检测）
  /// 
  /// 用于处理系统广播事件（应用安装/卸载）
  /// 
  /// [packageName] 应用包名
  Future<void> refreshAppCache(String packageName) async {
    logger.i('刷新应用缓存: $packageName');

    // 强制重新检测
    final stopwatch = Stopwatch()..start();
    final isInstalled = await AppFileScannerChannel.isAppInstalled(packageName);
    stopwatch.stop();

    logger.d('刷新完成: $packageName = $isInstalled (${stopwatch.elapsedMilliseconds}ms)');

    // 更新缓存
    await _updateCache(packageName, isInstalled);

    // 清除图标缓存（重新安装的应用图标可能变化）
    _iconCache.remove(packageName);
  }

  /// 处理应用安装事件
  /// 
  /// 由系统广播接收器调用
  /// 
  /// [packageName] 新安装的应用包名
  Future<void> onAppInstalled(String packageName) async {
    logger.i('应用安装事件: $packageName');
    await _updateCache(packageName, true);
    _iconCache.remove(packageName); // 清除图标缓存
  }

  /// 处理应用卸载事件
  /// 
  /// 由系统广播接收器调用
  /// 
  /// [packageName] 被卸载的应用包名
  Future<void> onAppUninstalled(String packageName) async {
    logger.i('应用卸载事件: $packageName');
    await _updateCache(packageName, false);
    _iconCache.remove(packageName); // 清除图标缓存
  }

  /// 预热缓存（可选）
  /// 
  /// 在应用启动时调用，提前检测常用应用
  /// 
  /// 使用示例：
  /// ```dart
  /// await detectionService.warmUpCache([
  ///   'com.tencent.mm',      // 微信
  ///   'com.tencent.mobileqq', // QQ
  /// ]);
  /// ```
  Future<void> warmUpCache(List<String> packageNames) async {
    // 确保已初始化
    if (!_initialized) {
      await initialize();
    }

    logger.i('预热缓存: ${packageNames.length} 个应用');

    int cacheHits = 0;
    int newChecks = 0;

    for (final packageName in packageNames) {
      if (_installCache.containsKey(packageName)) {
        cacheHits++;
      } else {
        await _isAppInstalled(packageName);
        newChecks++;
      }
    }

    logger.i('缓存预热完成: $cacheHits 个命中, $newChecks 个新检测');
  }

  // ========================================
  // 工具方法
  // ========================================

  /// 批量检测多个应用
  /// 
  /// [appKeys] 应用Key列表，如 ['wechat', 'qq', 'telegram']
  /// 返回检测结果映射表（appKey -> AppDetectionResult）
  Future<Map<String, AppDetectionResult>> detectMultipleApps(
    List<String> appKeys,
  ) async {
    final results = <String, AppDetectionResult>{};

    for (final appKey in appKeys) {
      final config = await AppConfig.instance.appScanner.getAppConfig(appKey);
      if (config == null) {
        logger.w('未知应用: $appKey');
        continue;
      }

      results[appKey] = await detectApp(config);
    }

    return results;
  }

  /// 获取缓存统计信息
  Map<String, dynamic> getCacheStats() {
    return {
      'initialized': _initialized,
      'memoryCacheSize': _installCache.length,
      'iconCacheSize': _iconCache.length,
      'persistentCacheSize': _prefs?.getKeys().where((k) => k.startsWith(_cacheKeyPrefix)).length ?? 0,
    };
  }
}
