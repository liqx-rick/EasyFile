# EasyFile 应用管理功能说明书（模版E）

## 1. 功能概述

EasyFile 的“应用管理”功能用于获取、展示和管理设备上已安装的应用信息，支持应用列表的缓存、搜索、排序、批量操作、存储空间统计、使用统计等。该功能与“安装包管理”完全分离，后者仅管理 APK 安装包文件。

## 2. 主要实现点

- 页面入口：`lib/ui/pages/app_management_page.dart`（`AppManagementPage`）
- 核心服务：`lib/core/services/app_management_service.dart`（`AppManagementService`）
- 应用数据结构：`lib/data/models/app_info.dart`（`EasyFileAppInfo`）
- 列表缓存：`lib/core/services/app_list_cache_manager.dart`（`AppListCacheManager`）
- 入口注册：`lib/ui/widgets/quick_access_section.dart`、`lib/viewmodel/file_viewmodel.dart`（`TabView.appManagement`）

## 3. 代码实现细节

### 3.1 页面与入口
- `AppManagementPage` 负责 UI 展示，依赖 `AppManagementService` 获取应用列表。
- 入口注册于 `TabView.appManagement`，由 `QuickAccessSection` 及 `FileViewModel` 控制 Tab 切换。

### 3.2 应用信息结构
- `EasyFileAppInfo` 定义于 `app_info.dart`，字段包括：
  - `name`（应用名）、`packageName`（包名）、`versionName`、`versionCode`、`icon`（图标）、`installTime`、`updateTime`、`isSystemApp`、`storageInfo`（存储信息）、`usageStats`（使用统计）。
- 支持从原生插件（`installed_apps`）和 JSON 互转。

### 3.3 应用列表获取与缓存
- `AppManagementService.getInstalledApps`：调用原生插件获取已安装应用列表，支持是否包含系统应用、是否加载图标。
- `AppManagementService.quickLoadApps`：优先从 `AppListCacheManager` 读取缓存，无缓存时调用原生接口。
- `AppListCacheManager`：基于 `SharedPreferences`，缓存应用列表（含图标），缓存有效期 24 小时。
- 支持缓存清理、全量/增量刷新。

### 3.4 存储与使用统计
- `AppManagementService.loadAppsWithStorage`：批量加载应用存储信息（通过 `AppStorageService`）、使用统计（通过 `UsageStatsService`），并合并进 `EasyFileAppInfo`。
- 存储信息结构见 `AppStorageInfo`，包括 `appSize`、`dataSize`、`cacheSize`、`cachedTime`。
- 使用统计结构见 `AppUsageStats`，包括 `lastTimeUsed`、`lastUpdateTime`、`effectiveLastTime`。

### 3.5 搜索、排序与筛选
- `AppManagementService.searchApps`：支持按名称/包名模糊搜索。
- `AppManagementService.sortBySize`、`sortByName`：支持按空间占用、名称（含拼音）排序。
- `AppManagementService.filterByMinSize`：支持按最小空间筛选。

### 3.6 增量刷新与基准时间
- `AppManagementService.quickRefresh`：检测已卸载/新安装应用，更新使用统计，移除无效缓存。
- `AppManagementService.validateAndUpdateBaseline`、`_calculateDeviceBaselineTime`：基于应用使用时间推算设备基准时间，缓存于本地。

### 3.7 其它
- 支持权限检测与请求（见 `UsageStatsPermissionService`）。
- UI 支持搜索栏、排序、系统应用显示切换、刷新提示等。

## 4. 与“安装包管理”区分
- “应用管理”仅管理已安装应用（通过原生接口获取），不涉及 APK 文件。
- “安装包管理”相关逻辑见 `ApkManagementPage`，与本模块无交集。

## 5. 主要相关文件
- `lib/ui/pages/app_management_page.dart`：页面与交互逻辑
- `lib/core/services/app_management_service.dart`：核心服务
- `lib/core/services/app_list_cache_manager.dart`：应用列表缓存
- `lib/data/models/app_info.dart`：应用信息结构
- `lib/viewmodel/file_viewmodel.dart`、`lib/ui/widgets/quick_access_section.dart`：Tab 入口

## 6. 参考实现点
- 应用列表获取与缓存：`AppManagementService.getInstalledApps`、`quickLoadApps`、`AppListCacheManager.getCachedAppList`、`saveAppList`
- 存储与使用统计加载：`AppManagementService.loadAppsWithStorage`
- 搜索/排序/筛选：`AppManagementService.searchApps`、`sortBySize`、`sortByName`、`filterByMinSize`
- 增量刷新：`AppManagementService.quickRefresh`
- 基准时间推算：`AppManagementService.validateAndUpdateBaseline`、`_calculateDeviceBaselineTime`

---

本说明 strictly based on 源码实现，未做主观推断。
