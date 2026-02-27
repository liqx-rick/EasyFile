# 三屏智能架构方案（负一屏 Assistant / 主页 / +1屏 Tools）

版本：v1.0
作者：产品/工程
日期：2026-02-26

---

## 目的
将应用从“被动文件管理器”升级为“智能文件助手”，满足应用商店审核对交互设计与功能深度的要求（参考华为审核指南3.5），通过主动任务推荐、数据可视化与场景化工具集，扩展使用场景并提升用户体验。

---

## 概要（1句）
引入应用级三屏交互（左：智能助手 / 中：文件浏览主页 / 右：专业工具集），每屏为完整独立页面，通过左右滑动切换；首版本实现基础任务卡与工具分组，后续分阶段完善可视化报告与智能相册。

---

## 页面结构

- MainContainerPage (容器)
  - PageView (3 页)
    - AssistantPage（-1屏，智能助手）
    - FileBrowserPage（0屏，现有主页，保持原样）
    - ToolsPage（+1屏，专业工具集）
  - 全局页面指示器（底部中央）
  - 首次使用滑动引导（首次运行显示）

---

## AssistantPage（负一屏） - 基础版

目标：主动发现并呈现用户需要处理的文件相关任务，提供一键进入对应功能页的快速入口。

### UI 布局（纵向滚动）：
```
┌────────────────────────────────────┐
│ AppBar: "智能助手" [刷新]           │
├────────────────────────────────────┤
│ 📋 待办任务 (2-5个动态卡片)         │
│ ┌────────────────────────────────┐ │
│ │ 🧹 重复文件建议                 │ │
│ │ 发现 156 个重复文件             │ │
│ │ 可节省 2.3GB                   │ │
│ │ [立即清理] [忽略]              │ │
│ └────────────────────────────────┘ │
│                                    │
│ ⚡ 快速操作 (3x2网格)              │
│ [大文件] [重复] [垃圾]             │
│ [缓存]   [截图] [相册]             │
│                                    │
│ 📊 简要统计                        │
│ 总存储: 128GB | 可用: 23GB         │
│ 本周新增: 458 个文件               │
│                                    │
│ 📝 最近活动 (简化版)                │
│ - 清理了 234 MB 垃圾文件           │
│ - 移入隐私空间 3 个文件             │
└────────────────────────────────────┘
```

### 模块详解：

**1. 智能任务卡片**（动态生成，按优先级显示2-5个）
- **重复文件提醒**：调取 `EnhancedDuplicateFileScanService` 缓存结果，显示重复组数+可节省空间
- **大文件提醒**：调取 `LargeFileService` 缓存，显示超过阈值的文件数（如100MB+）
- **垃圾文件提醒**：调取 `JunkFileService` 扫描结果，显示APK、临时文件、空文件夹总数+大小
- **应用缓存提醒**：调取 `AppManagementService`，显示可清理的应用缓存总大小
- **截图整理提醒**（新增）：扫描图片分类，识别文件名包含"screenshot"/"截图"或路径为 `/Pictures/Screenshots` 的图片，显示本周新增截图数

**2. 快速操作网格**（6 个常用工具入口，2x3或3x2布局）
- 大文件 → `LargeFilesPage`
- 重复 → `DuplicateFilesPage`
- 垃圾 → `JunkFilesPage`
- 缓存 → `AppManagementPage`（应用管理）
- 截图整理 → `CategoryFilePage`（图片分类，带截图筛选）
- 相册归档 → 智能相册（第二阶段实现，第一版跳转到图片分类）

**3. 简要统计**
- 总存储 / 可用空间（`disk_space_plus`）
- 本周新增文件数（基于 `NewFilesService` 或文件修改时间统计）

**4. 最近活动时间线**（第一版简化为操作摘要，3-5条）
- 从 `AppTrashManager` 获取最近清理记录
- 从 `PrivacyService` 获取最近隐私操作
- 从操作日志或统计中获取其他活动

