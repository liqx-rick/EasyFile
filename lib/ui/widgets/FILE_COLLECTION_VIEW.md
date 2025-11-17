# FileCollectionView 使用文档

## 概述

`FileCollectionView` 是一个轻量级、可配置的文件集合视图组件，支持列表/网格视图、分组、选择、下拉刷新等功能。

## 核心功能

### 1. 基础用法

```dart
FileCollectionView(
  items: fileList,
  gridMode: false,  // true 为网格视图
  onTap: (file) => print('点击: ${file.name}'),
  onLongPress: (file) => print('长按: ${file.name}'),
)
```

### 2. 分组显示

```dart
FileCollectionView(
  groups: [
    FileGroup(
      key: 'images',
      title: '图片文件',
      items: imageFiles,
      isCollapsible: true,
      initiallyExpanded: true,
    ),
    FileGroup(
      key: 'documents',
      title: '文档文件',
      items: docFiles,
    ),
  ],
  groupHeaderBuilder: (context, group) {
    return Container(
      padding: EdgeInsets.all(12),
      child: Text(group.title, style: TextStyle(fontWeight: FontWeight.bold)),
    );
  },
)
```

### 3. 选择模式

```dart
final selectionController = SelectionController();

FileCollectionView(
  items: fileList,
  selectionController: selectionController,
)

// 操作选择
selectionController.selectAll(fileList.map((f) => f.path).toList());
selectionController.clear();
print('已选中: ${selectionController.count}');
```

### 4. Header 插槽

```dart
FileCollectionView(
  items: fileList,
  headerBuilder: (context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: SearchBar(),
    );
  },
  stickyHeader: true,  // false 则 header 随内容滚动
)
```

### 5. 下拉刷新

```dart
FileCollectionView(
  items: fileList,
  onRefresh: () async {
    await loadFiles();
  },
)
```

### 6. 性能优化

```dart
FileCollectionView(
  items: largeFileList,
  cacheExtent: 500,  // 预加载范围
  onScrollNearEnd: () {
    // 触发分页加载
    loadMoreFiles();
  },
)
```

## API 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `items` | `List<FileItem>?` | 文件列表（与 groups 二选一） |
| `groups` | `List<FileGroup>?` | 分组列表 |
| `gridMode` | `bool` | 是否网格视图 |
| `itemBuilder` | `Widget Function(FileItem)?` | 自定义 item 构建器 |
| `groupHeaderBuilder` | `Widget Function(BuildContext, FileGroup)?` | 自定义分组 header |
| `onTap` | `void Function(FileItem)?` | 点击回调 |
| `onLongPress` | `void Function(FileItem)?` | 长按回调 |
| `headerBuilder` | `WidgetBuilder?` | Header 构建器 |
| `stickyHeader` | `bool` | Header 是否固定 |
| `selectionController` | `SelectionController?` | 选择控制器 |
| `onRefresh` | `Future<void> Function()?` | 下拉刷新回调 |
| `onScrollNearEnd` | `VoidCallback?` | 滚动到底部回调 |
| `cacheExtent` | `double?` | 缓存范围 |

## SelectionController API

```dart
// 属性
int count                          // 已选数量
bool isSelecting                   // 是否处于选择模式
Set<String> selected               // 已选路径集合

// 方法
void select(String path)           // 选中
void deselect(String path)         // 取消选中
void toggle(String path)           // 切换选择状态
void selectAll(List<String> paths) // 全选
void clear()                       // 清除选择
bool contains(String path)         // 是否包含
void dispose()                     // 销毁
```

## 迁移示例

### 迁移前

```dart
ListView.builder(
  itemCount: files.length,
  itemBuilder: (c, i) {
    final file = files[i];
    return ListTile(
      title: Text(file.name),
      onTap: () => openFile(file),
    );
  },
)
```

### 迁移后

```dart
FileCollectionView(
  items: files,
  onTap: openFile,
)
```

## 注意事项

1. `items` 和 `groups` 必须提供其中一个
2. 选择模式由外部控制，组件内部不维护选择状态
3. Header 如果设置为 `stickyHeader: false`，会使用 CustomScrollView 包裹
4. 分组模式下不支持网格视图
5. 记得在页面 dispose 时调用 `selectionController.dispose()`
