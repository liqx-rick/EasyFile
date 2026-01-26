# APK管理混合刷新方案

## 方案概述

采用**混合刷新策略**解决APK管理页面的实时性和性能问题：

### 核心特性

1. **后台静默刷新** - 60秒定时器不阻塞UI
2. **实时包监听** - BroadcastReceiver监听安装/卸载/更新事件
3. **页面级生命周期** - 进入页面启动监听，离开页面停止监听

---

## 技术实现

### 1. Dart层（UI + Service）

#### ApkParserChannel（新增方法）
```dart
// 开始监听应用包变化
static Future<void> startPackageListener()

// 停止监听应用包变化
static Future<void> stopPackageListener()

// 设置包变化回调
static void setPackageChangeCallback(Function(String, String) callback)
```

#### ApkManagerService（新增方法）
```dart
void startPackageListener(PackageChangeCallback callback)
void stopPackageListener()
```

#### ApkManagementPage（修改点）
```dart
initState() {
  // 1. 首次加载（使用缓存）
  _loadApkFiles();

  // 2. 60秒后台刷新（不显示loading）
  Timer.periodic(Duration(seconds: 60), (_) {
    _loadApkFilesInBackground();
  });

  // 3. 启动包监听（页面级）
  _apkManagerService.startPackageListener(_onPackageChanged);
}

dispose() {
  _refreshTimer?.cancel();
  _apkManagerService.stopPackageListener(); // 页面销毁时停止
  super.dispose();
}

// 后台静默刷新（关键改动）
Future<void> _loadApkFilesInBackground() async {
  final apkList = await _apkManagerService.scanApkFiles(forceRefresh: true);
  setState(() {
    _apkList = apkList; // 只更新数据，不设置loading状态
  });
}

// 包变化回调
void _onPackageChanged(String packageName, String action) {
  _loadApkFilesInBackground(); // 实时刷新
}
```

---

### 2. Kotlin层（BroadcastReceiver）

#### PackageChangeReceiver.kt（新文件）
```kotlin
class PackageChangeReceiver(private val methodChannel: MethodChannel) : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val packageName = intent.data?.schemeSpecificPart ?: return

        val action = when (intent.action) {
            Intent.ACTION_PACKAGE_ADDED -> {
                val replacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
                if (replacing) "replaced" else "added"
            }
            Intent.ACTION_PACKAGE_REMOVED -> {
                val replacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
                if (replacing) return else "removed"
            }
            Intent.ACTION_PACKAGE_REPLACED -> "replaced"
            else -> return
        }

        // 通知Flutter层
        methodChannel.invokeMethod("onPackageChanged", mapOf(
            "packageName" to packageName,
            "action" to action
        ))
    }
}
```

#### MainActivity.kt（新增方法）
```kotlin
private var packageChangeReceiver: PackageChangeReceiver? = null
private var isPackageListenerRegistered = false

private fun startPackageListener(messenger: BinaryMessenger) {
    val channel = MethodChannel(messenger, APK_PARSER_CHANNEL)
    packageChangeReceiver = PackageChangeReceiver(channel)

    val filter = IntentFilter().apply {
        addAction(Intent.ACTION_PACKAGE_ADDED)
        addAction(Intent.ACTION_PACKAGE_REMOVED)
        addAction(Intent.ACTION_PACKAGE_REPLACED)
        addDataScheme("package")
    }

    registerReceiver(packageChangeReceiver, filter)
    isPackageListenerRegistered = true
}

private fun stopPackageListener() {
    packageChangeReceiver?.let {
        unregisterReceiver(it)
        packageChangeReceiver = null
        isPackageListenerRegistered = false
    }
}
```

---

## 数据流

