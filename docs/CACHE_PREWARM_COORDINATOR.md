# 缓存预热系统重构说明

## 📋 问题分析

### 重构前的问题

在 `main.dart` 中存在**3个独立的缓存预热服务**：

```dart
// 1. 缩略图缓存（同步，阻塞启动）
final cacheManager = ThumbnailCacheManager();
await cacheManager.init();

// 2. MediaStore 缓存（异步，.then() 方式）
mediastoreCacheService.warmUp().then((_) { ... });

// 3. 应用文件缓存（延迟5秒，独立函数）
_startAppCachePrewarming();
```

**存在的问题**：
1. ❌ **缺乏统一协调**：各自独立执行，无全局视角
2. ❌ **无优先级管理**：无法控制哪些任务优先执行
3. ❌ **资源竞争风险**：可能同时运行多个耗时任务
4. ❌ **错误处理分散**：每个任务单独 try-catch
5. ❌ **无进度监控**：无法统一查看预热进度
6. ❌ **难以维护**：新增预热任务需要修改 main.dart

---

## ✅ 重构方案

### 统一缓存预热协调器

创建 `CachePrewarmCoordinator` 单例服务，统一管理所有预热任务。

#### 核心设计

```
┌─────────────────────────────────────────────────┐
│         CachePrewarmCoordinator                │
├─────────────────────────────────────────────────┤
│                                                 │
│  阶段1（启动时）：关键缓存初始化                │
│    ├─ 缩略图缓存（同步，阻塞）                  │
│    └─ 0-500ms                                  │
│                                                 │
│  阶段2（延迟3秒）：高优先级预热                 │
│    ├─ MediaStore 缓存                          │
│    └─ 相机照片/视频/录音                        │
│                                                 │
│  阶段3（延迟5秒）：低优先级预热                 │
│    ├─ 应用文件缓存                             │
│    └─ 微信/QQ/支付宝等高优先级应用              │
│                                                 │
└─────────────────────────────────────────────────┘
```

#### 关键特性

1. **优先级队列**
   - 阶段1：关键任务立即执行
   - 阶段2：延迟3秒（等待UI稳定）
   - 阶段3：延迟5秒（最低优先级）

2. **并发控制**
   - 避免同时运行多个耗时任务
   - 顺序执行，逐步完成

3. **进度监控**
   ```dart
   CachePrewarmCoordinator.instance.progressStream.listen((progress) {
     print('${progress.taskName}: ${progress.progressPercent}%');
   });
   ```

4. **错误隔离**
   - 单个任务失败不影响其他任务
   - 统一错误日志和上报

5. **可取消**
   ```dart
   CachePrewarmCoordinator.instance.cancelPrewarming();  // 取消所有
   CachePrewarmCoordinator.instance.cancelTask('mediastore');  // 取消单个
   ```

---

## 🔧 使用方法

### 在 main.dart 中集成

```dart
Future<void> main() async {
  // ... 其他初始化代码 ...

  // 🚀 统一缓存预热协调器
  await CachePrewarmCoordinator.instance.initialize();
  CachePrewarmCoordinator.instance.startPrewarming();

  // 可选：监听预热进度
  CachePrewarmCoordinator.instance.progressStream.listen((progress) {
    logger.d('预热进度: ${progress.taskName} - ${progress.progressPercent}%');
    if (progress.isFailed) {
      logger.e('预热失败: ${progress.error}');
    }
  });

  runApp(const EasyFileApp());
}
```

### 添加新的预热任务

只需在 `CachePrewarmCoordinator` 中添加新方法：

```dart
// 在 _executePrewarmPipeline 中添加
Future<void> _executePrewarmPipeline() async {
  await _prewarmMediaStore();
  await Future.delayed(Duration(seconds: 2));

  await _prewarmAppFiles();
  await Future.delayed(Duration(seconds: 2));

  // 🆕 新增任务
  await _prewarmNewTask();
}

// 实现新任务
Future<void> _prewarmNewTask() async {
  logger.i('【阶段4】预热新任务...');
  _emitProgress('新任务', 0.0);

  try {
    // 执行预热逻辑
    await someService.prewarm();
    _emitProgress('新任务', 1.0);
  } catch (e) {
    _emitProgress('新任务', 1.0, error: e.toString());
  }
}
```

---

## 📊 性能对比

| 指标 | 重构前 | 重构后 | 改善 |
|------|--------|--------|------|
| **代码行数** | ~70 行 | ~30 行（main.dart） | **减少57%** |
| **可维护性** | ⭐⭐ | ⭐⭐⭐⭐⭐ | 统一管理 |
| **错误处理** | 分散 | 集中 | 统一日志 |
| **进度监控** | ❌ 无 | ✅ 实时 | Stream 推送 |
| **可扩展性** | ⭐⭐ | ⭐⭐⭐⭐⭐ | 插件化 |

---

## 🎯 执行时间轴

```
应用启动
    │
    ├─ 0s        ▶ 初始化协调器（同步）
    │              └─ 缩略图缓存初始化
    │
    ├─ +3s       ▶ 启动预热（异步）
    │              └─ MediaStore 缓存预热
    │
    ├─ +5s       ▶ 应用文件预热
    │              └─ 微信/QQ/支付宝等
    │
    └─ +8s~15s   ▶ 预热完成
                   └─ 缓存全部就绪
```

---

## 📝 迁移检查清单

- [x] 创建 `CachePrewarmCoordinator` 协调器
- [x] 重构 `main.dart` 使用协调器
- [x] 移除旧的独立预热代码
- [x] 添加进度监听（可选）
- [x] 测试缓存命中率
- [ ] 监控性能指标（启动耗时、内存占用）

---

## 🔍 后续优化方向

1. **动态优先级调整**
   - 根据设备性能调整预热策略
   - 低端设备减少并发任务

2. **智能预热**
   - 基于用户行为预测需要预热的应用
   - 只预热用户常用的应用

3. **后台唤醒预热**
   - 应用从后台恢复时检查缓存有效性
   - 自动刷新过期缓存

4. **分布式预热**
   - WorkManager 定时后台预热
   - 确保缓存始终有效

---

## 📚 相关文件

- `lib/core/services/cache_prewarm_coordinator.dart` - 协调器实现
- `lib/main.dart` - 集成示例
- `lib/core/services/app_cache_prewarmer.dart` - 应用文件预热器
- `lib/core/services/mediastore_cache_service.dart` - MediaStore 缓存服务
- `lib/utils/thumbnail_cache_manager.dart` - 缩略图缓存管理器
