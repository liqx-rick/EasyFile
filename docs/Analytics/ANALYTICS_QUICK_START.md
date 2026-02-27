# Analytics 统一配置快速指南

本指南说明如何通过修改 **1 个配置文件 + 1 个密钥文件** 完成 EasyFile 埋点的部署和切换。

---

## 🚀 快速开始（1 步搞定）

> ⚠️ **重要说明**：当前代码实现仅从 `config/analytics_config.yaml` 读取配置。
> `.env.analytics` 文件是预留的构建时注入机制（用于 Gradle/BuildConfig），但 Dart 代码不读取该文件。

### 步骤 1：配置 AppKey

编辑 `config/analytics_config.yaml`，直接填入从友盟后台获取的 AppKey：

```yaml
providers:
  china:
    umeng:
      # 直接填入实际 AppKey（或使用环境变量注入）
      app_key: "你的友盟 Android 密钥"
      channel: "GooglePlay"
```

> 💡 **获取密钥**：访问 [友盟+官网](https://www.umeng.com/) 注册并创建应用

编辑 `config/analytics_config.yaml`：

```yaml
# 目标市场选择（国内用友盟，海外用 Firebase）
market: china    # china 或 international

# 渠道名称（根据发布渠道修改）
providers:
  china:
    umeng:
      channel: "GooglePlay"  # 改为你的实际渠道
```

**完成！** 运行 `flutter clean && flutter run` 即可生效。

---

## 📝 配置文件说明

### 核心配置文件（2 个）

```
config/
├── analytics_config.yaml        # 公共配置（提交到 Git）
└── .env.analytics              # 密钥配置（不提交 Git，保密）
```

### analytics_config.yaml 关键字段

```yaml
# 全局开关（false 完全禁用埋点）
enabled: true

# 市场选择（决定使用哪个 provider）
market: china           # china(友盟) / international(Firebase)

# 友盟 SDK 版本号（Android）
providers:
  china:
    umeng:
      sdk_versions:
        common: "9.6.8"      # 基础组件
        asms: "1.8.3"        # 反作弊组件
        abtest: "1.0.3"      # ABTest 组件
      channel: "GooglePlay"      # GooglePlay / Huawei / Xiaomi 等
```

### .env.analytics 密钥配置

```env
# Android 友盟密钥（32位字符串）
UMENG_ANDROID_KEY=xxxxx

# iOS 友盟密钥（未来使用）
UMENG_IOS_KEY=xxxxx
```

---

## 🔄 常见操作场景

### 场景 1：切换国内/海外市场

**只需修改 1 行配置：**

```yaml
# config/analytics_config.yaml
market: international  # 改为 international 即可切换到 Firebase
```

### 场景 2：切换发布渠道

**只需修改 1 行配置：**

```yaml
# config/analytics_config.yaml
providers:
  china:
    umeng:
      channel: "Huawei"  # 改为目标渠道名
```

### 场景 3：完全禁用埋点

**只需修改 1 行配置：**

```yaml
# config/analytics_config.yaml
enabled: false  # 改为 false 完全禁用
```

### 场景 4：更换友盟 AppKey

**只需修改密钥文件：**

```env
# config/.env.analytics
UMENG_ANDROID_KEY=新的AppKey
```

---

## 🛡️ 安全性说明

### 什么文件会提交到 Git？

✅ **会提交**（公共配置）：
- `config/analytics_config.yaml`
- `config/.env.analytics.example`（模板）

❌ **不会提交**（密钥文件）：
- `config/.env.analytics`（已在 .gitignore 中）

### 团队协作

每个开发者需要：
1. 从项目拉取最新代码
2. 自己创建 `config/.env.analytics` 文件
3. 填入开发环境的测试 AppKey

---

## 🔧 高级配置

### 隐私合规配置

```yaml
privacy:
  require_user_consent: true    # 需要用户同意
  gdpr_mode: true               # GDPR 模式
  auto_collect_device_id: false # 禁用自动采集设备 ID
```

### 功能开关

```yaml
features:
  crash_report: false         # 崩溃报告
  performance_monitor: false  # 性能监控
  ab_testing: false          # A/B 测试
```

### 调试模式

```yaml
debug:
  verbose_logging: true  # 详细日志
  dry_run: false        # 测试模式（不真实上报）
```

---

## 📊 配置生效验证

### Android 验证

运行应用后查看 Logcat：

```
I/UmengAnalyticsChannel: Umeng initialized successfully with AppKey: 12345678*** Channel: GooglePlay
```

### Flutter 验证

查看应用启动日志：

```
I/flutter: Analytics selecting provider: AnalyticsProvider.umeng
I/flutter: ✓ Analytics initialized
```

---

## ❌ 故障排查

### 问题 1：提示 "AppKey not configured"

**原因**：未创建 `.env.analytics` 或密钥为空

**解决**：
```bash
cd config
cp .env.analytics.example .env.analytics
vim .env.analytics  # 填入实际密钥
```

### 问题 2：编译失败 "Unresolved reference: BuildConfig"

**原因**：Gradle 配置未生效

**解决**：
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter run
```

### 问题 3：配置修改后不生效

**原因**：需要重新编译

**解决**：
```bash
flutter clean && flutter run
```

---

## 📚 完整配置示例

### 国内发布（Google Play）

```yaml
# config/analytics_config.yaml
enabled: true
market: china
providers:
  china:
    umeng:
      channel: "GooglePlay"
```

```env
# config/.env.analytics
UMENG_ANDROID_KEY=实际的友盟AppKey
```

### 国内发布（华为应用市场）

```yaml
# config/analytics_config.yaml
enabled: true
market: china
providers:
  china:
    umeng:
      channel: "Huawei"
```

### 海外发布（Firebase）

```yaml
# config/analytics_config.yaml
enabled: true
market: international
```

```env
# config/.env.analytics
FIREBASE_ANDROID_APP_ID=Firebase应用ID
```

---

## 🎯 架构优势

✅ **单一配置源**：所有配置集中在 `config/` 目录
✅ **密钥安全**：敏感信息不入库
✅ **快速切换**：改 1 个字段即可切换市场/渠道
✅ **团队协作**：每人维护自己的密钥文件
✅ **CI/CD 友好**：支持环境变量注入

---

## 相关文档

- [详细集成指南](./UMENG_ANALYTICS_INTEGRATION_GUIDE.md)
- [业务层调用示例](../lib/analytics/analytics_example.dart)
- [友盟官方文档](https://developer.umeng.com/)
