# EasyFile - Flutter 文件管理器

一个功能完整、界面美观的 Flutter 文件管理应用，支持文件浏览、搜索、预览和完整的文件操作功能。

## 📱 应用概述

EasyFile 是一个现代化的文件管理器，采用 Material Design 设计语言，提供直观易用的文件管理体验。应用支持 Android 平台，具有完整的文件系统操作能力。

### 🎯 核心特性

- **📁 文件浏览** - 支持多种文件类型的浏览和导航
- **🔍 智能搜索** - 快速搜索文件和文件夹，支持递归搜索
- **👁️ 文件预览** - 图片和文本文件的实时预览
- **📋 文件操作** - 复制、移动、重命名、删除等完整操作
- **🎨 美观UI** - Material Design 风格，深色/浅色主题支持
- **📊 详细信息** - 文件大小、修改时间等详细信息显示
- **🔲 灵活视图** - 统一的列表/网格视图切换，支持分组和选择模式

## 🚀 功能特性

### 文件浏览
- ✅ 支持所有文件类型和文件夹
- ✅ 按类型排序（文件夹优先，按名称排序）
- ✅ 文件类型图标显示（图片、文档、视频、音频等）
- ✅ 路径导航和返回功能
- ✅ 多平台路径支持（Android、iOS、Windows、macOS、Linux）
- ✅ 列表/网格视图无缝切换
- ✅ 支持分组显示（按日期、类型等）
- ✅ 统一的选择模式和批量操作

### 智能搜索
- ✅ 实时搜索文件名和扩展名
- ✅ 递归搜索子目录（可配置深度）
- ✅ 搜索结果显示完整路径
- ✅ 搜索模式下的特殊导航
- ✅ 快速清除搜索功能

### 文件预览
- ✅ **图片预览**：支持 JPG、PNG、GIF、BMP、WebP
  - 缩放功能（0.5x - 4.0x）
  - 拖拽查看
  - 全屏显示
- ✅ **文本预览**：支持 TXT、JSON、XML、HTML、Dart、Python 等
  - 语法高亮显示
  - 可选择和复制文本
  - 滚动查看长文本

### 文件操作
- ✅ **复制**：支持文件和文件夹的递归复制
- ✅ **移动**：智能移动，失败时自动回退到复制+删除
- ✅ **重命名**：带验证的智能重命名
- ✅ **删除**：安全删除，支持递归删除文件夹
- ✅ 操作进度显示
- ✅ 详细的错误处理和用户反馈

### 用户界面
- ✅ Material Design 3 风格
- ✅ 响应式布局设计
- ✅ 直观的文件类型图标
- ✅ 长按操作菜单
- ✅ 搜索栏动画效果
- ✅ 状态栏信息显示

## 🔧 技术架构

### 架构模式
- **MVP (Model-View-Presenter)** - 清晰的业务逻辑分离
- **Provider 状态管理** - 响应式UI更新
- **依赖注入 (GetIt)** - 松耦合的组件管理

### 项目结构
```
lib/
├── main.dart                 # 应用入口
├── app.dart                  # 应用配置
├── core/                     # 核心功能
│   ├── logger.dart          # 日志系统
│   └── di/                  # 依赖注入
│       └── locator.dart
├── data/                    # 数据层
│   ├── models/              # 数据模型
│   │   └── file_item.dart
│   ├── repositories/        # 仓库接口
│   │   └── file_repository.dart
│   └── sources/             # 数据源实现
│       ├── local_file_source.dart
│       └── path_provider.dart
├── presenter/               # 业务逻辑层
│   └── file_presenter.dart
├── viewmodel/              # 视图模型
│   └── file_viewmodel.dart
└── ui/                     # 用户界面
    ├── pages/              # 页面
    │   ├── file_browser_page.dart
    │   ├── category_file_page.dart
    │   ├── file_browser_root_page.dart
    │   └── file_preview_page.dart
    └── widgets/            # 组件
        ├── file_collection_view.dart   # 统一文件列表/网格组件
        ├── file_item_tile.dart
        ├── file_operation_sheet.dart
        ├── rename_dialog.dart
        ├── folder_picker_dialog.dart
        └── progress_dialog.dart
```

