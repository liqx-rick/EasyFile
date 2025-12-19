# 首页推荐详情页实现说明

## 📋 概述

实现了推荐详情页（`RecommendationDetailPage`），参考 `AppFileScanTestPage` 的实现，从统一架构的应用扫描机制中获取文件列表并展示。

## 🎯 实现功能

### 1. 应用类卡片（微信、QQ、Telegram、WPS）

**使用统一扫描器：**
```dart
final detectionService = AppDetectionService();
final scanner = UnifiedAppScanner(detectionService);

final result = await scanner.scanApp(
  appKey: appKey,  // 'wechat', 'qq', 'telegram', 'wps'
  useMediaStore: true,
  updateCache: true,
);
```

**特性：**
- ✅ 自动检测应用是否安装
- ✅ MediaStore 扫描（Android 11+，快速）
- ✅ 路径扫描（全版本兼容，全面）
- ✅ 结果去重与合并
- ✅ 文件数量缓存（6小时有效期）
- ✅ 显示扫描详情（系统扫描、路径扫描、差异文件）

### 2. 系统类卡片（时光记忆、视频、录音、大文件）

**使用文件呈现器：**
```dart
final filePresenter = context.read<FilePresenter>();
final files = await _scanPaths(filePresenter, paths);
```

**各类型实现：**

| 类型 | 扫描路径 | 过滤逻辑 |
|------|----------|----------|
| 时光记忆 | DCIM, Pictures | 所有文件 |
| 视频文件 | Movies, DCIM | 视频格式过滤 |
| 录音文件 | Recordings, Music | 所有文件 |
| 大文件 | 所有常见目录 | > 100MB，按大小降序 |

## 🎨 UI 设计

### 页面结构

```
┌─────────────────────────────────────┐
│  ← 推荐卡片标题           [刷新]    │
├─────────────────────────────────────┤
│  ┌─────────────────────────────┐   │
│  │ 图标  X 个文件              │   │  ← 统计卡片
│  │      总大小: XXX MB         │   │
│  │      扫描信息（应用类）     │   │
│  └─────────────────────────────┘   │
├─────────────────────────────────────┤
│  ┌─────────────────────────────┐   │
│  │ [缩略图] 文件名.jpg         │   │  ← 文件列表
│  │         1.2 MB · Pictures   │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │ [缩略图] 视频.mp4           │   │
│  │         45 MB · DCIM        │   │
│  └─────────────────────────────┘   │
│  ...                                │
└─────────────────────────────────────┘
```

### 状态视图

1. **加载中**
   - 居中显示 CircularProgressIndicator
   - 显示提示文字

2. **错误状态**
   - 显示错误图标
   - 显示错误信息
   - 提供"重试"按钮

3. **空状态**
   - 显示卡片图标
   - 提示"没有找到文件"

4. **文件列表**
   - 统计信息卡片（文件数、总大小、扫描详情）
   - 可滚动的文件列表
   - 每个文件显示缩略图、文件名、大小、路径

## 📁 文件列表项设计

```dart
ListTile(
  leading: FileThumbnail(file: file, size: 48),  // 48x48 缩略图
  title: Text(file.name),                        // 文件名
  subtitle: Text('大小 · 父目录'),                // 元信息
  onTap: () { /* 打开文件 */ },
)
```

## 🔧 技术实现

### 核心依赖

```dart
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:provider/provider.dart';
```

### 关键方法

#### 1. `_loadAppFiles()` - 应用文件扫描
```dart
final scanner = UnifiedAppScanner(detectionService);
final result = await scanner.scanApp(appKey: appKey);
setState(() {
  _scanResult = result;
  _files = result.allFiles;  // 合并后的完整列表
});
```

#### 2. `_loadSystemFiles()` - 系统文件扫描
```dart
switch (widget.card.type) {
  case RecommendationType.memories:
    files = await _scanPaths(presenter, ['/DCIM', '/Pictures']);
    break;
  case RecommendationType.videos:
    files = await _scanPaths(presenter, ['/Movies', '/DCIM']);
    files = files.where((f) => _isVideoFile(f.name)).toList();
    break;
  // ...
}
```

