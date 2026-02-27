# 应用文件扫描缓存修复报告

## 🐛 问题描述

**用户报告**：点击微信应用时，每次进入都有10秒扫描过程，缓存没有生效。

**日志分析**：
```
I/flutter (21421): [2026-01-25T20:40:07.525975] [INFO] 路径扫描: 44200 文件 (10361ms)
I/flutter (21421): [2026-01-25T20:48:18.933819] [INFO] 💾 扫描结果已缓存 (有效期: 6小时)
```

每次点击微信应用都会执行完整的路径扫描（10.36秒），虽然有缓存保存日志，但二次访问时没有"使用缓存结果"的日志。

**根本原因**：
1. ❌ UnifiedAppScanner每次都创建新实例
2. ❌ 实例变量`_scanCache`在新实例中为空
3. ❌ 热重载后实例重新创建，缓存丢失

## 🔍 根本原因

### 1. UnifiedAppScanner 缺少缓存机制

**原代码** (`lib/core/services/unified_app_scanner.dart`):
```dart
Future<AppScanResult> scanApp({
  required String appKey,
  bool updateCache = true, // 只是更新缓存，不检查缓存
}) async {
  logger.i('========== 开始扫描应用: ${config.appName} ($appKey) ==========');
  
  // ❌ 直接开始扫描，没有检查缓存
  final detectionResult = await _detectionService.detectApp(config);
  // ... 执行完整扫描（MediaStore + 路径扫描）
}
```

**问题**：
- `updateCache: true` 只是在扫描完成后更新`FileCountCache`（文件数量）
- **没有缓存扫描结果本身**
- 每次调用都会重新执行MediaStore扫描 + 路径扫描
- ❌ 使用实例变量导致缓存在新实例中丢失

### 2. AppFilesDataSource 强制刷新

**原代码** (`lib/core/data_sources/app_files_data_source.dart`):
```dart
final scanResult = await scanner.scanApp(
  appKey: appKey,
  useMediaStore: useMediaStore,
  updateCache: true, // ❌ 强制每次都更新，触发完整扫描
);
```

## ✅ 修复方案

### 方案A：添加扫描结果缓存机制（已实施）

**核心思路**：
1. 在`UnifiedAppScanner`中添加内存缓存（6小时有效期）
2. 每次扫描前先检查缓存是否有效
3. 缓存有效时直接返回，无效时才执行扫描
4. 添加`forceRefresh`参数支持强制刷新

**实施细节**：

#### 1. 添加缓存字段和配置

```dart
class UnifiedAppScanner {
  final AppDetectionService _detectionService;
  final FileCountCache? _fileCountCache;

  /// 最大递归深度（避免深层目录遍历）
  static const int maxRecursionDepth = 5;

  /// 📦 扫描结果缓存（appKey -> ScanResultCache）
  /// ⚠️ 使用静态变量确保跨实例共享缓存（关键！）
  static final Map<String, _ScanResultCache> _scanCache = {};

  /// ⏰ 缓存有效期（6小时）
  static const Duration _cacheExpiration = Duration(hours: 6);
  
  // ...
}

/// 扫描结果缓存（内部类）
class _ScanResultCache {
  final AppScanResult result;
  final DateTime timestamp;

  _ScanResultCache({
    required this.result,
    required this.timestamp,
  });
}
```

**关键设计**：
- ✅ 使用`static final`而非实例变量
- ✅ 避免每次创建新实例时缓存丢失
- ✅ 支持热重载时缓存保留

#### 2. 添加forceRefresh参数

```dart
Future<AppScanResult> scanApp({
  required String appKey,
  List<String> additionalPaths = const [],
  bool withIcon = false,
  bool useMediaStore = true,
  bool updateCache = true,
  bool forceRefresh = false, // ⭐ 新增：是否强制刷新
}) async {
  // ...
}
```

#### 3. 缓存检查逻辑

```dart
logger.i('========== 开始扫描应用: ${config.appName} ($appKey) ==========');

// 🚀 缓存检查：如果未强制刷新，先检查缓存
if (!forceRefresh && _scanCache.containsKey(appKey)) {
  final cached = _scanCache[appKey]!;
  final cacheAge = DateTime.now().difference(cached.timestamp);
  
  if (cacheAge < _cacheExpiration) {
    logger.i('✅ 使用缓存结果 (缓存年龄: ${cacheAge.inMinutes}分钟, 有效期: ${_cacheExpiration.inHours}小时)');
    logger.i('   文件数量: ${cached.result.allFiles.length}');
    logger.i('========== 扫描完成: ${config.appName} ==========');
    return cached.result; // 🎯 直接返回缓存
  } else {
    logger.i('⏰ 缓存已过期 (${cacheAge.inMinutes}分钟 > ${_cacheExpiration.inHours}小时), 执行新扫描');
    _scanCache.remove(appKey); // 清除过期缓存
  }
}

// 步骤1: 检测应用是否安装
final detectionResult = await _detectionService.detectApp(config);
// ... 继续执行完整扫描
```

#### 4. 保存扫描结果到缓存

```dart
// 步骤8: 构建扫描结果
final scanResult = AppScanResult(
  appName: config.appName,
  packageName: packageName,
  isInstalled: true,
  allFiles: allFiles,
  mediaStoreFiles: mediaStoreResult.files,
  pathScanFiles: pathScanResult.files,
  differenceFiles: differenceFiles,
  appIcon: appIcon,
  mediaStoreDuration: mediaStoreResult.duration,
  pathScanDuration: pathScanResult.duration,
);

// 步骤9: 更新缓存
_scanCache[appKey] = _ScanResultCache(
  result: scanResult,
  timestamp: DateTime.now(),
);
logger.i('💾 扫描结果已缓存 (有效期: ${_cacheExpiration.inHours}小时)');
```

