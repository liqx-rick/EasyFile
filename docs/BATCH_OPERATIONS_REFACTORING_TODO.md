# 批量操作架构重构计划（TODO）

## 📋 背景

当前项目中存在两套批量操作实现路径，导致代码重复和维护困难：
- **BatchOperationsService**（UI服务层）：自己实现文件删除/移动逻辑
- **FilePresenter**（业务逻辑层）：也实现了文件删除/移动逻辑

虽然两套实现都已修复ViewModel同步问题，但存在约200行重复代码。

---

## 🎯 重构目标

### 主要目标
- ✅ 消除重复代码（~200行）
- ✅ 统一业务逻辑到Presenter层
- ✅ 保持分层架构清晰
- ✅ 不影响现有功能和调用方

### 非目标
- ❌ 不改变对外接口
- ❌ 不破坏现有页面的调用
- ❌ 不影响UI交互逻辑

---

## 🏗️ 重构方案：方案A

### 核心思想
让 **BatchOperationsService** 调用 **FilePresenter** 的批量方法，消除重复逻辑。

### 分层职责

```
┌──────────────────────────────────────┐
│  BatchOperationsService (UI层)      │
│  - 确认对话框                        │
│  - 进度显示                          │
│  - 安全检查                          │
│  - 回收站选择                        │
│  - 结果展示                          │
└─────────────┬────────────────────────┘
              │ 调用
              ↓
┌──────────────────────────────────────┐
│  FilePresenter (业务层)              │
│  - 批量文件操作                      │
│  - ViewModel同步                     │
│  - 收藏管理                          │
│  - 返回操作结果                      │
└─────────────┬────────────────────────┘
              │ 调用
              ↓
┌──────────────────────────────────────┐
│  FileRepository (数据层)             │
│  - 文件系统操作                      │
│  - 实际删除/移动文件                 │
└──────────────────────────────────────┘
```

---

## 📝 实施步骤

### Step 1: 重构 batchDelete 方法

**当前实现**（BatchOperationsService）：
```dart
Future<void> _permanentDelete(BuildContext context, List<FileItem> files) async {
  for (final file in files) {
    if (file.isDirectory) {
      await Directory(file.path).delete(recursive: true);
    } else {
      await File(file.path).delete();
    }
    // 从ViewModel移除
    viewModel.removeFileFromList(file.path);
  }
}
```

**重构后**：
```dart
Future<void> _permanentDelete(BuildContext context, List<FileItem> files) async {
  // 提取文件路径列表
  final filePaths = files.map((f) => f.path).toList();
  
  // 调用Presenter执行批量删除（内部已处理ViewModel同步）
  final results = await presenter.batchDeleteFiles(filePaths);
  
  // 统计结果
  final successCount = results.values.where((v) => v).length;
  final failCount = results.length - successCount;
  
  // UI反馈保留在Service层
  // ...
}
```

**改动位置**：
- 文件：`lib/ui/services/batch_operations_service.dart`
- 行数：第296-370行（`_permanentDelete` 方法）
- 预计改动：删除约50行重复逻辑，新增5行调用代码

---

### Step 2: 重构 batchMove 方法

**当前实现**（BatchOperationsService）：
```dart
Future<void> batchMove(...) async {
  for (final path in selectedItems) {
    if (entity == FileSystemEntityType.directory) {
      await Directory(path).rename(targetPath);
    } else if (entity == FileSystemEntityType.file) {
      await File(path).rename(targetPath);
    }
    viewModel.updateFileInList(oldPath, movedFile);
  }
}
```

**重构后**：
```dart
Future<void> batchMove(...) async {
  // 安全检查、目标路径选择等UI逻辑保留
  // ...
  
  // 提取文件路径列表
  final filePaths = selectedItems.toList();
  
  // 调用Presenter执行批量移动（内部已处理ViewModel同步）
  final results = await presenter.batchMoveFiles(filePaths, destinationPath);
  
  // 统计结果并显示
  final successCount = results.values.where((v) => v).length;
  // ...
}
```

**改动位置**：
- 文件：`lib/ui/services/batch_operations_service.dart`
- 行数：第640-710行（批量移动循环部分）
- 预计改动：删除约60行重复逻辑，新增5行调用代码

---

### Step 3: 处理特殊逻辑

#### 3.1 回收站功能
- **保留位置**：BatchOperationsService
- **处理方式**：
  ```dart
  if (trashSettings.isEnabled) {
    // Service层决定是否使用回收站
    await _moveToTrash(files);
  } else {
    // 调用Presenter永久删除
    await presenter.batchDeleteFiles(filePaths);
  }
  ```

#### 3.2 安全检查
- **保留位置**：BatchOperationsService
- **处理方式**：在调用Presenter前进行验证，阻止危险操作

