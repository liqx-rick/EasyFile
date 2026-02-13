# 收藏功能说明书（模版E）

注意：本说明书完全基于代码实现的证据，未包含主观臆断。引用的符号与文件路径均来自源码实现。

## 概要
- 目标：描述“收藏”功能的入口、调用链、数据模型、持久化、并发/IO 行为、边界条件与测试要点。
- 范围：仅覆盖代码中实现的收藏相关逻辑及其直接依赖模块。

## 证据文件（实现点）
- `lib/presenter/file_presenter.dart` — `toggleFavoriteFile`, `loadFavoriteFiles`, `batchAddFavoriteFiles`
- `lib/viewmodel/file_viewmodel.dart` — `_favoriteFiles`, `addFavoriteFile`, `batchAddFavoriteFiles`, `removeFavoriteFile`, `setFavoriteFiles`, `isFavoriteFile`
- `lib/data/sources/favorite_files_local_source.dart` — 本地持久化方法：`getFavoriteFiles`, `saveFavoriteFiles`, `addFavoriteFile`, `removeFavoriteFile`, `updateFavoriteFilePath`, `batchAddFavoriteFiles`
- `lib/ui/services/single_file_operations_service.dart` — UI 触发单文件收藏（`toggleFavorite`）并显示反馈（SnackBar）
- `lib/ui/services/batch_operations_service.dart` — 批量收藏/取消收藏的交互策略（跳过文件夹/已收藏等）
- `lib/ui/pages/file_browser_page.dart` — 收藏 Tab 的 UI（工具栏构建 `_buildFavoriteToolBar`、空状态提示）
- `lib/ui/widgets/single_file_operations_sheet.dart` — 单文件操作菜单包含“添加到收藏/取消收藏”入口（不关闭菜单直接执行收藏）

## 入口点（UI）
- 单文件入口：`single_file_operations_sheet.dart` 的菜单项调用 `service.toggleFavorite(file)`（不先关闭菜单，执行后关闭菜单）。
- 直接操作入口：`single_file_operations_service.toggleFavorite(FileItem)` 调用 `FilePresenter.toggleFavoriteFile(FileItem)`，并在操作完成后显示 `SnackBar`（UI 反馈）。
- 批量入口：`batch_operations_service` 在选中多项时触发批量收藏/取消收藏逻辑，最后调用 `FilePresenter.batchAddFavoriteFiles(List<FavoriteFileItem>)`。
- 收藏 Tab：`file_browser_page.dart` 渲染收藏 Tab（包含工具栏与空状态提示），并在需要时触发 `FilePresenter.loadFavoriteFiles()` 来刷新视图。

## 数据模型
- `FavoriteFileItem`（数据模型）字段（源码可序列化/反序列化）：`path`、`addedTime`、`accessCount`、`lastAccessTime`、`userNote`、`tags`（见 `lib/data/models/favorite_file_item.dart` 实现）。

## 持久化（实现细节）
- 持久层实现：`FavoriteFilesLocalSource` 使用应用文档目录（`ApplicationDocumentsDirectory`）和 JSON 存储实现以下方法：
  - `getFavoriteFiles()`：读取并返回已保存的 `FavoriteFileItem` 列表；
  - `saveFavoriteFiles(List<FavoriteFileItem>)`：序列化并写入文件；
  - `addFavoriteFile(FavoriteFileItem)`、`removeFavoriteFile(FavoriteFileItem)`、`batchAddFavoriteFiles(List<FavoriteFileItem>)`：对存储进行增删改；
  - `updateFavoriteFilePath(oldPath, newPath)`：在文件被移动/重命名时更新收藏条目路径（存在该接口以保持同步）。
- 错误处理：持久层对 IO 异常进行捕获并返回/抛出相应错误（详见实现中的 try/catch 语句）。

## 业务逻辑与调用链（逐步、基于源码）
1. UI 发起：`single_file_operations_service.toggleFavorite(file)` 或 `batch_operations_service` 发起批量请求。
2. Presenter：调用 `FilePresenter.toggleFavoriteFile(FileItem)` 或 `FilePresenter.batchAddFavoriteFiles(List<FavoriteFileItem>)`。
   - `toggleFavoriteFile` 流程（代码要点）：
     - 查询 `viewModel.isFavoriteFile(file.path)` 判断当前收藏状态；
     - 若已收藏，调用 `favoriteFilesSource.removeFavoriteFile(...)`；否则构建 `FavoriteFileItem` 并调用 `favoriteFilesSource.addFavoriteFile(...)`；
     - 更新 `FileViewModel`（调用 `addFavoriteFile`/`removeFavoriteFile` 或 `setFavoriteFiles`）；
     - 当当前视图为收藏 Tab 时，触发 reload/刷新（实现中有分支处理以确保收藏 Tab 更新）。
   - `loadFavoriteFiles` 流程（代码要点）：
     - 从 `favoriteFilesSource.getFavoriteFiles()` 读取条目；
     - 为每个条目做并发文件存在性检查（异步检查文件是否仍存在），过滤掉不存在的条目；
     - 将有效条目转换为 `FileItem`（供 UI 列表渲染），并调用 `viewModel.setFiles(validFileItems)` 或 `viewModel.setFavoriteFiles(...)`。
   - `batchAddFavoriteFiles` 流程：
     - 接收多条 `FavoriteFileItem`，调用持久层的 `batchAddFavoriteFiles`，并在成功后一次性更新 `FileViewModel`（以减少 UI 重绘）。

