# EasyFile 存储空间统计与分析模块功能说明书（模版E）

## 1. 功能概述
EasyFile 的“存储空间统计与分析”模块用于统计和展示设备存储空间的总容量、剩余空间、各类文件（图片、视频、文档、音乐等）占用情况，并支持应用存储占用的查询。该模块为用户提供空间分布可视化、空间管理入口和相关操作。

## 2. 主要实现点
- 页面入口：`lib/ui/pages/storage_management_page.dart`（`StorageManagementPage`）
- 功能卡片入口：`lib/ui/widgets/storage_management_card.dart`（`StorageManagementCard`）
- 应用存储服务：`lib/core/services/app_storage_service.dart`（`AppStorageService`）

## 3. 代码实现细节

### 3.1 页面与入口
- `StorageManagementCard` 为主页面提供存储管理入口卡片，点击跳转至 `StorageManagementPage`。
- `StorageManagementPage` 展示存储总容量、剩余空间、各类文件占用统计，并集成大文件、重复文件、垃圾清理等入口。

### 3.2 存储空间统计
- 通过 `disk_space_plus` 插件获取设备总容量与剩余空间（`_loadStorageInfo` 方法）。
- 统计图片、视频、文档、音乐等类别文件的总占用（`_loadCategorySizes` 方法，缓存于本地）。
- 支持大文件扫描配置的缓存与加载。

### 3.3 应用存储占用查询
- `AppStorageService.getAppStorageInfo`：
  - 通过原生 Android StorageStatsManager API 查询指定包名的应用本体、数据、缓存占用。
  - 支持超时处理与平台兼容性判断。

### 3.4 其它
- 支持空间统计数据的本地缓存与过期处理。
- UI 支持进度、错误提示、动态布局等。

## 4. 与其它模块区分
- 仅统计和分析存储空间分布，不涉及大文件、垃圾、重复文件的具体扫描与清理。

## 5. 主要相关文件
- `lib/ui/pages/storage_management_page.dart`：页面与交互逻辑
- `lib/ui/widgets/storage_management_card.dart`：入口卡片
- `lib/core/services/app_storage_service.dart`：应用存储查询

## 6. 参考实现点
- 总容量/剩余空间统计：`StorageManagementPage._loadStorageInfo`
- 分类文件统计：`StorageManagementPage._loadCategorySizes`
- 应用存储查询：`AppStorageService.getAppStorageInfo`

---

本说明 strictly based on 源码实现，未做主观推断。
