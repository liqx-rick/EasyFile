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

### UI 状态相关
- [E401: UI state not cleared on tab switch](#e401)
- [E402: Recent tab not refreshed after returning from sub-page](#e402)

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

## 维护日志

- **2025-12-01**: 创建错误库，添加 E001（deactivated widget）
- **2025-12-01**: 添加 E401（UI state not cleared on tab switch）
- **2025-12-01**: 添加 E402（Recent tab not refreshed after returning from sub-page）
- [日期]: 添加 EXXX...

---

**最后更新：** 2025-12-01  
**维护者：** EasyFile Team
