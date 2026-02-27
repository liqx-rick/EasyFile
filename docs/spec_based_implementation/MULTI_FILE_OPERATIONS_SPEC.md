# 多文件操作（编辑模式）功能说明书

**文档版本**: 2.0
**生成日期**: 2026-02-11
**分析方法**: 源代码 Template E 全流程分析（基于实际代码实现）
**适用范围**: EasyFile 应用所有编辑模式（多选）相关页面与流程

---

## 执行摘要

编辑模式（Multi-File / Batch Operations）由三层结构实现：

1. **EditModeMixin** —— 编辑模式状态与选择控制（UI 层集成）
2. **BatchOperationsService** —— 批量操作业务逻辑（不存储 BuildContext）
3. **SelectionBottomBar** —— 编辑模式下的底部操作栏（用户交互）

本文档描述进入方式、支持的操作、关键流程、安全检查、UI 反馈以及与单文件操作的区别。

---

## 进入方式（代码已确认）

- `EditModeToolbarButton` 在文件浏览器工具栏中（Browse / Recent / Favorite / NewFiles 标签页）。见 `lib/ui/pages/file_browser_page.dart`
- `EditModeToolbarButton` 或 `IconButton(Icons.edit_outlined)` 在其他页面中（推荐聚合、归档管理、大文件、分类页等）
- 注意：长按文件/文件夹会打开单文件操作面板（`SingleFileOperationsSheet`）—— 不再直接进入编辑模式

调用 `enterEditMode()` 时，页面会：

- 设置 `_isEditMode = true`
- 显示短暂提示条
- 调用 `selectionController.enterSelectionMode()`
- 约 3 秒后自动隐藏提示条

编辑模式中：

- 列表项显示复选框
- 长按回调被禁用，避免冲突
- `SelectionBottomBar` 显示批量操作
- AppBar 前导区显示 `EditModeLeadingIndicator`，编辑按钮变为关闭图标

---

## 支持的批量操作（BatchOperationsService）

位置：`lib/ui/services/batch_operations_service.dart`

主要操作（每个方法接收 `BuildContext`）：

- `batchToggleFavorite(context, selectedItems)` —— 智能切换收藏（若全部已收藏则取消，否则只添加文件）
- `batchDelete(context, selectedItems)` —— 删除（支持回收站/永久删除），显示确认与进度
- `batchMove(context, selectedItems, currentPath, {shouldRefresh = true})` —— 移动到指定文件夹，防止循环移动
- `batchCopy(context, selectedItems, currentPath)` —— 复制，带冲突处理与进度
- `batchRename(context, selectedItems)` —— 重命名（仅允许单选，UI 在多选时禁用）
- `batchShare(context, selectedItems)` —— 分享文件（文件夹会被过滤并提示用户）

**实现说明**：

- 服务层不得在异步调用间持有 `BuildContext`，由调用方传入并检查 `mounted`
- 长时间异步任务后，需重新检查 `context.mounted` 再弹窗或导航
- 退出选择模式时，使用 `WidgetsBinding.instance.addPostFrameCallback` 避免 `setState` 时序问题

---

## UI 组件与行为

- `EditModeToolbarButton` / `EditModeActionButton`：调用 `enterEditMode()` / `exitEditMode()`
- `SelectAllButton`：三态全选控件（无/部分/全选）
- `EditModeHintBar`：进入编辑模式时短暂提示（约 3 秒）
- `SelectionBottomBar`：显示选中数量和主要操作（移动、删除），以及“更多”菜单（复制、重命名、分享、收藏）

**选择启用规则**：

- 重命名：仅当 `selectedPaths.length == 1` 时启用
- 分享：仅当所有选中项均为文件（无文件夹）时启用
- 收藏：至少选中一个文件时启用

---

## 关键流程（摘要）

**批量删除（启用回收站）**：

