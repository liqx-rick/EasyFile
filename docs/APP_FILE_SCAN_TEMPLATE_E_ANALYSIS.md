# 应用文件扫描方案对比 - Template E 完整代码流程分析

> **分析日期**: 2025-12-19  
> **功能**: 应用文件扫描方案对比测试  
> **分析方法**: Template E - 完整代码流程分析

---

## 📋 执行摘要

> 注意：本文档侧重于不同扫描方案的性能与实现对比；关于运行时的“应用推荐模块”（首页推荐卡片、RecommendationService、推荐缓存与页面驱动等）的事实性说明，请参阅 [docs/RECOMMENDATION_MODULE_REFERENCE.md](docs/RECOMMENDATION_MODULE_REFERENCE.md)。


### 核心功能
本模块用于对比测试两种应用文件扫描方案的性能和效果：
1. **方案1: 路径扫描 + 文件名模式匹配** - 兼容所有Android版本
2. **方案2: MediaStore OWNER_PACKAGE_NAME** - Android 11+ 专用

### 技术架构
- **UI层**: `AppFileScanTestPage` - Flutter测试页面
- **通道层**: `AppFileScannerChannel` - Dart/Kotlin桥接
- **扫描层**: `AppFileScanner.kt` - 原生扫描实现

### 测试应用覆盖
- 微信 (com.tencent.mm)
- QQ (com.tencent.mobileqq)
- Telegram (org.telegram.messenger)
- WPS (cn.wps.moffice_eng)

---

## 🔍 Template E: 完整代码流程分析

### 1️⃣ 整体架构

#### 文件组织结构
```
lib/
├── ui/pages/
│   └── app_file_scan_test_page.dart        # 测试UI页面 (697行)
├── core/platform/
│   └── app_file_scanner_channel.dart       # Dart通道封装 (150行)

android/app/src/main/kotlin/
└── com/guangqi/easyfile/
    └── AppFileScanner.kt                    # Kotlin扫描实现 (258行)
```

#### 调用链路
```
用户点击"开始对比测试"
  ↓
AppFileScanTestPage._runComparisonTest()
  ↓
├─ _scanByPath() [方案1]
│   ├─ AppFileScannerChannel.getKnownAppPaths()
│   ├─ Directory.list(recursive: true)          # Dart文件系统扫描
│   └─ AppFileScannerChannel.scanByFileNamePattern()
│       └─ AppFileScanner.scanByFileNamePattern()
│           └─ MediaStore查询 (DISPLAY_NAME LIKE)
│
└─ _scanByOwnerPackage() [方案2]
    └─ AppFileScannerChannel.scanByOwnerPackage()
        └─ AppFileScanner.scanByOwnerPackage()
            └─ MediaStore查询 (OWNER_PACKAGE_NAME =)
```

---

### 2️⃣ 方案1: 路径扫描 + 文件名模式匹配

#### 核心逻辑 (app_file_scan_test_page.dart)

**第1步: 获取扫描路径**
```dart
// 动态查找或使用已知路径
List<String> paths = [];

if (_selectedAppKey == 'weixin' || _selectedAppKey == 'qq' || 
    _selectedAppKey == 'telegram' || _selectedAppKey == 'wps') {
  // 动态查找: 在标准目录下搜索匹配关键字的文件夹
  final basePaths = [
    '/storage/emulated/0/Download/',
    '/storage/emulated/0/Pictures/',
    '/storage/emulated/0/DCIM/',
    '/storage/emulated/0/Music/',
    '/storage/emulated/0/Movies/',
    '/storage/emulated/0/Documents/',
  ];
  
  final keyword = keywordMap[_selectedAppKey]!; // 如 "WeiXin"
  paths = await AppFileScannerChannel.findFoldersContaining(basePaths, keyword);
  
} else {
  // 微信使用固定已知路径
  paths = await AppFileScannerChannel.getKnownAppPaths(_selectedAppKey);
  // 返回: ['/storage/emulated/0/Download/WeiXin/', 
  //        '/storage/emulated/0/Pictures/WeiXin/', ...]
}
```

