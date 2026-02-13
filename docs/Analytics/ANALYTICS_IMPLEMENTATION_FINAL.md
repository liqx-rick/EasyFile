# 埋点模块实现文档（最终版）

**文档状态**: 正式版  
**基于代码**: 2026-01-29 审查  
**适用范围**: EasyFile 埋点功能完整说明

---

## 一、功能概述

埋点模块提供统一的事件上报能力，支持多平台（Umeng/Firebase）切换。

**实现范围**:
- ✅ 事件上报 API（`AnalyticsManager.log`）
- ✅ 合规三步初始化（preInit → grant → init）
- ✅ 38 个业务事件封装（`AnalyticsHelper`）
- ✅ YAML 配置管理（`config/analytics_config.yaml`）
- ✅ Umeng SDK 原生集成（MethodChannel）
- ⚠️ Firebase 占位实现（no-op，不会实际上报）

**未实现**:
- ❌ 运行时 enable/disable API（无法在运行时动态切换）
- ❌ 数据清理 API（clear/dispose 方法不存在）
- ❌ Firebase 真实集成（仅为降级占位）

---

## 二、架构设计（基于代码）

```
业务层（UI Pages）
    ↓ 调用 AnalyticsHelper 或 AnalyticsManager.log()
AnalyticsManager（单例）
    ↓ 选择 provider（基于 config/analytics_config.yaml）
AnalyticsService（抽象接口）
    ├─ UmengAnalyticsService → MethodChannel('easyfile/analytics/umeng') → Android 原生
    └─ FirebaseAnalyticsService → no-op 占位（不上报）
```

**关键类**:
- `AnalyticsManager`: 单例管理器，提供静态 API（`preInit`, `grant`, `init`, `log`）
- `AnalyticsService`: 抽象接口（`initialize`, `logEvent`）
- `AnalyticsHelper`: 38 个业务事件封装方法
- `AnalyticsConfig`: YAML 配置读取器

---

## 三、使用方式

### 3.1 初始化流程（必须按顺序）

```dart
// 步骤 1：应用启动时预初始化（无需用户同意）
await AnalyticsManager.preInit();

// 步骤 2：用户同意隐私政策后授权
await AnalyticsManager.grant();

// 步骤 3：正式初始化并启用上报
await AnalyticsManager.init();
```

**重要**: 如果未完成 `init()`，后续 `log()` 会丢弃事件并记录警告。

### 3.2 记录事件

**推荐**: 使用 `AnalyticsHelper` 封装方法

```dart
// 扫描生命周期
await AnalyticsHelper.logScanStart('large_file');
await AnalyticsHelper.logScanFinish(
  scanType: 'large_file',
  durationMs: 5234,
  itemCount: 120,
  totalSizeMb: 1024.5,
);

// 隐私空间
await AnalyticsHelper.logPrivacySpaceEnter('main_page');

// 快捷访问
await AnalyticsHelper.logQuickAccessFolderClick(
  folderType: 'system',
  folderName: 'Downloads',
  isPinned: false,
);
```

**通用方式**: 直接调用管理器

```dart
await AnalyticsManager.log('custom_event', params: {
  'key1': 'value1',
  'key2': 123,
});
```

---

## 四、配置说明

### 4.1 配置文件路径

**唯一配置文件**: `config/analytics_config.yaml`

Dart 代码通过 `AnalyticsConfig.load()` 读取此文件，原生代码可通过 Gradle 注入到 BuildConfig。

### 4.2 关键配置字段

```yaml
# 全局开关
enabled: true

# 市场选择（决定 provider）
market: china  # china(Umeng) / international(Firebase)

# Umeng 配置
providers:
  china:
    umeng:
      app_key: "your_umeng_app_key"  # 从友盟后台获取
      channel: "GooglePlay"           # 发布渠道
      sdk_versions:
        common: "9.6.8"
        asms: "1.8.3"
```

**AppKey 来源**: 
- Dart: 从 YAML 读取（`AnalyticsConfig` 类）
- Android: 通过 Gradle 注入到 BuildConfig（需要配置 build.gradle.kts）

---

## 五、事件列表

`AnalyticsHelper` 提供 **38 个**封装方法，覆盖以下场景：

| 分类 | 事件数 | 示例方法 |
|------|--------|---------|
| 扫描 | 3 | `logScanStart`, `logScanFinish`, `logScanCancel` |
| 清理 | 3 | `logCleanAction`, `logCleanConfirm`, `logCleanSuccess` |
| 分类浏览 | 1 | `logCategoryEnter` |
| 文件浏览 | 2 | `logFileBrowseEnter`, `logFileBrowseAction` |
| 隐私空间 | 5 | `logPrivacySpaceEnter`, `logPrivacySpaceAuth`, etc. |
| 压缩包管理 | 6 | `logArchiveManagementEnter`, `logArchiveScanStart`, etc. |
| 快捷访问 | 6 | `logQuickAccessEnter`, `logQuickAccessFolderClick`, etc. |
| 回收站 | 3 | `logTrashView`, `logTrashRestore`, `logTrashPermanentDelete` |
| 应用管理 | 2 | `logAppManagementEnter`, `logAppSettingsOpen` |
| 设置 | 2 | `logSettingsEnter`, `logSettingsChange` |
| 其他 | 5 | `logLargeFilesEnter`, `logDuplicateFilesEnter`, etc. |

完整列表参见 `lib/analytics/analytics_helper.dart`。

---

## 六、核心逻辑说明

### 6.1 Provider 选择

`AnalyticsManager.preInitialize()` 读取 `config/analytics_config.yaml`:

