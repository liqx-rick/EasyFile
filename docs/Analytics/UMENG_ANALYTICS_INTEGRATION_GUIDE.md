# 友盟 Analytics 原生集成指南

本文档说明如何在 Android 和 iOS 端完成友盟 SDK 的依赖配置。

> 💡 **快速开始**：如果您只想快速部署，请查看 [快速配置指南](./ANALYTICS_QUICK_START.md)

---

## 概述

EasyFile 已实现统一配置方案，**只需修改 1 个配置文件即可完成部署：**

1. **`config/analytics_config.yaml`** - 公共配置（市场、渠道、功能开关、AppKey）

### 架构说明

**配置流程：**
```
config/analytics_config.yaml  →  AnalyticsConfig (Dart)  →  AnalyticsManager
                              →  Gradle/BuildConfig       →  原生代码
```

**已完成的模块：**
- ✅ **Android**: `UmengAnalyticsChannel.kt` 从 BuildConfig 读取配置
- 🚧 **iOS**: `AppDelegate.swift` 预留（未来支持）
- ✅ **Flutter**: `AnalyticsManager` 自动读取 YAML 配置

---

## 快速配置（推荐）

### 步骤 1：配置 AppKey 和渠道

编辑 `config/analytics_config.yaml`：

```yaml
# 市场选择
market: china    # china(友盟) / international(Firebase)

# AppKey 和渠道配置
providers:
  china:
    umeng:
      app_key: "你的实际AppKey"  # 从友盟后台获取
      channel: "GooglePlay"        # 根据发布渠道修改
```

### 步骤 2：重新编译

```bash
flutter clean && flutter run
```

**配置完成！** 更多详情请查看 [快速配置指南](./ANALYTICS_QUICK_START.md)

---

## 详细配置（高级）

如果您需要添加友盟 SDK 依赖或取消注释原生 API 调用，请继续阅读以下内容。

> **平台支持说明**：当前版本仅支持 Android 平台，iOS 实现已预留但暂不可用。

当前实现使用占位符的方式，原生 SDK 调用已被注释。要启用完整的友盟统计功能，需要按照以下步骤配置。

---

## Android 配置

### 1. 添加友盟依赖

编辑 `android/app/build.gradle.kts`，在 `dependencies` 块中添加：