### 验收标准（基础版）：
- ✅ 启动后自动触发一次后台扫描（利用现有缓存优先，超时则后台刷新）
- ✅ 至少生成 1 个任务卡（若设备上有可处理项）
- ✅ 每张任务卡支持跳转到对应页面并带上下文（例如：重复文件页自动触发扫描）
- ✅ 快速操作网格 6 个入口均可正常跳转
- ✅ 统计数字准确（或标注"正在计算"）
- ✅ 空状态显示友好提示"正在扫描..."而非"暂无任务"

---

## FileBrowserPage（主页，0屏） - 保持现状

**核心原则**：FileBrowserPage 本身保持不变，所有改动在 MainContainerPage 层面。

**调整方式**（两种可选方案）：

### 方案A：仅靠滑动发现（推荐，最小改动）
- FileBrowserPage 完全保持现状，不增加任何入口卡片
- 依赖底部页面指示器和首次滑动引导让用户发现左右两屏
- 优点：零侵入，FileBrowserPage 无需修改
- 缺点：依赖用户主动滑动探索

### 方案B：在快速推荐区添加提示卡片（可选）
- 在 `QuickAccessSection` 的第二屏（当前已有的副屏）底部添加两个提示卡片：
  ```
  [← 智能助手]  [专业工具 →]
  ```
- 点击后通过 `MainContainerPage` 的接口切换到对应屏幕
- 优点：引导更明确
- 缺点：需要修改 QuickAccessSection 并暴露页面切换接口

**推荐实施**：第一版采用方案A，第二版根据用户反馈考虑方案B。

**默认行为**：
- 应用启动默认停在主页（PageView initialPage = 1）
- 首次启动显示滑动引导（半透明覆盖层+箭头动画+文字提示）

---

## ToolsPage（+1屏） - 基础版

目标：把所有深度功能以场景化分组展现，便于用户发现并进入专业功能。

### UI 布局（纵向滚动）：
```
┌────────────────────────────────────┐
│ AppBar: "专业工具" [搜索]           │
├────────────────────────────────────┤
│                                    │
│ 🔧 存储优化                        │
│ ┌────────────────────────────────┐ │
│ │ [压缩包管理]  [回收站]          │ │
│ │  12个压缩包    3个文件          │ │
│ │                                 │ │
│ │ [垃圾清理]    [安装包管理]      │ │
│ │  可清理2.3GB   6个APK          │ │
│ └────────────────────────────────┘ │
│                                    │
│ 🔐 安全与隐私                      │
│ ┌────────────────────────────────┐ │
│ │ [隐私空间]    [应用管理]        │ │
│ │  8个文件       45个应用         │ │
│ └────────────────────────────────┘ │
│                                    │
│ ✨ 智能整理                        │
│ ┌────────────────────────────────┐ │
│ │ [智能相册]    [文件集合]        │ │
│ │  敬请期待      敬请期待         │ │
│ │                                 │ │
│ │ [文件笔记]    [批量工具]        │ │
│ │  敬请期待      敬请期待         │ │
│ └────────────────────────────────┘ │
│                                    │
│ 📦 更多工具（计划中）               │
│ - 文件同步                         │
│ - 网络传输                         │
│ - 格式转换                         │
└────────────────────────────────────┘
```

### 分组与工具详解：

**分组1：存储优化**（4个工具，2x2布局）
- **压缩包管理**：显示设备上压缩包总数，点击跳转 `ArchiveManagementPage`
- **回收站**：显示回收站文件数，点击跳转 `TrashPage`
- **垃圾清理**：显示可清理的垃圾总大小，点击跳转 `JunkFilesPage`
- **安装包管理**：显示APK文件数，点击跳转 `ApkManagementPage`

**分组2：安全与隐私**（2个工具，1x2布局）
- **隐私空间**：显示隐私文件数，点击跳转 `PrivacyAuthPage`（需验证）
- **应用管理**：显示已安装应用数，点击跳转 `AppManagementPage`

