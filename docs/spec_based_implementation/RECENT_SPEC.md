# 最近功能说明书（模版E）

注意：本说明书完全基于代码实现的证据，未包含主观臆断。引用的符号与文件路径均来自源码实现。

## 概要
- 目标：描述“最近”功能（最近访问/打开文件）的入口、数据模型、持久化、调用链、并发/清理行为、UI 触发点与测试要点。
- 范围：仅覆盖源码中实现的最近文件相关逻辑与其直接依赖（presenter/viewmodel/local source/model/调用点）。

## 证据文件（实现点）
- `lib/presenter/file_presenter.dart` — `loadRecentFiles()`, `addToRecentFiles(FileItem)`。
- `lib/data/sources/recent_files_local_source.dart` — `getRecentFiles()`, `saveRecentFiles()`, `addRecentFile()`, `removeRecentFile()`, `clearRecentFiles()`, `cleanupRecentFiles()`。
- `lib/data/models/recent_file_item.dart` — `RecentFileItem`（模型：`fromFileItem`, `toJson`, `fromJson`, `toFileItem`, `copyWithAccess`）。
- `lib/viewmodel/file_viewmodel.dart` — `_isRecentFilesMode`, `setIsRecentFilesMode(bool)`, `setFiles(List<FileItem>)`, `setCurrentPath('')`（用于标记最近模式）。
- 调用点（UI/导航）: `lib/ui/widgets/files_browse_card.dart`、`lib/ui/widgets/category_nav_bar.dart`、`lib/ui/pages/file_browser_page.dart`、`lib/ui/pages/category_file_page.dart` 等多处调用 `presenter.loadRecentFiles()` 或 `presenter.addToRecentFiles(file)`（源码中直接调用位置）。

## 入口点与触发时机（基于源码）
- 手动刷新/切换至最近 Tab：UI 页面在切换 Tab 或页面返回时调用 `presenter.loadRecentFiles()` 来刷新最近视图（见 `file_browser_page.dart`、`files_browse_card.dart` 中的调用）。
- 记录最近：对用户打开/操作文件处（例如 `category_file_page.dart`、`file_browser_root_page.dart`、`extracted_files_browser_page.dart` 等），代码在适当时机调用 `presenter.addToRecentFiles(file)` 将 `FileItem` 记录为最近项。

## 数据模型（实现细节）
- `RecentFileItem` 字段：`id`, `path`, `name`, `isDirectory`, `accessedAt`, `accessCount`（见 `lib/data/models/recent_file_item.dart`）。
- 从 `FileItem` 到 `RecentFileItem`：使用 `RecentFileItem.fromFileItem(FileItem)`，`id` 使用 `path.hashCode.toString()` 生成，`accessedAt` 取当前时间，`accessCount` 初始为 1。
- 更新访问：当添加已存在的最近项时，`RecentFilesLocalSource.addRecentFile` 会调用 `copyWithAccess()` 来更新访问时间并自增 `accessCount`，然后写回存储。

## 持久化策略（实现细节）
- 存储位置：`RecentFilesLocalSource` 使用 `getApplicationDocumentsDirectory()` 并写入 `recent_files.json`。
- 数量限制：本地实现限制为最多 `_maxRecentFiles = 20` 条（保存前按 `accessedAt` 倒序排序并截断）。
- 写入行为：`saveRecentFiles` 在写前会创建父目录、按时间排序并限制数量，然后将列表序列化为 JSON 写入文件。
- 错误处理：读取/写入均有 try/catch 捕获，异常时返回空列表或 `false`，并记录日志（`logger.e`/`logger.d`）。

## Presenter 行为（逐步、基于源码）
- `loadRecentFiles()` 流程要点（`lib/presenter/file_presenter.dart`）：
  - 首先调用 `recentFilesSource.cleanupRecentFiles()` 清理不存在的条目；
  - 调用 `recentFilesSource.getRecentFiles()` 获取持久化条目；
  - 使用 `AppConfig.instance.fileTypes` 对条目做**类型过滤**（仅保留图片/视频/音频/文档/压缩类，排除 APK 等不展示类型）；
  - 过滤掉目录项（`rf.isDirectory` 为 true 则排除）；
  - 将 `RecentFileItem` 通过 `toFileItem()` 转换为 `FileItem`，然后调用 `viewModel.setFiles(fileItems)`；
  - 设置 `viewModel.setCurrentPath('')` 与 `viewModel.setRootPath('')`，并调用 `viewModel.setIsRecentFilesMode(true)` 来标记最近视图模式。
  - 异常路径：若抛出异常，catch 中会 `logger.e` 并 `viewModel.setFiles([])`。
