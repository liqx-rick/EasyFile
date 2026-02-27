# 新文件功能说明书（模版E）

注意：本说明书完全基于源码实现的证据，未包含主观臆断。引用的符号与文件路径均来自源码实现。

## 概要
- 目标：描述“新文件”Tab 的入口、调用链、数据模型、缓存与扫描策略、并发/取消机制、UI 更新及测试要点。
- 范围：仅覆盖代码中实现的新文件相关逻辑与其直接依赖（presenter/scanner/local source/model/viewmodel/调用点）。

## 证据文件（实现点）
- `lib/presenter/file_presenter.dart` — `loadNewFiles({bool isUserRefresh})`, `_processNewFileItems`, `refreshNewFilesInBackground`, `newFilesScanner`, `newFilesLocalSource`。
- `lib/data/sources/new_files_scanner.dart` — `NewFilesScanner.scanNewFiles`, `NewFilesScanner.quickScanIfNeeded`, `cancelCurrentScan` 与取消令牌 `CancelToken`。
- `lib/data/sources/new_files_local_source.dart` — `loadCachedIndex`, `saveCachedIndex`, `clearCache`（缓存文件 `new_files_index.json`，缓存上限 `_maxCachedItems = 200`）。
- `lib/data/models/new_file_item.dart` — `NewFileItem`（`path`, `created`, `discovered`, `displayName`, `toJson`, `fromJson`, `toFileItem`）。
- `lib/viewmodel/file_viewmodel.dart` — `_newFiles`, `setNewFiles(List<FileItem>, {int? retentionDays, Map<String,String>? sourceMap})`, `newFilesRetentionDays` 等状态字段与 getters。
- UI 调用点（示例）：`lib/ui/pages/file_browser_page.dart` 等页面会在Tab切换或初始化时调用 `presenter.loadNewFiles()`。

## 入口点与触发时机（基于源码）
- 页面初次显示或切换到“新文件”Tab 时，UI 会调用 `presenter.loadNewFiles()` 以加载显示列表（见 `file_browser_page.dart` 中多个调用点）。
- 用户主动下拉刷新时会以 `isUserRefresh=true` 调用 `loadNewFiles`，触发强制扫描流程。

## 数据模型
- `NewFileItem` 字段与语义（`lib/data/models/new_file_item.dart`）：
  - `path`：文件系统路径；
  - `created`：文件创建/修改时间；
  - `discovered`：首次被扫描到的时间；
  - `displayName`：来源显示名（如“微信”、“下载”）；
- `NewFileItem.toFileItem()` 会尝试通过文件系统读取完整 `FileItem`（若文件不存在则返回 null）。

## 缓存与持久化
- 缓存文件：`NewFilesLocalSource` 使用 `getApplicationDocumentsDirectory()` 下的 `new_files_index.json` 存储轻量级索引；
- 缓存上限：`_maxCachedItems = 200`；写入时仅保存最多 200 条轻量索引；
- `loadCachedIndex()` 在文件不存在或解析错误时返回空列表；`saveCachedIndex()` 在写入失败时返回 `false` 并记录日志；
- `clearCache()` 支持删除缓存文件。缓存用于快速启动界面展示并配合智能扫描策略。

## 扫描策略与并发
- 扫描器：`NewFilesScanner` 提供 `scanNewFiles(retentionDays, maxResults)`，使用原生通道 `NewFilesNativeChannel.scanRecentFiles(retentionDays)`（优先使用MediaStore原生扫描以提高速度）；
- 取消机制：`NewFilesScanner` 使用 `CancelToken`，方法 `cancelCurrentScan()` 可在Tab切换或用户操作时中断扫描；扫描入口在开始时会取消之前的扫描。`quickScanIfNeeded` 中会检查 `_currentScanToken` 的取消状态并在需要时返回空结果；
- 智能缓存策略（`quickScanIfNeeded`）：
  - 若 `isUserRefresh == true`：总是执行扫描；
  - 否则若缓存存在且缓存文件修改时间小于 1 小时：返回 `null` 表示使用缓存并由 Presenter 在后台静默刷新；
  - 否则执行完整扫描；
- 结果限制：`scanNewFiles` / `quickScanIfNeeded` 接受 `maxResults` 参数用于限制返回条数（Presenter 传入 `displayCount * 2` 作为预留空间）。

