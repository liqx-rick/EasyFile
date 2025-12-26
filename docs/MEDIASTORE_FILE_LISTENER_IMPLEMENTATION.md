# MediaStore 文件监听机制实现文档

## 📋 概述

实现了基于 MediaStore ContentObserver 的文件变化监听机制，当用户添加、修改或删除文件时，自动清除应用统计缓存，确保显示最新数据。

## 🏗️ 架构设计

### 三层架构

```
┌─────────────────────────────────────────────┐
│           Android Native 层                  │
│  ┌───────────────────────────────────────┐  │
│  │  MediaStore ContentObserver           │  │
│  │  - 监听 Images/Videos/Audio/Downloads │  │
│  │  - 发送事件到 EventChannel             │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│          Flutter Channel 层                  │
│  ┌───────────────────────────────────────┐  │
│  │  AppFileScannerChannel                │  │
│  │  - watchFileChangeEvents()            │  │
│  │  - 接收并转换事件流                    │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│         Service 层（业务逻辑）                │
│  ┌───────────────────────────────────────┐  │
│  │  FileChangeListenerService            │  │
│  │  - 监听事件流                          │  │
│  │  - 防抖处理（2秒）                     │  │
│  │  - 清除 AppStatisticsCache            │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│            UI 层（页面）                     │
│  ┌───────────────────────────────────────┐  │
│  │  AppManagementPage                    │  │
│  │  QuickAccessSection                   │  │
│  │  - 初始化监听服务                      │  │
│  │  - 自动刷新显示                        │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

## 📁 文件结构

### 1. Android 端

**文件**: `android/app/src/main/kotlin/com/guangqi/easyfile/MainActivity.kt`

#### 添加内容：
- 常量：`FILE_CHANGE_EVENT_CHANNEL`
- 变量：`fileChangeEventSink`, `mediaStoreObserver`
- 方法：
  - `registerMediaStoreObserver()` - 注册监听器
  - `unregisterMediaStoreObserver()` - 取消监听器
- EventChannel 配置

#### 核心代码：
```kotlin
// 注册 MediaStore 监听
private fun registerMediaStoreObserver() {
    val handler = android.os.Handler(android.os.Looper.getMainLooper())
    
    mediaStoreObserver = object : android.database.ContentObserver(handler) {
        override fun onChange(selfChange: Boolean, uri: android.net.Uri?) {
            uri?.let {
                fileChangeEventSink?.success(mapOf(
                    "event" to "file_changed",
                    "uri" to it.toString(),
                    "timestamp" to System.currentTimeMillis()
                ))
            }
        }
    }
    
    // 监听各种媒体类型
    contentResolver.registerContentObserver(
        MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, mediaStoreObserver!!
    )
    // ... Videos, Audio, Downloads
}
```

### 2. Flutter Channel 层

**文件**: `lib/core/platform/app_file_scanner_channel.dart`

#### 添加内容：
- EventChannel: `_fileChangeEventChannel`
- Stream: `_fileChangeEventStream`
- 方法: `watchFileChangeEvents()`

#### 核心代码：
```dart
static Stream<Map<String, dynamic>> watchFileChangeEvents() {
  _fileChangeEventStream ??= _fileChangeEventChannel
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));
  return _fileChangeEventStream!;
}
```

### 3. Service 层

**新文件**: `lib/core/services/file_change_listener_service.dart`

#### 功能特性：
- ✅ 监听文件变化事件
- ✅ 防抖处理（默认2秒）
- ✅ 自动清除统计缓存
- ✅ 生命周期管理

#### 核心代码：
```dart
class FileChangeListenerService {
  final AppStatisticsCache statisticsCache;
  final int debounceMillis; // 防抖延迟
  
  Future<void> startListening() async {
    _subscription = AppFileScannerChannel.watchFileChangeEvents().listen(
      _handleFileChange,
    );
  }
  
  void _handleFileChange(Map<String, dynamic> event) {
    // 防抖：2秒内多次变化只触发一次缓存清除
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      Duration(milliseconds: debounceMillis), 
      _clearAllCache
    );
  }
}
```

### 4. UI 层集成

#### AppManagementPage

**文件**: `lib/ui/pages/app_management_page.dart`

```dart
class _AppManagementPageState extends State<AppManagementPage> {
  FileChangeListenerService? _fileChangeListener;
  
  @override
  void initState() {
    super.initState();
    _initFileChangeListener();
  }
  
  Future<void> _initFileChangeListener() async {
    final statisticsCache = AppStatisticsCache();
    await statisticsCache.initialize();
    
    _fileChangeListener = FileChangeListenerService(
      statisticsCache: statisticsCache,
    );
    await _fileChangeListener!.startListening();
  }
  
  @override
  void dispose() {
    _fileChangeListener?.dispose();
    super.dispose();
  }
}
```

#### QuickAccessSection

**文件**: `lib/ui/widgets/quick_access_section.dart`

```dart
// 使用推荐服务中的 statisticsCache
_fileChangeListener = FileChangeListenerService(
  statisticsCache: _recommendationService.statisticsCache,
);
```

## 🔄 工作流程

### 完整流程示例

```
用户操作: 拍照/下载文件
        ↓
MediaStore 发生变化
        ↓
ContentObserver.onChange() 被触发
        ↓
发送事件到 EventChannel
  event: "file_changed"
  uri: "content://media/external/images/media/123"
  timestamp: 1735123456789
        ↓
Flutter 接收事件
  AppFileScannerChannel.watchFileChangeEvents()
        ↓
FileChangeListenerService 处理
  - 防抖计时器启动（2秒）
  - 2秒内无新事件 → 执行清除
        ↓
