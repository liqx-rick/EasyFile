# Flutter 性能优化最佳实践

## 🎯 核心原则

本文档总结了 EasyFile 项目中的性能优化最佳实践，特别是针对大数据量列表和图片加载的优化策略。

---

## 1. 列表渲染优化

### ✅ 强制使用懒加载

**适用场景**：任何可能超过 20 项的列表

**推荐方案**：
- **简单列表**：`ListView.builder`
- **网格布局**：`GridView.builder`
- **分组列表**：`CustomScrollView` + `SliverList` / `SliverGrid`

```dart
// ✅ 正确：使用 builder 实现懒加载
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => buildItem(items[index]),
)

// ❌ 错误：一次性构建所有 widget
ListView(
  children: items.map((item) => buildItem(item)).toList(),
)
```

---

### ⚠️ 避免 shrinkWrap

**原因**：`shrinkWrap: true` 会强制计算所有子项的高度，失去懒加载优势。

**例外情况**：
- 数据量 < 10 项
- 在 Dialog 或 BottomSheet 中，且有明确的高度限制
- `ReorderableListView`（必须使用）

```dart
// ❌ 错误：大数据量使用 shrinkWrap
ListView.builder(
  shrinkWrap: true,  // 计算所有 3528 项的高度！
  itemCount: 3528,
  ...
)

// ✅ 正确：使用固定高度或 Flexible
SizedBox(
  height: 400,  // 固定高度
  child: ListView.builder(
    itemCount: 3528,
    ...
  ),
)
```

---

### 🔑 视图模式切换必须添加 Key

**原因**：确保切换时正确销毁旧 widget，释放资源。

```dart
// ❌ 错误：没有 key，可能复用旧 State
MyListView(
  isGridMode: isGrid,
)

// ✅ 正确：添加 key 确保重建
MyListView(
  key: ValueKey('view_${isGrid ? 'grid' : 'list'}'),
  isGridMode: isGrid,
)
```

---

### 📊 性能优化配置

```dart
SliverChildBuilderDelegate(
  (context, index) => buildItem(index),
  childCount: items.length,
  // 性能优化三件套
  addAutomaticKeepAlives: false,  // 不保持不可见 widget 状态
  addRepaintBoundaries: true,     // 隔离重绘，避免全局重绘
  addSemanticIndexes: false,      // 大数据量下禁用语义索引
)
```

---

## 2. 图片加载优化

### 🖼️ 强制限制缩略图尺寸

**原则**：永远不要在列表中加载原图

```dart
// ❌ 错误：加载原图（4000×3000，~45MB）
Image.file(file)

// ✅ 正确：限制缓存尺寸（200×200，~160KB）
Image.file(
  file,
  cacheWidth: size.clamp(100, 400),   // 必须设置
  cacheHeight: size.clamp(100, 400),  // 必须设置
  filterQuality: FilterQuality.low,   // 缩略图用低质量
)
```

**计算公式**：
```dart
final pixelRatio = MediaQuery.of(context).devicePixelRatio;
final cacheSize = (displaySize * pixelRatio).toInt().clamp(100, 400);
```

---

### 🗑️ 主动清理图片缓存

**清理时机**：

#### 时机 1：切换视图模式前
```dart
Future<void> toggleViewMode() async {
  // 切换前清理，避免新旧图片同时占用内存
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
  
  // 然后切换模式
  _viewMode = newMode;
  notifyListeners();
}
```

#### 时机 2：Widget 参数变化时
```dart
@override
void didUpdateWidget(MyWidget oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (oldWidget.gridMode != widget.gridMode) {
    // 检测到模式切换立即清理
    _clearImageCache();
  }
}

void _clearImageCache() {
  try {
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
  } catch (e) {
    // 忽略错误
  }
}
```

---

### ⚙️ 全局缓存配置