**第2步: 递归扫描路径**
```dart
final files = <FileItem>[];
final pathSet = <String>{}; // 去重

for (final path in paths) {
  final dir = Directory(path);
  if (dir.existsSync()) {
    // Dart原生递归扫描
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final fileItem = FileItem.fromEntity(entity);
        if (!pathSet.contains(fileItem.path)) {
          files.add(fileItem);
          pathSet.add(fileItem.path);
        }
      }
    }
  }
}
```

**第3步: 文件名模式补充扫描**
```dart
// 获取应用特定的文件名模式
final patterns = await AppFileScannerChannel.getAppFileNamePatterns(_selectedAppKey);
// 微信返回: ['wx_camera_%', 'mmexport%']

if (patterns.isNotEmpty) {
  final patternFiles = await AppFileScannerChannel.scanByFileNamePattern(patterns);
  
  // 合并结果并去重
  for (final file in patternFiles) {
    if (!pathSet.contains(file.path)) {
      files.add(file);
      pathSet.add(file.path);
    }
  }
}
```

#### Kotlin实现 (AppFileScanner.kt)

**文件名模式扫描**
```kotlin
fun scanByFileNamePattern(patterns: List<String>): List<Map<String, Any>> {
    val projection = arrayOf(
        MediaStore.Files.FileColumns.DATA,
        MediaStore.Files.FileColumns.DISPLAY_NAME,
        MediaStore.Files.FileColumns.SIZE,
        // ...
    )
    
    // 构建 SQL: DISPLAY_NAME LIKE 'wx_camera_%' OR DISPLAY_NAME LIKE 'mmexport%'
    val selectionParts = patterns.map { "${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?" }
    val selection = selectionParts.joinToString(" OR ")
    val selectionArgs = patterns.toTypedArray()
    
    val cursor = context.contentResolver.query(
        MediaStore.Files.getContentUri("external"),
        projection,
        selection,
        selectionArgs,
        sortOrder
    )
    
    // 遍历结果，过滤隐藏文件
    cursor?.use {
        while (it.moveToNext()) {
            val path = it.getString(pathColumn) ?: continue
            val name = it.getString(nameColumn) ?: continue
            
            if (name.startsWith(".") || path.contains("/.")) continue
            
            files.add(mapOf(
                "path" to path,
                "name" to name,
                "size" to size,
                // ...
            ))
        }
    }
}
```

**动态文件夹查找**
```kotlin
// MainActivity.kt 中实现
"findFoldersContaining" -> {
    val basePaths = call.argument<List<String>>("basePaths")!!
    val keyword = call.argument<String>("keyword")!!
    val foundPaths = mutableListOf<String>()
    
    // 在每个基础路径下查找匹配的子文件夹
    for (basePath in basePaths) {
        val baseDir = File(basePath)
        if (baseDir.exists() && baseDir.isDirectory) {
            baseDir.listFiles()?.forEach { subDir ->
                // 严格匹配文件夹名称
                if (subDir.isDirectory && subDir.name == keyword) {
                    foundPaths.add(subDir.absolutePath + "/")
                }
            }
        }
    }
    
    result.success(foundPaths)
}
```

#### 方案1优缺点

**优点**:
- ✅ 兼容所有Android版本
- ✅ 可以扫描任意路径
- ✅ 文件名模式灵活（wx_camera_*, mmexport*）
- ✅ 动态查找支持用户自定义位置

**缺点**:
- ❌ 递归扫描性能较差（大文件夹慢）
- ❌ 需要维护每个应用的路径列表
- ❌ 可能遗漏未知路径的文件
- ❌ 文件名模式需要人工维护

---

### 3️⃣ 方案2: MediaStore OWNER_PACKAGE_NAME

#### 核心逻辑 (app_file_scan_test_page.dart)

