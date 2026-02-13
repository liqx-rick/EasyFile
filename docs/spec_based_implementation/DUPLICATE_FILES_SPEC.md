# EasyFile 重复文件扫描与清理模块 说明书（模版E）

---

## 1. 模块定位与入口
- 页面入口：`lib/ui/pages/duplicate_files_page.dart`，类 `DuplicateFilesPage`。
- 服务入口：`lib/core/services/enhanced_duplicate_file_scan_service.dart`，类 `EnhancedDuplicateFileScanService`。
- 配置模型：`lib/core/models/duplicate_file_scan_config.dart`，类 `DuplicateFileScanConfig`。
- 扫描管理：`lib/core/services/duplicate_file_scan_manager.dart`，类 `DuplicateFileScanManager`。
- 缓存管理：`lib/core/services/duplicate_file_smart_cache.dart`，类 `DuplicateFileSmartCache`。
- 数据结构：`lib/data/models/duplicate_file_group.dart`，类 `DuplicateFileGroup`。

## 2. 功能概述
- 支持全量与分类（按类型）重复文件扫描。
- 三阶段高效检测算法：按大小分组 → 头部哈希（8KB）→ 完整MD5。
- 智能缓存与增量更新：仅扫描变化文件，极大提升二次扫描速度。
- 支持后台扫描、进度监听、批量操作、智能推荐保留/删除。

## 3. 主要实现点
### 3.1 页面与交互
- `DuplicateFilesPage` 负责 UI 展示、配置初始化、状态管理、调用扫描服务。
- 支持进度展示、批量选择、推荐操作、分组展示等。

### 3.2 扫描服务
- `EnhancedDuplicateFileScanService` 提供 smartScan() 方法：
  - 优先返回缓存，后台自动增量更新。
  - 检测文件变化（新增/修改/删除），仅对变化文件做重复检测。
  - 变化检测与合并逻辑详见 `_performIncrementalUpdate`、`_mergeResults`。
- 三阶段检测算法：
  - 阶段1：按文件大小分组。
  - 阶段2：同组内按头部8KB哈希分组。
  - 阶段3：同组内按完整MD5分组。
- 全量扫描由 `DuplicateFileService.scanDuplicateFiles()` 实现，支持进度回调、异步处理。

### 3.3 扫描管理
- `DuplicateFileScanManager` 负责多配置状态、进度、结果、监听器管理。
- 支持并发配置、后台扫描、取消、手动状态变更、缓存清理等。

### 3.4 智能缓存
- `DuplicateFileSmartCache`/`DuplicateFileScanCache`：
  - 支持持久化缓存、快速变化检测、增量更新、缓存大小控制。
  - 缓存结构含扫描时间、配置、分组、全量文件指纹。
  - 变化检测仅比对文件元数据（大小/修改时间），不读内容。

### 3.5 数据结构
- `DuplicateFileGroup`：一组内容完全相同的文件，含推荐保留/删除逻辑（排序由 `DuplicateFilesRecommendationEngine` 提供）。
- `FileItem`：文件基础信息，支持序列化/反序列化。

## 4. 关键流程
### 4.1 全量扫描
- 入口：`EnhancedDuplicateFileScanService._fullScanWithCache()` → `DuplicateFileScanManager.startScan()` → `DuplicateFileService.scanDuplicateFiles()`。
- 步骤：收集目标文件 → 按大小分组 → 头部哈希 → 完整哈希 → 生成分组。
- 结果缓存，供后续复用。

### 4.2 增量扫描
- 入口：`EnhancedDuplicateFileScanService._performIncrementalUpdate()`。
- 步骤：检测文件变化 → 仅对新增/修改文件做重复检测 → 合并新旧分组 → 更新缓存。
- 删除文件自动从分组移除。

### 4.3 缓存与清理
- 缓存持久化于本地，按配置唯一键区分。
- 支持按配置/全部清理缓存。

### 4.4 智能推荐
- 分组内文件排序与推荐由 `DuplicateFilesRecommendationEngine` 实现。
- 推荐保留文件：`DuplicateFileGroup.recommendedToKeep`。
- 推荐删除文件：`DuplicateFileGroup.recommendedToDelete`。

## 5. 主要配置项
- `DuplicateFileScanConfig`：
  - `minSizeInKB`：最小文件大小（KB）。
  - `scanMode`：全量/分类。
  - `selectedType`：分类模式下的文件类型。

## 6. 典型调用链
- UI 触发扫描 → `EnhancedDuplicateFileScanService.smartScan()` → 检查/加载缓存 → 增量/全量扫描 → 结果回调 UI。

## 7. 其它说明
- 所有扫描、缓存、推荐等均严格基于源码实现，未做主观推断。
- 详细字段、方法、流程请参见上述各实现文件。

---

（本说明 strictly based on EasyFile 源码，未做任何主观推断）
