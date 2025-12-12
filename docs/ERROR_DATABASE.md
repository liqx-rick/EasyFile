# Flutter 错误数据库

## 使用说明

1. **遇到错误时**：先在本文档搜索关键词
2. **找到匹配项**：按照解决方案尝试修复
3. **未找到匹配**：参考 `BUG_FIX_TEMPLATE.md` 进行系统性排查
4. **解决后**：将新错误添加到本库

---

## 错误索引

### Widget 生命周期相关
- [E001: Looking up a deactivated widget's ancestor is unsafe](#e001)
- [E002: setState() called after dispose()](#e002)
- [E003: Cannot use context after widget is disposed](#e003)

### 状态管理相关
- [E101: notifyListeners() during build](#e101)
- [E102: Multiple notifyListeners() in loop](#e102)

### 异步操作相关
- [E201: Unmounted widget after async operation](#e201)
- [E202: Memory leak from uncancelled Future](#e202)

### UI 渲染相关
- [E301: RenderBox layout exception](#e301)
- [E302: Overflow pixels error](#e302)
- [E303: Infinite rebuild loop caused by setState in build method](#e303)

### UI 状态相关
- [E401: UI state not cleared on tab switch](#e401)
- [E402: Recent tab not refreshed after returning from sub-page](#e402)

### 数据扫描相关
- [E501: Duplicate keys found in ListView/GridView](#e501)
- [E502: Category cache statistics not updated](#e502)

### 依赖注入相关
- [E601: Bad state: You tried to access an instance that is not ready yet](#e601)

---

## 详细错误条目

<a name="e001"></a>
### E001: Looking up a deactivated widget's ancestor is unsafe

**错误级别：** ⚠️ 高  
**首次发现：** 2025-12-01  
**最后更新：** 2025-12-01

#### 错误信息

```
Looking up a deactivated widget's ancestor is unsafe.
At this point the state of the widget's element tree is no longer stable.
```

#### 触发场景

1. PopupMenu/Dialog 回调中触发 notifyListeners()
2. 异步操作后使用已失效的 BuildContext
3. 批量操作中循环调用 notifyListeners()

#### 堆栈特征

```dart
#2 Element.dependOnInheritedWidgetOfExactType
#3 PopupMenuTheme.of (package:flutter/src/material/popup_menu_theme.dart:278:10)
#4 PopupMenuButtonState._positionBuilder
```

#### 根本原因

widget 树在异步操作或 notifyListeners() 期间重建，但某些代码仍在尝试访问旧的 widget 树。

#### 解决方案

**方案 A：延迟 notifyListeners()（推荐）**

```dart
// ❌ 错误
void updateData() {
  _data.update();
  notifyListeners(); // 立即触发重建
}

// ✅ 正确
void updateData() {
  _data.update();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    notifyListeners(); // 延迟到下一帧
  });
}
```

**方案 B：提前获取 Context 依赖**

```dart
// ❌ 错误
Future<void> operation(BuildContext context) async {
  await asyncCall();
  ScaffoldMessenger.of(context).showSnackBar(...); // context 可能失效
}

// ✅ 正确
Future<void> operation(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context); // 提前获取
  await asyncCall();
  if (!context.mounted) return;
  messenger.showSnackBar(...); // 使用预获取的引用
}
```

**方案 C：批量操作优化**

```dart
// ❌ 错误
for (final item in items) {
  addItem(item); // 每次都 notifyListeners()
}

// ✅ 正确
void batchAdd(List items) {
  for (final item in items) {
    _items.add(item); // 只更新数据
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    notifyListeners(); // 批量操作后只通知一次
  });
}
```

#### 预防措施

- [ ] ViewModel 中提供批量操作方法
- [ ] PopupMenu 回调使用 Future.microtask 包装
- [ ] 异步操作前获取 Context 依赖
- [ ] 异步操作后检查 mounted 状态

#### 相关文档

- [详细排查指南](./TROUBLESHOOTING_DEACTIVATED_WIDGET.md)
- [修复模板](./BUG_FIX_TEMPLATE.md)

#### 历史案例

- **2025-12-01**: 批量添加收藏功能触发此错误
  - 场景：PopupMenu 选择"添加收藏"
  - 原因：notifyListeners() 在 PopupMenu 关闭前被调用
  - 解决：延迟 notifyListeners() 到下一帧
  - 提交：[commit-hash]

- **2025-12-01**: 批量取消收藏功能触发此错误
  - 场景：收藏Tab中选择多个文件(>2个)，批量移除收藏
  - 原因：多重触发点
    1. `removeFavoriteFile()` 在循环中被调用，每次都触发 `notifyListeners()`
    2. 批量操作后立即调用 `loadFavoriteFiles()`，它内部有多次 `notifyListeners()` (`setLoading`, `setFavoriteFiles`, `setFiles`)
    3. 这些都发生在 PopupMenu 关闭前，导致 widget 树不稳定
  - 解决：三层防护
    1. ViewModel层：添加 `batchRemoveFavoriteFiles()` 方法，使用 `addPostFrameCallback` 延迟通知
    2. Presenter层：将 `loadFavoriteFiles()` 调用延迟到下一帧
    3. Service层：先退出选择模式，再用 `addPostFrameCallback` 延迟显示消息
  - 文件：`lib/viewmodel/file_viewmodel.dart`, `lib/presenter/file_presenter.dart`, `lib/ui/services/batch_operations_service.dart`

- **2025-12-06**: Category页面批量收藏操作触发此错误（编辑模式）
  - 场景：Category页面编辑模式下，通过底部工具栏的"更多"菜单执行添加/取消收藏
  - 原因：**双层触发点**
    1. `SelectionBottomBar` 的 `PopupMenuButton.onSelected` 回调立即执行，在 PopupMenu 关闭动画期间调用业务逻辑
    2. `BatchOperationsService.batchToggleFavorite()` 方法内部立即调用 `onExitSelectionMode()`，触发 `setState()` 更新
    3. 两层叠加：PopupMenu 还在执行关闭动画，但页面已经开始重建，导致 widget 树冲突
  - 错误堆栈关键帧：
    ```
    #3 PopupMenuTheme.of (package:flutter/src/material/popup_menu_theme.dart:278:10)
    #4 PopupMenuButtonState._positionBuilder
    ```
  - 解决：**双层延迟**
    1. UI层：`PopupMenuButton.onSelected` 使用 `Future.delayed(Duration(milliseconds: 100))` 延迟所有回调执行
    2. Service层：`onExitSelectionMode()` 调用移入 `addPostFrameCallback` 内部，与消息显示一起延迟
  - 修改文件：
    - `lib/ui/widgets/selection_bottom_bar.dart` - PopupMenu 回调延迟
    - `lib/ui/services/batch_operations_service.dart` - `onExitSelectionMode()` 延迟
  - **关键经验：**
    - ✅ **所有 PopupMenu 的 onSelected 回调都必须延迟执行**（参考 `file_preview_page.dart`）
    - ✅ **回调内部的所有状态更新（setState、notifyListeners）也必须延迟**
    - ✅ 双层防护比单层更可靠：UI层延迟 + Service层延迟

---

<a name="e002"></a>
### E002: setState() called after dispose()

**错误级别：** ⚠️ 高  
**首次发现：** [日期]  
**最后更新：** [日期]

#### 错误信息

```
setState() called after dispose()
```

#### 触发场景

1. 异步操作完成后调用 setState，但 widget 已被销毁
2. Timer/Stream 回调中调用 setState
3. 页面导航后回调仍在执行

#### 根本原因

异步操作或监听器的回调在 widget dispose 后仍在执行。

#### 解决方案

**方案 A：检查 mounted（推荐）**

```dart
Future<void> loadData() async {
  await fetchData();
  
  // ✅ 检查 widget 是否还存在
  if (!mounted) return;
  
  setState(() {
    _data = data;
  });
}
```

**方案 B：取消异步操作**

```dart
class _MyWidgetState extends State<MyWidget> {
  CancelableOperation? _operation;
  
  void loadData() {
    _operation = CancelableOperation.fromFuture(
      fetchData(),
      onCancel: () => print('Cancelled'),
    );
    
    _operation!.value.then((data) {
      if (!mounted) return;
      setState(() => _data = data);
    });
  }
  
  @override
  void dispose() {
    _operation?.cancel(); // 取消操作
    super.dispose();
  }
}
```

**方案 C：安全的 setState**

```dart
void safeSetState(VoidCallback fn) {
  if (mounted) {
    setState(fn);
  }
}
```

#### 预防措施

- [ ] 所有异步操作后检查 mounted
- [ ] dispose() 中取消 Timer/Stream 订阅
- [ ] 使用 CancelableOperation 管理异步任务

---

<a name="e003"></a>
### E003: Cannot use context after widget is disposed

**错误级别：** ⚠️ 中  
**首次发现：** [日期]  
**最后更新：** [日期]

#### 错误信息

```
Cannot use context after widget is disposed
```

#### 触发场景

异步操作后尝试使用 BuildContext（如导航、显示 SnackBar）。

#### 解决方案

参考 [E001 方案 B](#e001)：提前获取 Context 依赖。

---

<a name="e101"></a>
### E101: notifyListeners() during build

**错误级别：** 🔴 严重  
**首次发现：** [日期]  
**最后更新：** [日期]

#### 错误信息

```
setState() or markNeedsBuild() called during build
```

#### 触发场景

在 build() 方法中直接或间接调用 notifyListeners()。

#### 根本原因

Flutter 不允许在构建过程中修改 widget 树。

#### 解决方案

**方案：延迟到 build 完成后**

```dart
// ❌ 错误
@override
Widget build(BuildContext context) {
  viewModel.update(); // 可能触发 notifyListeners()
  return Widget();
}

// ✅ 正确
@override
Widget build(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    viewModel.update();
  });
  return Widget();
}
```

#### 预防措施

- [ ] 避免在 build() 中修改状态
- [ ] 使用 initState() 或事件回调处理状态变更

---

<a name="e102"></a>
### E102: Multiple notifyListeners() in loop

**错误级别：** ⚠️ 中（性能问题）  
**首次发现：** [日期]  
**最后更新：** [日期]

#### 问题描述

循环中每次迭代都调用 notifyListeners()，导致多次不必要的重建。

#### 解决方案

参考 [E001 方案 C](#e001)：批量操作优化。

---

<a name="e201"></a>
### E201: Unmounted widget after async operation

**错误级别：** ⚠️ 高  
**首次发现：** [日期]  
**最后更新：** [日期]

#### 错误信息

通常表现为：
- setState() called after dispose()
- Cannot use context after disposal
- 无错误但操作无效

#### 解决方案

参考 [E002](#e002)：检查 mounted 状态。

---

<a name="e202"></a>
### E202: Memory leak from uncancelled Future

**错误级别：** ⚠️ 中  
**首次发现：** [日期]  
**最后更新：** [日期]

#### 问题描述

Future/Stream 未取消，导致回调持有已销毁 widget 的引用。

#### 解决方案

参考 [E002 方案 B](#e002)：取消异步操作。

---

<a name="e301"></a>
### E301: RenderBox layout exception

**错误级别：** ⚠️ 中  
**首次发现：** [日期]  
**最后更新：** [日期]

#### 错误信息

```
RenderBox was not laid out: RenderXXX#xxxxx
```

#### 常见原因

1. 无限尺寸约束（如 ListView 中的 ListView）
2. Flex 子组件没有明确尺寸
3. 约束传递错误

#### 解决方案

**方案 A：使用 Expanded/Flexible**

```dart
// ❌ 错误
Column(
  children: [
    ListView(...), // 无限高度
  ],
)

// ✅ 正确
Column(
  children: [
    Expanded(
      child: ListView(...),
    ),
  ],
)
```

**方案 B：指定明确尺寸**

```dart
SizedBox(
  height: 200,
  child: ListView(...),
)
```

---

<a name="e302"></a>
### E302: Overflow pixels error

**错误级别：** 🟡 低  
**首次发现：** [日期]  
**最后更新：** [日期]

#### 错误信息

```
A RenderFlex overflowed by XX pixels
```

#### 解决方案

1. 使用 SingleChildScrollView
2. 使用 Flexible/Expanded
3. 缩小内容或调整间距

---

<a name="e303"></a>
### E303: Infinite rebuild loop caused by setState in build method

**错误级别：** 🔴 严重  
**首次发现：** 2025-12-12  
**最后更新：** 2025-12-13

#### 错误信息

```
控制台日志持续输出，应用性能严重下降
每隔 50-60ms 触发一次 rebuild
所有子 widget 频繁调用 didUpdateWidget 和 build
```

#### 触发场景

1. 在 `build()` 方法中直接或间接调用异步方法
2. 异步方法完成后调用 `setState()`
3. `setState()` 触发新的 `build()`
4. 形成无限循环

#### 典型代码模式

**错误代码示例：**

```dart
@override
Widget build(BuildContext context) {
  // ❌ 错误：在 build 中调用异步方法
  _loadDisplaySettings();
  
  return Widget(...);
}

Future<void> _loadDisplaySettings() async {
  final settings = await loadSettings();
  if (mounted) {
    setState(() {  // ← 触发新的 build()
      _settings = settings;
    });
  }
}
```

**循环过程：**
```
1. build() 被调用
   ↓
2. _loadDisplaySettings() 被调用
   ↓
3. 异步完成后 setState() 被调用
   ↓
4. 触发新的 build()
   ↓
5. 回到步骤 1（无限循环）
```

#### 症状特征

- ✅ **性能问题**：应用卡顿，CPU 占用高
- ✅ **日志爆炸**：控制台持续输出日志
- ✅ **规律性**：每隔固定时间间隔重复（通常 50-100ms）
- ✅ **级联效应**：所有子 widget 被迫 rebuild

#### 诊断方法

**1. 添加调试日志**

```dart
@override
Widget build(BuildContext context) {
  logger.d('🏗️ [build] CALLED at ${DateTime.now()}');
  return Widget(...);
}

@override
void didUpdateWidget(OldWidget oldWidget) {
  super.didUpdateWidget(oldWidget);
  logger.d('🔄 [didUpdateWidget] CALLED');
}
```

**2. 观察日志模式**

如果看到：
```
[00:00.000] 🏗️ [build] CALLED
[00:00.050] 🏗️ [build] CALLED
[00:00.100] 🏗️ [build] CALLED
...（持续不断）
```

说明存在无限 rebuild。

#### 根本原因

**Flutter 的设计原则：**
- `build()` 方法应该是**纯函数**（pure function）
- 不应该产生**副作用**（side effects）
- 不应该改变状态或触发新的 rebuild

**违反原则的后果：**
```
build() 应该只根据当前状态构建 UI
↓
如果 build() 改变状态（直接或间接）
↓
就会触发新的 build()
↓
形成无限循环
```

#### 解决方案

**方案 A：移到 initState（推荐）**

```dart
@override
void initState() {
  super.initState();
  _loadDisplaySettings(); // ✅ 只在初始化时调用一次
}

@override
Widget build(BuildContext context) {
  // ✅ build 方法不调用任何会触发 setState 的方法
  return Widget(...);
}
```

**方案 B：使用 FutureBuilder**

```dart
@override
Widget build(BuildContext context) {
  return FutureBuilder<Settings>(
    future: loadSettings(), // ✅ Future 只创建一次
    builder: (context, snapshot) {
      if (!snapshot.hasData) return LoadingWidget();
      return Widget(settings: snapshot.data);
    },
  );
}
```

**方案 C：使用 addPostFrameCallback**

```dart
@override
Widget build(BuildContext context) {
  // ✅ 在当前帧构建完成后执行
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && !_isInitialized) {
      _loadDisplaySettings();
      _isInitialized = true;
    }
  });
  
  return Widget(...);
}
```

#### 实际案例：CategoryFilePage

**问题代码（lib/ui/pages/category_file_page.dart）：**

```dart
@override
Widget build(BuildContext context) {
  // ❌ 每次 build 都调用
  _loadDisplaySettings();
  
  return ChangeNotifierProvider<FileViewModel>.value(
    value: widget.viewModel,
    child: Consumer<PageSettingsService>(...),
  );
}
```

**修复后：**

```dart
@override
void initState() {
  super.initState();
  // ✅ 只在初始化时调用一次
  _loadDisplaySettings();
}

@override
Widget build(BuildContext context) {
  // ✅ 不再调用会触发 setState 的方法
  return ChangeNotifierProvider<FileViewModel>.value(
    value: widget.viewModel,
    child: Consumer<PageSettingsService>(...),
  );
}
```

**效果：**
- ✅ 无限循环消失
- ✅ CPU 占用降低
- ✅ 滚动流畅
- ✅ 性能恢复正常

#### 附加优化（虽然不是根本原因）

在修复过程中发现的其他性能优化：

**1. setState 去重**

```dart
// ✅ 只在值真正改变时 setState
if (mounted && _duration != duration) {
  setState(() {
    _duration = duration;
  });
}
```

**2. 激活 KeepAlive**

```dart
@override
void initState() {
  super.initState();
  updateKeepAlive(); // ✅ 防止滚动时被销毁
}
```

**3. 缓存计算结果**

```dart
// ✅ 缓存避免重复计算
_cachedCacheWidth ??= (widget.size * MediaQuery.of(context).devicePixelRatio)
    .toInt()
    .clamp(150, 800);
```

#### 预防措施

**代码审查检查清单：**

- [ ] `build()` 方法中没有调用 `setState()`
- [ ] `build()` 方法中没有调用会触发 `setState()` 的异步方法
- [ ] 异步初始化逻辑放在 `initState()` 中
- [ ] 使用 `FutureBuilder` 或 `StreamBuilder` 处理异步数据
- [ ] 添加调试日志监控 rebuild 频率

**快速检测方法：**

```dart
// 在 build 方法开头添加
@override
Widget build(BuildContext context) {
  if (kDebugMode) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final interval = _lastBuildTime != null ? now - _lastBuildTime! : 0;
    _lastBuildTime = now;
    if (interval < 100) {
      logger.w('⚠️ Suspicious rapid rebuild: ${interval}ms interval');
    }
  }
  // ... rest of build
}
```

#### 相关文件

- `lib/ui/pages/category_file_page.dart`: 主要问题文件
- `lib/ui/widgets/real_video_thumbnail.dart`: 受影响的子 widget

#### 参考资料

- [Flutter Performance Best Practices](https://docs.flutter.dev/perf/best-practices)
- [Build Method Should Be Pure](https://api.flutter.dev/flutter/widgets/State/build.html)
- [setState Documentation](https://api.flutter.dev/flutter/widgets/State/setState.html)

#### 检查清单

修复此问题时的验证步骤：

- [ ] 移除 `build()` 中的异步方法调用
- [ ] 将初始化逻辑移到 `initState()`
- [ ] 添加调试日志验证 rebuild 频率
- [ ] 测试滚动性能
- [ ] 检查 CPU 占用是否正常
- [ ] 验证控制台日志不再持续输出
- [ ] 在真机上测试性能

#### 影响范围

- **严重性**：🔴 严重 - 导致应用几乎不可用
- **性能影响**：极高 - CPU 持续满载
- **用户体验**：极差 - 卡顿、耗电、发热
- **影响范围**：整个页面及其所有子 widget

---

## 贡献指南

### 添加新错误

1. 分配错误编号（按类别递增）
2. 填写完整模板
3. 提供可复现的代码示例
4. 记录解决方案和预防措施
5. 更新索引

### 错误编号规则

- **E0XX**: Widget 生命周期（00-99）
- **E1XX**: 状态管理（100-199）
- **E2XX**: 异步操作（200-299）
- **E3XX**: UI 渲染（300-399）
- **E4XX**: UI 状态（400-499）
- **E5XX**: 平台特定（500-599）
- **E9XX**: 其他（900-999）

### 错误模板

```markdown
<a name="eXXX"></a>
### EXXX: 错误标题

**错误级别：** 🔴/⚠️/🟡  
**首次发现：** YYYY-MM-DD  
**最后更新：** YYYY-MM-DD

#### 错误信息
[完整错误消息]

#### 触发场景
1. 场景描述1
2. 场景描述2

#### 堆栈特征（可选）
[关键堆栈行]

#### 根本原因
[问题本质]

#### 解决方案
**方案 A：标题**
[代码示例]

**方案 B：标题**
[代码示例]

#### 预防措施
- [ ] 措施1
- [ ] 措施2

#### 相关文档
- [链接]

#### 历史案例
- **日期**: 简要描述
  - 场景：
  - 原因：
  - 解决：
  - 提交：
```

---

<a name="e401"></a>
### E401: UI state not cleared on tab switch

**错误级别：** 🟡 中  
**首次发现：** 2025-12-01  
**最后更新：** 2025-12-01

#### 错误信息

无错误日志，视觉问题：UI 元素在不应该显示时仍保持可见状态。

#### 触发场景

1. Tab 切换时，某些 UI 状态（如高亮、选中态）未被清除
2. 依赖全局状态的 UI 组件没有监听 Tab 变化
3. 条件渲染逻辑不完整，未考虑所有 Tab 状态

#### 根本原因

UI 组件的状态判断条件不完整，只依赖部分状态（如 `currentPath`），没有考虑 Tab 上下文。当切换 Tab 时，虽然内容改变了，但某些依赖旧状态的 UI 元素仍然保持激活状态。

#### 解决方案

**方案 A：在状态判断中加入 Tab 条件（推荐）**

```dart
// ❌ 错误：只判断路径匹配
final isSelected = currentPath == folder.path ||
    currentPath.startsWith(folder.path);

// ✅ 正确：同时判断 Tab 和路径
final currentTab = widget.fileViewModel.currentTab;
final isSelected = currentTab == TabView.browse &&
    (currentPath == folder.path ||
     currentPath.startsWith(folder.path));
```

**方案 B：Tab 切换时重置相关状态**

```dart
void setCurrentTab(TabView tab) {
  _currentTab = tab;
  
  // 清除其他 Tab 特定的状态
  if (tab != TabView.browse) {
    _selectedFolder = null; // 清除选中的文件夹
  }
  
  notifyListeners();
}
```

**方案 C：使用 Tab-specific Widget**

```dart
// 根据 Tab 渲染不同组件，避免状态混淆
Widget build(BuildContext context) {
  return Consumer<FileViewModel>(
    builder: (context, vm, child) {
      switch (vm.currentTab) {
        case TabView.browse:
          return QuickAccessSection(showSelection: true);
        case TabView.favorite:
          return QuickAccessSection(showSelection: false);
        // ...
      }
    },
  );
}
```

#### 预防措施

- [ ] 所有依赖全局状态的 UI 组件都应检查 Tab 上下文
- [ ] Tab 切换时审查是否需要清除特定状态
- [ ] 使用明确的状态作用域，避免状态泄漏到其他 Tab
- [ ] Code Review 时检查条件判断是否完整

#### 相关文档

- [Flutter State Management Best Practices](https://flutter.dev/docs/development/data-and-backend/state-mgmt/intro)

#### 历史案例

- **2025-12-01**: 首页推荐卡片在收藏Tab仍显示高亮
  - 场景：在浏览Tab选中快速访问卡片后，切换到收藏Tab，卡片仍保持高亮
  - 原因：`isSelected` 判断只检查 `currentPath`，未检查 `currentTab`
  - 解决：在 `isSelected` 判断中添加 `currentTab == TabView.browse` 条件
  - 文件：`lib/ui/widgets/quick_access_section.dart`

---

<a name="e402"></a>
### E402: Recent tab not refreshed after returning from sub-page

**错误级别：** ⚠️ 中  
**首次发现：** 2025-12-01  
**最后更新：** 2025-12-01

#### 问题描述

用户在最近Tab时打开子页面（如分类页面、存储页面），在子页面中打开文件预览后，返回主页时，最近Tab没有显示新打开的文件。

#### 触发场景

1. 用户在主页的最近Tab
2. 打开分类页面或存储浏览页面
3. 在子页面中打开文件（文件被添加到recent列表）
4. 返回主页，仍在最近Tab
5. **问题**：最近Tab没有刷新，看不到刚打开的文件

#### 根本原因

- 文件打开时已经调用 `addToRecentFiles()` 添加到recent列表
- 但从子页面返回主页时，如果主页仍在最近Tab，不会触发Tab切换逻辑
- Tab切换逻辑中才有 `loadRecentFiles()` 调用
- 因此最近Tab显示的仍是旧数据

#### 解决方案

**方案 A：子页面返回时刷新（推荐）**

在打开子页面的导航代码中，使用 `await` 等待返回，然后检查并刷新：

```dart
// ❌ 错误：没有等待返回
onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => CategoryFilePage(...),
    ),
  );
}

// ✅ 正确：等待返回后刷新最近Tab
onTap: () async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => CategoryFilePage(...),
    ),
  );
  
  // 从子页面返回后，如果当前在最近Tab，刷新最近文件列表
  if (viewModel.currentTab == TabView.recent) {
    presenter.loadRecentFiles();
  }
}
```

**方案 B：使用RouteObserver监听页面返回**

更复杂但更通用的方案，适合需要在多个地方监听的情况。

#### 已修复文件

- `lib/ui/widgets/category_nav_bar.dart` - 分类入口
- `lib/ui/widgets/files_browse_card.dart` - 存储浏览入口
- `lib/ui/widgets/favorites_section.dart` - 收藏Tab的存储入口

#### 测试验证

**测试步骤：**

1. 在主页切换到最近Tab
2. 打开分类页面（如"文档"）
3. 在分类页面中打开一个文件
4. 关闭预览，返回主页
5. **预期**：最近Tab中应该立即显示刚打开的文件

**同样测试存储页面：**

1. 在主页切换到最近Tab  
2. 点击"存储浏览"卡片
3. 在存储页面中打开一个文件
4. 返回主页
5. **预期**：最近Tab中应该立即显示刚打开的文件

#### 预防措施

- [ ] 所有打开子页面的地方都应使用 `await` 等待返回
- [ ] 返回后检查是否需要刷新最近Tab
- [ ] 考虑封装通用的导航方法处理刷新逻辑
- [ ] Code Review 时检查导航代码是否处理了返回后的刷新

#### 相关问题

- 类似问题可能出现在其他需要"返回后刷新"的场景
- 考虑引入统一的页面生命周期管理机制

#### 历史案例

- **2025-12-01**: 从分类页面返回后最近Tab未刷新
  - 场景：在最近Tab打开分类页面→打开文件→返回主页
  - 根因：返回时已在最近Tab，不触发Tab切换的loadRecentFiles()
  - 解决：在category_nav_bar返回后检查并刷新最近Tab
  - 文件：`lib/ui/widgets/category_nav_bar.dart`

---

<a name="e501"></a>
### E501: Duplicate keys found in ListView/GridView

**错误级别：** 🔴 严重  
**首次发现：** 2025-12-08  
**最后更新：** 2025-12-08

#### 错误信息

```
Multiple widgets used the same GlobalKey.
The offending widgets were:
- KeyedSubtree-[GlobalKey#xxxxx]
- KeyedSubtree-[GlobalKey#xxxxx]

A GlobalKey can only be specified on one widget at a time in the widget tree.
```

#### 触发场景

1. 重复文件清理页面显示重复文件列表
2. 分类页面（图片/视频/文档等）显示文件列表
3. 文件路径被重复扫描导致同一文件出现多次

#### 堆栈特征

```dart
#0 GlobalKey._debugReserveFor
#1 BuildOwner._debugTrackElementThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans
#2 Element.inflateWidget
```

#### 根本原因

**路径发现逻辑中的父子路径重叠**：

`getCommonScanPaths()` 三阶段路径发现策略：
1. 阶段1: 添加系统预定义目录（DCIM, Pictures, Music 等）
2. 阶段2: 添加根目录本身（`/storage/emulated/0`）
3. 阶段3: 发现用户自定义文件夹（根目录第一层扫描）

**问题**：阶段2的根目录与阶段1的系统目录、阶段3的用户文件夹形成父子关系：
- 根目录递归扫描会扫描到 `/storage/emulated/0/DCIM` 下的所有文件
- 系统目录会再次扫描 `/storage/emulated/0/DCIM` 下的所有文件
- 结果：每个文件被扫描2次，路径完全相同

**影响**：
- 文件数量统计错误（实际3763个文件，显示7527个）
- ListView/GridView 使用文件路径作为 key，导致 duplicate keys 错误
- 扫描性能降低50%（重复扫描）

#### 解决方案

**方案：移除根目录扫描（阶段2）**

```dart
// ❌ 错误：添加根目录导致路径重叠
Future<List<String>> getCommonScanPaths() async {
  final paths = <String>[];
  
  // 阶段1: 系统目录
  paths.addAll(await _getSystemPaths()); // /storage/emulated/0/DCIM
  
  // 阶段2: 根目录本身（问题所在！）
  paths.add('/storage/emulated/0'); // 会递归扫描所有子目录
  
  // 阶段3: 用户文件夹
  paths.addAll(await _discoverUserFolders()); // /storage/emulated/0/MyFolder
  
  return paths;
}

// ✅ 正确：注释掉阶段2
Future<List<String>> getCommonScanPaths() async {
  final paths = <String>[];
  
  // 阶段1: 系统预定义目录
  final systemPaths = await _getSystemPaths();
  paths.addAll(systemPaths);
  
  // 阶段2: 根目录本身（❌ 已废弃 - 会导致路径重叠）
  // 原因分析：
  // 1. 阶段1的系统目录 + 阶段3的用户文件夹已覆盖根目录的所有子目录
  // 2. 如果再添加根目录并递归扫描，会导致所有文件被扫描2次
  // 3. 根目录直接放置文件的场景极少，可以接受不扫描
  // 结论：删除此阶段，避免2倍重复扫描
  /*
  String? rootPath;
  if (Platform.isAndroid) {
    rootPath = '/storage/emulated/0';
  }
  if (rootPath != null && Directory(rootPath).existsSync()) {
    paths.add(rootPath);
  }
  */
  
  // 阶段3: 用户自定义文件夹
  final discoveredPaths = await _discoverUserFolders();
  paths.addAll(discoveredPaths);
  
  return paths;
}
```

#### 验证结果

修复前：
- 扫描路径数：100个
- 图片数量：7527个（重复扫描）
- 错误：Duplicate keys found

修复后：
- 扫描路径数：99个
- 图片数量：3763个（正常）
- 无错误，UI正常显示

#### 最佳实践

**1. 路径发现策略设计**
- ✅ 确保路径列表中没有父子关系
- ✅ 系统目录 + 用户文件夹已覆盖所有场景
- ✅ 接受不扫描根目录直接放置的文件（极少场景）

**2. 路径去重验证**
```dart
// 在路径发现后添加父子关系检测
final existingPaths = <String>[];
for (final path in paths) {
  // 检查是否与现有路径形成父子关系
  final hasParentChild = existingPaths.any((existing) =>
    path.startsWith('$existing/') || existing.startsWith('$path/'));
  
  if (hasParentChild) {
    logger.w('⚠️ Path overlap detected: $path');
  }
  
  existingPaths.add(path);
}
```

**3. 数据去重保护**
```dart
// 在数据聚合层添加去重
final uniqueFiles = <String, FileItem>{};
for (final file in categoryFiles) {
  uniqueFiles[file.path] = file; // 使用路径作为key自动去重
}
final result = uniqueFiles.values.toList();
```

#### 相关问题

- 类似路径重叠问题可能出现在其他扫描场景
- 考虑建立统一的路径发现和验证机制
- 重复文件扫描、缓存清理等功能都依赖 `getCommonScanPaths()`

#### 历史案例

- **2025-12-08**: 重复文件清理页面显示 duplicate keys 错误
  - 场景：打开重复文件清理 → 扫描完成 → GridView 崩溃
  - 根因：根目录与系统目录路径重叠，导致文件被扫描2次
  - 解决：移除 getCommonScanPaths() 中的根目录添加逻辑
  - 文件：`lib/presenter/file_presenter.dart`
  - 性能提升：扫描速度提升约2倍

---

<a name="e502"></a>
### E502: Category cache statistics not updated

**错误级别：** ⚠️ 中等  
**首次发现：** 2025-12-08  
**最后更新：** 2025-12-08

#### 错误信息

```
提示栏显示："已发现 7527 个图片文件，正在加载..."
实际扫描后：找到 3763 个图片文件
下次进入时：仍然显示 "已发现 7527 个图片文件，正在加载..."
```

#### 触发场景

1. 首次进入分类页面（图片/视频等）
2. 扫描完成后显示正确的文件数量
3. 再次进入该分类页面
4. 提示栏显示的是旧的缓存统计数据

#### 根本原因

**缓存更新不完整**：

分类页面扫描文件时：
1. Step 0: 从 `CategoryFileCacheService` 读取统计缓存显示提示
2. Step 1: 从文件列表缓存加载数据显示
3. Step 2: 后台扫描最新数据
4. Step 3: 更新UI并保存**文件列表缓存**
5. ❌ 未更新**统计数据缓存** ← 问题所在

下次进入时：
- Step 0 仍然读取到旧的统计数据（7527）
- 导致提示信息错误

#### 解决方案

**在扫描完成后同步更新统计数据缓存**

```dart
// ❌ 错误：只保存文件列表缓存
Future<void> _loadCategoryFiles() async {
  // ... 扫描文件 ...
  
  setState(() {
    _files = files;
    _loadingProgress = '找到 ${files.length} 个${categoryInfo.name}文件';
  });
  
  // 保存到缓存
  await _saveToCache(files); // ❌ 只保存文件列表
}

// ✅ 正确：同时更新统计数据缓存
Future<void> _loadCategoryFiles() async {
  // ... 扫描文件 ...
  
  setState(() {
    _files = files;
    _loadingProgress = '找到 ${files.length} 个${categoryInfo.name}文件';
  });
  
  // 保存到缓存
  await _saveToCache(files);
  
  // ✅ 更新统计数据缓存
  try {
    final cacheService = CategoryFileCacheService();
    final currentCounts = await cacheService.getCategoryCounts() ?? {};
    
    // 更新当前分类的文件数
    currentCounts[_getCategoryEnumFromType(widget.categoryType)] = files.length;
    
    // 保存更新后的统计数据
    await cacheService.saveCategoryCounts(currentCounts);
    
    logger.d('Updated category count cache: ${categoryInfo.name} = ${files.length}');
  } catch (e) {
    logger.w('Failed to update category count cache: $e');
  }
}
```

#### 验证结果

修复前：
- 第一次进入：显示 "已发现 7527 个图片"
- 扫描完成：显示 "找到 3763 个图片"
- 第二次进入：显示 "已发现 7527 个图片"（错误）

修复后：
- 第一次进入：显示 "已发现 7527 个图片"（旧缓存）
- 扫描完成：显示 "找到 3763 个图片"，同时更新统计缓存
- 第二次进入：显示 "已发现 3763 个图片"（正确✅）

#### 最佳实践

**1. 缓存一致性管理**
- ✅ 统计数据缓存与文件列表缓存同步更新
- ✅ 避免只更新部分缓存导致数据不一致

**2. 缓存服务设计**
```dart
class CategoryFileCacheService {
  // 统计数据缓存（快速加载提示信息）
  Future<Map<FileCategory, int>?> getCategoryCounts();
  Future<bool> saveCategoryCounts(Map<FileCategory, int> counts);
  
  // 文件列表缓存（详细数据）
  Future<List<FileItem>> loadCache(String key);
  Future<void> saveCache(String key, List<FileItem> files);
  
  // ✅ 确保两者同步
  Future<void> updateCategoryData(CategoryType type, List<FileItem> files) async {
    await saveCache('category_cache_${type.name}', files);
    
    final counts = await getCategoryCounts() ?? {};
    counts[type] = files.length;
    await saveCategoryCounts(counts);
  }
}
```

**3. 用户体验优化**
- Step 0: 显示缓存统计（快速响应）
- Step 1: 加载缓存列表（立即可用）
- Step 2: 后台更新数据
- Step 3: 同步更新所有缓存（保持一致）

#### 相关问题

- 其他分类（视频、音乐、文档）可能存在相同问题
- 综合扫描功能也依赖统计数据缓存
- 需要统一的缓存更新策略

#### 历史案例

- **2025-12-08**: 图片分类提示栏显示过时的文件数量
  - 场景：修复 Bug #6 后发现提示信息未更新
  - 根因：只更新了文件列表缓存，未更新统计数据缓存
  - 解决：在扫描完成后同步更新统计数据缓存
  - 文件：`lib/ui/pages/category_file_page.dart`
  - 影响：用户体验，提示信息不准确但不影响功能

---

<a name="e601"></a>
### E601: Bad state: You tried to access an instance that is not ready yet

**错误级别：** 🔴 严重  
**首次发现：** 2025-12-12  
**最后更新：** 2025-12-12

#### 错误信息

```
Bad state: You tried to access an instance of JunkFileService/TrashFileService that is not ready yet
```

#### 触发场景

1. 在 `initState()` 中同步获取通过 `registerLazySingletonAsync` 注册的服务
2. 服务依赖其他异步服务（如 FilePresenter）
3. 尝试在服务完全初始化前调用其方法

#### 堆栈特征

```dart
#0      _GetItImplementation.get (package:get_it/get_it_impl.dart:xxx)
#1      _JunkFilesPageState.initState (lib/ui/pages/junk_files_page.dart:37)
```

#### 根本原因

GetIt 的 `registerLazySingletonAsync` 注册的服务需要异步初始化，但在 `initState()` 中使用同步方法 `locator<Service>()` 获取会导致服务尚未准备好。

**依赖链示例：**
```dart
// locator.dart
registerLazySingletonAsync<FilePresenter>(...);  // 异步服务

registerLazySingletonAsync<JunkFileService>(() async {
  final filePresenter = await locator.getAsync<FilePresenter>(); // 依赖异步服务
  return JunkFileService(filePresenter: filePresenter);
});

// junk_files_page.dart (错误)
@override
void initState() {
  super.initState();
  _service = locator<JunkFileService>(); // ❌ 同步获取异步服务
  _startScan();
}
```

#### 解决方案

**方案 A：使用 getAsync 异步获取（推荐）**

```dart
class _JunkFilesPageState extends State<JunkFilesPage> {
  JunkFileService? _service; // ✅ 改为可空类型

  @override
  void initState() {
    super.initState();
    _initializeService(); // ✅ 异步初始化
  }

  /// 异步初始化服务
  Future<void> _initializeService() async {
    try {
      _service = await locator.getAsync<JunkFileService>(); // ✅ 异步获取
      if (mounted) {
        _startScan();
      }
    } catch (e) {
      logger.e('初始化 JunkFileService 失败: $e');
      if (mounted) {
        _showError('服务初始化失败: $e');
      }
    }
  }

  /// 开始扫描
  Future<void> _startScan({bool forceRefresh = false}) async {
    if (_service == null) { // ✅ 添加空检查
      logger.e('服务未初始化');
      return;
    }
    
    // ... 使用 _service!.method() 调用服务方法
    final files = await _service!.scanJunkFiles(...);
  }
}
```

**方案 B：改为同步注册（如果可能）**

```dart
// 如果服务不依赖其他异步服务，可以改为同步注册
locator.registerLazySingleton<JunkFileService>(() {
  return JunkFileService(
    filePresenter: locator<FilePresenter>(), // 假设 FilePresenter 已经是同步的
  );
});
```

#### 关键点

1. **服务声明**：`late final Service _service;` → `Service? _service;`
2. **获取方式**：`locator<Service>()` → `await locator.getAsync<Service>()`
3. **空安全**：所有服务调用前检查 `_service == null`
4. **使用方式**：`_service.method()` → `_service!.method()`

#### 相关文件

- `lib/core/di/locator.dart`: 服务注册
- `lib/ui/pages/junk_files_page.dart`: 垃圾文件清理页面
- `lib/ui/pages/trash_files_page.dart`: 回收站页面

#### 检查清单

- [ ] 确认服务在 locator 中是通过 `registerLazySingletonAsync` 注册
- [ ] 将服务字段改为可空类型：`Service? _service;`
- [ ] 创建异步初始化方法：`Future<void> _initializeService()`
- [ ] 使用 `await locator.getAsync<Service>()` 获取服务
- [ ] 在所有服务调用前检查 null：`if (_service == null) return;`
- [ ] 使用非空断言调用方法：`_service!.method()`
- [ ] 添加错误处理和 mounted 检查

#### 影响范围

- 严重性：🔴 应用无法启动或核心功能不可用
- 影响：无法访问垃圾文件清理和回收站功能
- 用户体验：功能完全不可用

#### 预防措施

1. **代码审查**：检查所有使用 `locator<>()` 的地方，确认服务是同步还是异步注册
2. **命名约定**：考虑为异步服务添加命名约定（如 `AsyncJunkFileService`）
3. **文档化**：在 `locator.dart` 中添加注释说明哪些服务需要异步获取
4. **单元测试**：测试异步服务的获取和初始化流程

---

## 维护日志

- **2025-12-01**: 创建错误库，添加 E001（deactivated widget）
- **2025-12-01**: 添加 E401（UI state not cleared on tab switch）
- **2025-12-01**: 添加 E402（Recent tab not refreshed after returning from sub-page）
- **2025-12-08**: 添加 E501（Duplicate keys found - 路径重叠问题）
- **2025-12-08**: 添加 E502（Category cache statistics not updated）
- **2025-12-12**: 添加 E601（Async service access in initState）
- **2025-12-13**: 添加 E303（Infinite rebuild loop - setState in build method）

---

**最后更新：** 2025-12-13  
**维护者：** EasyFile Team
