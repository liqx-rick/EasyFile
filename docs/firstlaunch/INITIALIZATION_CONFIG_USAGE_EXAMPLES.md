# 初始化配置使用示例

本文档提供 `InitializationConfig` 的实际使用示例。

## 📍 调用位置

`initializeFromScratch()` 在以下位置被调用：

1. **startup_orchestrator.dart** (第36行) - 首次安装场景
2. **data_load_service.dart** - 错误降级场景（3处）

## 🎯 使用场景

### 场景1: 默认配置（推荐）

**适用**: 大多数用户，追求完整体验

```dart
// startup_orchestrator.dart
await _appInitService.initializeFromScratch();
// 自动加载配置：默认全部开启
```

**效果**:
- ✅ 分类页面秒开（已预扫描缓存）
- ✅ 首页推荐应用秒开（已预扫描）
- ⏱️ 初始化时间: 60-70秒

---

### 场景2: 快速启动模式

**适用**: 低端设备、追求极致速度

```dart
// startup_orchestrator.dart
import 'initialization_config.dart';

await _appInitService.initializeFromScratch(
  config: InitializationConfig.quickStart(),
);
```

**效果**:
- ⚡ 初始化时间: 10-15秒（节省55秒）
- ⚠️ 首次进入分类页需等待3-7秒
- ⚠️ 首次进入首页需等待1-2秒

---

### 场景3: 平衡模式（用户提到的配置）

**适用**: 优先首页体验，分类页可以等待

```dart
// startup_orchestrator.dart
import 'initialization_config.dart';

await _appInitService.initializeFromScratch(
  config: InitializationConfig(
    enableP1CategoryScan: false,  // 跳过分类扫描（节省35秒）
    enableP1AppScan: true,        // 保留应用扫描（首页秒开）
  ),
);
```

**效果**:
- ⚡ 初始化时间: 30-40秒（节省35秒）
- ✅ 首页推荐应用秒开
- ⚠️ 首次进入分类页需等待（两阶段扫描）

**推荐用途**:
- 用户主要使用首页推荐功能
- 不常用分类页面
- 希望快速完成初始化

---

### 场景4: 只关注分类页

**适用**: 不使用推荐应用功能的用户

```dart
await _appInitService.initializeFromScratch(
  config: InitializationConfig(
    enableP1CategoryScan: true,   // 保留分类扫描（分类页秒开）
    enableP1AppScan: false,       // 跳过应用扫描（节省20秒）
  ),
);
```

**效果**:
- ⚡ 初始化时间: 45-50秒（节省20秒）
- ✅ 分类页面秒开
- ⚠️ 首页推荐卡片首次加载慢1-2秒

---

## 🔧 实施步骤

### 1. 在 startup_orchestrator.dart 中应用配置

```dart
// lib/core/services/startup/startup_orchestrator.dart

import 'initialization_config.dart'; // ← 添加import

class StartupOrchestrator {
  // ... 现有代码 ...

  Future<void> orchestrate() async {
    logger.i('[Orchestrator] Starting orchestration...');

    final scene = await _detectStartupScene();
    logger.i('[Orchestrator] Detected startup scene: $scene');

    switch (scene) {
      case StartupScene.freshInstall:
        logger.i('[Orchestrator] Executing freshInstall scenario...');

        // 🔧 修改这里：根据需要选择配置
        await _appInitService.initializeFromScratch(
          config: InitializationConfig(
            enableP1CategoryScan: false,  // ← 你的配置
            enableP1AppScan: true,
          ),
        );
        break;

      case StartupScene.normalOpen:
        // 保持不变
        await _dataLoadService.loadFromDatabase();
        break;
    }
  }
}
```

### 2. 动态配置（高级）

根据设备性能动态选择配置：

```dart
Future<void> orchestrate() async {
  // ... 检测场景 ...

  switch (scene) {
    case StartupScene.freshInstall:
      // 检测设备性能
      final deviceInfo = await DeviceInfo.get();
      final isLowEndDevice = deviceInfo.totalMemory < 2 * 1024 * 1024 * 1024; // <2GB

      final config = isLowEndDevice
        ? InitializationConfig.quickStart()  // 低端设备：快速模式
        : InitializationConfig.full();       // 高端设备：完整模式

      await _appInitService.initializeFromScratch(config: config);
      break;
    // ...
  }
}
```

---

## 📊 性能对比表

| 配置场景 | 初始化时间 | 分类页首次打开 | 首页首次打开 | 推荐场景 |
|---------|----------|--------------|------------|---------|
| **完整模式** | 60-70秒 | 秒开 | 秒开 | 大多数用户 |
| **平衡模式** | 30-40秒 | 3-7秒 | 秒开 | 主要用首页 |
| **跳过分类** | 45-50秒 | 3-7秒 | 秒开 | 不用推荐 |
| **快速模式** | 10-15秒 | 3-7秒 | 1-2秒 | 低端设备 |

---

## ⚠️ 注意事项

### 1. 配置持久化

配置会自动保存到 SharedPreferences：

```dart
final config = InitializationConfig(...);
await config.save(); // 保存

final loaded = await InitializationConfig.load(); // 下次自动加载
```

### 2. 降级场景中的配置

在 `data_load_service.dart` 的错误降级中，建议使用快速模式：

```dart
// data_load_service.dart

Future<void> loadFromCache() async {
  try {
    // ... 检查缓存 ...
    if (!isValid) {
      // 降级时使用快速模式，减少等待
      await appInitService.initializeFromScratch(
        config: InitializationConfig.quickStart(),
      );
      return;
    }
    // ...
  } catch (e) {
    // 错误降级也使用快速模式
    await appInitService.initializeFromScratch(
      config: InitializationConfig.quickStart(),
    );
  }
}
```

### 3. 用户体验权衡

- **开启扫描**: 用户第一次打开相关页面时体验更好（秒开）
- **关闭扫描**: 初始化更快完成，但首次打开页面需要等待

选择配置时要考虑目标用户的使用习惯。

---

## 📝 总结

**推荐配置策略**:

1. **默认发布版本**: 使用完整模式（体验最佳）
2. **低端设备优化**: 检测内存<2GB时自动切换快速模式
3. **用户自定义**: 在设置页面提供开关，让用户自己选择

**实施建议**:

```dart
// 第一版：使用默认配置（最安全）
await _appInitService.initializeFromScratch();

// 第二版：添加设备检测（优化低端设备）
final config = isLowEnd ? InitializationConfig.quickStart() : InitializationConfig.full();
await _appInitService.initializeFromScratch(config: config);

// 第三版：添加用户设置（给用户选择权）
final config = await InitializationConfig.load(); // 读取用户偏好
await _appInitService.initializeFromScratch(config: config);
```