> **版本说明**：版本号已统一管理在 `config/analytics_config.yaml` 的 `providers.china.umeng.sdk_versions` 字段中。
> Gradle 会自动读取配置并应用到依赖。如需升级版本，只需修改 YAML 配置文件即可。
>
> **查看最新版本**：访问 [友盟+ Maven 仓库](https://developer.umeng.com/docs/119267/detail/118584) 或 [Maven Central](https://search.maven.org/)

```kotlin
dependencies {
    // 友盟统计 SDK（版本号从 config/analytics_config.yaml 读取）
    implementation("com.umeng.umsdk:common:$umengCommonVersion")        // 友盟基础组件
    implementation("com.umeng.umsdk:asms:$umengAsmsVersion")          // 反作弊组件
    implementation("com.umeng.umsdk:abtest:$umengAbtestVersion")        // ABTest 组件（可选）

    // 如果需要完整功能，还需要添加：
    // implementation("com.umeng.umsdk:apm:1.9.5")        // 性能监控
    // implementation("com.umeng.umsdk:crash:0.0.5")      // 崩溃收集
}
```

**注意**：上述代码中的 `$umengCommonVersion` 等变量已在 build.gradle.kts 中定义，会自动从配置文件读取。

### 2. 配置 AppKey 和渠道

无需修改代码，只需编辑配置文件。

**编辑 `config/.env.analytics`：**
```env
UMENG_ANDROID_KEY=你的实际AppKey
```

**编辑 `config/analytics_config.yaml`（可选）：**
```yaml
providers:
  china:
    umeng:
      sdk_versions:
        common: "9.6.8"      # 升级版本时修改这里
        asms: "1.8.3"
        abtest: "1.0.3"
      channel: "GooglePlay"  # 修改为你的渠道
```

配置会在编译时自动注入到 `BuildConfig`，原生代码无需修改。

### 3. 启用真实上报（可选）

> ⚠️ **前提条件**：必须先完成步骤 1（添加友盟 SDK 依赖），否则编译会失败。

当前实现使用占位符模式，原生 SDK API 调用已被注释。如果需要启用真实数据上报到友盟后台，需要取消注释。

**编辑 `android/app/src/main/kotlin/com/guangqi/easyfile/analytics/UmengAnalyticsChannel.kt`：**

找到以下被注释的代码并取消注释：

```kotlin
// 在 handleInit() 方法中（约第 XX 行）：
// UMConfigure.init(context, appKey, channel, UMConfigure.DEVICE_TYPE_PHONE, null)
// UMConfigure.setLogEnabled(BuildConfig.DEBUG)
// MobclickAgent.setPageCollectionMode(MobclickAgent.PageMode.AUTO)

// 在 handleLogEvent() 方法中（约第 XX 行）：
// MobclickAgent.onEventObject(context, event, umengParams)

// 在 handleSetEnabled() 方法中（约第 XX 行）：
// MobclickAgent.setCollectionEnabled(enabled)
```

**注意**：
- ✅ 配置参数已从 BuildConfig 自动读取，无需修改代码
  - `BuildConfig.UMENG_APP_KEY`：来自 `config/.env.analytics` 的 `UMENG_ANDROID_KEY`
  - `BuildConfig.UMENG_CHANNEL`：来自 `config/analytics_config.yaml` 的 `providers.china.umeng.channel`
  - `BuildConfig.ANALYTICS_ENABLED`：来自 `config/analytics_config.yaml` 的 `enabled`
- ✅ 只需要删除注释符号 `//`，不需要修改任何代码逻辑
- ⚠️ 如果未添加 SDK 依赖就取消注释，会报错：`Unresolved reference: UMConfigure`

### 4. 混淆配置（如果使用 ProGuard）

在 `android/app/proguard-rules.pro` 中添加：

```proguard
# 友盟混淆规则
-keep class com.umeng.** {*;}
-keepclassmembers class * {
   public <init> (org.json.JSONObject);
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
```

### 5. 权限声明（通常已有）

确保 `android/app/src/main/AndroidManifest.xml` 包含必要权限：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

---

## iOS 配置

> ⚠️ **重要提示**：当前 EasyFile 产品暂不支持 iOS 平台，本节配置仅为未来 iOS 版本预留。
> 如果您只开发 Android 版本，可以跳过本节内容。

### 1. 添加友盟依赖（通过 CocoaPods）

创建或编辑 `ios/Podfile`（如果不存在，运行 `flutter build ios` 会自动生成）：

在 `target 'Runner' do` 块内添加：

```ruby
target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

  # 友盟统计 SDK
  pod 'UMCommon', '~> 7.4.4'      # 友盟基础组件
  pod 'UMDevice', '~> 2.2.1'      # 设备信息收集
  pod 'UMAPM', '~> 1.7.1'         # 性能监控（可选）
end
```

然后在 `ios` 目录下运行：

```bash
pod install
```

### 2. 配置 AppKey 和渠道

> ℹ️ **未来支持**：iOS 端将采用与 Android 相同的统一配置方案，从 `config/.env.analytics` 读取密钥。

**当前临时方案**：编辑 `ios/Runner/AppDelegate.swift`，在 `UmengAnalyticsHandler` 类中修改：

```swift
private let umengAppKey = "YOUR_UMENG_APP_KEY_HERE"  // 从友盟后台获取
private let umengChannel = "App Store"              // 根据发布渠道修改
```

**未来方案**：iOS 版本实现后，将通过以下方式配置：
- **密钥**：`config/.env.analytics` 中的 `UMENG_IOS_KEY`
- **渠道**：`config/analytics_config.yaml` 中的 `channel`
- **注入方式**：Podfile 读取配置并生成 Info.plist 或通过 Swift 读取

**已更新说明**：
- 本项目已将 iOS 平台的 Umeng AppKey 写入 `config/.env.analytics`（字段 `UMENG_IOS_KEY`），值由产品提供。
- 注意：当前 EasyFile 产品暂不支持 iOS 平台，iOS 原生 SDK 调用仍保持注释状态且不会启用真实上报。若未来启用 iOS，再按文档取消注释并添加 Pod 依赖即可。

### 3. 启用真实上报（可选）

> ⚠️ **前提条件**：必须先完成步骤 1（添加友盟 SDK 依赖），否则编译会失败。

当前实现使用占位符模式，原生 SDK API 调用已被注释。如果需要启用真实数据上报，需要取消注释。

**编辑 `ios/Runner/AppDelegate.swift`：**

找到 `UmengAnalyticsHandler` 类中被注释的代码并取消注释：

```swift
// 在 handleInit() 方法中：
// UMConfigure.initWithAppkey(umengAppKey, channel: umengChannel)
// UMConfigure.setLogEnabled(true)
// MobClick.setScenarioType(.E_UM_NORMAL)

// 在 handleLogEvent() 方法中：
// MobClick.event(event, attributes: umengParams)
```

**注意**：
- ⚠️ 如果未添加 SDK 依赖就取消注释，会报错：`Use of unresolved identifier 'UMConfigure'`
- ℹ️ 配置参数（AppKey、Channel）当前需要手动修改常量，未来版本将自动从配置文件读取

### 4. 隐私合规（iOS 14+ 必须）

在 `ios/Runner/Info.plist` 中添加隐私说明：

```xml
<key>NSUserTrackingUsageDescription</key>
<string>为了优化您的体验并提供更好的服务，我们需要收集匿名使用数据</string>
```

如需启用 IDFA 追踪（需用户授权），在 Swift 代码中添加：

```swift
import AppTrackingTransparency

// 在合适的时机请求授权
if #available(iOS 14, *) {
    ATTrackingManager.requestTrackingAuthorization { status in
        // 处理授权结果
    }
}
```

---

## 友盟 SDK 版本说明

文档中提到的友盟 SDK 版本号（如 9.6.8, 1.8.3 等）为编写时的推荐稳定版本。

**版本号格式**：`主版本.次版本.修订号`（例如：9.6.8）
- **主版本**：重大架构变更或 API 破坏性更新
- **次版本**：新功能添加，向后兼容
- **修订号**：Bug 修复和小改进

**版本管理策略**：
1. **固定版本（推荐生产）**：使用具体版本号，确保稳定性
   ```kotlin
   implementation("com.umeng.umsdk:common:9.6.8")
   ```

2. **动态版本（谨慎使用）**：自动获取最新版本，可能引入不兼容
   ```kotlin
   implementation("com.umeng.umsdk:common:+")  // 不推荐
   ```

3. **版本范围（折中方案）**：允许小版本更新
   ```kotlin
   implementation("com.umeng.umsdk:common:9.6.+")  // 允许 9.6.x 更新
   ```

**建议**：保持文档版本号，在实际部署时根据友盟官网最新推荐版本适当调整。

---

## 获取友盟 AppKey

1. 访问友盟+ 官网：[https://www.umeng.com/](https://www.umeng.com/)
2. 注册/登录账号
3. 在控制台创建应用（Android 和 iOS 需要分别创建）
4. 获取各自平台的 AppKey（32位字符串）
5. 将 AppKey 填入上述配置文件中

---

## 验证集成

### Android 验证

运行应用后，在 Logcat 中查找日志：

```
I/UmengAnalyticsChannel: Umeng initialized successfully with AppKey: xxxxx
D/UmengAnalyticsChannel: Logged event: enter_module with params: {module=large_file_scan}
```

### iOS 验证

在 Xcode Console 中查找日志：

```
[UmengAnalytics] Initialized successfully with AppKey: xxxxx
[UmengAnalytics] Logged event: enter_module with params: Optional(["module": "large_file_scan"])
```

### Flutter 验证

在应用启动日志中查找：

```
I/flutter: ✓ Analytics initialized
```

在业务代码调用埋点后，会看到事件上报日志。

---

## 测试模式与调试

### 在测试阶段使用占位符 AppKey

如果暂时没有友盟账号或 AppKey，可以保持当前的占位符配置。此时：
- MethodChannel 桥接正常工作
- Flutter 层调用不会报错
- 原生层会打印日志但不会真实上报
- 不影响开发和测试

### 切换到 Firebase（可选）

如果需要切换到 Firebase Analytics（例如发布到国际市场）：

**方式 1：通过配置文件切换（推荐）**

只需修改 `config/analytics_config.yaml`：
```yaml
market: international  # 从 china 改为 international
```

`AnalyticsManager` 会自动根据 `market` 字段选择对应的 provider。

**方式 2：代码中显式指定**

```dart
// 在 main.dart 中
await AnalyticsManager.init(provider: AnalyticsProvider.firebase);
```

**前置条件**：
1. 修改 `lib/analytics/firebase_analytics_service.dart`，实现实际的 Firebase 集成
2. 添加 `firebase_analytics` 依赖到 `pubspec.yaml`
3. 配置 Firebase 项目（`google-services.json` / `GoogleService-Info.plist`）
4. 在 `config/.env.analytics` 中添加 Firebase 配置（如需要）

---

## 常见问题

### Q: 编译时提示找不到友盟类

**A**: 确保已添加依赖并运行 Gradle Sync（Android）或 `pod install`（iOS）。

### Q: 运行时提示 AppKey 无效

**A**: 检查 AppKey 是否正确，Android 和 iOS 的 AppKey 是不同的。

### Q: 想要完全禁用埋点

**A**: 调用 `AnalyticsManager.enable(false)` 或在初始化时传入 `AnalyticsProvider.none`。

### Q: 需要采集页面浏览事件

**A**: 友盟 Android SDK 支持自动页面采集（已在 `handleInit` 中配置）。如需手动控制，可添加 `logPageView` 方法。

---

## 隐私合规说明

### GDPR / CCPA 合规

在用户首次启动时，应该：
1. 展示隐私政策和用户协议
2. 明确告知数据收集用途
3. 在用户同意后才调用 `AnalyticsManager.init()`
4. 提供"禁用数据收集"的选项

示例代码：

```dart
// 在用户同意隐私协议后
final hasConsent = await PrivacyService.hasUserConsent();
if (hasConsent) {
  await AnalyticsManager.init();
} else {
  await AnalyticsManager.init(provider: AnalyticsProvider.none);
}
```

### 用户撤销授权

提供设置页选项：

```dart
// 在设置页面
void onDisableAnalytics() async {
  await AnalyticsManager.enable(false);
  await AnalyticsManager.clearAll();
}
```

---

## 相关文档

- [友盟+ Android SDK 文档](https://developer.umeng.com/docs/119267/detail/118584)
- [友盟+ iOS SDK 文档](https://developer.umeng.com/docs/119267/detail/118585)
- [Flutter MethodChannel 官方文档](https://docs.flutter.dev/platform-integration/platform-channels)

---

## 总结

当前实现已经完成了完整的架构搭建：
- ✅ 抽象层设计（`AnalyticsService`）
- ✅ MethodChannel 桥接代码（Android/iOS）
- ✅ 全局管理器（`AnalyticsManager`）
- ✅ 业务层示例（`analytics_example.dart`）
- ✅ **统一配置方案**（`config/analytics_config.yaml` + `config/.env.analytics`）
- ⏳ 友盟 SDK 依赖配置（需按本文档操作）
- ⏳ 取消注释原生 API 调用（启用真实上报）

## 配置方式对比

### ✅ 新版统一配置（推荐）

**修改位置：** 只需修改 2 个配置文件
- `config/analytics_config.yaml`
- `config/.env.analytics`

**优势：**
- 配置集中，易于管理
- 密钥不入库，安全性高
- 支持快速切换市场/渠道
- 无需修改原生代码

**详情：** 查看 [快速配置指南](./ANALYTICS_QUICK_START.md)

### ❌ 旧版分散配置（已废弃）

**修改位置：** 需要修改 4-5 个文件
- `android/app/build.gradle.kts`（依赖）
- `UmengAnalyticsChannel.kt`（硬编码 AppKey）
- `analytics_config.dart`（provider 选择）
- ...

**缺点：**
- 配置分散难以维护
- AppKey 硬编码在代码中
- 切换市场需要改多处

---

按照本文档完成配置后，即可开始真实的数据采集和分析。
