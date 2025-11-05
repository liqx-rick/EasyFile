# 贡献指南

欢迎为 EasyFile 项目做出贡献！本文档将指导您如何有效地参与项目开发。

## 📋 目录

- [开发环境设置](#开发环境设置)
- [代码规范](#代码规范)
- [提交规范](#提交规范)
- [Pull Request 流程](#pull-request-流程)
- [问题报告](#问题报告)
- [功能建议](#功能建议)

## 🛠️ 开发环境设置

### 1. 环境要求

- **Flutter SDK**: 3.0.0 或更高版本
- **Dart SDK**: 3.0.0 或更高版本
- **Android Studio**: 最新版本 (推荐)
- **VS Code**: 最新版本 (可选)
- **Git**: 最新版本

### 2. 项目设置

1. **Fork 项目**
   ```bash
   # 在 GitHub 上 Fork 项目，然后克隆您的 Fork
   git clone https://github.com/YOUR_USERNAME/easyfile.git
   cd easyfile
   ```

2. **添加上游仓库**
   ```bash
   git remote add upstream https://github.com/ORIGINAL_OWNER/easyfile.git
   ```

3. **安装依赖**
   ```bash
   flutter pub get
   ```

4. **运行项目**
   ```bash
   flutter run
   ```

### 3. 开发工具配置

#### Android Studio 配置
- 安装 Flutter 和 Dart 插件
- 配置代码格式化：`File > Settings > Editor > Code Style > Dart`
- 启用保存时格式化：`File > Settings > Tools > Actions on Save`

#### VS Code 配置
- 安装 Flutter 和 Dart 扩展
- 配置 `.vscode/settings.json`:
```json
{
  "dart.previewFlutterUiGuides": true,
  "dart.previewFlutterUiGuidesCustomTracking": true,
  "editor.formatOnSave": true,
  "editor.rulers": [80],
  "editor.tabSize": 2
}
```

## 📝 代码规范

### 1. 代码风格

我们遵循 [Dart 官方代码风格指南](https://dart.dev/guides/language/effective-dart/style)。

#### 关键规则：

1. **命名规范**
   ```dart
   // 类名使用 PascalCase
   class FileManager { }
   
   // 方法和变量使用 camelCase
   void loadFiles() { }
   String currentPath = '';
   
   // 常量使用 lowerCamelCase
   const double maxFileSize = 1024;
   
   // 私有成员使用下划线前缀
   String _internalData = '';
   ```

2. **文件结构**
   ```dart
   // 1. 导入语句（按字母顺序）
   import 'dart:io';
   import 'package:flutter/material.dart';
   import 'package:provider/provider.dart';
   
   // 2. 相对导入
   import '../models/file_item.dart';
   import '../utils/path_utils.dart';
   
   // 3. 类定义
   class FileBrowserPage extends StatefulWidget {
     // 构造函数
     // 字段
     // 方法
   }
   ```

3. **注释规范**
   ```dart
   /// 文件操作的核心接口
   /// 
   /// 提供文件的基本 CRUD 操作，包括：
   /// - 文件列表获取
   /// - 文件搜索
   /// - 文件复制、移动、删除
   abstract class FileRepository {
     /// 获取指定目录下的文件列表
     /// 
     /// [path] 目录路径
     /// 返回该目录下的所有文件和文件夹
     Future<List<FileItem>> getFiles(String path);
   }
   ```

### 2. 架构规范

#### MVP 架构
- **Model**: 数据模型和业务逻辑
- **View**: UI 组件和用户交互
- **Presenter**: 连接 Model 和 View

#### 目录结构
```
lib/
├── core/           # 核心功能（日志、依赖注入等）
├── data/           # 数据层
│   ├── models/     # 数据模型
│   ├── repositories/ # 仓库接口
│   └── sources/    # 数据源实现
├── presenter/      # 业务逻辑层
├── viewmodel/      # 视图模型
└── ui/             # 用户界面
    ├── pages/      # 页面
    └── widgets/    # 组件
```

### 3. 错误处理

```dart
// 使用 try-catch 处理异常
Future<void> loadFiles() async {
  try {
    setLoading(true);
    final files = await _repository.getFiles(_currentPath);
    setFiles(files);
    Logger.info('Files loaded successfully: ${files.length}');
  } catch (e) {
    Logger.error('Failed to load files: $e');
    setError('加载文件失败: $e');
  } finally {
    setLoading(false);
  }
}
```

## 📊 提交规范

我们使用 [Conventional Commits](https://www.conventionalcommits.org/) 规范。

### 提交格式

```
<类型>[可选范围]: <描述>

[可选正文]

[可选脚注]
```

### 提交类型

- `feat`: 新功能
- `fix`: 修复 bug
- `docs`: 文档更新
- `style`: 代码格式化（不影响功能）
- `refactor`: 代码重构
- `test`: 添加或修改测试
- `chore`: 构建过程或工具变动

### 示例

```bash
# 新功能
git commit -m "feat(search): add recursive file search functionality"

# 修复 bug
git commit -m "fix(ui): resolve bottom overflow in file operation sheet"

# 文档更新
git commit -m "docs: update API documentation for FileRepository"

# 代码重构
git commit -m "refactor(presenter): simplify file operation error handling"
```

## 🔄 Pull Request 流程

### 1. 创建功能分支

```bash
# 确保主分支是最新的
git checkout main
git pull upstream main

# 创建新的功能分支
git checkout -b feature/your-feature-name
```

### 2. 开发和测试

1. **编写代码**
   - 遵循代码规范
   - 添加必要的注释
   - 确保代码通过所有测试

2. **运行测试**
   ```bash
   # 运行所有测试
   flutter test
   
   # 运行特定测试
   flutter test test/file_repository_test.dart
   ```

3. **代码格式化**
   ```bash
   # 格式化代码
   dart format lib/ test/
   
   # 分析代码
   flutter analyze
   ```

### 3. 提交更改

```bash
# 添加更改
git add .

# 提交更改
git commit -m "feat: add new file operation feature"

# 推送到您的 Fork
git push origin feature/your-feature-name
```

### 4. 创建 Pull Request

1. 在 GitHub 上创建 Pull Request
2. 填写 PR 模板
3. 等待代码审查
4. 根据反馈修改代码

### PR 模板

```markdown
## 变更描述
简要描述此 PR 的变更内容

## 变更类型
- [ ] 新功能
- [ ] Bug 修复
- [ ] 文档更新
- [ ] 代码重构
- [ ] 性能优化
- [ ] 其他

## 测试
- [ ] 通过了所有现有测试
- [ ] 添加了新的测试
- [ ] 手动测试通过

## 截图（如果适用）
添加相关截图

## 检查清单
- [ ] 代码遵循项目规范
- [ ] 自我审查了代码
- [ ] 添加了必要的注释
- [ ] 更新了相关文档
```

## 🐛 问题报告

### 报告 Bug

使用 GitHub Issues 报告 bug，请包含以下信息：

1. **Bug 描述**: 清晰简洁的描述
2. **重现步骤**: 详细的重现步骤
3. **预期行为**: 您期望发生什么
4. **实际行为**: 实际发生了什么
5. **环境信息**:
   - Flutter 版本
   - Dart 版本
   - 设备信息
   - 操作系统版本

### Bug 报告模板

```markdown
**Bug 描述**
简要描述 bug

**重现步骤**
1. 打开应用
2. 点击 '...'
3. 滚动到 '...'
4. 看到错误

**预期行为**
应该发生什么的清晰简洁描述

**截图**
如果适用，添加截图来帮助解释问题

**环境信息**
- Flutter 版本: [例如 3.0.0]
- Dart 版本: [例如 3.0.0]
- 设备: [例如 Samsung Galaxy S21]
- 操作系统: [例如 Android 12]

**附加信息**
添加有关问题的任何其他信息
```

## 💡 功能建议

### 提出新功能

1. 首先检查是否已有类似的功能请求
2. 创建新的 Issue 并使用功能请求模板
3. 详细描述功能和用例
4. 等待社区讨论和维护者反馈

### 功能请求模板

```markdown
**功能描述**
您希望添加什么功能？

**问题描述**
这个功能解决什么问题？

**解决方案描述**
您希望如何实现这个功能？

**备选方案**
您考虑过其他解决方案吗？

**附加信息**
添加任何其他相关信息或截图
```

## 🎯 开发最佳实践

### 1. 测试驱动开发 (TDD)

```dart
// 先写测试
test('should copy file successfully', () async {
  // Arrange
  final source = '/path/to/source.txt';
  final dest = '/path/to/destination.txt';
  
  // Act
  final result = await repository.copyFile(source, dest);
  
  // Assert
  expect(result, isTrue);
});

// 然后实现功能
Future<bool> copyFile(String source, String dest) async {
  // 实现逻辑
}
```

### 2. 日志记录

```dart
// 使用统一的日志系统
Logger.info('Starting file operation', 'FileRepository');
Logger.debug('Processing file: $fileName', 'FileRepository');
Logger.error('Operation failed: $error', 'FileRepository');
```

### 3. 性能优化

```dart
// 使用 const 构造函数
const FileItemTile({
  Key? key,
  required this.file,
}) : super(key: key);

// 避免不必要的重建
class FileList extends StatelessWidget {
  const FileList({Key? key, required this.files}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) => FileItemTile(file: files[index]),
    );
  }
}
```

### 4. 内存管理

```dart
// 及时释放资源
@override
void dispose() {
  _controller.dispose();
  _subscription?.cancel();
  super.dispose();
}

// 使用 StreamSubscription 管理流
StreamSubscription? _subscription;

void _listenToChanges() {
  _subscription = stream.listen(
    (data) => handleData(data),
    onError: (error) => handleError(error),
  );
}
```

## 🤝 社区指南

### 行为准则

1. **尊重他人**: 保持友善和专业
2. **建设性反馈**: 提供有用的建议和批评
3. **开放心态**: 接受不同观点和建议
4. **学习态度**: 帮助他人学习和成长

### 沟通渠道

- **GitHub Issues**: 报告 bug 和功能请求
- **GitHub Discussions**: 技术讨论和问答
- **Pull Requests**: 代码审查和讨论

## 📚 学习资源

- [Flutter 官方文档](https://flutter.dev/docs)
- [Dart 语言指南](https://dart.dev/guides)
- [Material Design 指南](https://material.io/design)
- [Provider 状态管理](https://pub.dev/packages/provider)

## 🙏 致谢

感谢所有为 EasyFile 项目做出贡献的开发者！您的参与让这个项目变得更好。

---

如有任何问题，请随时通过 GitHub Issues 联系我们！