## Presenter 流程（基于源码）
- `loadNewFiles({bool isUserRefresh = false})` 流程要点：
  1. 设置 `viewModel.setLoading(true)`；
  2. 从 `AppConfig.instance.fileScan` 读配置：`newFilesRetentionDays` 与 `newFilesDisplayCount`；
  3. 读取缓存：`newFilesLocalSource.loadCachedIndex()`；
  4. 调用 `newFilesScanner.quickScanIfNeeded(cachedItems, retentionDays, maxResults, isUserRefresh)`；
     - `quickScanIfNeeded` 返回 `List<NewFileItem>` 表示直接使用扫描结果；返回 `null` 表示使用缓存且 Presenter 发起后台刷新；
  5. 选取 `scannedItems ?? cachedItems` 作为数据源；
  6. 调用 `_processNewFileItems(filteredItems, displayCount)`：
     - 该方法按时间顺序处理 `NewFileItem` 列表，执行类型过滤（使用 `AppConfig.instance.fileTypes`），检查文件存在性，然后转换为 `FileItem`，并在满足 `displayCount` 后停止；
  7. 构建 `sourceMap`（path -> displayName），调用 `viewModel.setNewFiles(fileItems, retentionDays: retentionDays, sourceMap: sourceMap)`；
  8. 后台异步保存缓存 `newFilesLocalSource.saveCachedIndex(newFileItems)`（不阻塞 UI）；
  9. 若使用缓存且非用户刷新，则 `refreshNewFilesInBackground()` 启动后台静默刷新以更新缓存与 UI。
- `refreshNewFilesInBackground()` 复用扫描与处理逻辑，执行 `newFilesScanner.scanNewFiles()`，处理结果后静默调用 `viewModel.setNewFiles(...)` 并保存缓存。

## 类型过滤与展示规则
- 仅展示 `FileTypesConfig` 判定为支持的文件类型（图片/视频/音频/文档/压缩等），并排除 APK（同收藏/最近相同的规则）。`
- 处理顺序：先类型过滤再应用数量限制，确保展示配额仅计入支持类型的文件（逻辑在 `_processNewFileItems` 中实现）。

## 错误处理与回退策略
- 若 `quickScanIfNeeded` 返回空（使用缓存）且缓存为空，Presenter 最终仍会处理并在 catch 分支中通过 `viewModel.setError('加载新文件失败：$e')` 通知错误；
- `newFilesLocalSource.saveCachedIndex` 的失败通过 `catchError` 记录日志，不影响当前 UI 展示（异步保存不会阻塞 UI）。

## 并发/取消注意点（基于源码）
- Presenter 在每次扫描前不直接取消扫描，而是 `NewFilesScanner.scanNewFiles` 内部会在开始前取消之前的扫描（`_currentScanToken`），保证不会出现重复长时任务；
- `CancelToken` 可在外部通过 `NewFilesScanner.cancelCurrentScan()` 显式触发（用于Tab切换或用户取消）。

## ViewModel 行为（更新契约）
- `viewModel.setNewFiles(List<FileItem> files, {int? retentionDays, Map<String,String>? sourceMap})` 用于接收 Presenter 提供的最终可展示 `FileItem` 列表及相关元数据；
- `newFilesRetentionDays` 在 ViewModel 中暴露以便 UI 读取并展示保留时间相关信息。

## UI 触发点（示例位置）
- `file_browser_page.dart` 在 Tab 切换或页面初始化时调用 `presenter.loadNewFiles()`；
- 页面可能在使用缓存时立即显示已有缓存并在后台静默刷新（Presenter 的 `quickScanIfNeeded` + `refreshNewFilesInBackground` 协作）。

## 测试要点 / 回归检查（基于源码）
- 场景：首次启动且无缓存 → `loadNewFiles(isUserRefresh:false)` 应触发完整扫描并最终调用 `viewModel.setNewFiles(...)`；
- 场景：有缓存且缓存年龄 < 1 小时 → `loadNewFiles` 应返回并使用缓存（`quickScanIfNeeded` 返回 null），随后 `refreshNewFilesInBackground()` 应在后台更新 UI 与缓存；
- 场景：用户下拉刷新 → `loadNewFiles(isUserRefresh:true)` 应始终执行扫描并刷新 UI；
- 场景：扫描过程中用户切换 Tab → `NewFilesScanner.cancelCurrentScan()` 应被调用（或扫描器内部取消 token 生效），避免浪费资源；
- 验证类型过滤：展示结果仅包含 `AppConfig.instance.fileTypes` 判定为支持的文件类型；
- 缓存边界：保存时仅保留 `_maxCachedItems`（200 条），且写入错误不应阻塞 UI。

## 参考实现位置（代码路径）
- Presenter: `lib/presenter/file_presenter.dart` (`loadNewFiles`, `_processNewFileItems`, `refreshNewFilesInBackground`)
- Scanner: `lib/data/sources/new_files_scanner.dart` (`scanNewFiles`, `quickScanIfNeeded`, `cancelCurrentScan`, `CancelToken`)
- 缓存源: `lib/data/sources/new_files_local_source.dart` (`loadCachedIndex`, `saveCachedIndex`, `clearCache`)
- 模型: `lib/data/models/new_file_item.dart` (`NewFileItem`)
- ViewModel: `lib/viewmodel/file_viewmodel.dart` (`setNewFiles`, `newFilesRetentionDays`, `_newFiles`)
- UI 调用点（示例）: `lib/ui/pages/file_browser_page.dart`

---
生成说明：此文档由源码证据驱动生成，所有行为描述直接映射到上述列出的源码函数与方法。如需我基于此生成测试用例或创建 `test/` 目录下的集成/单元测试脚本，我可以继续实现并运行它们（需要本地环境支持）。
