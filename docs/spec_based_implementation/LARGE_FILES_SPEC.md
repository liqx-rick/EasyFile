# EasyFile 大文件扫描模块功能说明书（模版E）

## 1. 功能概述
EasyFile 的“大文件扫描”模块用于高效扫描设备存储中的大文件，支持自定义最小文件大小、类型过滤、结果数量限制、缓存优化等。该模块通过智能深度策略和剪枝优化，提升扫描性能，便于用户快速定位占用空间较大的文件。

## 2. 主要实现点
- 页面入口：`lib/ui/pages/large_files_page.dart`（`LargeFilesPage`）
- 核心服务：`lib/core/services/large_file_service.dart`（`LargeFileService`）
- 缓存服务：`lib/core/services/large_file_cache_manager.dart`（`LargeFileCacheManager`）
- 扫描配置：`lib/core/models/large_file_scan_config.dart`（`LargeFileScanConfig`）

## 3. 代码实现细节

### 3.1 页面与入口
- `LargeFilesPage` 负责 UI 展示与交互，依赖 `LargeFileService` 进行大文件扫描。
- 支持批量操作（删除、移动等）、配置调整、缓存加载与刷新。

### 3.2 扫描服务与策略
- `LargeFileService.scanLargeFiles`：
  - 支持自定义最小文件大小（默认100MB）、最大结果数（默认300）、类型过滤、剪枝优化。
  - 复用 `FilePresenter.getCommonScanPaths` 获取扫描路径。
  - 针对不同路径动态调整扫描深度。
  - 采用异步扫描，避免阻塞 UI。
  - 结果去重后按文件大小降序排序，超出最大数量时截断。

### 3.3 缓存机制
- `LargeFileCacheManager`：
  - 支持扫描结果的持久化缓存（默认7天有效），包括文件列表、扫描配置、时间戳。
  - 提供缓存保存、加载、过期检测与清理。
  - 加载缓存时校验配置与有效期，过期或配置变更时自动清理。

### 3.4 扫描配置
- `LargeFileScanConfig`：
  - 支持最小文件大小、类型过滤、扫描范围、最大结果数、快速扫描标记等参数。
  - 支持配置复制、等价性判断、JSON序列化。

### 3.5 其它
- 支持批量操作服务（`BatchOperationsService`）、文件项结构（`FileItem`）。
- UI 支持进度、差异化扫描、批量选择、结果统计等。

## 4. 与其它模块区分
- 仅针对大文件扫描与管理，不涉及垃圾清理、重复文件、空间统计等其它功能。

## 5. 主要相关文件
- `lib/ui/pages/large_files_page.dart`：页面与交互逻辑
- `lib/core/services/large_file_service.dart`：核心扫描服务
- `lib/core/services/large_file_cache_manager.dart`：缓存服务
- `lib/core/models/large_file_scan_config.dart`：扫描配置

## 6. 参考实现点
- 扫描服务：`LargeFileService.scanLargeFiles`
- 缓存机制：`LargeFileCacheManager.saveCache`、`loadCache`
- 配置结构：`LargeFileScanConfig`

---

本说明 strictly based on 源码实现，未做主观推断。