### 核心技术栈
- **Flutter 3.0+** - 跨平台UI框架
- **Dart 3.0+** - 编程语言
- **Provider** - 状态管理
- **GetIt** - 依赖注入
- **path_provider** - 路径访问
- **permission_handler** - 权限管理

## 📋 依赖项

### 核心依赖
```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.0
  get_it: ^7.6.0
  path_provider: ^2.1.0
  permission_handler: ^11.0.0
```

### 开发依赖
```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

## 🛠️ 安装和运行

### 环境要求
- Flutter SDK 3.0.0 或更高版本
- Dart SDK 3.0.0 或更高版本
- Android SDK (对于 Android 部署)
- Android Studio 或 VS Code

### 安装步骤

1. **克隆项目**
   ```bash
   git clone <repository-url>
   cd easyfile
   ```

2. **安装依赖**
   ```bash
   flutter pub get
   ```

3. **配置权限** (Android)
   确保 `android/app/src/main/AndroidManifest.xml` 包含必要权限

4. **运行应用**
   ```bash
   flutter run
   ```

### 构建发布版本
```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release
```

## 📱 使用指南

### 基本操作

1. **文件浏览**
   - 点击文件夹进入子目录
   - 点击返回按钮回到上级目录
   - 状态栏显示当前路径和文件统计

2. **文件搜索**
   - 点击搜索图标打开搜索栏
   - 输入文件名或扩展名进行搜索
   - 点击清除按钮或关闭图标退出搜索

3. **文件预览**
   - 点击图片文件查看大图
   - 双指缩放图片
   - 点击文本文件查看内容
   - 长按选择和复制文本

4. **文件操作**
   - 长按文件或文件夹打开操作菜单
   - 选择复制、移动、重命名或删除
   - 按照提示完成操作

### 高级功能

1. **批量操作**
   - 搜索特定类型文件
   - 选择多个搜索结果进行操作

2. **路径管理**
   - 点击文件夹图标快速切换常用目录
   - 自动记忆常用路径

## 🔐 权限说明

### Android 权限
- **READ_EXTERNAL_STORAGE** - 读取外部存储文件
- **WRITE_EXTERNAL_STORAGE** - 写入外部存储文件
- **MANAGE_EXTERNAL_STORAGE** - 管理外部存储（Android 11+）

权限将在首次使用时自动请求，用户可以在系统设置中管理这些权限。

## 🐛 故障排除

### 常见问题

1. **权限被拒绝**
   - 检查应用权限设置
   - 手动在系统设置中授予存储权限

2. **文件无法访问**
   - 确认文件路径存在
   - 检查文件是否被其他应用占用

3. **预览失败**
   - 确认文件格式受支持
   - 检查文件是否损坏

### 调试信息
应用包含详细的日志系统，可以通过以下方式查看：
```bash
flutter logs
adb logcat | grep flutter
```

## 🚧 路线图

### 计划功能
- [ ] 云存储集成（Google Drive、OneDrive）
- [ ] 文件压缩和解压
- [ ] 批量文件操作
- [ ] 文件分享功能
- [ ] 深色主题优化
- [ ] 平板电脑布局适配

### 技术改进
- [ ] 性能优化
- [ ] 内存使用优化
- [ ] 更多文件格式支持
- [ ] 国际化支持

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

## 🤝 贡献

欢迎贡献代码！请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 了解详细的贡献指南。

### 开发流程
1. Fork 项目
2. 创建功能分支
3. 提交更改
4. 创建 Pull Request

## 📞 支持

如有问题或建议，请通过以下方式联系：
- 提交 Issue
- 发送邮件
- 加入讨论群

## 🏆 致谢

感谢所有为这个项目做出贡献的开发者和测试用户！

---

**EasyFile** - 让文件管理变得简单高效！