#### 3. `_scanPaths()` - 路径扫描工具方法
```dart
Future<List<FileItem>> _scanPaths(
  FilePresenter presenter,
  List<String> paths,
) async {
  final allFiles = <FileItem>[];
  final seenPaths = <String>{};  // 去重

  for (final path in paths) {
    final files = await presenter.loadFilesFromPath(path);
    // 合并并去重
  }

  return allFiles;
}
```

## 🚀 使用示例

### 从首页推荐卡片跳转

```dart
// 点击推荐卡片
onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => RecommendationDetailPage(
        card: recommendationCard,  // 包含 type, title, icon, appKey 等信息
      ),
    ),
  );
}
```

### 应用类卡片示例
```dart
final wechatCard = RecommendationCard(
  type: RecommendationType.wechat,
  title: '微信文件',
  icon: Icons.chat,
  color: Color(0xFF07C160),
  fileCount: 156,
  appKey: 'wechat',  // 关键字段
);
```

### 系统类卡片示例
```dart
final memoriesCard = RecommendationCard(
  type: RecommendationType.memories,
  title: '时光记忆',
  icon: Icons.camera,
  color: Colors.purple,
  fileCount: 234,
  appKey: null,  // 系统类不需要
);
```

## ✅ 优势

### 1. **架构统一**
- 应用类直接复用 `UnifiedAppScanner`
- 系统类使用 `FilePresenter`
- 避免重复实现扫描逻辑

### 2. **性能优化**
- 优先使用 MediaStore（Android 11+）
- 文件数量缓存（6小时有效期）
- 路径去重避免重复扫描

### 3. **用户体验**
- 加载状态明确（加载中、错误、空、成功）
- 刷新按钮支持重新扫描
- 文件缩略图预览
- 清晰的统计信息

### 4. **扩展性强**
- 新增应用类型：只需在 `AppScannerConfigs` 添加配置
- 新增系统类型：在 `_loadSystemFiles()` 添加 case
- 文件操作：在 `onTap` 中实现（删除、移动、分享等）

## 📊 性能数据

参考 `AppFileScanTestPage` 测试结果：

| 应用 | 文件数量 | MediaStore 耗时 | 路径扫描耗时 |
|------|----------|-----------------|--------------|
| 微信 | 500+ | 0.2s | 1.5s |
| QQ | 300+ | 0.15s | 1.2s |
| Telegram | 200+ | 0.1s | 0.8s |

**结论：** MediaStore 扫描速度是路径扫描的 **5-10倍**

## 🔮 未来优化

### 1. 文件操作
- [ ] 点击打开文件
- [ ] 长按显示操作菜单（删除、分享、移动）
- [ ] 批量选择模式
- [ ] 文件排序（按名称、大小、日期）

### 2. 性能优化
- [ ] 分页加载（大量文件时）
- [ ] 虚拟滚动（VirtualScrollView）
- [ ] 缩略图懒加载

### 3. 功能增强
- [ ] 文件搜索
- [ ] 文件类型过滤
- [ ] 详细信息查看
- [ ] 文件详情页

## 🐛 已知限制

1. **MediaStore 限制**
   - 仅支持 Android 11+
   - 部分应用文件可能检测不到（权限限制）

2. **路径扫描限制**
   - 深度遍历性能较低
   - 大量文件时加载缓慢

3. **缓存机制**
   - 文件数量缓存 6 小时
   - 刷新时会重新扫描（耗时）

## 📝 总结

成功实现了推荐详情页，完全复用统一应用扫描架构：
- ✅ **应用类**：使用 `UnifiedAppScanner`，性能优异
- ✅ **系统类**：使用 `FilePresenter`，逻辑清晰
- ✅ **UI 设计**：参考现有页面，风格统一
- ✅ **状态管理**：完整的加载、错误、空、成功状态
- ✅ **用户体验**：刷新、统计、缩略图预览

代码简洁、可维护性强，为后续功能扩展奠定了良好基础！
