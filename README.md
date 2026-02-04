# EasyFile（易览文件）

易览文件是一个 Flutter 文件管理应用。代码层面包含：文件浏览/搜索/预览、快速访问与推荐卡片、存储管理（大文件/重复文件/垃圾文件等入口）、压缩包查看与解压、回收站、应用管理，以及带 PIN/生物识别的隐私空间。

> 本 README 以当前仓库代码为唯一事实来源：只描述已存在的页面/服务与明确的行为，不做规划性描述。

## 功能概览（已实现）

- 文件浏览：最近（Recent）、浏览（Browse）、收藏（Favorites，可配置开关）、新文件（New Files，可配置开关）、应用管理（App Management，可配置开关）等 Tab 形态的主页体验。
- 快速访问：主页快速访问区支持进入文件夹，并提供功能卡入口：压缩包管理、回收站、垃圾文件清理、安装包管理、应用管理、隐私空间。
- 文件预览：文件预览页支持图片/视频/PDF/文本等类型的预览与沉浸式浏览；当打开的是压缩包文件，会自动跳转到压缩包查看器。
- 压缩包：压缩包管理页/查看器页，支持列出内容与解压（底层为 FFI + Native 库实现，见“限制与已知问题”）。
- 存储管理：存储管理页包含分类大小统计（读取缓存后后台扫描更新）、并提供进入垃圾文件清理/大文件/重复文件等页面的入口；另有缓存管理页用于查看与清理多类缓存。
- 隐私空间：隐私空间服务包含 PIN 初始化/校验、生物识别校验、会话有效期管理；隐私空间主页用于查看/打开/移出/删除隐私文件。
- 隐私合规与埋点：启动时检查隐私政策同意状态；仅在用户同意后执行埋点系统的授权与正式初始化。

## 启动与运行流程（代码路径）

1. 应用入口在 [lib/main.dart](lib/main.dart)：初始化配置、全局服务与依赖注入，然后 `runApp(EasyFileApp)`。
2. 应用壳层在 [lib/app.dart](lib/app.dart)：
   - 注册生命周期监听，并在前后台切换时触发隐私会话管理与埋点事件。
   - 首次进入时优先请求存储相关权限，然后检查隐私政策同意状态；未同意会弹出隐私政策弹窗（不同意直接退出应用）。
   - 完成初始化后：根据进程内是否已展示过 Splash 决定展示启动页或直接进入主页（主页为 `FileBrowserPage`）。

## 代码结构（按目录）

- `lib/app.dart`：应用壳层、权限/隐私同意门禁、导航决策。
- `lib/ui/`：页面与组件（主页、存储管理、压缩包、回收站、隐私空间、设置等）。
- `lib/core/`：核心服务（权限、缓存、推荐、扫描、回收站、隐私、启动编排等）。
- `lib/presenter/`、`lib/viewmodel/`：Presenter + ViewModel 组合（如 `FilePresenter`/`FileViewModel`）。
- `lib/ffi/`：压缩包相关 FFI 绑定（libarchive / UnRAR / minizip 等）。
- `config/analytics_config.yaml`：埋点配置文件（由 AnalyticsConfig 加载）。

## 开发运行

```bash
flutter pub get
flutter run
```

说明：应用会在启动阶段请求存储相关权限；部分能力依赖 Android 原生接口/权限与 MethodChannel。

## 当前限制与已知问题（来自代码的明确约束）

- 压缩包能力包含明显的平台限制：FFI 动态库加载在非支持平台会抛 `UnsupportedError`（Android 依赖 `.so`，部分代码含 Windows 测试路径，但整体实现以 Android 为主）。
- 加密 7z 文件：`ArchiveService` 中存在“当前版本暂不支持（解压/预览）加密的 7z 文件”的明确提示与分支处理。
- 应用存储占用信息：`AppStorageService` 依赖 Android `StorageStatsManager`（Android 8.0+），不支持时会返回 `null`。
- 远程配置：`RemoteConfigStorage` 的 HTTP 拉取逻辑是 TODO，当前用模拟数据填充远程配置缓存。
- Firebase 埋点：`FirebaseAnalyticsService` 是 no-op 占位实现（initialize/logEvent 都是 TODO），用于兜底避免空指针；同时 `AnalyticsManager` 在未完成正式初始化时会丢弃事件。
- 推荐卡片文件数：推荐卡片读取文件数量时使用持久化缓存（`getFileCountFast`），缓存 miss 时文件数显示为 0（不会在卡片渲染阶段自动回退实时扫描）。

## 权限说明（与代码一致）

应用在启动阶段会检查并请求存储相关权限（见 `PermissionService` 与 `AppNavigator._requestStoragePermissionIfNeeded`）：

- 优先尝试 `MANAGE_EXTERNAL_STORAGE`（Android 11+ 的“所有文件访问权限”）。
- 若未获得完整权限，会请求基础存储权限；在 Android 13+ 场景下会额外请求照片/视频权限。

## 许可与开源状态

本项目为非开源代码仓库，当前没有开源计划，也不提供开源许可证授权声明。
