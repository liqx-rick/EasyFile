# 代码审查清单

> 你是一个严谨的代码审查专家。在代码提交前，请按照以下标准进行全面检查。

## 🧹 代码清理

### 1. 删除冗余代码
- [ ] 未使用的变量
- [ ] 未使用的方法
- [ ] 未使用的类
- [ ] 未使用的导入语句

### 2. 删除冗余注释
- [ ] 过时的注释
- [ ] 无意义的注释
- [ ] 重复的注释
- [ ] 自动生成的默认注释

### 3. 删除调试代码
- [ ] print 语句
- [ ] debugPrint 语句
- [ ] 临时测试代码
- [ ] 注释掉的代码块

---

## 📝 代码质量

### 1. 添加必要注释
- [ ] 复杂逻辑的说明
- [ ] 公共 API 的文档注释
- [ ] 关键参数的用途说明
- [ ] 性能相关的注释（shrinkWrap、缓存限制等）
- [ ] 业务逻辑的解释（为什么这样做）

### 2. 命名规范
- [ ] 变量：小驼峰 `userName`
- [ ] 类：大驼峰 `UserProfile`
- [ ] 常量：大写下划线 `MAX_SIZE`
- [ ] 私有成员：下划线前缀 `_privateMethod`
- [ ] 文件名：小写下划线 `user_profile.dart`
- [ ] 语义化命名（见名知意）

### 3. 代码格式
- [ ] 运行 `dart format .`
- [ ] 保持一致的缩进（2 空格）
- [ ] 适当的空行分隔
- [ ] 删除行尾空白
- [ ] 每行代码长度不超过 80-120 字符

---

## ✅ 错误检查

### 1. 编译错误
- [ ] `flutter analyze` 无错误
- [ ] `dart analyze` 无警告

### 2. 语法错误
- [ ] 代码可以正常编译
- [ ] 所有导入都能正确解析

### 3. 逻辑错误
- [ ] 检查 null 安全
- [ ] 检查边界条件
- [ ] 检查异常处理
- [ ] 检查资源释放

### 4. 性能问题
- [ ] 避免在列表中使用 shrinkWrap
- [ ] 确保图片有缓存限制
- [ ] 避免在 build 方法中创建新对象
- [ ] 使用 const 构造函数

---

## 📱 Flutter 特定检查

### Widget 最佳实践
- [ ] 避免在 build 方法中创建新对象（优先使用 const）
- [ ] 大列表使用 ListView.builder 而非 ListView
- [ ] 图片资源正确声明在 pubspec.yaml
- [ ] 使用正确的 Key（必要时）

### 异步与状态管理
- [ ] 异步操作正确处理（避免内存泄漏）
- [ ] 使用了正确的生命周期方法
- [ ] StatefulWidget 正确 dispose 资源（控制器、监听器等）
- [ ] 避免在 dispose 后调用 setState

### 资源管理
- [ ] TextEditingController 已释放
- [ ] AnimationController 已释放
- [ ] Stream/StreamSubscription 已关闭
- [ ] FocusNode 已释放

---

## 🛠️ 自动化工具

### 静态分析
```bash
# 分析代码
flutter analyze
# 或
dart analyze

# 检查分析配置
cat analysis_options.yaml
```

### 依赖检查
```bash
# 检查依赖更新
flutter pub outdated

# 获取依赖
flutter pub get
```

### 代码格式化
```bash
# 格式化所有代码
dart format .

# 格式化特定文件
dart format lib/
```

### 测试覆盖
```bash
# 运行测试
flutter test

# 生成覆盖率报告
flutter test --coverage
```

---

## 📦 提交准备

### 版本控制
- [ ] commit message 清晰描述变更
- [ ] 遵循约定式提交（Conventional Commits）
- [ ] 是否需要更新 CHANGELOG.md
- [ ] 大版本更新是否更新了版本号（pubspec.yaml）

### 文档更新
- [ ] 是否需要更新 README.md
- [ ] 是否需要更新 API 文档
- [ ] 是否需要更新用户文档
- [ ] 功能变更是否记录在 RELEASE_NOTES.md

### 依赖管理
- [ ] pubspec.yaml 中无未使用的依赖
- [ ] pubspec.lock 已提交
- [ ] 新增依赖已说明用途

---

## 🎯 完整检查清单

在提交前，请确保：

- [ ] 删除所有未使用的导入
- [ ] 删除注释掉的代码
- [ ] 删除 print 和 debugPrint 语句
- [ ] 删除临时测试代码
- [ ] 添加必要的文档注释
- [ ] 检查命名是否符合规范
- [ ] 运行 `dart format .`
- [ ] 运行 `flutter analyze` 确保无警告
- [ ] 运行相关单元测试
- [ ] 检查是否有 TODO 或 FIXME 未处理
- [ ] 检查性能问题（shrinkWrap、缓存等）
- [ ] 检查资源是否正确释放
- [ ] 更新相关文档

---

## 🚫 禁止提交

以下情况**严禁提交**：

- ❌ 包含调试代码（print、debugPrint）
- ❌ 有编译错误或警告
- ❌ 有注释掉的大段代码
- ❌ 命名不符合规范
- ❌ 格式混乱、缩进不一致
- ❌ 存在明显的内存泄漏风险
- ❌ 测试未通过
- ❌ 破坏现有功能

---

## 📋 快速使用指南

### 在对话中使用
你可以直接对我说：

- `review code` - 审查当前文件
- `代码审查` - 全面检查
- `提交前检查` - 完整审查流程
- `检查性能问题` - 仅检查性能相关
- `清理冗余代码` - 仅清理部分

### 审查流程
1. 代码清理（删除冗余）
2. 代码质量（注释、命名、格式）
3. 错误检查（编译、逻辑、性能）
4. Flutter 特定检查
5. 生成问题报告
6. 提供修复建议

---

## 🔍 检查示例

### ✅ 好的代码
```dart
/// 用户配置服务，处理用户偏好设置的读写
class UserPreferenceService {
  static const int MAX_CACHE_SIZE = 100;
  
  final SharedPreferences _prefs;
  
  UserPreferenceService(this._prefs);
  
  /// 获取用户主题模式
  /// 返回 'light', 'dark' 或 'system'
  String getThemeMode() {
    return _prefs.getString('theme_mode') ?? 'system';
  }
  
  @override
  void dispose() {
    // 释放资源
  }
}
```

### ❌ 需要改进的代码
```dart
class service {  // ❌ 类名应大驼峰
  var x;  // ❌ 无意义的变量名
  
  void doSomething() {
    print('debug');  // ❌ 调试代码
    // var oldCode = 1;  // ❌ 注释掉的代码
    
    // TODO: fix this later  // ❌ 未处理的 TODO
  }
}
```

---

## 📚 相关文档

- [CONTRIBUTING.md](CONTRIBUTING.md) - 贡献指南
- [BUG_FIX_WORKFLOW.md](BUG_FIX_WORKFLOW.md) - Bug 修复流程
- [PERFORMANCE_BEST_PRACTICES.md](PERFORMANCE_BEST_PRACTICES.md) - 性能最佳实践

---

**最后更新**：2025-12-15
