# 单文件操作功能说明书

**文档版本**: 1.0
**生成日期**: 2026-02-11
**分析方法**: Template E - 完整代码流程分析
**适用范围**: EasyFile 应用所有单文件处理场景

---

## 📋 执行摘要

应用中存在**三个**单文件操作入口点，均调用统一的 `SingleFileOperationsService` 服务：

1. **文件列表长按** - 在任何文件列表页面长按文件时显示操作菜单
2. **文件预览页面** - 在预览页面通过顶部工具栏按钮或更多菜单进行操作
3. **编辑模式单选** - 编辑模式下只选中一个文件时，部分批量操作自动变为单文件操作

---

## 🔍 入口点 1: 文件列表长按操作

### 触发方式
在文件列表中**长按**文件或文件夹。

### 实现机制

- **服务**: `lib/ui/services/single_file_operations_service.dart`
- **UI 组件**: `lib/ui/widgets/single_file_operations_sheet.dart`
- **列表视图**: `lib/ui/widgets/file_collection_view.dart`

调用链路：
```
用户长按文件
  ↓
FileCollectionView.onLongPress 回调
  ↓
页面级方法 _showSingleFileOperationsMenu()
  ↓
showModalBottomSheet() 显示 SingleFileOperationsSheet
  ↓
SingleFileOperationsService 处理具体操作
```

### 操作菜单内容

文件夹操作（示例）: 查看详情、重命名、移动、复制、删除

文件操作（示例）: 查看详情、收藏/取消收藏、重命名、移动、复制、移入隐私空间、分享、删除

压缩包专属: 查看内容、解压
可打印文件: 打印（图片/PDF/文本）

---

## 🔍 入口点 2: 文件预览页面操作

### 触发方式
在 `FilePreviewPage` 通过 AppBar 快捷按钮或更多（PopupMenu）菜单触发。

### 实现机制

- **预览页面**: `lib/ui/pages/file_preview_page.dart`
- **服务**: `lib/ui/services/single_file_operations_service.dart`

AppBar 上常见按钮：打印、分享、收藏；更多菜单包含重命名/移动/复制/删除/查看详情等。

操作成功后会标记页面为已修改（`_fileModified = true`），并在返回父页面时触发刷新。

---

## 🔍 入口点 3: 编辑模式下单选操作

### 触发方式
编辑模式（`EditModeMixin`）下只选择一个文件时，`SelectionBottomBar` 将启用单文件相关操作。

### 实现机制

- **底部工具栏**: `lib/ui/widgets/selection_bottom_bar.dart`
- 单选判断条件: `selectedPaths.length == 1`

支持操作：移动、删除、复制、重命名（仅单选启用）、分享、收藏/取消收藏。

编辑模式中通常禁用项的长按（避免与选择冲突）。

---

## 🛠️ 核心服务：SingleFileOperationsService

### 依赖
`SingleFileOperationsService` 依赖 `FileViewModel`、`FilePresenter` 与调用方 `BuildContext`，并接受 `onRefresh`、`onFileDeleted`、`onUIUpdate` 回调以便更新页面或关闭预览。

### 主要功能（摘要）
- 收藏/取消收藏 (`toggleFavorite`)
- 重命名 (`renameFile`)：包含路径安全检查与对话框交互，返回 `bool` 表示成功与否
- 移动 (`moveFile`)：选择目标目录、验证目标安全与循环移动检测
- 复制 (`copyFile`)
- 删除 (`deleteFile`)：增强确认对话框与风险检查，成功后触发 `onFileDeleted`
- 分享 (`shareFile`)
- 打印 (`printFile`)：图片/PDF/文本支持
- 隐私空间移动 (`moveToPrivacySpace`)
- 压缩包查看/解压 (`viewArchiveContents` / `extractArchive`)

### 安全与日志
- 使用 `PathSecurity` 评估路径风险等级，禁止对高风险或系统目录执行危险操作
- 对敏感操作记录日志 `PathSecurity.logOperation(...)`

---

## 🎨 UI 组件：SingleFileOperationsSheet

组件结构：头部（缩略图+文件名+关闭）→ 操作列表（可滚动）→ 底部安全区。
操作项通过 `_buildOperationTile()` 统一渲染；执行操作前弹窗关闭，随后在服务中执行对应行为。

---

## 🔒 重要交互与保护策略

- 编辑模式与长按互斥：在编辑模式下，`FileCollectionView` 禁用长按回调，避免冲突。
- 重命名/删除/移动等操作在执行前均做路径安全检查与用户确认。
- 操作后依赖 `ViewModel` 的更新通知机制自动刷新页面，无需页面层强制刷新（但服务提供 `onRefresh` 回调供页面调用）。

---

## ✅ 操作能力对比（简表）

| 操作 | 文件 | 文件夹 | 长按菜单 | 预览页 | 编辑模式单选 |
|---|---:|---:|:---:|:---:|:---:|
| 查看详情 | ✅ | ✅ | ✅ | ✅ | ❌ |
| 收藏/取消收藏 | ✅ | ❌ | ✅ | ✅ | ✅ |
| 重命名 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 移动 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 复制 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 分享 | ✅ | ❌ | ✅ | ✅ | ✅ |
| 打印 | ✅¹ | ❌ | ✅ | ✅ | ❌ |
| 隐私空间 | ✅ | ❌ | ✅ | ❌ | ❌ |
| 删除 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 压缩包查看/解压 | ✅² | ❌ | ✅ | ❌ | ❌ |

注：¹ 仅图片/PDF/文本； ² 仅压缩包文件

---

## 📖 参考文件
- `lib/ui/services/single_file_operations_service.dart`
- `lib/ui/widgets/single_file_operations_sheet.dart`
- `lib/ui/pages/file_preview_page.dart`
- `lib/ui/widgets/selection_bottom_bar.dart`
- `docs/FILE_PREVIEW_FEATURE_SPEC.md`
- `docs/APP_FILE_SCAN_TEMPLATE_E_ANALYSIS.md`

---

**说明书结束**