#### 5. AppFilesDataSource 支持forceRefresh

```dart
@override
Future<List<FileItem>> queryFiles(Map<String, dynamic> params) async {
  // 1. 验证必需参数
  final appKey = params['appKey'] as String?;
  if (appKey == null || appKey.isEmpty) {
    throw ArgumentError('appKey is required');
  }

  // 2. 可选参数
  final fileTypes = params['fileTypes'] as List<String>?;
  final useMediaStore = params['useMediaStore'] as bool? ?? true;
  final forceRefresh = params['forceRefresh'] as bool? ?? false; // ⭐ 新增

  logger.i('$name.queryFiles - appKey: $appKey, fileTypes: $fileTypes');

  // 3. 执行扫描（默认使用缓存，除非forceRefresh=true）
  final scanResult = await scanner.scanApp(
    appKey: appKey,
    useMediaStore: useMediaStore,
    updateCache: true,              // 始终更新文件数量缓存
    forceRefresh: forceRefresh,     // ⭐ 控制是否使用扫描结果缓存
  );
  
  // ...
}
```

## 📊 预期效果

### 首次访问（缓存未命中）
```
[INFO] ========== 开始扫描应用: 微信 (wechat) ==========
[INFO] 应用已安装: com.tencent.mm
[INFO] MediaStore扫描: 1399 文件 (127ms)
[INFO] 路径扫描: 44200 文件 (10361ms)
[INFO] 总文件数: 44204
[INFO] 💾 扫描结果已缓存 (有效期: 6小时)
[INFO] ========== 扫描完成: 微信 ==========
```
**耗时**: ~10.5秒（首次扫描正常）

### 二次访问（缓存命中）
```
[INFO] ========== 开始扫描应用: 微信 (wechat) ==========
[INFO] ✅ 使用缓存结果 (缓存年龄: 2分钟, 有效期: 6小时)
[INFO]    文件数量: 44204
[INFO] ========== 扫描完成: 微信 ==========
```
**耗时**: <50ms（**200倍提升**）

### 缓存过期后
```
[INFO] ========== 开始扫描应用: 微信 (wechat) ==========
[INFO] ⏰ 缓存已过期 (361分钟 > 6小时), 执行新扫描
[INFO] 应用已安装: com.tencent.mm
[INFO] MediaStore扫描: 1450 文件 (130ms)
[INFO] 路径扫描: 44500 文件 (10500ms)
[INFO] 💾 扫描结果已缓存 (有效期: 6小时)
```
**耗时**: ~10.6秒（缓存过期，重新扫描）

## 🎯 性能对比

| 场景 | 修复前 | 修复后 | 提升 |
|------|--------|--------|------|
| **首次访问** | 10.5秒 | 10.5秒 | 无变化 |
| **二次访问（2分钟内）** | 10.5秒 | <50ms | **210倍** |
| **三次访问（1小时内）** | 10.5秒 | <50ms | **210倍** |
| **缓存过期（>6小时）** | 10.5秒 | 10.5秒 | 无变化 |

## 📝 使用说明

### 默认行为（使用缓存）
```dart
final dataSource = AppFilesDataSource(
  scanner: scanner,
  detectionService: detectionService,
);

// 自动使用缓存（6小时内）
final files = await dataSource.queryFiles({
  'appKey': 'wechat',
});
```

### 强制刷新（下拉刷新）
```dart
// 用户下拉刷新时
final files = await dataSource.queryFiles({
  'appKey': 'wechat',
  'forceRefresh': true, // 强制重新扫描
});
```

## ✅ 验证计划

### 1. 日志验证
- [ ] 首次点击微信应用 → 日志显示"执行新扫描"
- [ ] 返回后再次点击 → 日志显示"使用缓存结果"
- [ ] 等待6小时后再点击 → 日志显示"缓存已过期"

### 2. 性能验证
- [ ] 首次访问耗时：~10秒
- [ ] 二次访问耗时：<100ms
- [ ] 缓存命中率：>90%（6小时内）

### 3. 功能验证
- [ ] 缓存的文件列表与实际扫描一致
- [ ] 下拉刷新能正确更新数据
- [ ] 切换Tab（图片/视频）正常工作

## 🚀 后续优化建议

### 1. 持久化缓存（可选）
当前是内存缓存，应用重启后失效。可以考虑：
```dart
// 保存到磁盘
await CacheManager.saveScanResult(appKey, scanResult);

// 应用启动时加载
final cached = await CacheManager.loadScanResult(appKey);
```

### 2. 智能缓存失效
监听文件系统变化，自动失效缓存：
```dart
// 监听应用目录变化
FileSystemWatcher.watch('/storage/emulated/0/Download/WeiXin')
  .listen((event) {
    _scanCache.remove('wechat'); // 文件变化时清除缓存
  });
```

### 3. 缓存大小限制
防止内存占用过大：
```dart
static const int maxCacheSize = 10; // 最多缓存10个应用

if (_scanCache.length >= maxCacheSize) {
  // 移除最旧的缓存
  _removeOldestCache();
}
```

## 📚 相关文档
- [CACHE_OPTIMIZATION_USAGE_GUIDE.md](CACHE_OPTIMIZATION_USAGE_GUIDE.md)
- [DATA_SOURCE_USAGE_GUIDE.md](DATA_SOURCE_USAGE_GUIDE.md)
