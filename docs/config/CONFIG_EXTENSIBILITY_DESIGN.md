# 配置系统扩展性设计文档

## 🎯 扩展性设计总览

本配置系统的扩展性设计基于**依赖抽象**原则，所有配置类依赖 `ConfigStorage` 接口而非具体实现。这使得我们可以轻松扩展到：

1. ✅ **远程配置** - Firebase Remote Config / 自建配置服务
2. ✅ **AB Test** - 不同用户组使用不同配置
3. ✅ **灰度发布** - 逐步开放新功能
4. ✅ **数据库存储** - 使用 SQLite/Hive 替代 SharedPreferences
5. ✅ **多环境配置** - 开发/测试/生产使用不同配置源

---

## 🏗️ 核心扩展点

### 1. ConfigStorage 抽象接口

**位置**: `lib/core/config/storage/config_storage.dart`

这是整个扩展性设计的**核心**：

```dart
abstract class ConfigStorage {
  int? getInt(String key);
  bool? getBool(String key);
  
  Future<bool> setInt(String key, int value);
  Future<bool> setBool(String key, bool value);
  
  /// 批量写入（关键！用于远程配置合并）
  Future<void> setAll(Map<String, dynamic> values);
}
```

**为什么这是核心？**
- 所有配置类（`FeatureConfig`、`FileScanConfig`）只依赖这个接口
- 业务代码不知道配置来自哪里（本地/远程/数据库）
- 切换存储实现时，业务代码**零改动**

---

### 2. 已实现的存储实现

#### ✅ LocalConfigStorage (生产环境)

使用 SharedPreferences，适合本地配置。

```dart
final localStorage = await LocalConfigStorage.create();
await AppConfig.instance.initialize(storage: localStorage);
```

#### ✅ MockConfigStorage (单元测试)

完全内存实现，不依赖设备存储。

```dart
final mockStorage = MockConfigStorage();
await AppConfig.instance.initialize(storage: mockStorage);
```

#### ✅ RemoteConfigStorage (远程配置)

**新增实现**，展示如何接入远程配置。

```dart
final remoteStorage = await RemoteConfigStorage.create(
  remoteUrl: 'https://api.example.com/config',
  localFallback: await LocalConfigStorage.create(),
);
await AppConfig.instance.initialize(storage: remoteStorage);
```

**特性**：
- 远程优先，本地 fallback
- 支持刷新配置
- 网络失败时自动降级到本地

---

### 3. 批量更新接口（关键扩展点）

所有配置类都提供 `mergeWith()` 方法：

#### FeatureConfig.mergeWith()

```dart
/// 批量更新功能开关（用于远程配置）
Future<void> mergeWith(Map<String, bool> remoteFlags) async {
  final prefixedData = remoteFlags.map(
    (key, value) => MapEntry('$_keyPrefix$key', value),
  );
  await _storage.setAll(prefixedData);
}
```

#### FileScanConfig.mergeWith()

```dart
/// 批量更新扫描配置（用于远程配置）
Future<void> mergeWith(Map<String, dynamic> remoteConfig) async {
  final prefixedData = remoteConfig.map(
    (key, value) => MapEntry('$_keyPrefix$key', value),
  );
  await _storage.setAll(prefixedData);
}
```

**用途**：
- 从服务器拉取配置后批量应用
- AB Test 分组配置
- 灰度发布控制

---

## 🚀 扩展场景实现

### 场景一：接入 Firebase Remote Config

```dart
// 1. 创建 Firebase Remote Config 适配器
class FirebaseConfigStorage implements ConfigStorage {
  final FirebaseRemoteConfig _remoteConfig;
  final ConfigStorage _localFallback;

  FirebaseConfigStorage(this._remoteConfig, this._localFallback);

  static Future<FirebaseConfigStorage> create() async {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ));
    await remoteConfig.fetchAndActivate();

    final localFallback = await LocalConfigStorage.create();
    return FirebaseConfigStorage(remoteConfig, localFallback);
  }

  @override
  bool? getBool(String key) {
    try {
      return _remoteConfig.getBool(key);
    } catch (e) {
      return _localFallback.getBool(key);
    }
  }

  @override
  int? getInt(String key) {
    try {
      return _remoteConfig.getInt(key);
    } catch (e) {
      return _localFallback.getInt(key);
    }
  }

  // ... 其他方法实现
}

// 2. 在 main.dart 中使用
Future<void> main() async {
  await Firebase.initializeApp();
  
  final firebaseStorage = await FirebaseConfigStorage.create();
  await AppConfig.instance.initialize(storage: firebaseStorage);
  
  runApp(const EasyFileApp());
}
```

