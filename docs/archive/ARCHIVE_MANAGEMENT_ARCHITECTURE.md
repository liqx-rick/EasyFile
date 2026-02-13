# Archive Management Architecture

## Overview

压缩包管理模块采用组件化架构，通过 Mixin 组合实现功能复用，使用 FFI 调用原生库（libarchive、UnRAR、minizip-ng）进行压缩包操作。

## Core Components

### 1. UI Layer

#### ArchiveManagementPage (1317 lines)
- **职责**: 主入口页面，包含压缩包列表和解压记录两个 Tab
- **继承链**: 
  - `CategoryLikePageMixin` - 分类浏览功能
  - `EditModeMixin` - 编辑模式与批量操作
  - `BatchOperationsMixin` - 批量操作（移动/复制/删除）
  - `SingleTickerProviderStateMixin` - Tab 动画
  - `WidgetsBindingObserver` - 生命周期监听
- **状态管理** (13个活跃字段):
  - Tab: `_tabController`, `_recordCount`
  - 解压记录: `_extractionRecords`, `_recordFolderExistsMap`, `_isLoadingRecords`, `_extractedArchives`
  - 扫描: `_isScanning`, `_errorMessage`
  - 搜索: `_searchController`, `_searchFocusNode`, `_isSearchMode`
  - 排序: `_sortBy`, `_sortAscending`
  - 选择: `_selectionController` (来自 EditModeMixin)

#### ArchiveViewerPage (719 lines)
- **职责**: 压缩包内容预览（无需解压）+ 单文件预览
- **功能**:
  - 显示压缩包内部文件列表（文件名/大小/修改时间/压缩率）
  - 判断文件预览支持性（图片/视频/音频/PDF/文本/文档）
  - 为预览自动解压单个文件到临时缓存
  - 图标显示逻辑：支持类型显示彩色图标，压缩包/未知类型显示灰色图标
- **依赖**: `ArchivePreviewCacheManager`, `ArchiveService`, `AppConfig`

#### ArchiveListItem (203 lines)
- **职责**: 压缩包列表项自定义 Widget
- **特性**: 
  - 显示压缩包缩略图、名称、大小、修改时间、文件数
  - 支持编辑模式下的复选框
  - 包含 `CheckboxPosition` 枚举（待迁移到 `file_collection_view.dart`）

### 2. Service Layer

#### ArchiveService (1091 lines)
- **职责**: 压缩包操作的核心服务
- **功能**:
  - 格式检测与路由（7z/ZIP/RAR 自动识别）
  - 解压（全量/单文件）
  - 列表内容
  - 验证完整性
  - 创建压缩包
- **FFI 集成**:
  - libarchive 3.8.5: 处理 7z/ZIP 格式
  - UnRAR SDK: 处理 RAR 格式
  - minizip-ng: ZIP 创建
- **字符编码**:
  - 7z: UTF-16LE
  - ZIP: UTF-8, CP936 (GB2312)
  - RAR: UTF-8
- **Native 函数**:
  - `archive_extract_async`: 全量解压
  - `list_archive_contents`: 列出内容
  - `extract_single_file`: 单文件解压
  - `validate_archive`: 验证完整性

#### ArchivePreviewCacheManager (282 lines)
- **职责**: 预览文件缓存管理
- **策略**: LRU (Least Recently Used)
- **操作**:
  - `extractForPreview()`: 解压单文件到缓存
  - `_ensureCacheLimit()`: 自动清理超限缓存
  - `clearAllCache()`: 清空所有缓存
- **配置**: 通过 `AppConfig.instance.tempFilesConfig` 控制缓存大小限制

#### ExtractionRecordService
- **职责**: 解压记录持久化（SharedPreferences）
- **功能**: 保存/加载/删除解压记录，记录源文件路径、目标路径、时间

#### PageSettingsService
- **职责**: 页面设置持久化（排序方式/顺序）
- **集成**: 与 ArchiveManagementPage 状态同步

### 3. Data Models

#### ArchiveEntryInfo (158 lines)
- **职责**: 压缩包内部文件条目的数据模型
- **字段**: 文件名、路径、大小、压缩后大小、修改时间、是否目录、压缩率

## Key Design Decisions

### 1. Mixin 组合模式
- **优点**: 代码复用，避免深层继承
- **实现**: CategoryLikePageMixin + EditModeMixin + BatchOperationsMixin
- **效果**: ArchiveManagementPage 复用了 90% 的分类浏览和编辑逻辑

### 2. FFI 原生集成
- **原因**: Dart/Flutter 无成熟的压缩包库，性能需求高
- **方案**: 使用 C 语言封装 libarchive/UnRAR/minizip-ng
- **优化**: 异步操作 + Isolate 防止 UI 阻塞

### 3. Tab 架构整合
- **历史**: 曾有独立的 `ExtractionRecordsPage`（已废弃 2026-01-16）
- **现状**: 整合到 ArchiveManagementPage 的第二个 Tab
- **好处**: 减少页面导航，统一用户体验

### 4. 预览缓存策略
- **问题**: 压缩包内文件预览需要先解压，频繁解压影响性能
- **方案**: LRU 缓存 + 自动清理
- **配置**: 可通过 AppConfig 调整缓存大小限制