**分组3：智能整理**（4个工具，2x2布局，第一版占位）
- **智能相册**：第二阶段实现，第一版显示"敬请期待"或跳转到图片分类
- **文件集合**：未来功能，第一版显示"敬请期待"（禁用状态）
- **文件笔记**：未来功能，第一版显示"敬请期待"（禁用状态）
- **批量工具**：第一版可跳转到任意文件浏览页并自动进入编辑模式

### 统计数字获取：
- 压缩包数：实时扫描或从 `ArchiveManagementPage` 缓存读取
- 回收站文件数：`AppTrashManager.getStatistics()`
- 垃圾文件大小：`JunkFileCacheManager` 缓存或快速估算
- APK数量：扫描或从缓存读取
- 隐私空间文件数：`PrivacyService.getPrivateFiles().length`
- 应用数：`AppManagementService` 缓存

### 验收标准（基础版）：
- ✅ 页面为完整独立页面，采用纵向滚动布局
- ✅ 三个分组按场景清晰划分，视觉层次分明
- ✅ 每个工具显示关键统计数字（第一版可异步加载，显示骨架屏或0）
- ✅ 已实现功能的工具可正常跳转到目标页面
- ✅ 未实现功能显示"敬请期待"并禁用点击（或显示Toast提示）
- ✅ 工具卡片设计与助手页卡片风格统一

---

## 数据来源与复用

**现有服务复用**：
- `EnhancedDuplicateFileScanService`：重复文件扫描与缓存
- `LargeFileService` + `LargeFileCacheManager`：大文件扫描与缓存
- `JunkFileService` + `JunkFileCacheManager`：垃圾文件扫描与缓存
- `AppManagementService` + `AppListCacheManager`：应用信息与缓存
- `StorageStatService`：存储空间统计
- `RecommendationService`：推荐卡片生成
- `AppTrashManager`：回收站管理与统计
- `PrivacyService`：隐私空间管理
- `NewFilesService`：新文件检测
- `disk_space_plus` 插件：存储空间获取

**新增组件**（需实现）：
- `SmartTaskGenerator`：智能任务生成器
  - 输入：各服务的扫描结果/缓存
  - 输出：优先级排序的 `TaskCard` 列表
  - 任务优先级算法：按影响大小（可节省空间）和紧急度排序
- `FileReportGenerator`（第二阶段）：文件报告生成器
  - 持久化每日存储快照（用于趋势图）
  - 聚合统计数据生成报告
- `SmartAlbumService`（第二阶段）：智能相册服务
  - EXIF 地理信息提取
  - 图片规则识别（截图、表情包、证件照）
  - 时间分组算法

**数据识别规则**：
- **截图识别**：
  - 文件名正则：`/(screenshot|截图|screenshot_|IMG-\d{8}-WA\d{4})/i`
  - 路径匹配：`/Pictures/Screenshots/`、`/DCIM/Screenshots/`
  - Android系统截图路径：`/Pictures/Screenshots`
- **表情包识别**：
  - 文件大小：< 100KB
  - 图片尺寸：宽高均 < 500px
  - 文件名包含：`sticker`、`emoji`、`表情`
- **证件照识别**：
  - 宽高比接近 1:1（头像）或 3:4（标准证件照）
  - 文件名包含：`证件照`、`ID_photo`、`passport`

---

## 首次引导 & 截图/文案策略

### 首次滑动引导设计：

**触发时机**：应用首次启动且从未显示过引导（通过 SharedPreferences 标记）

**视觉设计**：
```
┌────────────────────────────────────┐
│                                    │
│                                    │
│         [主页正常内容]              │
│                                    │
│                                    │
│  ◄─────                    ─────► │
│  智能助手在这里        专业工具在这里 │
│  (动画箭头)             (动画箭头)  │
│                                    │
│         [知道了] [跳过]             │
│                                    │
└────────────────────────────────────┘
```

**实现方式**：
- 半透明黑色遮罩层（opacity: 0.7）
- 双向箭头使用 Lottie 动画或自定义动画
- 文字提示简洁明了（不超过10个字/方向）
- 支持点击遮罩关闭或点击"跳过"
- 点击"知道了"后自动左滑一次演示，然后回到主页

