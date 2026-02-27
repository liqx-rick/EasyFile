# EasyFile 安装包管理（APK管理）功能说明书（模版E）

## 1. 功能概述
EasyFile 的“安装包管理”模块（APK管理）用于扫描、展示和管理设备存储中的 APK 安装包文件，支持批量解析、安装状态检测、删除、跳转安装/详情等操作。该模块与“应用管理”完全分离，仅针对 APK 文件，不涉及已安装应用。

## 2. 主要实现点
- 页面入口：`lib/ui/pages/apk_management_page.dart`（`ApkManagementPage`）
- 核心服务：`lib/core/services/apk_manager_service.dart`（`ApkManagerService`）
- APK数据结构：`lib/data/models/apk_info.dart`（`ApkInfo`）
- 缓存服务：`lib/core/services/apk_cache_service.dart`（`ApkCacheService`）
- 详情页：`lib/ui/pages/apk_detail_page.dart`
- 入口注册：`lib/ui/widgets/quick_access_section.dart`（功能卡片）

## 3. 代码实现细节

### 3.1 页面与入口
- `ApkManagementPage` 负责 UI 展示，依赖 `ApkManagerService` 获取和管理 APK 列表。
- 入口注册于 `QuickAccessSection` 的功能卡片，与“应用管理”Tab分离。

### 3.2 APK 信息结构
- `ApkInfo` 定义于 `apk_info.dart`，字段包括：
  - `filePath`（APK文件路径）、`appName`、`packageName`、`versionName`、`versionCode`、`appIconBase64`、`minSdkVersion`、`targetSdkVersion`、`isDebug`、`fileSize`、`modifiedTime`、`status`（安装状态）。
- 支持 JSON 互转、状态变更（`copyWith`）。

### 3.3 APK 扫描与缓存
- `ApkManagerService.scanApkFiles`：混合扫描策略，优先 MediaStore，补充文件系统，合并去重。
- 支持缓存（`ApkCacheService`，24小时有效），优先加载缓存，过期/无缓存时全量扫描。
- `ApkCacheService` 提供 APK 列表的持久化缓存、过期检测与清理。

### 3.4 APK 解析与状态检测
- `ApkManagerService` 调用 `ApkParserChannel.parseApkBatch` 批量解析 APK，获取详细信息。
- 通过 `ApkParserChannel.checkInstallStatusBatch` 检测每个 APK 的安装状态（未安装/已安装/版本不同等）。
- 解析结果合并后保存至缓存。

### 3.5 UI 交互与操作
- 支持批量展示 APK 信息、刷新、删除、跳转安装（未安装时）、跳转应用详情（已安装时）。
- `ApkDetailPage` 展示单个 APK 详细信息及操作按钮（安装、打开设置、删除等）。
- 页面监听包变更（安装/卸载/更新），可快速刷新安装状态（不重新扫描文件）。

### 3.6 其它
- 支持扫描进度、错误处理、缓存优先加载与后台刷新。
- 与“应用管理”完全分离，无已安装应用的增删改查逻辑。

## 4. 与“应用管理”区分
- “安装包管理”仅管理存储中的 APK 文件，不涉及已安装应用。
- “应用管理”相关逻辑见 `AppManagementPage`、`AppManagementService`，与本模块无交集。

## 5. 主要相关文件
- `lib/ui/pages/apk_management_page.dart`：页面与交互逻辑
- `lib/core/services/apk_manager_service.dart`：核心服务
- `lib/core/services/apk_cache_service.dart`：APK 列表缓存
- `lib/data/models/apk_info.dart`：APK 信息结构
- `lib/ui/pages/apk_detail_page.dart`：APK 详情页
- `lib/ui/widgets/quick_access_section.dart`：入口注册

## 6. 参考实现点
- APK 扫描与缓存：`ApkManagerService.scanApkFiles`、`ApkCacheService.getCachedApkList`、`saveApkListCache`
- 解析与状态检测：`ApkParserChannel.parseApkBatch`、`checkInstallStatusBatch`
- UI 操作与刷新：`ApkManagementPage._loadApkFilesWithCache`、`_loadApkFilesInBackground`、`_quickUpdateInstallStatus`

---

本说明 strictly based on 源码实现，未做主观推断。