### 5. 图标显示逻辑
- **原则**: 与 FilePreviewPage 的实际预览能力保持一致
- **实现**: `_canPreviewFile()` 检查文件类型（图片/视频/音频/PDF/文本/文档）
- **效果**: 用户通过图标颜色直观判断文件是否可预览

## Resolved Historical Issues

### 1. UTF-16LE 编码问题 (2026-01-20)
- **问题**: 7z 文件内的 UTF-16LE 文件名无法解压，报错 "Pathname cannot be converted from UTF-16LE to current locale"
- **解决**: 在 4 个原生函数中添加字符集选项：
  ```c
  archive_read_set_options(a, "7zip:hdrcharset=UTF-16LE");
  archive_read_set_options(a, "zip:hdrcharset=UTF-8,CP936");
  ```
- **位置**: `native/src/archive_wrapper.c` (lines 137-138, 395-396, 455-456, 559-560)

### 2. 图标显示不准确 (2026-01-20)
- **问题**: 压缩包预览页面，不可预览的文件仍显示彩色图标
- **解决**: 在 ArchiveViewerPage 中实现 `_canPreviewFile()` 判断，只有支持预览的文件类型才显示彩色图标
- **对齐**: 与 FilePreviewPage 的实际预览能力保持一致

### 3. 代码冗余清理 (2026-01-20)
- **删除**: `extraction_records_page.dart` (150 lines, 已标记 @Deprecated)
- **删除**: 9 个重构过程文档 (3800 lines)
- **保留**: 4 个构建/设置指南文档

## Component Dependencies

```
ArchiveManagementPage
├── CategoryLikePageMixin (lib/ui/mixins/category_like_page_mixin.dart)
├── EditModeMixin (lib/ui/mixins/edit_mode_mixin.dart)
├── BatchOperationsMixin (lib/ui/mixins/batch_operations_mixin.dart)
├── ArchiveService
├── PageSettingsService
├── ExtractionRecordService
└── ArchiveListItem

ArchiveViewerPage
├── ArchiveService
├── ArchivePreviewCacheManager
├── AppConfig
└── FilePreviewPage (预览路由)

ArchiveService
├── libarchive FFI (native/src/archive_wrapper.c)
├── UnRAR FFI
└── minizip-ng FFI

ArchivePreviewCacheManager
├── ArchiveService (单文件解压)
└── AppConfig (缓存配置)
```

## Performance Considerations

### 1. 大型压缩包列表
- **问题**: 数千个文件的压缩包列表渲染性能
- **方案**: ListView.builder + 虚拟滚动
- **优化空间**: 可考虑分页加载或虚拟列表

### 2. 解压操作
- **当前**: Isolate 异步执行，避免 UI 阻塞
- **监控**: 通过进度回调更新 UI

### 3. 缓存管理
- **当前**: LRU 自动清理
- **监控**: 缓存大小通过 AppConfig 配置

## Maintenance Guide

### 添加新压缩格式支持
1. 在 `ArchiveService` 中添加格式检测逻辑
2. 在原生层实现对应的 FFI 函数
3. 更新 `_canPreviewFile()` 判断逻辑（如果需要）

### 修改预览支持类型
1. 更新 `ArchiveViewerPage._canPreviewFile()` 方法
2. 确保与 `FilePreviewPage` 的实际预览能力保持一致
3. 同步更新 `AppConfig.instance.fileTypes` 配置

### 调整缓存策略
1. 修改 `AppConfig.tempFilesConfig` 中的缓存大小限制
2. 调整 `ArchivePreviewCacheManager._ensureCacheLimit()` 清理逻辑

### 添加新的批量操作
1. 在 `BatchOperationsMixin` 中添加通用逻辑
2. 在 `ArchiveManagementPage` 中添加 UI 入口

## Testing Checklist

- [ ] UTF-16LE 文件名的 7z 压缩包解压
- [ ] 中文文件名的 ZIP 压缩包（CP936 编码）
- [ ] RAR 加密压缩包解压
- [ ] 大型压缩包（1000+ 文件）列表性能
- [ ] 预览缓存自动清理
- [ ] 解压记录持久化
- [ ] 批量操作（移动/复制/删除）
- [ ] 搜索和排序功能
- [ ] Tab 切换与状态保持

## Known Limitations

1. **CheckboxPosition 枚举**: 临时定义在 `archive_list_item.dart`，应迁移到 `file_collection_view.dart`
2. **排序状态副本**: `_sortBy` 和 `_sortAscending` 在本地状态和 `PageSettingsService` 中重复，可考虑直接读取服务
3. **预览支持判断**: 当前硬编码在 `_canPreviewFile()` 中，未来可考虑配置化

## Future Enhancements

1. **单元测试**: 为 `ArchiveService` 和 `ArchivePreviewCacheManager` 添加测试覆盖
2. **性能监控**: 为大型压缩包操作添加性能埋点
3. **配置化预览支持**: 将预览类型判断逻辑配置化，便于扩展
4. **增量加载**: 对超大压缩包内容列表实现分页/虚拟滚动

---

**Last Updated**: 2026-01-20  
**Module Stability**: Stable (当前最终稳定方案)  
**Code Health**: 7/10 (已完成冗余清理)
