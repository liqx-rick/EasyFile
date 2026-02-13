# 压缩包功能说明书（模版E）

注意：本说明书严格基于代码实现，所有行为描述均以源码为证据。引用的符号与文件路径均来自实际实现。

## 概要
- 目标：描述压缩包管理、预览、解压、记录与浏览功能的入口、调用链、数据模型、FFI处理、UI交互、并发与错误处理。
- 范围：覆盖压缩包扫描、解压、进度反馈、密码处理、记录与解压后浏览等核心逻辑。

## 证据文件（实现点）
- `lib/ui/pages/archive_management_page.dart` — 压缩包管理页面，负责扫描、展示、批量操作、单文件操作、解压入口。
- `lib/ui/dialogs/extract_archive_dialog.dart` — 解压入口对话框，负责目标目录与文件夹名选择，调用进度对话框。
- `lib/ui/dialogs/extraction_progress_dialog.dart` — 解压进度对话框，负责进度反馈、密码输入、结果展示、停止操作、完成后导航。
- `lib/core/services/archive_service.dart` — FFI压缩包处理服务，负责多格式解压（ZIP、RAR、7z、TAR等）、密码处理、空间检查、后台Isolate、停止操作。
- `lib/core/services/extraction_record_service.dart` — 解压记录管理，负责记录、批量检查、删除、浏览。
- `lib/ui/pages/extracted_files_browser_page.dart` — 解压后文件浏览页面，支持搜索、编辑、返回逻辑。
- `lib/viewmodel/file_viewmodel.dart` — 解压上下文状态（extractionSourceName、extractionTargetPath、shouldHighlightExtraction等）。

## 入口点与触发时机
- 管理入口：`ArchiveManagementPage` 扫描并展示所有压缩包，支持搜索、筛选、排序、批量操作。
- 解压入口：单文件操作菜单或管理页面调用 `ExtractArchiveDialog`，用户选择目标目录与文件夹名后，调用 `ExtractionProgressDialog`。
- 进度反馈：`ExtractionProgressDialog` 调用 `ArchiveService.extractToInBackground`，显示进度、支持停止、处理密码输入。
- 记录与浏览：解压完成后调用 `ExtractionRecordService.addRecord`，用户可在管理页面或进度对话框跳转到 `ExtractedFilesBrowserPage` 浏览解压内容。

## 数据模型与状态
- 压缩包文件：`FileItem`。
- 解压记录：`ExtractionRecord`（archivePath、targetPath、fileCount、时间戳等）。
- 解压上下文：`FileViewModel` 提供 extractionSourceName、extractionTargetPath、shouldHighlightExtraction，用于页面高亮与导航。

## FFI处理与多格式支持
- `ArchiveService` 负责多格式解压：
  - RAR：使用 UnRAR SDK（`UnrarFFI`）；
  - ZIP：使用 minizip-ng（`MinizipFFI`）；
  - 其它：使用 libarchive（`ArchiveFFI`）；
- 解压流程：
  - 检查空间、处理文件夹名冲突（autoRename）、创建目标目录；
  - 按格式分流调用对应 FFI；
  - 支持密码输入与重试（最多3次）；
  - 支持后台Isolate（`extractToInBackground`）；
  - 支持停止操作（`stopExtraction`，libarchive可真正停止，RAR/ZIP仅关闭进度对话框）。

## UI交互与反馈
- 解压入口：`ExtractArchiveDialog` 负责目标目录与文件夹名选择，调用进度对话框。
- 进度反馈：`ExtractionProgressDialog` 显示进度条、状态信息、支持停止、密码输入、结果展示。
- 完成后：可跳转到 `ExtractedFilesBrowserPage` 浏览解压内容。
- 管理页面：`ArchiveManagementPage` 支持批量操作、记录管理、解压后高亮。

## 记录与回溯
- 解压完成后调用 `ExtractionRecordService.addRecord` 记录操作，管理页面支持批量检查文件夹存在性、删除记录、浏览记录。
- 解压记录用于高亮已解压压缩包、导航到解压内容。

## 并发与错误处理
- 解压操作在后台Isolate执行，避免UI阻塞。
- 支持停止操作（libarchive可真正停止，RAR/ZIP仅关闭进度对话框）。
- 密码处理：解压失败时检测错误信息，弹出密码输入对话框，最多重试3次。
- 空间不足、文件损坏、密码错误等均有详细错误反馈与日志记录。

## 测试要点 / 回归检查
- 验证多格式解压（ZIP、RAR、7z、TAR等）均能正确分流并处理。
- 验证密码输入与重试流程（最多3次，失败后有错误提示）。
- 验证停止操作（libarchive可真正停止，RAR/ZIP仅关闭进度对话框）。
- 验证解压记录添加、批量检查、删除、浏览。
- 验证解压后高亮与导航（extractionTargetPath、shouldHighlightExtraction）。
- 验证空间检查、文件夹名冲突处理（autoRename）。
- 验证异常路径（空间不足、损坏、密码错误等）均有详细日志与UI反馈。

## 参考实现位置（代码路径）
- 管理页面: `lib/ui/pages/archive_management_page.dart`
- 解压入口: `lib/ui/dialogs/extract_archive_dialog.dart`
- 进度反馈: `lib/ui/dialogs/extraction_progress_dialog.dart`
- FFI服务: `lib/core/services/archive_service.dart`
- 记录管理: `lib/core/services/extraction_record_service.dart`
- 解压浏览: `lib/ui/pages/extracted_files_browser_page.dart`
- 状态管理: `lib/viewmodel/file_viewmodel.dart`

---
生成说明：此文档由源码证据驱动生成，所有行为描述直接映射到上述列出的源码函数与方法。如需生成测试用例或脚本，可基于此进一步实现。
