# 多渠道编译方案（待实现）

> 🚧 **状态**：待实现 | **优先级**：中 | **预计工作量**：2-4 小时

---

## 📋 需求背景

### 当前问题

EasyFile 目前的渠道配置方式存在以下问题：

1. **需要多次编译**：发布到不同渠道（Google Play、华为、小米等）需要手动修改 `config/analytics_config.yaml` 中的 `channel` 字段，然后重新编译
2. **容易出错**：手动修改配置容易忘记或填错
3. **不利于 CI/CD**：自动化流水线需要额外的脚本逻辑
4. **缺乏灵活性**：无法为不同渠道定制资源（如应用图标、名称等）

### 业务场景

```
需求：同时发布到 5 个应用商店
- Google Play（国际版）
- 华为应用市场
- 小米应用商店
- OPPO 软件商店
- vivo 应用商店

当前方案：需要手动修改配置 5 次，编译 5 次
期望方案：一次性编译所有渠道包，自动命名
```

---

## 🎯 解决方案：Gradle Product Flavors

### 方案概述

使用 Android Gradle 的 `productFlavors` 特性，在编译时自动为每个渠道生成独立的 APK。

**核心原理**：
```
Gradle Build Script → Product Flavors 配置 → BuildConfig 注入 → APK 输出
```

**效果**：
```bash
# 单条命令编译所有渠道
./gradlew assembleRelease

# 输出 5 个 APK
build/app/outputs/apk/googleplay/release/app-googleplay-release.apk
build/app/outputs/apk/huawei/release/app-huawei-release.apk
build/app/outputs/apk/xiaomi/release/app-xiaomi-release.apk
build/app/outputs/apk/oppo/release/app-oppo-release.apk
build/app/outputs/apk/vivo/release/app-vivo-release.apk
```

---

## 📐 技术设计

### 1. Gradle 配置结构

**修改文件**：`android/app/build.gradle.kts`

```kotlin
android {
    // 定义 flavor 维度
    flavorDimensions += "channel"

    // 定义各个渠道
    productFlavors {
        create("googleplay") {
            dimension = "channel"
            applicationIdSuffix = ".googleplay"  // 可选：不同包名
            versionNameSuffix = "-gp"            // 可选：版本后缀

            // 注入渠道标识到 BuildConfig
            buildConfigField("String", "CHANNEL", "\"GooglePlay\"")

            // 可选：为该渠道定制资源
            resValue("string", "app_name", "EasyFile")
        }

        create("huawei") {
            dimension = "channel"
            buildConfigField("String", "CHANNEL", "\"Huawei\"")
            resValue("string", "app_name", "EasyFile")
        }

        create("xiaomi") {
            dimension = "channel"
            buildConfigField("String", "CHANNEL", "\"Xiaomi\"")
            resValue("string", "app_name", "EasyFile")
        }

        create("oppo") {
            dimension = "channel"
            buildConfigField("String", "CHANNEL", "\"OPPO\"")
            resValue("string", "app_name", "EasyFile")
        }

        create("vivo") {
            dimension = "channel"
            buildConfigField("String", "CHANNEL", "\"vivo\"")
            resValue("string", "app_name", "EasyFile")
        }
    }
}
```

### 2. 原生代码适配

**修改文件**：`android/app/src/main/kotlin/.../UmengAnalyticsChannel.kt`

```kotlin
private fun handleInit(call: MethodCall, result: MethodChannel.Result) {
    val context = this.context ?: run {
        result.error("ERROR", "Context not available", null)
        return
    }

    // 从 BuildConfig 读取渠道（优先级高于配置文件）
    val channel = BuildConfig.CHANNEL
    val appKey = BuildConfig.UMENG_APP_KEY

    if (appKey.isEmpty() || appKey == "YOUR_UMENG_APP_KEY_HERE") {
        result.error("ERROR", "AppKey not configured", null)
        return
    }

    Log.i(TAG, "Umeng initializing with Channel: $channel, AppKey: ${maskAppKey(appKey)}")

    // 初始化友盟 SDK
    // UMConfigure.init(context, appKey, channel, UMConfigure.DEVICE_TYPE_PHONE, null)

    result.success(mapOf("status" to "initialized", "channel" to channel))
}
```

### 3. Flutter 编译命令

```bash
# 编译单个渠道
flutter build apk --release --flavor googleplay

# 编译所有渠道（需要脚本）
flutter build apk --release --flavor googleplay
flutter build apk --release --flavor huawei
flutter build apk --release --flavor xiaomi
flutter build apk --release --flavor oppo
flutter build apk --release --flavor vivo
```

### 4. 配置文件调整

**`config/analytics_config.yaml` 简化**：

```yaml
# 移除 channel 字段（由 Product Flavor 提供）
providers:
  china:
    umeng:
      # channel: "GooglePlay"  # ❌ 删除这一行（改用 Gradle Flavor 提供）
      sdk_versions:               # ✅ 保留版本号配置
        common: "9.6.8"
        asms: "1.8.3"
        abtest: "1.0.3"

      # 渠道配置移到 Gradle Product Flavors
```

---

## 🔧 实现步骤

### 阶段 1：Gradle 配置（预计 1 小时）

- [ ] 修改 `android/app/build.gradle.kts` 添加 `productFlavors` 配置
- [ ] 为每个渠道定义 `buildConfigField("String", "CHANNEL", "...")`
- [ ] 测试编译单个 flavor：`flutter build apk --flavor googleplay`
- [ ] 验证 BuildConfig 生成是否正确

### 阶段 2：原生代码适配（预计 0.5 小时）

