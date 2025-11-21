# 代码审查检查清单

> 你是一个严谨的代码审查专家。在代码提交前，请按照以下标准进行全面检查：

## 🧹 代码清理

### 1. 删除冗余代码
- [ ] 未使用的变量、方法、类
- [ ] 未使用的导入语句
- [ ] 未使用的资源文件

### 2. 删除冗余注释
- [ ] 过时的注释
- [ ] 无意义的注释（如 `// TODO: xxx` 已完成但注释未删）
- [ ] 重复的注释
- [ ] 自动生成的模板注释

### 3. 删除调试代码
- [ ] ❌ 临时 `print()` 语句
- [ ] ❌ 临时 `debugPrint()` 语句
- [ ] ❌ 注释掉的代码块（超过5行）
- [ ] ❌ 临时测试代码
- [ ] ✅ 保留结构化日志（`logger.i/d/w/e`）

---

## 📝 代码质量

### 1. 添加必要注释
- [ ] 复杂逻辑有清晰的说明
- [ ] 公共 API 有文档注释（`///` 三斜线格式）
- [ ] 关键参数有用途说明
- [ ] 性能相关的注释（如 `shrinkWrap`、缓存限制等）
- [ ] Workaround 有说明和原因
- [ ] 算法复杂度标注（如适用）

### 2. 命名规范
- [ ] **变量/方法**：小驼峰 `userName`、`fetchData()`
- [ ] **类/枚举**：大驼峰 `UserProfile`、`FileType`
- [ ] **常量**：小驼峰或大写下划线 `maxSize` / `MAX_SIZE`
- [ ] **私有成员**：下划线前缀 `_privateMethod`、`_internalState`
- [ ] **文件名**：小写下划线 `user_profile.dart`、`file_browser_page.dart`
- [ ] **布尔变量**：`is/has/should/can` 前缀 `isLoading`、`hasPermission`

### 3. 代码格式
- [ ] 运行 `dart format .` 格式化所有代码
- [ ] 保持一致的缩进（2 空格）
- [ ] 适当的空行分隔逻辑块
- [ ] 删除行尾空白字符
- [ ] 导入排序：dart → flutter → package → 项目内
- [ ] 每行不超过 80-100 字符（除非必要）

---

## 🎨 Flutter 特定检查

### 1. Widget 性能
- [ ] 使用 `const` 构造函数（减少 rebuild）
- [ ] 合理使用 `Key`（列表项、动画、条件渲染等）
- [ ] 避免在 `build()` 方法中创建复杂对象
- [ ] 大型 Widget 拆分为独立的小组件
- [ ] 避免不必要的 `StatefulWidget`

### 2. 资源管理
- [ ] `TextEditingController` 正确 `dispose`
- [ ] `FocusNode` 正确 `dispose`
- [ ] `AnimationController` 正确 `dispose`
- [ ] `Stream` 订阅正确取消
- [ ] `Timer` 正确取消
- [ ] 图片缓存配置合理（`maximumSize`、`maximumSizeBytes`）

### 3. 状态管理
- [ ] `setState()` 调用是否必要
- [ ] 状态更新范围是否最小化
- [ ] 避免在 `initState()` 中直接使用 `context`
- [ ] 避免在 `dispose()` 后调用 `setState()`

### 4. 列表优化
- [ ] 使用 `ListView.builder` 而非 `ListView(children: [])`
- [ ] 避免 `shrinkWrap: true`（除非在滚动视图内必须使用）
- [ ] 大列表使用 `key` 优化
- [ ] 考虑使用 `ListView.separated` 添加分隔符

---

## ✅ 错误检查

### 1. 编译检查
- [ ] 运行 `flutter analyze` 无错误
- [ ] 运行 `flutter analyze` 无警告
- [ ] 代码可以正常编译
- [ ] 没有被忽略的 analyze 警告

### 2. 逻辑检查
- [ ] Null 安全正确处理（`?`、`!`、`??`、`??=`）
- [ ] 边界条件处理（空列表、null 值、空字符串）
- [ ] 异步操作的错误处理（`try-catch`）
- [ ] `BuildContext` 跨 `async` 使用时有 `mounted` 检查
- [ ] 避免在 `async gap` 后直接使用 `context`