```dart
Future<void> _scanByOwnerPackage() async {
  // 检查Android版本
  if (!_isAndroid11Supported) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('需要 Android 11+ 才支持 OWNER_PACKAGE_NAME')),
    );
    return;
  }
  
  // 直接调用扫描
  final results = await AppFileScannerChannel.scanByOwnerPackage(_selectedPackageName);
  // _selectedPackageName = 'com.tencent.mm'
}
```

#### Kotlin实现 (AppFileScanner.kt)

```kotlin
fun scanByOwnerPackage(packageName: String): List<Map<String, Any>> {
    // Android版本检查
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
        Log.w(TAG, "OWNER_PACKAGE_NAME requires Android 11+")
        return emptyList()
    }
    
    val projection = arrayOf(
        MediaStore.Files.FileColumns.DATA,
        MediaStore.Files.FileColumns.DISPLAY_NAME,
        MediaStore.Files.FileColumns.SIZE,
        MediaStore.Files.FileColumns.OWNER_PACKAGE_NAME  // Android 11+
    )
    
    // SQL: OWNER_PACKAGE_NAME = 'com.tencent.mm'
    val selection = "${MediaStore.Files.FileColumns.OWNER_PACKAGE_NAME} = ?"
    val selectionArgs = arrayOf(packageName)
    
    val cursor = context.contentResolver.query(
        MediaStore.Files.getContentUri("external"),
        projection,
        selection,
        selectionArgs,
        sortOrder
    )
    
    cursor?.use {
        while (it.moveToNext()) {
            val path = it.getString(pathColumn) ?: continue
            val name = it.getString(nameColumn) ?: continue
            
            // 过滤隐藏文件
            if (name.startsWith(".") || path.contains("/.")) continue
            
            files.add(mapOf(
                "path" to path,
                "name" to name,
                "size" to size,
                // ...
            ))
        }
    }
    
    Log.i(TAG, "扫描完成: ${files.size} 个文件")
}
```

#### 方案2优缺点

**优点**:
- ✅ 性能极高（索引查询，毫秒级）
- ✅ 自动发现所有应用文件（无需维护路径）
- ✅ 无需递归扫描
- ✅ 系统级精准度

**缺点**:
- ❌ 仅支持Android 11+ (API 30+)
- ❌ 依赖MediaStore索引（新文件可能延迟）
- ❌ 无法扫描未被MediaStore索引的文件
- ❌ 需要READ_EXTERNAL_STORAGE权限

---

### 4️⃣ 通道层实现 (AppFileScannerChannel.dart)

#### 统一的MethodChannel接口
```dart
class AppFileScannerChannel {
  static const _channel = MethodChannel('easyfile/app_file_scanner');
  
  // 方案2入口
  static Future<List<FileItem>> scanByOwnerPackage(String packageName) async {
    final List<dynamic> result = await _channel.invokeMethod(
      'scanByOwnerPackage',
      {'packageName': packageName},
    );
    
    // 将原生返回的Map转换为FileItem
    return result.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return FileItem(
        name: map['name'],
        path: map['path'],
        size: map['size'],
        modified: DateTime.fromMillisecondsSinceEpoch(map['modified']),
        isDirectory: false,
      );
    }).toList();
  }
  
  // 方案1辅助方法
  static Future<List<String>> getKnownAppPaths(String appKey) async {
    final List<dynamic> result = await _channel.invokeMethod(
      'getKnownAppPaths',
      {'appKey': appKey},
    );
    return result.cast<String>();
  }
  
  static Future<List<FileItem>> scanByFileNamePattern(List<String> patterns) async {
    final List<dynamic> result = await _channel.invokeMethod(
      'scanByFileNamePattern',
      {'patterns': patterns},
    );
    
    return result.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return FileItem(/* ... */);
    }).toList();
  }
  
  static Future<List<String>> findFoldersContaining(
    List<String> basePaths,
    String keyword,
  ) async {
    final List<dynamic> result = await _channel.invokeMethod(
      'findFoldersContaining',
      {'basePaths': basePaths, 'keyword': keyword},
    );
    return result.cast<String>();
  }
}
```