- `addToRecentFiles(FileItem file)` 流程要点：
  - 跳过文件夹（`file.isDirectory`），并使用 `AppConfig.instance.fileTypes` 做**类型过滤**（只记录支持类型，包含 APK）；
  - 使用 `RecentFileItem.fromFileItem(file)` 构建 `RecentFileItem` 并调用 `recentFilesSource.addRecentFile(recentFile)`；
  - `addRecentFile` 会检查是否已存在：存在则调用 `copyWithAccess()` 更新访问时间和次数，否则追加并保存；
  - 错误会被捕获并记录（`logger.w`）。

## 本地数据源关键行为与边界条件
- `getRecentFiles()`：读取 JSON 并反序列化为 `List<RecentFileItem>`；若文件不存在或解析失败，返回空列表。
- `addRecentFile()`：若路径已存在则更新访问信息，否则追加；调用 `saveRecentFiles()` 去写入磁盘并执行排序/截断（最多 20 条）。
- `cleanupRecentFiles()`：同步检查每个 `RecentFileItem` 对应的文件或目录是否仍存在（使用 `existsSync()`）；若有失效项则从列表移除并保存更新后的列表。
- `removeRecentFile()` 与 `clearRecentFiles()`：分别支持删除单条记录与清空所有记录（删除存储文件）。

## UI 行为与交互细节（代码可见）
- 页面返回或入口跳转后刷新：如 `FilesBrowseCard` 在从 `FileBrowserRootPage` 返回时，会在 `onTap` 返回后判断 `viewModel.currentTab == TabView.recent`，若为 true 则调用 `presenter.loadRecentFiles()` 刷新最近列表。此类调用点在几个页面/组件中存在（保证最近视图及时同步）。
- 记录时机：代码在文件打开/预览/操作的关键路径（`category_file_page.dart`、`file_browser_root_page.dart` 等）调用 `presenter.addToRecentFiles(file)`，由 presenter 决定是否记录与如何写入。

## 并发与一致性注意点（基于源码）
- `cleanupRecentFiles()` 在 `loadRecentFiles()` 之前被调用以保证持久化数据中不包含已删除的文件；该方法使用同步 `existsSync()` 检查路径有效性，从而避免 UI 显示不存在的条目。
- 写入限制与顺序：`saveRecentFiles()` 在写入前会将条目按 `accessedAt` 倒序排序并截断到 `_maxRecentFiles`，保证磁盘存储固定上限。

## 错误路径与日志（实现中有捕获/记录）
- 所有磁盘 IO 操作（读取、写入、删除）在 `RecentFilesLocalSource` 中均包裹 try/catch 并调用 `logger` 记录错误；发生错误时返回空列表或 `false`，上层 `FilePresenter` 会在 `loadRecentFiles()` 捕获异常并将 `viewModel` 文件列表置空。

## 测试要点 / 回归检查（基于源码）
- 验证 `addToRecentFiles`：
  - 对支持类型文件多次记录，应只保留一条记录，且 `accessCount` 随后访问递增；
  - 对不支持类型或目录调用时不应在持久层新增记录。
- 验证 `loadRecentFiles`：
  - 当持久化包含已删除文件时，调用 `loadRecentFiles()` 后 UI 列表不应包含这些条目（`cleanupRecentFiles()` 生效）；
  - 当持久化包含多种类型，最终展示仅包含 `AppConfig.instance.fileTypes` 判定为支持的类型（图片/视频/音频/文档/压缩）。
- 验证持久化边界：
  - 当添加超过 `_maxRecentFiles` 条目后，磁盘文件仅保留最新的 20 条；
  - `saveRecentFiles()` 的写入在异常时返回 `false`，调用 `addRecentFile()` 时应能感知并记录失败（日志）。

## 参考实现位置（代码路径）
- Presenter: `lib/presenter/file_presenter.dart` (`loadRecentFiles`, `addToRecentFiles`)
- ViewModel: `lib/viewmodel/file_viewmodel.dart` (`setIsRecentFilesMode`, `setFiles`, `setCurrentPath`)
- 本地数据源: `lib/data/sources/recent_files_local_source.dart` (`getRecentFiles`, `addRecentFile`, `cleanupRecentFiles`, `saveRecentFiles`)
- 模型: `lib/data/models/recent_file_item.dart` (`RecentFileItem`)
- 主要调用点（示例）: `lib/ui/widgets/files_browse_card.dart`, `lib/ui/widgets/category_nav_bar.dart`, `lib/ui/pages/category_file_page.dart`, `lib/ui/pages/file_browser_page.dart`

---
生成说明：此文档由源码证据驱动生成，所有描述直接映射到列出的源码函数与方法。如需我基于这些实现生成测试脚本（单元/集成）或示例交互序列，我可以继续在 `test/` 中创建对应用例。