**位置**：`main()` 函数中

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 配置全局图片缓存限制
  PaintingBinding.instance.imageCache.maximumSize = 100;        // 最多 100 张
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20;  // 50MB
  
  runApp(MyApp());
}
```

**建议值**：
- 移动设备：50-100 张，25-50MB
- 平板设备：100-200 张，50-100MB

---

## 3. Widget 数量优化

### ❌ 避免为装饰创建额外 Widget

**问题案例**：分隔线导致 childCount 翻倍

```dart
// ❌ 错误：为分隔线创建额外 widget
SliverList(
  delegate: SliverChildBuilderDelegate(
    (context, index) {
      if (index.isOdd) {
        return const Divider();  // 额外的 widget
      }
      return buildItem(index ~/ 2);
    },
    childCount: items.length * 2 - 1,  // 翻倍！
  ),
)
```

**优化方案**：使用装饰器

```dart
// ✅ 正确：使用 DecoratedBox 的 border
SliverList(
  delegate: SliverChildBuilderDelegate(
    (context, index) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: dividerColor),
          ),
        ),
        child: buildItem(index),
      );
    },
    childCount: items.length,  // 不翻倍
  ),
)
```

**效果**：
- Widget 数量：7055 → 3528（减少 50%）
- 布局计算：减少 50%
- 内存占用：减少 50%

---

## 4. 内存管理检查清单

在实现任何列表视图前，必须确认：

- [ ] 是否使用了懒加载组件？（`ListView.builder` / `SliverList`）
- [ ] 是否避免了 `shrinkWrap: true`？（除非必要）
- [ ] 图片是否设置了 `cacheWidth` 和 `cacheHeight`？
- [ ] 是否配置了全局图片缓存限制？
- [ ] 视图切换是否添加了 `key`？
- [ ] 是否在关键时机清理了图片缓存？
- [ ] `childCount` 是否等于实际数据量？（不能翻倍）
- [ ] 是否添加了性能优化配置？（`addAutomaticKeepAlives` 等）

---

## 5. 性能监控指标

### ⚠️ 警告信号

如果出现以下现象，说明可能有性能问题：

1. **UI 响应**
   - 列表滚动卡顿（FPS < 30）
   - 视图切换耗时 > 2 秒
   - 应用在浏览大量图片后无响应

2. **内存问题**
   - `Exhausted heap space` 错误
   - 内存占用持续增长不下降
   - 应用在后台被系统杀死

3. **用户体验**
   - 图片加载缓慢
   - 切换视图有明显延迟
   - 滚动不流畅

### 📈 性能基准

**目标指标**（3000+ 项数据）：
- 初始加载：< 1 秒
- 滚动 FPS：> 55
- 视图切换：< 2 秒
- 内存占用：< 200MB（不含系统）

---

## 6. 代码审查要点

### 审查 ListView/GridView
```dart
// 检查点 1：是否使用 .builder
ListView.builder(...)  // ✅

// 检查点 2：是否有 shrinkWrap
shrinkWrap: true,  // ⚠️ 需要理由

// 检查点 3：itemCount 是否合理
itemCount: items.length * 2  // ❌ 可能有问题
```

### 审查 Image
```dart
// 检查点 1：是否有缓存尺寸
Image.file(
  file,
  cacheWidth: ...,   // ✅ 必须有
  cacheHeight: ...,  // ✅ 必须有
)

// 检查点 2：尺寸是否合理
cacheWidth: 4000,  // ❌ 太大
cacheWidth: 200,   // ✅ 合理
```

### 审查视图切换
```dart
// 检查点 1：是否有 key
MyView(
  key: ValueKey('view_$mode'),  // ✅ 必须有
  mode: mode,
)

// 检查点 2：是否清理缓存
void toggleMode() {
  imageCache.clear();  // ✅ 必须清理
  ...
}
```

---

## 7. 实战案例

### 案例：图片分类页面崩溃

**问题**：3528 张图片，分组模式下切换到列表视图时崩溃。

**根本原因**：
1. `childCount` 翻倍（7055 个 widget）
2. Widget 未正确销毁（缺少 key）
3. 缓存未清理（新旧图片同时存在）

**解决方案**：
1. 使用 `DecoratedBox` 替代分隔线（childCount 不翻倍）
2. 添加 `key: ValueKey('grouped_${gridMode ? 'grid' : 'list'}')`
3. 在 `toggleViewMode()` 和 `didUpdateWidget()` 中清理缓存

**效果**：
- 切换耗时：10+ 秒 → 5 秒
- 内存峰值：崩溃 → 正常
- Widget 数量：7055 → 3528

---

## 8. 参考资源

### Flutter 官方文档
- [Performance best practices](https://docs.flutter.dev/perf/best-practices)
- [Optimizing performance](https://docs.flutter.dev/perf/rendering-performance)

### 项目相关
- `lib/ui/widgets/file_collection_view.dart` - 标准实现参考
- `lib/ui/widgets/image_thumbnail.dart` - 图片加载参考
- `lib/main.dart` - 全局配置参考

---

## 📝 总结

**核心思想**：
1. **最小化 Widget 数量** - 能用装饰器就不用额外 widget
2. **确保正确销毁** - 关键参数变化时必须加 key
3. **主动内存管理** - 不依赖 GC，主动清理缓存
4. **严格限制尺寸** - 永远不加载原图到列表

遵循这些原则，可以轻松处理 10000+ 条数据的列表而不崩溃。

---

**最后更新**：2025-11-19  
**维护者**：EasyFile Team
