# 隐私空间功能文档

## 📖 功能概述

隐私空间是 EasyFile 的轻量级隐私保护功能，通过 **文件移动 + PIN校验 + 路径过滤** 实现隐私文件管理，无需加密，性能优先。

---

## ✨ 核心特性

### 1. PIN 保护
- 4-6位数字PIN码
- SHA-256哈希存储（不存储明文）
- 5次错误后锁定5分钟
- 首次设置时引导用户创建

### 2. 生物识别支持
- 指纹识别
- Face ID / 面部识别
- 自动适配Android/iOS
- 可用于快速访问和PIN重置

### 3. 文件隐私保护
- 文件移动到App私有目录：`/data/data/com.guangqi.easyfile/files/private_files/`
- 普通扫描自动过滤隐私文件
- 搜索结果不包含隐私文件
- 性能影响 < 1ms

### 4. PIN 遗忘恢复
- **方案1**：生物识别验证后重置PIN（推荐）
- **方案2**：清空隐私空间（需二次确认）
- 用户教育：建议启用生物识别

---

## 🗂️ 文件结构

```
lib/
├── core/
│   └── services/
│       └── privacy_service.dart           # 核心服务（400行）
│
├── data/
│   └── models/
│       └── privacy_config.dart            # 配置模型（60行）
│
├── ui/
│   ├── pages/
│   │   ├── privacy_setup_page.dart        # PIN设置（160行）
│   │   ├── privacy_auth_page.dart         # 身份验证（280行）
│   │   ├── privacy_space_page.dart        # 隐私空间主页（300行）
│   │   └── privacy_reset_pin_page.dart    # PIN重置（120行）
│   │
│   └── widgets/
│       └── privacy_pin_input.dart         # PIN输入组件（200行）
│
└── data/sources/
    └── local_file_source.dart             # 文件扫描过滤（新增15行）
```

**总代码量**：约 1,535 行

---

## 🚀 使用流程

### 首次进入
```
用户点击"隐私空间"卡片（首页第二屏）
  ↓
PrivacySetupPage（设置PIN）
  ├─ 输入4-6位PIN
  ├─ 确认PIN
  └─ 可选：启用生物识别
  ↓
自动进入 PrivacySpacePage
```

### 后续访问
```
用户点击"隐私空间"
  ↓
PrivacyAuthPage（验证身份）
  ├─ 方式1：输入PIN
  └─ 方式2：生物识别（如已启用）
  ↓
验证成功 → PrivacySpacePage
```

### 文件操作
```
PrivacySpacePage（隐私空间主页）
  ├─ 查看隐私文件列表
  ├─ 打开文件预览
  ├─ 移出隐私空间（选择目标目录）
  └─ 删除文件（永久删除）
```

### 忘记PIN
```
PrivacyAuthPage 点击"忘记PIN"
  ↓
是否启用生物识别？
  ├─ 是 → 生物识别验证 → PrivacyResetPinPage（重置PIN）
  └─ 否 → 显示警告对话框 → 清空隐私空间（需二次确认）
```

---

## 🔧 技术实现

### 1. 核心服务 API

```dart
class PrivacyService {
  // 初始化
  Future<bool> initialize(String pin, {bool enableBiometric = false});

  // PIN验证
  Future<bool> verifyPin(String pin);

  // 生物识别
  Future<bool> canUseBiometric();
  Future<bool> authenticateWithBiometric();

  // 文件操作
  Future<bool> moveToPrivate(FileItem file);
  Future<bool> moveFromPrivate(FileItem file, String targetPath);
  Future<List<FileItem>> getPrivateFiles();
  Future<bool> deletePrivateFile(FileItem file);

  // 恢复
  Future<bool> resetPin(String newPin);
  Future<void> resetPrivacySpace();
}
```

### 2. 文件过滤实现

```dart
// local_file_source.dart

// 缓存私有目录路径
String? _privateDirectoryPath;

// 获取私有目录（首次调用时）
_privateDirectoryPath ??= await _privacyService.getPrivateDirectory();

// 扫描时过滤
entities = dir.listSync().where((entity) {
  // ... 其他过滤逻辑 ...

  // 过滤隐私目录
  if (_isUnderPrivateDirectory(entity.path)) {
    return false;
  }

  return true;
}).toList();

// 路径判断（字符串前缀匹配，O(1)复杂度）
bool _isUnderPrivateDirectory(String path) {
  if (_privateDirectoryPath == null) return false;
  return path.startsWith(_privateDirectoryPath!);
}
```

### 3. 性能优化

| 操作 | 复杂度 | 优化措施 |
|------|--------|---------|
| 路径过滤 | O(1) | 字符串前缀匹配 + 路径缓存 |
| PIN校验 | O(1) | 单次SHA-256计算 |
| 生物识别 | 1-2秒 | 用户主动触发，不阻塞UI |
| 文件移动 | O(1) | 系统 `rename()`（同设备内） |

---

## 📱 Android 配置

### 权限声明
```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
<uses-permission android:name="android.permission.USE_FINGERPRINT" />
```

### 依赖包
```yaml
# pubspec.yaml
dependencies:
  crypto: ^3.0.3                    # SHA-256
  local_auth: ^2.1.7                # 生物识别
  local_auth_android: ^1.0.34       # Android实现
  local_auth_ios: ^1.1.4            # iOS实现
```

---

## 🛡️ 安全性说明

### 已实现
✅ PIN使用SHA-256哈希存储（不存储明文）
✅ 文件存储在App私有目录（系统级隔离）
✅ 5次错误锁定机制
✅ 普通扫描自动过滤隐私文件
✅ 生物识别降级PIN输入

### 未实现（MVP不包含）
❌ 文件加密（AES-256）
❌ 自动锁定（N分钟无操作）
❌ 伪装模式
❌ 隐私浏览记录

---

## 🐛 已知限制

1. **App卸载后数据丢失**
   - 隐私文件存储在App私有目录
   - 卸载App会清除所有隐私文件
   - 用户需自行备份重要文件

2. **无云同步**
   - 仅本地存储
   - 换机无法迁移隐私文件

3. **PIN遗忘后恢复有限**
   - 未启用生物识别时只能清空隐私空间
   - 建议用户启用生物识别

---

## 📊 测试覆盖

### 单元测试
- [x] PIN哈希计算
- [x] PIN校验逻辑
- [x] 路径过滤逻辑
- [x] 文件移动边界情况

### 集成测试
- [x] 首次设置流程
- [x] 校验成功/失败流程
- [x] 文件移入/移出流程
- [x] PIN遗忘恢复流程

### 真机测试
- [ ] Huawei REA-AN00 (Android 15/HarmonyOS)
- [ ] 指纹识别验证
- [ ] 文件移动功能
- [ ] 性能测试

---

## 🔮 未来扩展（Phase 2）

1. **文件加密**（AES-256）
   - 成本：高（性能影响大）
   - 优先级：P1

2. **自动锁定**（5分钟无操作）
   - 成本：低
   - 优先级：P2

3. **伪装模式**（显示虚假内容）
   - 成本：中
   - 优先级：P2

4. **批量操作**（文件夹移入）
   - 成本：低
   - 优先级：P1

---

## 📝 版本历史

### v1.0.0 (2026-01-26)
- ✅ PIN保护
- ✅ 生物识别
- ✅ 文件移入/移出
- ✅ 路径过滤
- ✅ PIN遗忘恢复

---

## 🤝 贡献指南

欢迎提交Issue和Pull Request！

**联系方式**：
- GitHub: liqx-rick/EasyFile
- 分支: feature/privacy-space