**效果**：
- 所有配置自动从 Firebase 读取
- 本地配置作为 fallback
- 业务代码**无需任何修改**

---

### 场景二：AB Test 实现

```dart
// 1. 根据用户 ID 分组
Future<String> getABTestGroup(String userId) async {
  final hash = userId.hashCode % 100;
  if (hash < 10) return 'experiment_A';      // 10% 实验组 A
  if (hash < 20) return 'experiment_B';      // 10% 实验组 B
  return 'control';                          // 80% 对照组
}

// 2. 应用不同配置
Future<void> applyABTestConfig(String userId) async {
  final group = await getABTestGroup(userId);
  
  switch (group) {
    case 'experiment_A':
      // 实验组 A：启用新 UI，更激进的阈值
      await AppConfig.instance.feature.mergeWith({
        'new_ui': true,
        'premium': true,
      });
      await AppConfig.instance.fileScan.mergeWith({
        'large_file_threshold': 30,  // 30MB 就算大文件
        'new_files_retention': 3,    // 只保留 3 天
      });
      
    case 'experiment_B':
      // 实验组 B：启用新 UI，保守的阈值
      await AppConfig.instance.feature.mergeWith({
        'new_ui': true,
        'premium': false,
      });
      await AppConfig.instance.fileScan.mergeWith({
        'large_file_threshold': 100,  // 100MB 才算大文件
        'new_files_retention': 15,    // 保留 15 天
      });
      
    case 'control':
      // 对照组：使用默认配置
      break;
  }
  
  // 上报用户分组（用于数据分析）
  await analytics.logEvent('ab_test_group', {'group': group});
}

// 3. 在应用启动时应用
Future<void> main() async {
  await AppConfig.instance.initialize();
  
  final userId = await getUserId();
  await applyABTestConfig(userId);
  
  runApp(const EasyFileApp());
}
```

**效果**：
- 不同用户看到不同功能
- 可以量化新功能的效果
- 风险可控（小范围测试）

---

### 场景三：灰度发布

```dart
// 1. 从服务器获取灰度配置
class GrayReleaseService {
  final String apiUrl = 'https://api.example.com/gray-release';
  
  Future<void> applyGrayReleaseConfig() async {
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final config = jsonDecode(response.body) as Map<String, dynamic>;
        
        // 批量应用灰度配置
        await AppConfig.instance.feature.mergeWith({
          'new_files': config['enable_new_files'] ?? true,
          'large_files': config['enable_large_files'] ?? true,
          'premium': config['enable_premium'] ?? false,
        });
        
        logger.i('Gray release config applied');
      }
    } catch (e) {
      logger.e('Failed to fetch gray release config: $e');
      // 失败时使用默认配置
    }
  }
}

// 2. 定期刷新配置（可选）
class ConfigRefreshService {
  Timer? _timer;
  final GrayReleaseService _grayRelease = GrayReleaseService();
  
  void startPeriodicRefresh({Duration interval = const Duration(hours: 1)}) {
    _timer = Timer.periodic(interval, (_) async {
      await _grayRelease.applyGrayReleaseConfig();
    });
  }
  
  void stop() {
    _timer?.cancel();
  }
}

// 3. 在应用中使用
Future<void> main() async {
  await AppConfig.instance.initialize();
  
  // 应用灰度配置
  final grayRelease = GrayReleaseService();
  await grayRelease.applyGrayReleaseConfig();
  
  // 启动定期刷新（可选）
  final refreshService = ConfigRefreshService();
  refreshService.startPeriodicRefresh(interval: const Duration(hours: 6));
  
  runApp(const EasyFileApp());
}
```

**效果**：
- 可以实时控制功能开关
- 出现问题时快速止血
- 不需要发布新版本

---

### 场景四：多环境配置

```dart
// 1. 根据环境使用不同的配置源
class EnvironmentConfigFactory {
  static Future<ConfigStorage> create() async {
    final env = AppConfig.instance.build.environment;
    
    switch (env) {
      case Environment.development:
        // 开发环境：使用 Mock 数据
        return MockConfigStorage()
          ..setAll({
            'feature_new_files': true,
            'feature_premium': true,  // 开发时启用所有功能
            'scan_large_file_threshold': 10,  // 降低阈值便于测试
          });
        
      case Environment.staging:
        // 测试环境：使用测试服务器
        return await RemoteConfigStorage.create(
          remoteUrl: 'https://test-api.example.com/config',
          localFallback: await LocalConfigStorage.create(),
        );
        
      case Environment.production:
        // 生产环境：使用 Firebase Remote Config
        return await FirebaseConfigStorage.create();
    }
  }
}

// 2. 在 main.dart 中使用
Future<void> main() async {
  final storage = await EnvironmentConfigFactory.create();
  await AppConfig.instance.initialize(storage: storage);
  
  runApp(const EasyFileApp());
}
```