**持久化标记**：
```dart
SharedPreferences.setBool('three_screen_guidance_shown', true)
```

### 应用商店截图策略：

**截图顺序**（5-6张）：
1. **智能助手页**（最重要）
   - 展示 2-3 个智能任务卡片
   - 标注："主动发现优化机会"
   - 确保任务数据可见（不是空状态）

2. **文件报告可视化**（第二阶段，第一版用设计稿）
   - 存储趋势图 + 分类占比饼图
   - 标注："数据洞察，一目了然"

3. **专业工具页**
   - 展示三个分组（存储优化、安全隐私、智能整理）
   - 标注："场景化工具集，专业高效"

4. **压缩包免解压预览**或**隐私空间**
   - 展示技术深度
   - 标注："技术创新，极致体验"

5. **主页**（推荐+分类）
   - 保留传统文件管理展示
   - 标注："智能推荐，快速访问"

6. **三屏架构示意图**（可选）
   - 用设计图展示三屏切换关系
   - 标注："三屏智能架构"

### 上架文案策略：

**应用名称**：易览文件 - 智能文件助手

**一句话简介**：
> 三屏智能架构，主动优化建议，让文件管理更智能

**详细描述开头**（前100字最关键）：
```
易览文件采用创新的三屏智能架构，不仅是文件管理器，更是您的智能文件助手。

🎯 智能助手（左屏）：主动发现重复文件、大文件、垃圾文件，一键优化
📊 数据洞察（左屏）：可视化报告、存储趋势、使用习惯分析
🔧 专业工具（右屏）：场景化工具集，压缩包、隐私、批量处理样样精通
📱 快速访问（主页）：智能推荐、分类管理、收藏最近一应俱全

【技术创新】
✓ 三阶段重复检测算法（大小→哈希→MD5），百万文件秒级完成
✓ FFI 原生性能，C/C++ 压缩算法，100MB 压缩包免解压预览
✓ 增量扫描技术，二次扫描速度提升 10 倍
✓ 智能推荐算法，基于访问频率和时间权重个性化推荐
```

**应用审核说明**（补充材料）：
```markdown
【创新亮点总结】

1. 三屏智能架构（交互创新）
   - 左屏：智能助手，主动推送优化建议
   - 中屏：文件管理，保留传统操作
   - 右屏：专业工具，场景化分组

2. 使用场景覆盖（非单一场景）
   ✓ 日常管理：文件浏览、分类查找、快速访问
   ✓ 智能优化：重复清理、垃圾清理、大文件管理
   ✓ 数据洞察：存储趋势、使用分析、清理统计
   ✓ 专业处理：压缩管理、隐私保护、批量操作
   ✓ 内容整理：智能相册、文件归档、笔记标注

3. 与普通文件管理器差异
   - 普通管理器：被动浏览 + 手动操作
   - 易览文件：主动推荐 + 智能优化 + 数据洞察
```

---

## 分阶段实施计划（概要）

### 第一阶段（2-3 周） - 必做（可提交审核）
1. 创建 `MainContainerPage` 并将 `FileBrowserPage` 嵌入中屏（3 天）
2. `AssistantPage` 基础版：智能任务卡 + 快速操作（6 天）
3. `ToolsPage` 基础版：分组布局 + 现有功能入口（4 天）
4. 页面指示器、首次滑动引导（2 天）
5. 准备应用商店必需素材（截图、文案、审核说明）（3 天）

### 第二阶段（1-2 周） - 强化（建议）

**6. AssistantPage 增强：可视化文件报告**（5 天）

在助手页的简要统计下方添加完整的文件报告卡片，支持点击查看详情页。

**文件报告内容**：
- **存储趋势图**（折线图）：最近7天/30天的存储空间变化曲线
  - 数据来源：每日记录总存储和可用空间（需新增持久化）
  - 图表库：使用 `fl_chart` 包
- **清理统计**（卡片展示）：
  - 本周/本月清理的垃圾文件大小
  - 节省空间排行（重复文件、垃圾清理、应用缓存）
  - 数据来源：`AppTrashManager` 统计 + 操作日志