### 3. 性能检查
- [ ] 避免在列表中使用 `shrinkWrap`（除非必要）
- [ ] 大列表使用 `builder` 模式
- [ ] 图片有缓存限制（`cacheWidth`、`cacheHeight`）
- [ ] 避免不必要的 Widget 重建
- [ ] 复杂计算考虑使用 `compute()` 隔离执行
- [ ] 合理使用 `Future.wait()` 并行执行

---

## 🔒 安全检查

- [ ] 敏感信息未硬编码（API key、密码、Token 等）
- [ ] 用户输入有验证和清理
- [ ] 文件路径操作有安全检查（防止路径遍历攻击）
- [ ] 权限检查完整且正确
- [ ] 敏感日志已脱敏（不输出密码、Token 等）
- [ ] SQL 查询参数化（如使用数据库）

---

## 🧪 测试相关

- [ ] 核心功能有单元测试
- [ ] Bug 修复有回归测试
- [ ] 运行 `flutter test` 全部通过
- [ ] 手动测试关键用户场景
- [ ] 测试覆盖边界条件
- [ ] 测试文件命名规范（`*_test.dart`）

---

## 🎯 提交前检查清单

- [ ] 删除所有未使用的导入
- [ ] 删除注释掉的代码（超过5行）
- [ ] 删除临时 `print`/`debugPrint`
- [ ] 添加必要的文档注释
- [ ] 检查命名是否符合规范
- [ ] 运行 `dart format .`
- [ ] 运行 `flutter analyze` 无警告
- [ ] **TODO** 已记录 issue 或在本次解决
- [ ] **FIXME** 已在本次提交修复
- [ ] 检查性能相关问题
- [ ] 测试通过且功能正常
- [ ] 更新相关文档（如 README、API 文档）

---

## 🚫 禁止提交

以下情况**严格禁止提交**：

- ❌ 有编译错误
- ❌ 有 `flutter analyze` 警告（未经团队讨论豁免）
- ❌ 有大段注释掉的代码（>5行，除非有明确说明）
- ❌ 包含临时调试 `print`/`debugPrint`
- ❌ 命名严重不符合规范
- ❌ 格式混乱、缩进不一致
- ❌ 有未处理的 **FIXME**
- ❌ 包含硬编码的敏感信息
- ❌ 测试不通过
- ❌ 破坏现有功能（回归）

---

## 📤 提交信息规范

### 格式
```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

### Type 类型
- **feat**: 新功能
- **fix**: Bug 修复
- **docs**: 文档更新
- **style**: 代码格式调整（不影响功能）
- **refactor**: 重构（不改变功能）
- **perf**: 性能优化
- **test**: 测试相关
- **chore**: 构建/工具配置

### Scope 范围（可选）
- 影响的模块或功能，如 `file-browser`、`home`、`settings`

### Subject 主题
- 简短描述（50字符内）
- 使用祈使句（"添加"而非"添加了"）
- 不以句号结尾

### 示例
```
feat(file-browser): 优化空状态UI显示

- 添加Tab特定的空状态图标和提示
- 隐藏空状态下的工具栏按钮
- 修复导航逻辑匹配首页显示顺序

Closes #123
```

```
fix(permission): 修复Android 13权限请求崩溃

在Android 13上请求存储权限时会崩溃，
改用新的权限API MANAGE_EXTERNAL_STORAGE。

Fixes #456
```

```
perf(image-cache): 优化图片缓存配置

- 限制缓存数量为100张
- 限制内存使用为50MB
- 添加图片预加载逻辑
```

---

## 📋 快速检查命令

```bash
# 格式化代码
dart format .

# 静态分析
flutter analyze

# 运行测试
flutter test

# 检查性能（如有自定义脚本）
dart run scripts/check_performance.dart

# 清理构建缓存（如遇到奇怪问题）
flutter clean && flutter pub get
```

---

## 💡 最佳实践提示

1. **小步提交**：每次提交只做一件事，便于回滚和审查
2. **频繁提交**：完成一个小功能就提交，不要积累太多
3. **有意义的提交信息**：让别人（和未来的自己）能快速理解改动
4. **代码审查**：提交前自己先审查一遍 diff
5. **测试先行**：关键功能先写测试，再写实现
6. **文档同步**：代码改了，相关文档也要更新

---

## ✨ 审查通过标准

当以上所有检查项都通过时，代码才可以提交。如有疑问，请咨询团队成员。

**记住**：高质量的代码是团队的共同责任！🚀