## ViewModel 行为
- `FileViewModel` 维护 `_favoriteFiles` 列表，并提供：
  - `addFavoriteFile(FavoriteFileItem)`：将新条目加入内存列表并 `notifyListeners()`；
  - `removeFavoriteFile(String path)`：按路径删除并通知；
  - `batchAddFavoriteFiles(List<FavoriteFileItem>)`：批量加入并在合适时使用延迟（post-frame / 防抖）来避免 UI 冲突；
  - `isFavoriteFile(String path)`：判断路径是否存在于 `_favoriteFiles` 中（用于 toggle 判断）。

## 并发与 IO 注意点（基于源码实现）
- `loadFavoriteFiles` 在 presenter 内对每个持久化条目进行异步文件存在性检查（并行），并仅保留存在的文件条目返回给 viewModel。该行为意味着：
  - 收藏条目可能因文件被删除而在加载时被过滤；
  - Presenter 负责在加载阶段执行这些过滤以保证 UI 不显示不存在的文件。
- 批量操作通过 `batchAddFavoriteFiles` 在持久层原子式地写入以减少频繁 IO；ViewModel 也提供批量更新接口以减少重复 `notifyListeners()`。

## 同步策略（文件被移动/重命名/删除）
- 源码中持久层提供 `updateFavoriteFilePath(oldPath, newPath)` 方法，用于在文件路径变化时更新收藏记录；
- `loadFavoriteFiles` 的存在性检查会自动去除已删除文件的收藏条目；
- 由此可见：系统通过显式路径更新方法 + 加载时存在性过滤来保持收藏与文件系统的一致性（实现可见于 presenter 与 local source）。

## 批量操作规则（实现中明确的行为）
- 批量服务在开始前会：
  - 跳过文件夹（仅文件可被收藏）；
  - 跳过已收藏项（避免重复添加）；
  - 对可收藏项构建 `FavoriteFileItem` 列表并调用 presenter 的批量接口。

## UI 反馈与用户体验（代码可见行为）
- 单文件操作：在 `single_file_operations_service.toggleFavorite` 完成后显示 `SnackBar`（成功/失败反馈）；
- 菜单行为：`single_file_operations_sheet` 在执行收藏操作时**不先关闭菜单**，操作完成后再关闭（见菜单项 onTap 实现）。

## 错误路径与日志（实现中有捕获/记录）
- 本地持久化的 IO 异常会被捕获并在 presenter 层处理（实现中存在 try/catch），对上层 UI 返回失败状态以便显示错误反馈。

## 测试要点 / 回归检查（基于源码）
- 验证 `toggleFavoriteFile`：
  - 在未收藏时添加后，`FileViewModel.isFavoriteFile(path)` 返回 true，并且 `FavoriteFilesLocalSource` 中包含该条目；
  - 在已收藏时移除后，`isFavoriteFile` 返回 false，持久化不包含该条目。
- 验证 `loadFavoriteFiles`：
  - 当持久化包含已删除的文件路径时，加载后 UI 不应显示该条目（存在性检查生效）；
  - 当文件被移动并调用 `updateFavoriteFilePath` 后，加载应能以新路径正确显示。
- 验证批量操作：
  - 跳过文件夹与已收藏项；
  - 批量添加后持久层与 viewModel 同步且 UI 更新为预期。

## 参考实现位置（代码路径）
- Presenter: `lib/presenter/file_presenter.dart`
- ViewModel: `lib/viewmodel/file_viewmodel.dart`
- 持久层: `lib/data/sources/favorite_files_local_source.dart`
- 单文件 UI 服务: `lib/ui/services/single_file_operations_service.dart`
- 批量 UI 服务: `lib/ui/services/batch_operations_service.dart`
- 收藏 Tab 页面: `lib/ui/pages/file_browser_page.dart`
- 单文件操作菜单: `lib/ui/widgets/single_file_operations_sheet.dart`

---
生成说明：此文档由代码证据驱动生成，所有行为描述直接映射到上述列出的源码函数与方法。如需将文档扩展为包含示例交互序列或 QA 测试脚本，我可以基于这些实现进一步生成对应用例。