- **文件增长分析**（柱状图）：
  - 本周/本月新增文件数量和大小
  - 按文件类型分类（图片、视频、文档等）
  - 数据来源：`NewFilesService` + 文件类型统计
- **使用习惯分析**（列表展示）：
  - 最常访问的分类（基于 `RecentFilesLocalSource`）
  - 最常访问的应用文件（基于访问频率）
  - 最活跃时间段（可选）
- **分类占比**（饼图）：
  - 图片、视频、文档、音频、其他的存储占比
  - 数据来源：`StorageStatService` 或 `FileTypeAnalyzer`

**实现方式**：
- 主报告卡片在助手页显示摘要
- 点击"查看完整报告"跳转到独立的 `FileReportPage`
- 报告页面支持切换时间范围（7天/30天/90天）
- 数据异步加载，显示骨架屏

**7. 智能相册基础实现**（5 天）

在工具页"智能整理"分组中实现智能相册功能：

**智能相册类型**：
- **时间相册**：按月/季度自动分组（基于文件修改时间）
- **地点相册**：读取图片EXIF地理信息自动分组（使用 `exif` 包）
- **自动识别相册**：
  - 截图相册：文件名包含 "screenshot"/"截图" 或路径匹配
  - 表情包相册：小尺寸图片（<100KB 且尺寸<500x500）
  - 证件照相册：特定尺寸比例（1:1 或 3:4）

**实现方式**：
- 创建 `SmartAlbumPage`，列出所有智能相册类型
- 点击相册类型进入相册详情（复用 `CategoryFilePage` 架构）
- 第一版支持时间相册和自动识别相册
- 地点相册在第二版根据EXIF数据完整度决定是否实现

**8. 测试、性能调优与QA**（4 天）
- 三屏滑动性能测试（确保流畅60fps）
- 各页面跳转和数据加载测试
- 边界情况测试（无数据、大量数据、权限拒绝等）
- 内存占用优化（避免三屏同时加载大量数据）
- 用户体验测试（首次引导、滑动发现等）

---

## 验收准则（提交审核前）

- 三屏可滑动、每屏为独立页面，且所有跳转正常
- AssistantPage 能根据扫描产出至少 1 条任务并支持跳转
- ToolsPage 中各工具可跳转、统计数字正确或有占位符说明
- 首次引导在首次启动显示且可跳过
- 应用截图、上架文案已更新并突出创新点

---

## 风险与缓解

- 风险：审核官不滑动到负一/正一屏导致错判
  - 缓解：首页显著提示“左滑查看智能助手 / 右滑查看专业工具”，并将关键截图放在应用商店首张
- 风险：设备上无扫描数据导致助手空白
  - 缓解：首次启动即触发快速扫描并显示示例/占位式内容（明确标注“正在扫描/示例数据”）

---

## 参考（代码位置）

**现有代码**：
- 主页入口与推荐卡片： `lib/ui/widgets/quick_access_section.dart`
- 文件浏览主页： `lib/ui/pages/file_browser_page.dart`
- 重复文件： `lib/core/services/enhanced_duplicate_file_scan_service.dart`
- 垃圾文件： `lib/core/services/junk_file_service.dart`
- 大文件： `lib/ui/pages/large_files_page.dart`
- 存储统计： `lib/ui/pages/storage_management_page.dart`
- 隐私空间： `lib/core/services/privacy_service.dart`
- 应用管理： `lib/core/services/app_management_service.dart`
- 回收站： `lib/core/services/app_trash_manager.dart`
- 新文件： `lib/core/services/new_files_service.dart`