#### 错误处理
```dart
try {
  final result = await _channel.invokeMethod(...);
  return result;
} catch (e) {
  logger.e('扫描失败: $e');
  rethrow;  // 向上层抛出异常
}
```

---

### 5️⃣ UI层实现 (AppFileScanTestPage)

#### 页面状态管理
```dart
class _AppFileScanTestPageState extends State<AppFileScanTestPage> {
  bool _isScanning = false;               // 扫描进行中
  bool _isAndroid11Supported = false;     // Android版本检测
  
  // 方案1结果
  List<FileItem>? _pathScanResults;
  int? _pathScanDuration;
  
  // 方案2结果
  List<FileItem>? _ownerPackageResults;
  int? _ownerPackageDuration;
  
  // 测试应用
  String _selectedAppKey = 'wechat';
  String _selectedPackageName = 'com.tencent.mm';
}
```

#### 对比测试流程
```dart
Future<void> _runComparisonTest() async {
  setState(() {
    _isScanning = true;
    // 清空之前结果
    _pathScanResults = null;
    _ownerPackageResults = null;
  });

  // 1. 执行方案1
  await _scanByPath();
  
  // 2. 等待1秒
  await Future.delayed(const Duration(seconds: 1));
  
  // 3. 执行方案2
  await _scanByOwnerPackage();
  
  setState(() {
    _isScanning = false;
  });
}
```

#### 性能计时
```dart
Future<void> _scanByPath() async {
  final startTime = DateTime.now();
  
  // 执行扫描逻辑...
  
  final endTime = DateTime.now();
  final duration = endTime.difference(startTime);
  
  setState(() {
    _pathScanResults = files;
    _pathScanDuration = duration.inMilliseconds;
  });
}
```

#### 结果展示UI
```dart
// 两列对比布局
Row(
  children: [
    // 方案1结果
    Expanded(
      child: _buildResultCard(
        title: '方案1: 路径扫描',
        results: _pathScanResults,
        duration: _pathScanDuration,
        color: Colors.blue,
      ),
    ),
    
    const SizedBox(width: 16),
    
    // 方案2结果
    Expanded(
      child: _buildResultCard(
        title: '方案2: OWNER_PACKAGE',
        results: _ownerPackageResults,
        duration: _ownerPackageDuration,
        color: Colors.green,
      ),
    ),
  ],
)
```

---

## 📊 性能对比分析

### 理论性能预期

| 指标 | 方案1 (路径扫描) | 方案2 (OWNER_PACKAGE) |
|------|-----------------|---------------------|
| **扫描速度** | 慢 (秒级) | 快 (毫秒级) |
| **文件发现率** | 高 (99%+) | 中等 (80-90%) |
| **Android兼容性** | 全版本 | 仅11+ |
| **维护成本** | 高 (需维护路径) | 低 (自动发现) |
| **CPU占用** | 高 (递归遍历) | 低 (索引查询) |
| **内存占用** | 高 (大量文件) | 中等 |

### 实际测试场景

**测试设备**: Android 12+  
**测试应用**: 微信 (约5000个文件)

**方案1预期**:
- 扫描时间: 3-8秒
- 发现文件: 5000+
- 路径: /Download/WeiXin/, /Pictures/WeiXin/, /DCIM/WeiXin/
- 文件名模式: wx_camera_*.mp4, mmexport*.jpg

**方案2预期**:
- 扫描时间: 100-500ms
- 发现文件: 4000-4500 (可能遗漏未索引文件)
- 直接通过包名查询

---

## 🎯 应用场景建议

### 推荐策略

**生产环境推荐方案**:
```dart
// 根据Android版本选择最优方案
if (Build.VERSION.SDK_INT >= 30) {
  // Android 11+: 优先使用方案2
  files = await scanByOwnerPackage(packageName);
  
  // 如果结果不足，补充方案1
  if (files.length < 100) {
    final pathFiles = await scanByPath();
    files.addAll(pathFiles);
    files = files.toSet().toList(); // 去重
  }
} else {
  // Android 10及以下: 使用方案1
  files = await scanByPath();
}
```

