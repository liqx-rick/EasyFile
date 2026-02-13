# EasyFile 设置模块功能说明书（模版E）

## 1. 概述
本说明书基于 EasyFile 项目源码，系统梳理“设置”模块的全部功能实现，涵盖全局配置、页面/视图设置、主题设置、设置页面 UI 及相关持久化机制。所有内容均严格依据代码实现，无主观推断。

## 2. 主要实现文件
- lib/core/config/app_config.dart
- lib/core/services/page_settings_service.dart
- lib/core/services/theme_settings_service.dart
- lib/ui/pages/settings_page.dart

## 3. 功能结构与实现细节

### 3.1 全局配置（AppConfig）
- 单例模式，统一入口：`AppConfig.instance`
- 主要配置模块：
  - `build`：编译期配置（环境、版本等）
  - `feature`：功能开关（Feature Toggle），如新文件、回收站、开发者选项等
  - `fileScan`：文件扫描策略与阈值
  - `fileTypes`：支持的文件类型
  - `appScanner`：应用扫描相关配置
  - `duplicateFilesRec`：重复文件推荐算法参数
  - `cacheConfig`：缓存相关配置
- 持久化存储通过 `ConfigStorage`（默认 SharedPreferences），支持自定义存储实现
- 初始化方法：`initialize({ConfigStorage? storage})`，需在 main() 早期调用
- 支持重置所有配置为默认值（仅用于单元测试）：`resetToDefaults()`

### 3.2 页面/视图设置（PageSettingsService）
- 单例模式，入口：`PageSettingsService()`
- 管理各页面的视图模式（列表/网格）、排序方式、分组状态等
- 用户自定义设置以 `Map<PageId, PageSettings>` 持久化，key 为页面 ID
- 主要方法：
  - `initialize()`：从 SharedPreferences 加载设置，支持版本迁移
  - `getPageSettings(PageId)`：获取指定页面的实际设置（用户设置优先，默认值兜底）
  - `setViewMode(PageId, ViewMode)`、`setSortType(PageId, SortType)`、`setSortAscending(PageId, bool)`、`setGroupEnabled(PageId, bool)`：分别设置视图、排序、分组
  - `toggleViewMode(PageId)`、`toggleSortDirection(PageId)`、`toggleGroupEnabled(PageId)`：切换相关设置
  - `resetToDefaults()`、`resetPage(PageId)`、`resetRecommendSettings()`：重置全部/单页/推荐页设置
  - `getGridShowFileInfo(PageId)`、`setGridShowFileInfo(bool)`：网格模式下是否显示文件信息
- 所有设置变更均持久化到 SharedPreferences

### 3.3 主题设置（ThemeSettingsService）
- 单例模式，入口：`ThemeSettingsService()`
- 管理应用主题（浅色、深色、跟随系统）
- 主要方法：
  - `initialize()`：从 SharedPreferences 加载主题
  - `setThemeMode(ThemeMode)`：设置主题并持久化
  - `toggleThemeMode()`：循环切换主题（浅→深→系统→浅）
- 主题设置变更通过 `notifyListeners()` 通知 UI 层

### 3.4 设置页面 UI（SettingsPage）
- 入口 Widget：`SettingsPage`（lib/ui/pages/settings_page.dart）
- 主要分区：
  - 显示偏好：主题切换、视图/排序重置、文件显示、隐藏空文件夹
  - 存储与缓存管理：缓存清理、回收站设置（按功能开关显示）
  - 功能设置：新文件模块设置（按功能开关显示）
  - 开发者选项：推荐阈值、重复文件扫描、系统回收站诊断、性能测试入口（按功能开关显示）
- 典型交互：
  - 主题切换：弹窗选择，调用 `FilePresenter.setThemeMode()` 持久化
  - 视图/排序重置：弹窗确认，调用 `PageSettingsService.resetToDefaults()`
  - 文件显示设置、回收站设置、新文件设置等均通过跳转子页面实现
  - 推荐阈值调整、重置推荐等通过弹窗与 SnackBar 反馈
- 依赖服务：`PageSettingsService`、`FileDisplaySettingsService`、`AppConfig`、`CacheManagerService`、`RecommendationService` 等

## 4. 持久化与数据流
- 所有用户设置均通过 SharedPreferences 持久化（通过各 Service 封装）
- 设置变更通过 `notifyListeners()` 机制驱动 UI 实时刷新
- 主题、页面设置等均支持初始化加载与版本迁移

## 5. 典型调用链举例
- 主题切换：SettingsPage → FilePresenter.setThemeMode() → ThemeSettingsService.setThemeMode() → SharedPreferences
- 视图/排序重置：SettingsPage → PageSettingsService.resetToDefaults() → SharedPreferences
- 推荐阈值调整：SettingsPage → AppConfig.instance.fileScan.setRecommendationFileCountThreshold() → SharedPreferences

## 6. 其它说明
- 所有设置项的显示与否均严格受功能开关（FeatureConfig）控制
- 设置页面 UI 采用分区与条件渲染，确保不同功能模块的可插拔性
- 代码中所有设置项均有注释说明，便于追溯

---

> 本文档内容全部基于 EasyFile 源码实现，未做任何主观推断。