**需新建文件**：
- `lib/ui/pages/main_container_page.dart` - 三屏容器
- `lib/ui/pages/assistant_page.dart` - 智能助手页
- `lib/ui/pages/tools_page.dart` - 专业工具页
- `lib/core/services/smart_task_generator.dart` - 智能任务生成器
- `lib/data/models/task_card.dart` - 任务卡片数据模型
- `lib/ui/widgets/task_card_widget.dart` - 任务卡片组件
- `lib/ui/widgets/tool_tile_widget.dart` - 工具卡片组件
- `lib/ui/widgets/swipe_guidance_overlay.dart` - 滑动引导遮罩
- `lib/ui/pages/file_report_page.dart` - 文件报告页（第二阶段）
- `lib/core/services/file_report_generator.dart` - 报告生成器（第二阶段）
- `lib/ui/pages/smart_album_page.dart` - 智能相册页（第二阶段）
- `lib/core/services/smart_album_service.dart` - 智能相册服务（第二阶段）

**路由调整**：
- `lib/main.dart` 或 `lib/app.dart`：将初始页面从 `FileBrowserPage` 改为 `MainContainerPage`

---

## 技术实现要点

### MainContainerPage 架构
```dart
class MainContainerPage extends StatefulWidget {
  const MainContainerPage({Key? key}) : super(key: key);

  @override
  State<MainContainerPage> createState() => _MainContainerPageState();
}

class _MainContainerPageState extends State<MainContainerPage> {
  late PageController _pageController;
  int _currentPage = 1; // 默认停在主页
  bool _showGuidance = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
    _checkFirstRun();
  }

  Future<void> _checkFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('three_screen_guidance_shown') ?? false;
    if (!shown) {
      setState(() => _showGuidance = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 三屏 PageView
          PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
              _onPageChanged(index);
            },
            children: const [
              AssistantPage(),      // -1屏
              FileBrowserPage(),    // 0屏
              ToolsPage(),          // +1屏
            ],
          ),

          // 页面指示器
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: _buildPageIndicator(),
          ),

          // 首次引导
          if (_showGuidance)
            SwipeGuidanceOverlay(
              onDismiss: () => _dismissGuidance(),
            ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: _currentPage == index ? 24 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: _currentPage == index
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.withOpacity(0.3),
          ),
        );
      }),
    );
  }

  void _onPageChanged(int index) {
    // 埋点：记录页面切换
    AnalyticsHelper.logScreenSwitch(
      from: _getPageName(_currentPage),
      to: _getPageName(index),
    );
  }

  String _getPageName(int index) {
    switch (index) {
      case 0: return 'assistant';
      case 1: return 'home';
      case 2: return 'tools';
      default: return 'unknown';
    }
  }

  Future<void> _dismissGuidance() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('three_screen_guidance_shown', true);
    setState(() => _showGuidance = false);
  }
}
```

### SmartTaskGenerator 核心逻辑
```dart
class SmartTaskGenerator {
  Future<List<TaskCard>> generateTasks() async {
    final tasks = <TaskCard>[];

    // 1. 检查重复文件（优先级：高）
    final duplicateCache = await _loadDuplicateCache();
    if (duplicateCache != null && duplicateCache.groups.isNotEmpty) {
      final savableSize = _calculateSavableSize(duplicateCache.groups);
      if (savableSize > 50 * 1024 * 1024) { // > 50MB
        tasks.add(TaskCard(
          type: TaskType.duplicateFiles,
          priority: _calculatePriority(savableSize),
          title: '发现 ${duplicateCache.groups.length} 组重复文件',
          subtitle: '可节省 ${FileUtils.formatSize(savableSize)}',
          action: () => _navigateToDuplicateFiles(),
          dismissible: true,
        ));
      }
    }

    // 2. 检查大文件
    // 3. 检查垃圾文件
    // 4. 检查应用缓存
    // 5. 检查截图

    // 按优先级排序
    tasks.sort((a, b) => b.priority.compareTo(a.priority));

    // 最多返回 5 个任务
    return tasks.take(5).toList();
  }

  int _calculatePriority(int size) {
    // 优先级算法：基于可节省空间大小
    if (size > 1024 * 1024 * 1024) return 5; // > 1GB: 最高
    if (size > 500 * 1024 * 1024) return 4;   // > 500MB
    if (size > 100 * 1024 * 1024) return 3;   // > 100MB
    if (size > 50 * 1024 * 1024) return 2;    // > 50MB
    return 1;
  }
}
```