清除 AppStatisticsCache
  statisticsCache.clearAll()
        ↓
下次查询时重新扫描
  获取最新统计数据
```

## ⚙️ 配置参数

### 防抖延迟

```dart
FileChangeListenerService(
  statisticsCache: cache,
  debounceMillis: 2000, // 可调整，默认2000ms
);
```

**建议值**：
- 2000ms（默认）- 平衡响应速度和性能
- 1000ms - 更快响应，但可能频繁清除缓存
- 5000ms - 更少清除，但延迟更高

### 监听的 MediaStore URI

| URI | 说明 | Android 版本 |
|-----|------|------------|
| `MediaStore.Images.Media.EXTERNAL_CONTENT_URI` | 图片 | 全部 |
| `MediaStore.Video.Media.EXTERNAL_CONTENT_URI` | 视频 | 全部 |
| `MediaStore.Audio.Media.EXTERNAL_CONTENT_URI` | 音频 | 全部 |
| `MediaStore.Downloads.EXTERNAL_CONTENT_URI` | 下载 | Android 10+ |

## 📊 性能影响

### 资源消耗

| 项目 | 开销 | 说明 |
|------|------|------|
| 内存 | 极低 (~1KB) | 只保存监听器引用 |
| CPU | 极低 | 事件触发时短暂处理 |
| 电量 | 忽略不计 | 系统级监听，无轮询 |

### 响应延迟

- **事件触发延迟**: <100ms（系统级通知）
- **防抖延迟**: 2000ms（可配置）
- **总延迟**: ~2100ms（从文件变化到缓存清除）

## 🧪 测试验证

### 单元测试

**文件**: `test/services/file_change_listener_service_test.dart`

```bash
flutter test test/services/file_change_listener_service_test.dart
```

### 手动测试步骤

1. **启动应用**，进入"应用管理"页面
2. **拍照或下载文件**
3. **观察日志**：
   ```
   [FileChangeListenerService] 文件变化: content://media/...
   [FileChangeListenerService] ✓ 文件变化 -> 已清除所有应用统计缓存
   ```
4. **下拉刷新**应用列表，验证统计数据已更新

## 🐛 故障排查

### 问题1: 监听未启动

**症状**: 添加文件后统计数据不更新

**检查**:
```bash
# 查看日志
adb logcat | grep "MediaStore监听"
```

**可能原因**:
- 权限不足（需要存储权限）
- EventChannel 未正确注册

### 问题2: 频繁清除缓存

**症状**: 性能下降，频繁扫描

**解决**:
- 增加防抖延迟：`debounceMillis: 5000`
- 检查是否有其他应用频繁修改文件

### 问题3: 内存泄漏

**症状**: 长时间运行后内存增长

**解决**:
- 确保 `dispose()` 被调用
- 检查 `_subscription` 是否正确取消

## 📚 使用示例

### 最小示例

```dart
// 1. 创建缓存服务
final cache = AppStatisticsCache();
await cache.initialize();

// 2. 创建监听服务
final listener = FileChangeListenerService(
  statisticsCache: cache,
);

// 3. 启动监听
await listener.startListening();

// 4. 不需要时停止
listener.dispose();
```

### 与 RecommendationService 集成

```dart
// 使用推荐服务的缓存
final recommendationService = RecommendationService(...);

final listener = FileChangeListenerService(
  statisticsCache: recommendationService.statisticsCache,
);

await listener.startListening();
```

## 🔮 未来优化

### 1. 选择性清除缓存

目前清除所有应用缓存，可优化为：
- 根据 URI 判断文件类型
- 只清除相关应用的缓存

```dart
void _handleFileChange(Map<String, dynamic> event) {
  final uri = event['uri'] as String;
  
  if (uri.contains('wechat')) {
    // 只清除微信缓存
    statisticsCache.clear('wechat');
  }
}
```

### 2. 批量清除优化

短时间内多次变化时，收集所有变化后批量处理：

```dart
Set<String> _changedApps = {};

void _handleFileChange(event) {
  _changedApps.add(detectApp(event['uri']));
  _debounceTimer?.cancel();
  _debounceTimer = Timer(..., () {
    for (var app in _changedApps) {
      statisticsCache.clear(app);
    }
    _changedApps.clear();
  });
}
```

### 3. 智能刷新UI

文件变化时不仅清除缓存，还通知UI刷新：

```dart
class FileChangeListenerService {
  final Function()? onCacheCleared;
  
  void _clearAllCache() {
    statisticsCache.clearAll();
    onCacheCleared?.call(); // 通知UI
  }
}
```

## ✅ 总结

### 优点

- ✅ **实时性**: 文件变化 <3秒 自动更新
- ✅ **性能**: 系统级监听，零额外开销
- ✅ **可靠性**: ContentObserver 稳定可靠
- ✅ **易维护**: 代码结构清晰，易于扩展

### 适用场景

- ✅ 应用文件统计（当前实现）
- ✅ 相册应用（监听图片变化）
- ✅ 文件管理器（监听文件系统）
- ✅ 下载管理（监听下载目录）

### 不适用场景

- ❌ 非 MediaStore 文件（如应用私有目录）
- ❌ 需要精确文件路径（只提供 URI）
- ❌ 需要实时显示（有2秒防抖延迟）

## 📞 相关文档

- [Android ContentObserver 文档](https://developer.android.com/reference/android/database/ContentObserver)
- [MediaStore API 文档](https://developer.android.com/reference/android/provider/MediaStore)
- [Flutter EventChannel 文档](https://api.flutter.dev/flutter/services/EventChannel-class.html)
- [AppStatisticsCache 实现文档](../lib/core/services/app_statistics_cache.dart)