```
用户操作/系统事件
    ↓
┌───────────────────────────────────────┐
│  触发条件                             │
├───────────────────────────────────────┤
│ 1. 页面初次加载 → 读取缓存            │
│ 2. 60秒定时器   → 后台全盘扫描        │
│ 3. 安装/卸载App → BroadcastReceiver   │
└───────────────────────────────────────┘
    ↓
┌───────────────────────────────────────┐
│  刷新策略                             │
├───────────────────────────────────────┤
│ • 后台刷新：不设置_isLoading          │
│ • 静默更新：setState只更新_apkList    │
│ • 实时响应：包监听立即触发刷新        │
└───────────────────────────────────────┘
    ↓
UI保持可交互 + 数据实时同步
```

---

## 对比分析

| 方面 | 旧方案 | 新方案（混合） |
|------|--------|----------------|
| **刷新频率** | 60秒 | 60秒（后台） + 实时监听 |
| **UI阻塞** | ❌ 每次显示loading | ✅ 完全不阻塞 |
| **安装状态** | ❌ 60秒延迟 | ✅ 实时更新 |
| **新APK检测** | ✅ 60秒内发现 | ✅ 60秒内发现 |
| **资源消耗** | 中等 | 低（事件驱动） |
| **实现复杂度** | ⭐ | ⭐⭐⭐ |

---

## 测试场景

### 场景1：安装新APK
1. 在APK管理页面
2. 使用其他应用安装一个APK
3. **预期**：立即看到新应用状态变为"已安装"

### 场景2：卸载应用
1. 在APK管理页面
2. 卸载某个已安装应用
3. **预期**：对应APK状态立即变为"未安装"

### 场景3：应用更新
1. 在APK管理页面
2. 更新某个应用
3. **预期**：状态实时从"可升级"变为"已安装"

### 场景4：下载新APK
1. 在APK管理页面
2. 浏览器下载新APK
3. **预期**：60秒内出现新APK条目（定时器触发）

### 场景5：页面切换
1. 进入APK管理页面（启动监听）
2. 返回上一页（停止监听）
3. **预期**：logcat显示"APK包监听已启动"和"APK包监听已停止"

---

## 性能优化

### 已实现优化
- ✅ 后台刷新（不显示loading）
- ✅ 页面级监听（离开页面自动停止）
- ✅ 30分钟缓存（首次加载快速）

### 未来优化（可选）
- ⬜ 增量扫描（只扫描Download目录）
- ⬜ 去重检测（避免重复扫描同一APK）
- ⬜ 分页加载（APK数量>100时）

---

## 日志示例

### 正常运行
```
[ApkManagerService] 使用缓存数据: 11个APK
[MainActivity] APK包监听已启动（页面级）
[PackageChangeReceiver] 应用包变化: com.example.app (added)
[ApkManagerService] 开始扫描APK文件...
[ApkManagerService] 扫描完成: 12个APK
```

### 页面离开
```
[MainActivity] APK包监听已停止
```

---

## 常见问题

**Q: 为什么不用应用级监听？**
A: 用户不在APK管理页面时，监听没有意义，且浪费资源。

**Q: 新下载的APK需要多久显示？**
A: 最多60秒（定时器周期），通常在30-60秒内出现。

**Q: 会不会漏掉某些安装事件？**
A: 不会。BroadcastReceiver监听所有包变化，包括系统应用、用户应用。

**Q: 退出应用时需要手动停止监听吗？**
A: 不需要。`onDestroy()`会自动调用`stopPackageListener()`。

---

## 代码清单

### 新增文件
- `receivers/PackageChangeReceiver.kt`

### 修改文件
- `lib/core/channels/apk_parser_channel.dart`
- `lib/core/services/apk_manager_service.dart`
- `lib/ui/pages/apk_management_page.dart`
- `android/app/src/main/kotlin/com/guangqi/easyfile/MainActivity.kt`

### 新增MethodChannel方法
- `startPackageListener`
- `stopPackageListener`
- `onPackageChanged`（回调）

---

## 版本信息

- **实现日期**: 2026-01-26
- **Android最低版本**: Android 11 (API 30)
- **测试设备**: Huawei REA-AN00, Android 15