### 数据加载策略
- **AssistantPage**：
  - 优先从缓存加载（立即显示）
  - 后台异步刷新扫描结果
  - 使用 `FutureBuilder` 或 `StreamBuilder` 管理状态

- **ToolsPage**：
  - 统计数字异步加载，显示骨架屏
  - 使用 `FutureBuilder` 包装每个统计数字
  - 缓存统计结果（5分钟有效期）

### 性能优化
- PageView 使用 `PageStorageBucket` 保持页面状态
- 每屏使用 `AutomaticKeepAliveClientMixin` 避免重建
- 图表渲染使用 `RepaintBoundary` 隔离
- 大列表使用 `ListView.builder` 懒加载

---


 以下内容为手动添加 chat里的关键信息：
 ------------------------------------------------------------------------------
 [-1屏] 智能文件助手页面（AssistantPage）
整屏布局（完整独立页面）：
┌────────────────────────────────────────┐
│ AppBar: "智能助手" [设置]               │
├────────────────────────────────────────┤
│                                        │
│  🎯 待办任务 (2-5个动态卡片)            │
│  ┌──────────────────────────────────┐ │
│  │ 🧹 重复文件建议                   │ │
│  │ 发现 156 个重复文件，可节省 2.3GB  │ │
│  │ [立即查理] [忽略]                 │ │
│  └──────────────────────────────────┘ │
│                                        │
│  ┌──────────────────────────────────┐ │
│  │ 📸 截图整理建议                   │ │
│  │ 本周新增 45 张截图                │ │
│  │ [查看详情] [稍后]                 │ │
│  └──────────────────────────────────┘ │
│                                        │
│  📊 我的文件报告                       │
│  ┌──────────────────────────────────┐ │
│  │ 本月数据总览                      │ │
│  │ ├─ 新增文件: 458 个               │ │
│  │ ├─ 已清理: 3.2 GB                │ │
│  │ ├─ 最活跃: 图片分类               │ │
│  │ └─ [查看完整报告] →               │ │
│  └──────────────────────────────────┘ │
│                                        │
│  ⚡ 快速操作                           │
│  [大文件] [重复] [垃圾]               │
│  [缓存]   [截图] [相册]               │
│                                        │
│  📚 最近活动                           │
│  - 清理了 234 MB 垃圾文件              │
│  - 整理了 12 个重复文件                │
│  - 移入隐私空间 3 个文件               │
│                                        │
│                                        │
│  ← 向右滑动返回主页                    │
└────────────────────────────────────────┘
       ● ○ ○  (页面指示器)




四、审核说明文档建议
提交审核时附加说明（重点强调）：

 【应用创新亮点】

1. 三屏智能架构
   - 左屏：智能助手（主动服务、数据洞察）
   - 中屏：文件管理（快速访问、个性推荐）
   - 右屏：专业工具（深度功能、场景分组）

2. 智能化升级
   - 主动发现优化机会（重复文件、大文件、垃圾文件）
   - 智能任务推荐（基于用户使用习惯）
   - 数据可视化报告（存储趋势、使用分析）

3. 场景全覆盖
   - 日常管理：快速浏览、分类查找
   - 存储优化：智能清理、空间分析
   - 数据洞察：趋势报告、习惯分析
   - 专业处理：压缩管理、隐私保护、批量操作
   - 内容整理：智能相册、文件归档

4. 交互创新
   - 三屏滑动导航（参考主流App设计）
   - 智能任务卡片（主动交互）
   - 可视化数据展示（直观易懂）

【与普通文件管理器的差异】
- 普通管理器：被动浏览 + 手动操作
- 易览文件：主动推荐 + 智能优化 + 数据洞察 + 场景化管理

【技术深度体现】
- FFI原生性能（C/C++压缩算法）
- 三阶段重复检测算法（大小→哈希→MD5）
- 增量扫描技术（10倍速度提升）
- 智能推荐算法（基于访问频率和时间权重）