1. 用户点击底部栏“删除”
2. 对所有路径调用 `PathSecurity.getPathRiskLevel()`，若存在 `danger` / `forbidden` 则终止
3. 显示确认对话框，列出文件/文件夹数量及回收站行为
4. 若启用回收站：标记数据库记录、从 UI 移除、后台移动文件；否则显示进度条并永久删除
5. 完成后调用 `onExitSelectionMode()`（通过 `addPostFrameCallback`），并显示 SnackBar 结果

**批量移动**：

- 打开文件夹选择器，验证目标文件夹（避免移入自身/子文件夹）
- 执行 `PathSecurity` 检查目标路径
- 逐个移动文件，更新 ViewModel，可选择刷新视图

**批量收藏切换**：

- 若所有选中文件均已收藏 → 取消收藏；否则仅对文件添加收藏，并提示用户

---

## 安全检查（PathSecurity）

- 所有写操作前必须调用 `PathSecurity.getPathRiskLevel()`
- 对 `forbidden` 和 `danger` 级别直接拦截，对 `warning` 级别需用户确认后放行
- 关键操作需调用 `PathSecurity.logOperation()` 记录日志

---

## BuildContext 与生命周期最佳实践

- 服务层不得持有 `BuildContext`，由调用方传入
- 异步操作前后均需检查 `context.mounted`
- PopupMenu 操作延迟约 100ms 执行，避免菜单关闭后触发导航
- 异步操作后需更新页面状态时，使用 `addPostFrameCallback`

---

## 页面集成示例

1. 混入 `EditModeMixin` 并提供 `selectionController`
2. 在 `initState()` 中创建 `BatchOperationsService`，传入 `onRefresh` 和 `onExitSelectionMode` 回调
3. 在 AppBar 中添加 `EditModeToolbarButton`，编辑模式时显示 `SelectAllButton`
4. 当 `isEditMode == true` 时显示 `SelectionBottomBar`，将其回调绑定到 `BatchOperationsService`

---

## 性能优化建议

1. **大量文件批量操作**：
   - 使用后台队列或分片处理
   - 显示进度对话框提供实时反馈
   - 避免阻塞 UI 主线程

2. **UI 同步**：
   - 优先使用 `viewModel.updateFileInList()` 更新单项
   - 仅在必要时调用 `onRefresh()` 全量刷新

3. **选择状态管理**：
   - 使用 `ValueNotifier` 监听选择变化
   - 避免频繁 `setState()` 导致整页重建

---

## 安全最佳实践

1. **PathSecurity 检查**：
   - 所有写操作前必须调用 `PathSecurity.getPathRiskLevel()`
   - 遇到 `forbidden` / `danger` 立即中断并提示用户

2. **确认对话框**：
   - 删除操作必须显示确认对话框
   - 明确显示操作影响（文件数量、是否可恢复）

3. **错误处理**：
   - 捕获异步操作异常并显示友好提示
   - 记录关键操作日志便于排查问题

---

## BuildContext 生命周期

1. **异步操作**：
   - 操作前检查 `context.mounted`
   - 操作后再次检查避免异常

2. **回调延迟**：
   - PopupMenu 回调延迟 100ms 执行
   - 状态更新使用 `addPostFrameCallback`

3. **服务设计**：
   - 服务层不持有 `BuildContext`
   - 所有 UI 操作要求调用方传入 `context`

---

## 参考源码文件

- `lib/ui/mixins/edit_mode_mixin.dart` —— 编辑模式状态管理
- `lib/ui/services/batch_operations_service.dart` —— 批量操作业务逻辑
- `lib/ui/widgets/selection_bottom_bar.dart` —— 选择操作底部栏
- `lib/ui/widgets/edit_mode_widgets.dart` —— 编辑模式 UI 组件
- `lib/ui/mixins/batch_operations_mixin.dart` —— 批量操作 Mixin（已废弃）
- `lib/ui/pages/file_browser_page.dart` —— 文件浏览页集成示例
- `lib/ui/pages/recommend_aggregate_page.dart` —— 推荐聚合页集成示例

---

**文档版本**: 2.0
**最后更新**: 2026-02-11
**分析方法**: Template E - 基于实际代码实现的完整流程分析
**验证范围**: 所有编辑模式相关页面的实际实现代码

---