**效果**：
- 开发环境启用所有功能，方便调试
- 测试环境使用测试服务器配置
- 生产环境使用正式配置服务

---

### 场景五：风险开关（止血）

```dart
// 紧急情况下，通过远程配置快速禁用有问题的功能

// 服务器端配置（JSON）
{
  "feature_new_files": false,        // 新文件功能崩溃，紧急关闭
  "scan_concurrency": 2,             // 并发扫描导致 ANR，降低并发数
  "feature_large_files": true,       // 大文件功能正常
  "scan_timeout": 60                 // 扫描超时时间缩短到 60 秒
}

// 客户端自动应用
// 下次用户打开应用时，自动获取最新配置，有问题的功能已被关闭
```

**效果**：
- 出现严重 bug 时，无需发布新版本
- 几分钟内就能止血
- 影响范围可控

---

## 📊 扩展性对比

| 扩展场景 | 传统硬编码 | 本配置系统 |
|---------|-----------|-----------|
| **远程配置** | 不支持 | ✅ 实现 `RemoteConfigStorage` 即可 |
| **AB Test** | 需要大量 if-else | ✅ `mergeWith()` 批量应用 |
| **灰度发布** | 需要发布新版本 | ✅ 服务器控制，实时生效 |
| **紧急止血** | 需要发布 hotfix | ✅ 远程关闭功能，几分钟生效 |
| **多环境** | 修改代码重新编译 | ✅ 根据环境选择配置源 |
| **单元测试** | 难以隔离 | ✅ 注入 `MockConfigStorage` |

---

## 🎯 核心设计原则回顾

### 依赖倒置原则 (DIP)

```
高层模块（业务代码）
    ↓ 依赖
抽象接口（ConfigStorage）
    ↑ 实现
低层模块（LocalConfigStorage / RemoteConfigStorage / ...）
```

**好处**：
- 业务代码不关心配置来源
- 切换存储实现时，业务代码零改动
- 易于测试和扩展

### 开闭原则 (OCP)

**对扩展开放**：
- 添加新的存储实现（如 DatabaseConfigStorage）
- 添加新的配置类（如 UiConfig，如果未来需要）

**对修改封闭**：
- 已有代码无需修改
- 扩展不影响现有功能

---

## ✅ 扩展性检查清单

- [x] **ConfigStorage 抽象接口** - 核心扩展点
- [x] **LocalConfigStorage** - 本地存储实现
- [x] **MockConfigStorage** - 测试用实现
- [x] **RemoteConfigStorage** - 远程配置示例
- [x] **mergeWith() 方法** - 批量更新接口
- [x] **setFeature() 方法** - 动态修改单个配置
- [x] **依赖注入** - `initialize(storage:)` 支持自定义存储
- [x] **完整文档** - 扩展场景示例
- [x] **单元测试** - 验证扩展性

---

## 🚀 未来可扩展方向

### 1. 数据库存储（高性能场景）

```dart
class DatabaseConfigStorage implements ConfigStorage {
  final Database _db;
  
  // 使用 SQLite/Hive 存储配置
  // 优点：查询快、支持复杂类型
}
```

### 2. 加密存储（敏感配置）

```dart
class EncryptedConfigStorage implements ConfigStorage {
  final ConfigStorage _delegate;
  final Cipher _cipher;
  
  // 加密存储敏感配置（如会员信息）
}
```

### 3. 多层配置（优先级覆盖）

```dart
class LayeredConfigStorage implements ConfigStorage {
  final List<ConfigStorage> _layers;
  
  // 层级：远程 > 本地用户设置 > 默认值
  // 类似 CSS 的层叠机制
}
```

### 4. 配置版本管理

```dart
class VersionedConfigStorage implements ConfigStorage {
  // 支持配置回滚
  // 记录配置变更历史
}
```

---

## 📝 总结

本配置系统的扩展性设计已经**完整实现**，核心特点：

1. ✅ **抽象存储层** - 依赖 `ConfigStorage` 接口
2. ✅ **批量更新** - `mergeWith()` 支持远程配置
3. ✅ **依赖注入** - 可自由切换存储实现
4. ✅ **完整示例** - 远程配置、AB Test、灰度发布
5. ✅ **易于扩展** - 添加新实现无需修改现有代码

**一句话总结**：这是一个**生产级可用**的配置系统，支持从简单的本地配置到复杂的远程配置、AB Test 的无缝升级。
