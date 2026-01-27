# 缓存预热系统架构

## 系统概览

```
┌─────────────────────────────────────────────────────────────────┐
│                         应用启动流程                              │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                   CachePrewarmCoordinator                       │
│                      （统一协调器）                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────┐    │
│  │  阶段1：关键缓存初始化（同步，阻塞启动）                │    │
│  │  执行时间：0-500ms                                     │    │
│  ├───────────────────────────────────────────────────────┤    │
│  │  ✓ ThumbnailCacheManager                             │    │
│  │    └─ 视频/音频缩略图缓存                             │    │
│  └───────────────────────────────────────────────────────┘    │
│                          │                                      │
│                          ▼                                      │
│  ┌───────────────────────────────────────────────────────┐    │
│  │  阶段2：高优先级预热（延迟3秒，异步）                  │    │
│  │  执行时间：3s-6s                                       │    │
│  ├───────────────────────────────────────────────────────┤    │
│  │  ✓ MediaStoreCacheService                            │    │
│  │    ├─ 相机照片（时光记忆）                             │    │
│  │    ├─ 相机视频（生活剪影）                             │    │
│  │    └─ 录音文件（声音记录）                             │    │
│  └───────────────────────────────────────────────────────┘    │
│                          │                                      │
│                          ▼                                      │
│  ┌───────────────────────────────────────────────────────┐    │
│  │  阶段3：低优先级预热（延迟5秒，异步）                  │    │
│  │  执行时间：5s-15s                                      │    │
│  ├───────────────────────────────────────────────────────┤    │
│  │  ✓ AppCachePrewarmer                                 │    │
│  │    ├─ 微信文件扫描（priority=1）                       │    │
│  │    ├─ QQ文件扫描（priority=1）                         │    │
│  │    ├─ 支付宝文件扫描（priority=1）                     │    │
│  │    └─ 其他高优先级应用                                 │    │
│  └───────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 服务依赖关系

```
CachePrewarmCoordinator
    │
    ├─ ThumbnailCacheManager
    │   ├─ 视频缩略图（FFmpeg）
    │   └─ 音频封面（MediaStore）
    │
    ├─ MediaStoreCacheService
    │   ├─ MediaStoreScanner
    │   ├─ SharedPreferences（持久化）
    │   └─ FileCountCache（数量缓存）
    │
    └─ AppCachePrewarmer
        ├─ AppDetectionService（应用检测）
        ├─ UnifiedAppScanner（文件扫描）
        │   ├─ MediaStore扫描
        │   └─ 路径扫描
        └─ FileCountCache（数量缓存）
```

## 缓存类型与有效期

| 缓存类型 | 服务 | 有效期 | 存储方式 | 用途 |
|---------|------|--------|---------|------|
| 缩略图 | ThumbnailCacheManager | 永久 | 磁盘文件 | 视频/音频预览 |
| MediaStore | MediaStoreCacheService | 1-4小时 | SharedPreferences + 内存 | 相机照片/视频/录音 |
| 应用文件数量 | FileCountCache | 24小时 | SharedPreferences | 应用管理推荐 |
| 应用扫描结果 | UnifiedAppScanner | 24小时 | 内存 | 应用文件列表 |

## 预热策略

### 优先级划分

```
┌────────────────┬─────────────────┬──────────────┬─────────────┐
│   优先级      │   执行时机      │   任务类型   │  预期耗时    │
├────────────────┼─────────────────┼──────────────┼─────────────┤
│ 🔴 关键       │   启动时（同步） │  缩略图缓存  │  0-500ms    │
│ 🟡 高优先级   │   延迟3秒（异步）│  MediaStore  │  500ms-2s   │
│ 🟢 低优先级   │   延迟5秒（异步）│  应用文件    │  3-10s      │
└────────────────┴─────────────────┴──────────────┴─────────────┘
```

### 执行条件

1. **关键任务（阶段1）**
   - 条件：无条件执行
   - 阻塞：阻塞应用启动
   - 失败策略：记录日志，继续启动

2. **高优先级任务（阶段2）**
   - 条件：应用启动后3秒
   - 阻塞：不阻塞UI
   - 失败策略：记录日志，不影响其他任务

3. **低优先级任务（阶段3）**
   - 条件：应用启动后5秒
   - 阻塞：不阻塞UI
   - 失败策略：记录日志，下次重试

## 性能监控

### 关键指标

```dart
// 预热进度监控
CachePrewarmCoordinator.instance.progressStream.listen((progress) {
  // 指标1：任务名称
  String taskName = progress.taskName;

  // 指标2：进度百分比
  int percent = progress.progressPercent;

  // 指标3：是否失败
  bool failed = progress.isFailed;

  // 指标4：错误信息
  String? error = progress.error;

  // 上报到统计平台
  Analytics.track('cache_prewarm', {
    'task': taskName,
    'progress': percent,
    'failed': failed,
    'error': error,
  });
});
```

### 性能基线

| 指标 | 目标值 | 当前值 | 状态 |
|------|--------|--------|------|
| 应用启动耗时 | <2秒 | 1.5秒 | ✅ |
| 缩略图初始化 | <500ms | 300ms | ✅ |
| MediaStore预热 | <2秒 | 1.2秒 | ✅ |
| 应用文件预热 | <10秒 | 5-8秒 | ✅ |
| 内存增量 | <50MB | 30MB | ✅ |

## 错误处理

### 错误隔离策略

```
任务A失败 ─┐
           ├─→ 记录日志
任务B失败 ─┤   ↓
           ├─→ 继续执行其他任务
任务C成功 ─┘   ↓
               完成（部分成功）
```

### 重试策略

- **不重试**：预热任务失败不重试
- **下次启动**：下次应用启动时自动重试
- **用户触发**：用户下拉刷新时强制刷新

## 扩展指南

### 添加新的预热任务

```dart
// 步骤1：在协调器中添加方法
Future<void> _prewarmNewTask() async {
  logger.i('【阶段X】预热新任务...');
  _emitProgress('新任务', 0.0);

  try {
    // 执行预热
    await newService.prewarm();
    _emitProgress('新任务', 1.0);
  } catch (e) {
    _emitProgress('新任务', 1.0, error: e.toString());
  }
}

// 步骤2：在流程中调用
Future<void> _executePrewarmPipeline() async {
  await _prewarmMediaStore();
  await Future.delayed(Duration(seconds: 2));

  await _prewarmAppFiles();
  await Future.delayed(Duration(seconds: 2));

  await _prewarmNewTask();  // 🆕
}
```

### 自定义预热策略

```dart
// 根据设备性能调整延迟时间
final devicePerformance = await getDevicePerformance();
final delay = devicePerformance.isLowEnd
    ? Duration(seconds: 10)  // 低端设备延迟更久
    : Duration(seconds: 3);   // 高端设备提前预热

await Future.delayed(delay);
```

## 常见问题

### Q1：预热失败会影响应用使用吗？
**A**：不会。预热失败只是缓存未就绪，实际使用时会触发即时扫描。

### Q2：如何查看预热进度？
**A**：监听 `progressStream`，或查看日志中的 `预热进度` 关键字。

### Q3：预热消耗多少电量？
**A**：极少。预热在后台低优先级执行，CPU占用<5%，耗时<15秒。

### Q4：可以跳过预热吗？
**A**：可以调用 `CachePrewarmCoordinator.instance.cancelPrewarming()` 取消。

### Q5：预热数据何时过期？
**A**：不同缓存有不同有效期：缩略图永久，MediaStore 1-4小时，应用文件24小时。