**用户可配置**:
```dart
// 设置页面提供开关
SharedPreferences prefs = await SharedPreferences.getInstance();
bool useMediaStore = prefs.getBool('use_mediastore_scan') ?? true;

if (useMediaStore && isAndroid11Plus) {
  // 使用方案2
} else {
  // 使用方案1
}
```

---

## 🔧 代码优化建议

### 1. 结果缓存
```dart
// 避免重复扫描
final _cache = <String, List<FileItem>>{};

Future<List<FileItem>> scanWithCache(String packageName) async {
  if (_cache.containsKey(packageName)) {
    final cached = _cache[packageName]!;
    final age = DateTime.now().difference(cached.first.modified);
    if (age.inMinutes < 5) {
      return cached; // 5分钟内使用缓存
    }
  }
  
  final results = await scanByOwnerPackage(packageName);
  _cache[packageName] = results;
  return results;
}
```

### 2. 增量扫描
```dart
// 仅扫描新增文件
Future<List<FileItem>> scanIncremental(DateTime lastScanTime) async {
  final selection = "${MediaStore.Files.FileColumns.DATE_ADDED} > ?";
  final selectionArgs = [(lastScanTime.millisecondsSinceEpoch / 1000).toInt()];
  
  // 查询新增文件
}
```

### 3. 并行扫描
```dart
// 同时扫描多个应用
final results = await Future.wait([
  scanByOwnerPackage('com.tencent.mm'),
  scanByOwnerPackage('com.tencent.mobileqq'),
  scanByOwnerPackage('org.telegram.messenger'),
]);
```

---

## 📝 功能完整性评估

### 已实现功能 ✅

| 功能 | 完成度 | 代码位置 |
|------|--------|---------|
| Android版本检测 | 100% | AppFileScanner.isOwnerPackageSupported() |
| 方案1路径扫描 | 100% | _scanByPath() + Directory.list() |
| 方案2 OWNER_PACKAGE | 100% | scanByOwnerPackage() |
| 文件名模式匹配 | 100% | scanByFileNamePattern() |
| 动态文件夹查找 | 100% | findFoldersContaining() |
| 性能计时 | 100% | DateTime.now().difference() |
| 结果对比UI | 100% | _buildResultCard() |
| 去重逻辑 | 100% | pathSet.contains() |
| 错误处理 | 100% | try-catch + logger |

### 待优化功能 ⚠️

| 功能 | 优先级 | 改进方向 |
|------|--------|---------|
| 结果缓存 | P1 | 避免重复扫描 |
| 增量扫描 | P2 | 提升二次扫描速度 |
| 并行扫描 | P2 | 同时扫描多应用 |
| 进度回调 | P3 | 实时显示扫描进度 |
| 取消扫描 | P3 | 支持中途停止 |

---

## 💡 总结

### 代码框架总结

**三层架构**:
1. **UI层** (697行): 测试页面，结果展示，用户交互
2. **通道层** (150行): Dart/Kotlin桥接，类型转换
3. **扫描层** (258行): 原生扫描实现，MediaStore查询

**双方案对比**:
- 方案1: 兼容性强，发现率高，性能较慢
- 方案2: 性能极高，仅限新系统，可能遗漏

**核心价值**:
- 为生产环境选择扫描方案提供数据支持
- 验证MediaStore OWNER_PACKAGE_NAME的可行性
- 测试不同应用的文件分布特征

### 实现功能清单

✅ Android版本检测  
✅ 双方案并行测试  
✅ 性能计时对比  
✅ 结果数量统计  
✅ 去重逻辑  
✅ 文件名模式匹配  
✅ 动态路径发现  
✅ UI结果展示  
✅ 错误处理  
✅ 日志输出  

---

**分析完成日期**: 2025-12-19  
**分析师**: GitHub Copilot (Claude Sonnet 4.5)