#### 3.3 进度显示
- **当前问题**：Service层自己循环删除，可实时更新进度
- **方案1**（推荐）：保持当前批量操作不显示详细进度（用户体验更流畅）
- **方案2**（可选）：让Presenter支持进度回调
  ```dart
  await presenter.batchDeleteFiles(
    filePaths,
    onProgress: (current, total) {
      // 更新进度对话框
    },
  );
  ```

---

### Step 4: 测试验证

#### 4.1 功能测试清单
- [ ] 文件浏览页批量删除
- [ ] 文件浏览页批量移动
- [ ] 分类文件页批量删除
- [ ] 分类文件页批量移动
- [ ] 存储分析页批量删除
- [ ] 存储分析页批量移动
- [ ] 大文件页批量删除
- [ ] 大文件页批量移动
- [ ] 新文件Tab批量删除后列表更新
- [ ] 新文件Tab批量移动后路径更新
- [ ] 回收站功能正常工作
- [ ] 安全检查正常阻止危险操作

#### 4.2 边界测试
- [ ] 删除不存在的文件
- [ ] 移动到不存在的目录
- [ ] 移动文件夹到自己的子目录
- [ ] 权限不足的文件操作
- [ ] 批量操作中部分成功部分失败

---

## 📊 改动影响评估

### 需要改动的文件
| 文件 | 改动类型 | 改动量 | 风险等级 |
|------|----------|--------|----------|
| `batch_operations_service.dart` | 删除重复逻辑，改为调用Presenter | 中等（~200行） | 🟡 中 |
| `file_presenter.dart` | 已完成（添加ViewModel同步） | 已完成 | ✅ 无 |

### 不受影响的文件
- ✅ `file_browser_page.dart` - 接口不变
- ✅ `category_file_page.dart` - 接口不变
- ✅ `storage_page.dart` - 接口不变
- ✅ `large_files_page.dart` - 接口不变
- ✅ 所有其他调用方 - 零影响

### 代码质量提升
- **总代码量**：-209行
- **重复逻辑**：-50%（删除×2、移动×2 → 删除×1、移动×1）
- **维护性**：显著提升（业务逻辑统一）

---

## ⏱️ 时间估算

| 阶段 | 预计时间 | 说明 |
|------|----------|------|
| Step 1: 重构batchDelete | 1小时 | 包括代码修改和初步测试 |
| Step 2: 重构batchMove | 1小时 | 包括代码修改和初步测试 |
| Step 3: 处理特殊逻辑 | 0.5小时 | 回收站、安全检查验证 |
| Step 4: 完整测试 | 2小时 | 所有页面、所有场景 |
| **总计** | **4.5小时** | 约半个工作日 |

---

## 🚀 执行建议

### 创建独立分支
```bash
git checkout -b refactor/batch-operations-architecture
```

### 分阶段提交
1. **Commit 1**: 重构 batchDelete 方法
2. **Commit 2**: 重构 batchMove 方法  
3. **Commit 3**: 处理特殊逻辑和边界情况
4. **Commit 4**: 完成测试，更新文档

### 代码审查重点
- ✅ 确认所有页面的批量操作仍正常工作
- ✅ 确认新文件Tab的列表更新正确
- ✅ 确认回收站功能未受影响
- ✅ 确认安全检查仍然有效

---

## 📌 前置条件

### 已完成（当前分支：fix/new-files-module-gaps）
- ✅ FilePresenter.batchDeleteFiles() 添加 viewModel.removeFileFromList()
- ✅ FilePresenter.batchMoveFiles() 添加 viewModel.updateFileInList()
- ✅ 单文件操作的ViewModel同步已修复

### 待执行（后续分支：refactor/batch-operations-architecture）
- ⏸️ BatchOperationsService重构
- ⏸️ 消除重复代码
- ⏸️ 全面测试验证

---

## 📚 相关文档

- [NEW_FILES_FEATURE_GAP_ANALYSIS.md](NEW_FILES_FEATURE_GAP_ANALYSIS.md) - 新文件功能缺口分析
- [BUG_FIX_WORKFLOW.md](BUG_FIX_WORKFLOW.md) - Bug修复工作流程
- [ERROR_DATABASE.md](ERROR_DATABASE.md) - 错误数据库

---

## 📝 备注

- 本重构为**架构优化**，不是紧急Bug修复
- 建议在当前分支修复完成并测试通过后再执行
- 重构期间需要全面的回归测试
- 建议在开发环境充分测试后再合并到主分支

---

**创建时间**：2025年12月13日  
**创建分支**：fix/new-files-module-gaps  
**优先级**：P2（中等）  
**预计执行时间**：下周  