- `enabled: false` → 使用 Firebase 占位（不上报）
- `market: china` → 使用 `UmengAnalyticsService`
- `market: international` → 使用 `FirebaseAnalyticsService`（当前为 no-op）

### 6.2 Umeng 三步合规

`UmengAnalyticsService` 实现：

1. **preInitialize()** → 调用原生 `preInit` 方法
2. **grantPrivacy()** → 调用原生 `grantPrivacy` 方法
3. **initialize()** → 调用原生 `init` 方法

原生需实现 MethodChannel 方法（`easyfile/analytics/umeng`）:
- `preInit` - 预初始化
- `grantPrivacy` - 隐私授权
- `init` - 正式初始化
- `logEvent` - 记录事件

### 6.3 事件丢弃逻辑

`AnalyticsManager._logEvent()`:

```dart
if (!_initialized) {
  logger.w('Analytics not initialized, dropping event: $event');
  return;
}
```

未完成 `init()` 的事件会被丢弃，不会上报。

### 6.4 异常降级

- 配置加载失败 → 使用 Firebase 占位（不上报）
- MethodChannel 调用失败 → 捕获异常并记录日志（不阻塞业务）

---

## 七、限制与未覆盖场景

### 7.1 已知限制

1. **无运行时开关**: `AnalyticsManager` 不提供 `setEnabled()`/`disable()` API，无法在运行时动态切换
2. **无清理 API**: 不支持 `clear()`/`dispose()` 清理本地缓存
3. **Firebase 未集成**: `FirebaseAnalyticsService` 仅为占位，不会实际上报
4. **仅支持 Android**: iOS 原生集成未实现

### 7.2 依赖条件

- **Dart 侧**: 需要 `config/analytics_config.yaml` 配置文件
- **Android 侧**: 需要原生实现 `MethodChannel` 接口（`UmengAnalyticsChannel.kt`）
- **Umeng 上报**: 需要在 `build.gradle.kts` 中添加 Umeng SDK 依赖

### 7.3 未覆盖场景

- 崩溃上报（未启用 Umeng crash 组件）
- 性能监控（未启用 Umeng apm 组件）
- 用户属性设置（未实现 `setUserProperty` API）
- A/B 测试（已添加依赖但未实现调用）

---

## 八、验证方法

### 8.1 日志监控（Android）

```bash
adb logcat -s UmengAnalyticsChannel:D
```

预期输出示例：

```
D/UmengAnalyticsChannel: Logged event: scan_start with params: {type=large_file}
D/UmengAnalyticsChannel: Logged event: scan_finish with params: {type=large_file, duration_ms=5234, ...}
```

### 8.2 检查初始化状态

启动应用后查看日志：

```
I/flutter: Analytics pre-initializing...
I/flutter: Analytics selecting provider: AnalyticsProvider.umeng
I/flutter: UmengAnalyticsService pre-initialized (Step 1/3)
I/flutter: UmengAnalyticsService privacy granted (Step 2/3)
I/flutter: UmengAnalyticsService fully initialized (Step 3/3)
```

### 8.3 QA 检查清单

- [ ] 应用启动后 5 秒内看到 `app_launch` 事件
- [ ] 切换前后台看到 `app_background`/`app_foreground` 事件
- [ ] 进入扫描页面看到对应 `*_enter` 事件
- [ ] 执行扫描后看到 `scan_start` → `scan_finish` 完整流程
- [ ] 未完成 `init()` 前事件被丢弃（日志有警告）

---

## 九、实现与设计差异

### 9.1 配置文件差异

**设计**: 使用 `.env.analytics` 密钥文件 + `analytics_config.yaml`  
**实现**: 仅使用 `analytics_config.yaml`，AppKey 直接写在 YAML 中  
**影响**: 简化配置流程，但需注意 AppKey 不应提交到公开仓库

### 9.2 API 差异

**设计**: `AnalyticsManager` 提供 `setEnabled`/`clear`/`dispose` 方法  
**实现**: 这些方法不存在  
**影响**: 无法在运行时切换埋点开关或清理缓存

### 9.3 事件数量差异

**早期文档**: 声称 ~30 个事件  
**实际实现**: 38 个 helper 方法（`AnalyticsHelper`）  
**影响**: 需更新测试覆盖清单

### 9.4 Firebase 状态

**设计**: 支持 Firebase 和 Umeng 双平台切换  
**实现**: Firebase 为 no-op 占位，不会实际上报  
**影响**: 海外市场无法使用埋点功能

---

## 十、相关文件

### 代码文件

- `lib/analytics/analytics_manager.dart` - 管理器
- `lib/analytics/analytics_service.dart` - 抽象接口
- `lib/analytics/analytics_helper.dart` - 业务封装（38 个方法）
- `lib/analytics/umeng_analytics_service.dart` - Umeng 实现
- `lib/analytics/firebase_analytics_service.dart` - Firebase 占位
- `lib/analytics/analytics_config.dart` - 配置读取
- `config/analytics_config.yaml` - 配置文件
- `android/.../UmengAnalyticsChannel.kt` - Android 原生桥接

### 文档文件

- `ANALYTICS_API_QUICKSTART.md` - 快速入门（调用示例）
- `ANALYTICS_IMPLEMENTATION_CHECKLIST.md` - 实施清单
- `UMENG_ANALYTICS_INTEGRATION_GUIDE.md` - 原生集成指南
- `P0_ANALYTICS_TEST_GUIDE.md` - 测试指南（部分过时）

---

**文档维护**: 本文档基于代码实现生成，如代码变更请同步更新。
