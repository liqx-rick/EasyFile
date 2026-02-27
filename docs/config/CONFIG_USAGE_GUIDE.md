# 配置系统使用指南

## 快速开始

### 1. 配置系统已集成

配置系统已经在 `main.dart` 中初始化，无需额外操作：

```dart
Future<void> main() async {
  await logger.init();
  
  // 配置系统自动初始化
  await AppConfig.instance.initialize();
  
  // ... 其他初始化
}
```

### 2. 在业务代码中使用

#### ✅ 功能开关 (FeatureConfig)

```dart
// 检查功能是否启用
if (AppConfig.instance.feature.isNewFilesEnabled) {
  // 显示新文件 Tab
  tabs.add(NewFilesTab());
}

if (AppConfig.instance.feature.isTrashEnabled) {
  // 显示回收站功能
}

// 动态修改功能开关（灰度发布）
await AppConfig.instance.feature.setFeature('new_files', enabled: false);

// 批量更新（远程配置）
await AppConfig.instance.feature.mergeWith({
  'large_files': true,
  'premium': true,
});
```

#### ✅ 策略阈值 (FileScanConfig)

```dart
// 使用大文件阈值
final thresholdBytes = 
    AppConfig.instance.fileScan.largeFileThreshold * 1024 * 1024;
final largeFiles = files.where((f) => f.size > thresholdBytes).toList();

// 使用新文件保留天数
final cutoffDate = DateTime.now().subtract(
  Duration(days: AppConfig.instance.fileScan.newFilesRetentionDays),
);

// 使用缓存过期时长
final cacheExpiry = Duration(
  hours: AppConfig.instance.fileScan.newFilesCacheExpiry,
);

// 修改策略阈值
await AppConfig.instance.fileScan.setLargeFileThreshold(100); // 100MB
await AppConfig.instance.fileScan.setNewFilesRetentionDays(15); // 15天
```

#### ✅ 环境判断 (BuildConfig)

```dart
// ❌ 错误：直接使用 kDebugMode
import 'package:flutter/foundation.dart';
if (kDebugMode) {
  logger.d('Debug log');
}

// ✅ 正确：使用 AppConfig
if (AppConfig.instance.build.isDebug) {
  logger.d('Debug log');
}

// 环境切换
switch (AppConfig.instance.build.environment) {
  case Environment.development:
    enableMockData();
  case Environment.staging:
    useTestServer();
  case Environment.production:
    useProductionServer();
}

// 获取应用信息
final packageName = AppConfig.instance.build.packageName;
final isAndroid = AppConfig.instance.build.supportsAndroid;
```

---

## 配置原则

### ❌ 不应该进 Config 的

1. **UI 常量** - 字体大小、padding、margin
   - 原因：用户不可感知差异，必须和代码强一致
   - 示例：`fontSize: 14.0`、`padding: 8.0`

2. **系统路径** - Android/iOS 文件系统路径
   - 原因：必须和代码强一致，属于工具类而非配置
   - 示例：`/storage/emulated/0/Download`

3. **业务常量** - 代码逻辑中的常量
   - 原因：不会被产品反复改
   - 示例：`const maxRetryCount = 3`

### ✅ 强烈值得进 Config 的

1. **功能开关** (Feature Toggle)
   ```dart
   bool get isNewFilesEnabled => ...;
   ```

2. **策略阈值**
   ```dart
   int get largeFileThreshold => ...;  // 50MB? 100MB? 产品可能调整
   ```

3. **推荐/排序/优先级规则**
   ```dart
   int get recommendationScore => ...;
   ```

4. **风险开关** (止血用)
   ```dart
   bool get enableExperimentalFeature => ...;
   int get scanConcurrency => ...;  // 并发数，可能导致 ANR
   ```

5. **实验性体验参数**
   ```dart
   int get cacheExpiry => ...;  // 缓存时长，影响体验
   ```

---

## 远程配置示例

### 从服务器获取配置

```dart
// 1. 获取远程配置
final response = await http.get('https://api.example.com/config');
final remoteConfig = jsonDecode(response.body);

// 2. 批量更新功能开关
await AppConfig.instance.feature.mergeWith({
  'new_files': remoteConfig['feature_new_files'],
  'large_files': remoteConfig['feature_large_files'],
  'premium': remoteConfig['feature_premium'],
});

// 3. 批量更新扫描配置
await AppConfig.instance.fileScan.mergeWith({
  'large_file_threshold': remoteConfig['scan_large_threshold'],
  'new_files_retention': remoteConfig['scan_retention_days'],
});
```

### AB Test 示例

```dart
// 获取用户的 AB Test 分组
final userGroup = await getABTestGroup(userId);

if (userGroup == 'experiment') {
  // 实验组：启用新功能
  await AppConfig.instance.feature.setFeature('new_ui', enabled: true);
  await AppConfig.instance.fileScan.setLargeFileThreshold(30); // 更激进的阈值
} else {
  // 对照组：使用默认配置
  await AppConfig.instance.feature.setFeature('new_ui', enabled: false);
}
```

---

## 单元测试

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/config/storage/mock_config_storage.dart';

void main() {
  setUp(() async {
    // 使用 Mock 存储，完全隔离 SharedPreferences
    final mockStorage = MockConfigStorage();
    await AppConfig.instance.initialize(storage: mockStorage);
  });

  test('my test', () {
    // 测试代码
    expect(AppConfig.instance.feature.isNewFilesEnabled, true);
  });

  tearDown(() async {
    await AppConfig.instance.resetToDefaults();
  });
}
```

---

## 总结

配置系统设计遵循以下原则：

✅ **简洁** - 只包含真正需要配置的项  
✅ **聚焦** - 功能开关 + 策略阈值  
✅ **可扩展** - 支持远程配置和 AB Test  
✅ **易测试** - 依赖抽象，可注入 Mock  

**核心思想**：控制配置数量，可进可不进的时候，不要放入 config 中。