- [ ] 修改 `UmengAnalyticsChannel.kt` 读取 `BuildConfig.CHANNEL`
- [ ] 移除配置文件中的 channel 读取逻辑
- [ ] 添加日志输出当前渠道名
- [ ] 测试不同 flavor 下渠道名是否正确

### 阶段 3：配置文件清理（预计 0.5 小时）

- [ ] 从 `analytics_config.yaml` 移除 `channel` 字段
- [ ] 更新 `analytics_config.dart` 移除 channel 读取逻辑
- [ ] 更新文档说明新的渠道配置方式
- [ ] 添加迁移指南（从旧配置到新配置）

### 阶段 4：自动化脚本（预计 1 小时）

- [ ] 创建 `scripts/build_all_channels.sh`（Linux/Mac）
- [ ] 创建 `scripts/build_all_channels.ps1`（Windows）
- [ ] 实现自动编译所有 flavor
- [ ] 实现 APK 自动重命名和归档
- [ ] 添加编译日志和错误处理

### 阶段 5：文档更新（预计 1 小时）

- [ ] 更新 `ANALYTICS_QUICK_START.md` 说明新的渠道编译方式
- [ ] 更新 `UMENG_ANALYTICS_INTEGRATION_GUIDE.md` 添加 Product Flavors 说明
- [ ] 创建 `CHANNEL_BUILD_HOWTO.md` 详细说明多渠道编译流程
- [ ] 更新 `README.md` 添加快速编译指南

---

## 📊 方案对比

| 特性 | 当前方案（手动修改配置） | Product Flavors 方案 |
|------|------------------------|---------------------|
| 编译次数 | N 次（N=渠道数） | 1 次 |
| 出错风险 | 高（手动修改） | 低（自动化） |
| CI/CD 支持 | 需要额外脚本 | 原生支持 |
| 资源定制 | 不支持 | 支持（图标、名称等） |
| 维护成本 | 高 | 低 |
| 学习成本 | 低 | 中 |
| 实现成本 | 0 | 2-4 小时（一次性） |

---

## 🎯 预期收益

### 开发效率提升

- **节省时间**：从 "修改配置 → 编译 → 验证" 的 N 次循环，缩短为 1 次编译
- **减少错误**：消除手动修改配置的人为失误
- **提升体验**：开发者无需关心渠道切换细节

### CI/CD 友好

```yaml
# GitHub Actions 示例
- name: Build All Channels
  run: |
    flutter build apk --release --flavor googleplay
    flutter build apk --release --flavor huawei
    flutter build apk --release --flavor xiaomi

- name: Upload Artifacts
  uses: actions/upload-artifact@v3
  with:
    name: apks
    path: build/app/outputs/apk/**/*.apk
```

### 扩展性增强

未来可轻松添加新渠道：
```kotlin
// 只需添加新的 flavor 定义
create("tencent") {
    dimension = "channel"
    buildConfigField("String", "CHANNEL", "\"Tencent\"")
}
```

---

## ⚠️ 注意事项

### 1. Flutter 侧配置

如果使用 Product Flavors，需要在 `flutter run` 或 `flutter build` 时指定 flavor：

```bash
# 开发模式
flutter run --flavor googleplay

# 发布模式
flutter build apk --release --flavor huawei
```

### 2. BuildConfig 变量冲突

确保 `BuildConfig.CHANNEL` 与现有的 `BuildConfig` 字段不冲突：
- 已有字段：`UMENG_APP_KEY`, `UMENG_CHANNEL`, `ANALYTICS_ENABLED`
- 新增字段：`CHANNEL`（建议命名为 `CHANNEL_NAME` 避免混淆）

### 3. 向后兼容

实现时需要保留旧配置的兼容性：
```kotlin
// 优先使用 BuildConfig，回退到配置文件
val channel = BuildConfig.CHANNEL.takeIf { it.isNotEmpty() }
    ?: getChannelFromConfig()
```

### 4. iOS 支持

当前 iOS 平台暂不支持，未来实现时需要在 `ios/Runner.xcodeproj` 中配置 Scheme：
- Xcode → Product → Scheme → Manage Schemes
- 为每个渠道创建独立的 Scheme

---

## 🔗 参考资料

- [Android Gradle Plugin - Configure Product Flavors](https://developer.android.com/studio/build/build-variants#product-flavors)
- [Flutter - Build and release an Android app](https://docs.flutter.dev/deployment/android#build-an-app-bundle)
- [Gradle Kotlin DSL Primer](https://docs.gradle.org/current/userguide/kotlin_dsl.html)

---

## 📝 实现检查清单

完成后请确认以下内容：

- [ ] 所有 flavor 均可成功编译
- [ ] BuildConfig.CHANNEL 在原生代码中可正确读取
- [ ] 不同 flavor 的 APK 文件名可区分
- [ ] 友盟后台可按渠道区分数据
- [ ] 配置文件已清理，无冗余字段
- [ ] 文档已更新，说明新的编译流程
- [ ] 自动化脚本可正常运行
- [ ] CI/CD 流水线已适配新方案

---

## 🚀 后续优化方向

1. **多维度 Flavor**：添加 `buildType` 维度（debug/release/beta）
2. **动态渠道包**：使用 [Walle](https://github.com/Meituan-Dianping/walle) 实现秒级多渠道打包
3. **APK 体积优化**：不同渠道移除未使用的资源
4. **自动化测试**：为每个渠道添加自动化测试流程

---

**文档版本**：v1.0
**创建日期**：2026-01-28
**维护者**：EasyFile Team
**优先级**：中（在埋点功能稳定后实施）
