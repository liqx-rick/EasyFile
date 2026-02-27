# EasyFile 垃圾文件清理模块功能说明书（模版E）

## 1. 功能概述
EasyFile 的“垃圾文件清理”模块用于扫描和清理设备中的无用文件，包括 APK 安装包、临时文件、空文件夹等。支持自定义扫描配置、缓存优化、批量操作，并集成系统回收站提示。该模块帮助用户释放存储空间，提升设备可用性。

## 2. 主要实现点
- 页面入口：`lib/ui/pages/junk_files_page.dart`（`JunkFilesPage`）
- 核心服务：`lib/core/services/junk_file_service.dart`（`JunkFileService`）
- 缓存服务：`lib/core/services/junk_file_cache_manager.dart`（`JunkFileCacheManager`）
- 扫描配置：`lib/core/models/junk_file_scan_config.dart`（`JunkFileScanConfig`）
- 文件结构：`lib/data/models/junk_file_item.dart`（`JunkFileItem`）

## 3. 代码实现细节

### 3.1 页面与入口
- `JunkFilesPage` 负责 UI 展示与交互，依赖 `JunkFileService` 进行垃圾文件扫描与清理。
- 支持类型筛选、批量选择、进度展示、系统回收站提示等。

### 3.2 扫描服务与策略
- `JunkFileService.scanJunkFiles`：
  - 支持自定义扫描配置（`JunkFileScanConfig`），包括是否扫描 APK、临时文件、空文件夹、最小临时文件天数、排除路径等。
  - 复用 `FilePresenter.getCommonScanPaths` 获取扫描路径。
  - 递归扫描各路径，支持深度限制、排除规则、空文件夹识别。
  - 结果去重后按文件大小降序排序。
  - 支持进度回调、强制刷新、缓存优先加载。

### 3.3 缓存机制
- `JunkFileCacheManager`：
  - 支持扫描结果的持久化缓存（7天有效），包括文件列表、扫描配置、时间戳。
  - 加载缓存时校验配置与有效期，过期或配置变更时自动清理。

### 3.4 扫描配置
- `JunkFileScanConfig`：
  - 支持是否扫描 APK、临时文件、空文件夹、最小天数、排除路径等参数。
  - 支持配置复制、等价性判断、JSON序列化。

### 3.5 其它
- 支持系统回收站提示与统计（集成 `SystemTrashPreferences` 及相关逻辑）。
- UI 支持进度、错误提示、批量操作、类型筛选等。

## 4. 与其它模块区分
- 仅针对垃圾文件扫描与清理，不涉及大文件、重复文件、空间统计等其它功能。

## 5. 主要相关文件
- `lib/ui/pages/junk_files_page.dart`：页面与交互逻辑
- `lib/core/services/junk_file_service.dart`：核心扫描服务
- `lib/core/services/junk_file_cache_manager.dart`：缓存服务
- `lib/core/models/junk_file_scan_config.dart`：扫描配置
- `lib/data/models/junk_file_item.dart`：文件结构

## 6. 参考实现点
- 扫描服务：`JunkFileService.scanJunkFiles`
- 缓存机制：`JunkFileCacheManager.saveCache`、`loadCache`
- 配置结构：`JunkFileScanConfig`

---

本说明 strictly based on 源码实现，未做主观推断。
