# 文件预览功能规格说明

生成时间：2026-02-10

基于对代码库的 Template E 完整流程分析，本文件汇总应用内文件预览功能的功能说明、实现细节、交互设计、性能与已知限制，便于产品、测试与开发参考。

**目录**
- 功能概述
- 支持的文件类型与预览能力
- 用户交互设计
- 技术实现要点与代码位置
- 性能优化与缓存策略
- 已知限制与兼容性
- 参考文件

## 功能概述
应用内置的文件预览系统支持在应用内直接查看多种文件类型，无需跳转到第三方应用。预览功能采用沉浸式全屏设计，支持滑动切换多个文件，并集成了文件操作快捷入口。

## 支持的文件类型与能力

1. 图片（完整支持）
   - 支持格式：jpg/jpeg, png, gif, bmp, webp 等
   - 特性：InteractiveViewer 缩放（0.5x–4.0x）、平移、黑色背景、打印
   - 代码位置：[lib/ui/pages/file_preview_page.dart](lib/ui/pages/file_preview_page.dart#L1387)

2. 视频（完整支持）
   - 支持格式：mp4、mov、avi、mkv、webm 等
   - 特性：播放/暂停、进度条、倍速、全屏、字幕（若存在）
   - 代码位置：`VideoPlayerWidget`（见 `lib/ui/widgets/video_player_widget.dart`）

3. 音频（完整支持）
   - 支持格式：mp3、wav、aac、flac、ogg、m4a等
   - 特性：后台播放、通知栏和锁屏控制、播放列表
   - 代码位置：`BackgroundAudioPlayerWidget`（见 `lib/ui/widgets/background_audio_player_widget.dart`）

4. PDF（完整支持）
   - 引擎：`pdfx`，垂直滚动、缩放、页码显示、打印
   - 错误处理：损坏或权限问题提示并提供“用其他应用打开”备选
   - 代码位置：[lib/ui/pages/file_preview_page.dart](lib/ui/pages/file_preview_page.dart#L1189)

5. 文本（完整支持）
   - 支持格式：txt, log, md, json, xml, csv, html 等
   - 特性：编码自动检测（UTF-8/UTF-16/GBK 推断）、可滚动查看、打印
   - 代码位置：[lib/ui/pages/file_preview_page.dart](lib/ui/pages/file_preview_page.dart#L1054)

6. Office 文档（信息预览）
   - 不渲染内容，仅展示文件信息与图标，并提供“用其他应用打开”入口

7. 压缩包（列表与单文件预览）
   - 支持格式：zip, rar, 7z, tar(.gz/.bz2/.xz) 等
   - 特性：免解压查看目录、进入子目录、单文件临时解压预览（有大小限制）、密码检测提示
   - 缓存与大小限制：单文件上限 (配置项 `archivePreviewMaxFileSizeMB`，默认示例 200MB)，整体缓存上限 (配置项 `archivePreviewCacheSizeMB`)
   - 代码位置：[lib/ui/pages/archive_viewer_page.dart](lib/ui/pages/archive_viewer_page.dart) + [lib/core/services/archive_preview_cache_manager.dart](lib/core/services/archive_preview_cache_manager.dart)

8. APK 包
   - 不在预览中渲染，显示提示并提供跳转到安装包管理页面

## 用户交互设计

- 沉浸式全屏（SystemUiMode.immersive）：打开预览时隐藏系统栏，提供3秒后自动隐藏/点击切换显示的UI逻辑。
- 多文件滑动切换：当 `fileList` 被传入时启用 `PageView`，支持左右滑动并带页码指示器（自动淡出以节省渲染）。
- AppBar 和操作按钮：非只读模式下显示打印、分享、收藏和更多操作菜单（详情/重命名/移动/复制/删除）。操作成功后通过 `_fileModified` 标记并在返回时触发父页面刷新。

## 技术实现要点（摘录）

- 预览路由：`FilePreviewPage`（主入口），单文件或 `PageView` 多文件模式。[lib/ui/pages/file_preview_page.dart](lib/ui/pages/file_preview_page.dart)
- 类型判断：使用 `FileUtils` 中的类型判断（例如 `isImageFile`, `isVideoFile`, `isPdfFile`）来决定渲染组件。[lib/utils/file_utils.dart](lib/utils/file_utils.dart)
- 压缩包单文件预览：由 `ArchivePreviewCacheManager.extractForPreview()` 提取并缓存单个文件到临时缓存目录，使用 MD5(archivePath) 作为缓存分区。
  参考：[lib/core/services/archive_preview_cache_manager.dart](lib/core/services/archive_preview_cache_manager.dart#L1)
- 文本编码检测：BOM 检查 → UTF-8 解码尝试 → GBK 解码尝试 → 字节不可打印比例阈值（5%）判定。
  参考：[lib/ui/pages/file_preview_page.dart](lib/ui/pages/file_preview_page.dart#L1054-L1088)

## 性能优化与缓存策略

- 图片缓存：全局 ImageCache 配置（条数与內存上限由 `main.dart` 配置，示例：最多 500 张、200MB）。
- 压缩包预览缓存：按压缩包哈希分目录存储，元数据文件记录创建时间，超出阈值按 LRU 淘汰。
- PDF 异步打开：使用 `PdfDocument.openFile()` 异步加载并将 `PdfController` 包装为 Future，避免阻塞 UI。
- 递归搜索与加载：递归操作（如压缩包条目提取、文件夹递归搜索）均有深度/大小保护（例如递归深度 3、提取大文件显示进度与确认）。

## 已知限制与兼容性

1. 加密或受保护的 PDF 文件：当前不支持在内置查看器中输入密码来解密（提供“用其他应用打开”作为回退）。
2. RAR 5.x 及以上：原生解压库可能不支持最新 RAR 版本，导致无法读取某些压缩包条目。详见 `ArchiveService` 实现。
3. Office 文档内容渲染：不支持 Word/Excel/PPT 的原生渲染。
4. 大文件限制：为保证内存与响应性，单个压缩包内文件预览有上限（配置项 `archivePreviewMaxFileSizeMB`）；图片缓存与总体临时缓存也受限于配置。
5. 搜索与索引：预览与搜索功能依赖已加载的文件列表或缓存，应用中并未实现全盘索引以支持即时全局检索。

## 建议与改进点（短期优先级）

- 支持加密PDF密码输入以提升文档预览兼容性。
- 提供可配置的压缩包临时预览大小阈值和缓存清理策略界面。
- 为常见大格式（如大型 PDFs、长视频）增加预热/分页加载优化。
- 在可能场景下引入轻量级索引（或后台索引任务）以改善全盘搜索与预览触发性能。

## 参考文件（代码定位）

- `lib/ui/pages/file_preview_page.dart` - 主预览实现（图片/视频/音频/PDF/文本与沉浸式交互）
- `lib/ui/pages/archive_viewer_page.dart` - 压缩包内容列表示例与单文件预览触发
- `lib/core/services/archive_preview_cache_manager.dart` - 压缩包单文件解压缓存管理
- `lib/ui/widgets/video_player_widget.dart` - 视频播放封装
- `lib/ui/widgets/background_audio_player_widget.dart` - 音频播放封装

---

如需将此文档加入 README 索引或生成面向最终用户的简要使用说明，我可以继续追加对应内容或导出 HTML。
