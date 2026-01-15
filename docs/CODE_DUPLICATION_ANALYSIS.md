# ArchiveManagementPage 代码重复详细对比

**目的**: 具体指出哪些代码在两个页面中重复，并说明如何统一  
**生成时间**: 2026-01-13

---

## 📊 重复代码统计

| 重复区域 | ArchiveManagementPage 行数 | CategoryFilePage 对应行数 | 相似度 | 建议处理 |
|---------|--------------------------|-------------------------|--------|---------|
| 搜索逻辑 | 71-87 | 230-260 | 95% | 提取到 Mixin |
| 筛选逻辑 | 133-180 | 286-320 | 90% | 提取到 Mixin |
| 排序逻辑 | 162-177 | 1700-1720 | 100% | 使用 FileComparatorUtil |
| 列表项构建 | 492-540 | 1450-1500 | 85% | 使用 FileCollectionView |
| 单文件操作 | 545-568 | 1740-1760 | 100% | ✅ 已正确复用 |
| 批量操作 | 375-388 | 1050-1080 | 100% | ✅ 已正确复用 |

**总重复代码**: ~190 行（ArchiveManagementPage 的 30%）

---

## 🔴 关键问题代码对比

### 问题 1: 搜索逻辑完全重复

#### ArchiveManagementPage (行 71-87)

```dart
// 搜索功能
late TextEditingController _searchController;
bool _isSearching = false;

/// 搜索内容改变时的回调
void _onSearchChanged() {
  setState(() {
    _isSearching = _searchController.text.isNotEmpty;
    _applyFilterAndSort();  // 需要手动调用重新排序
  });
}

/// 清除搜索
void _clearSearch() {
  _searchController.clear();
  setState(() {
    _isSearching = false;
    _applyFilterAndSort();
  });
}
```

#### CategoryFilePage (行 230-260)

```dart
// 搜索
bool _isSearchMode = false;
String _searchQuery = '';
final TextEditingController _searchController = TextEditingController();
final FocusNode _searchFocusNode = FocusNode();

// 在 _filteredFiles getter 中自动计算搜索结果
List<FileItem> get _filteredFiles {
  var result = _files;

  // 按文件类型筛选
  // ...

  // 按搜索关键词筛选
  if (_searchQuery.isNotEmpty) {
    result = result
        .where(
          (f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
  }

  return result;
}
```

#### 对比分析

| 方面 | ArchiveManagementPage | CategoryFilePage | 优劣 |
|-----|----------------------|-----------------|------|
| 状态管理 | `bool _isSearching` | `String _searchQuery` | ⚠️ 不同步 |
| 搜索触发 | 手动调用 `_applyFilterAndSort()` | 自动计算属性 | ✅ CategoryFilePage 更优雅 |
| 代码复用 | 独立实现 | 独立实现 | ❌ 完全重复 |
| 清除搜索 | 需要手动 `setState()` | 自动更新 | ❌ 容易出错 |

#### 问题案例

```dart
// ArchiveManagementPage 的潜在 bug：
void _clearSearch() {
  _searchController.clear();
  // 如果忘记调用 _applyFilterAndSort()，列表不会更新！
  setState(() {
    _isSearching = false;
    // 需要手动调用，很容易忘记
    _applyFilterAndSort();  // 如果这行被删除，BUG！
  });
}

// 更好的做法（从 CategoryFilePage 学）：
String get _searchQuery => _searchController.text;

void _clearSearch() {
  _searchController.clear();
  // _filteredFiles getter 会自动重新计算，无需手动调用
  setState(() {});
}
```

---

### 问题 2: 排序逻辑完全重复

#### ArchiveManagementPage (行 162-177)

```dart
// 3. 排序
_filteredArchives.sort((a, b) {
  int result;
  switch (_sortBy) {
    case 'name':
      result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      break;
    case 'size':
      result = a.size.compareTo(b.size);
      break;
    case 'time':
      result = a.modified.compareTo(b.modified);
      break;
    default:
      result = 0;
  }
  return _sortAscending ? result : -result;
});
```

#### CategoryFilePage (不直接使用 sort，而是使用 FileComparatorUtil)

```dart
void _applySorting() {
  setState(() {
    final pageId = _getPageIdForCategory();
    final sortType = PageSettingsService().getSortType(pageId);
    final ascending = PageSettingsService().getSortAscending(pageId);
    
    // 使用工具类而非 switch-case
    FileComparatorUtil.sortFilesInPlace(_files, sortType, ascending: ascending);
  });
}
```

#### 对比分析

| 方面 | ArchiveManagementPage | CategoryFilePage | 问题 |
|-----|----------------------|-----------------|------|
| 排序实现 | 自建 switch-case | 使用 FileComparatorUtil | ❌ 维护多个排序逻辑 |
| 排序持久化 | 无 | 通过 PageSettingsService | ❌ 用户偏好丢失 |
| Bug 修复范围 | 需改两处 | 改一处 | ❌ 容易不同步 |
| 代码行数 | 16 行 | 4 行 | ❌ 代码冗余 |

#### 具体危害

假设 FileComparatorUtil 中发现了文件修改时间排序的 bug：

```dart
// FileComparatorUtil 中修复（只需改这一处）
case SortType.modifiedTime:
  return a.modified.toUtc().compareTo(b.modified.toUtc()); // 修复：转换为 UTC
  break;

// 但是 ArchiveManagementPage 还有老的 bug 代码
case 'time':
  result = a.modified.compareTo(b.modified);  // ❌ 仍是 BUG！
  break;
```

**结果**: 
- CategoryFilePage 自动获得修复 ✅
- ArchiveManagementPage 仍然有 bug ❌

---

### 问题 3: 筛选逻辑重复实现

#### ArchiveManagementPage (行 133-180)

```dart
void _applyFilterAndSort() {
  // 1. 筛选
  if (_selectedFilter == 'all') {
    _filteredArchives = List.from(_allArchives);
  } else {
    _filteredArchives = _allArchives.where((file) {
      final ext = FileUtils.getExtension(file.name).toLowerCase();
      switch (_selectedFilter) {
        case 'zip':
          return ext == 'zip';
        case 'rar':
          return ext == 'rar';
        case '7z':
          return ext == '7z';
        case 'other':
          return !['zip', 'rar', '7z'].contains(ext);
        default:
          return true;
      }
    }).toList();
  }
  
  // 2. 搜索过滤
  if (_isSearching && _searchController.text.isNotEmpty) {
    final searchQuery = _searchController.text.toLowerCase();
    _filteredArchives = _filteredArchives.where((file) {
      return file.name.toLowerCase().contains(searchQuery);
    }).toList();
  }

  // 3. 排序（见问题2）
  // ...
}
```

#### CategoryFilePage (行 286-320)

```dart
List<FileItem> get _filteredFiles {
  var result = _files;

  // 按文件类型筛选
  if (widget.categoryType == CategoryType.documents &&
      _documentTypeFilter != DocumentFileType.all) {
    result =
        result.where((f) => _documentTypeFilter.matches(f.name)).toList();
  } else if (widget.categoryType == CategoryType.downloads &&
      _downloadTypeFilter != DownloadFileType.all) {
    result =
        result.where((f) => _downloadTypeFilter.matches(f.name)).toList();
  }

  // 按搜索关键词筛选
  if (_searchQuery.isNotEmpty) {
    result = result
        .where(
          (f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
  }

  return result;
}
```

#### 对比分析

| 方面 | ArchiveManagementPage | CategoryFilePage | 问题 |
|-----|----------------------|-----------------|------|
| 搜索过滤 | 手动实现 (每次都 where) | 同 | ❌ 重复代码 |
| 格式筛选 | switch-case | 通过对象模式（DocumentFileType.matches） | ⚠️ 架构不统一 |
| 计算时机 | 需要手动调用 setState | 自动计算属性 | ❌ 容易遗漏 |

---

### 问题 4: 列表项构建逻辑重复

#### ArchiveManagementPage (行 492-540)

```dart
Widget _buildArchiveItem(FileItem archive, ThemeData theme) {
  final ext = FileUtils.getExtension(archive.name).toUpperCase();
  final parentDir = archive.path.substring(0, archive.path.lastIndexOf('/'));
  final isSelected = _selectionController.contains(archive.path);
  final isSelectionMode = _selectionController.isSelectionMode;

  return GestureDetector(
    onLongPress: isSelectionMode ? null : () {
      _selectionController.select(archive.path);
    },
    onTap: () {
      if (isSelectionMode) {
        _selectionController.toggle(archive.path);
      } else {
        _showOperationsMenu(archive);
      }
    },
    child: ListTile(
      leading: isSelectionMode
          ? Checkbox(
              value: isSelected,
              onChanged: (value) {
                _selectionController.toggle(archive.path);
              },
            )
          : Icon(
              Icons.folder_zip,
              size: 40,
              color: _getFormatColor(ext),
            ),
      title: Text(
        archive.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${FileSizeFormatter.formatBytes(archive.size)} • ${TimeFormatter.formatRelativeTime(archive.modified)}',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            parentDir,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
      trailing: !isSelectionMode
          ? IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showOperationsMenu(archive),
            )
          : null,
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.1),
    ),
  );
}
```

#### CategoryFilePage 对应逻辑 (使用 FileCollectionView)

```dart
return FileCollectionView(
  items: _filteredFiles,
  gridMode: _isGridView,
  config: config,
  selectionController: _selectionController,
  showCheckbox: isEditMode,
  onItemTap: (file) => _previewFile(file),
  onItemLongPress: (file) => enterEditMode(),
  // ... 其他配置
);
```

#### 对比分析

| 方面 | ArchiveManagementPage | CategoryFilePage | 差异 |
|-----|----------------------|-----------------|------|
| 实现方式 | 自建 ListTile 构建 | 使用 FileCollectionView 组件 | ❌ 重复 UI 构建 |
| 代码行数 | 50+ 行 | 10 行 | ❌ 冗余 |
| 虚拟滚动 | 无（简单 ListView.builder） | 有（自动） | ❌ 大量文件时性能差 |
| 长按进入编辑模式 | 手动实现 | 自动支持 | ❌ 代码重复 |
| 编辑模式 UI 切换 | 手动管理 Checkbox | 自动切换 | ❌ 容易出错 |

#### 特定问题：长按逻辑

```dart
// ArchiveManagementPage
onLongPress: isSelectionMode ? null : () {
  _selectionController.select(archive.path);
},

// 问题：没有调用 enterEditMode()！
// 应该是：
onLongPress: isSelectionMode ? null : () {
  enterEditMode();  // 从 EditModeMixin 获得
  _selectionController.select(archive.path);
},

// CategoryFilePage + FileCollectionView
onItemLongPress: (file) => enterEditMode(),
// ✅ 正确，使用 EditModeMixin 的方法
```

---

## 🟢 正确复用的部分

### 已正确复用：单文件操作服务

#### ArchiveManagementPage (行 545-568)

```dart
void _showOperationsMenu(FileItem archive) {
  final presenter = locator<FilePresenter>();
  final viewModel = context.read<FileViewModel>();

  final service = SingleFileOperationsService(
    context: context,
    viewModel: viewModel,
    presenter: presenter,
    onRefresh: _scanArchives,
  );

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SingleFileOperationsSheet(
      file: archive,
      service: service,
    ),
  );
}
```

#### 评价

✅ **正确复用！** 
- 使用标准的 SingleFileOperationsService
- 与 CategoryFilePage 使用完全相同的接口
- 无重复代码

---

### 已正确复用：批量操作服务

#### ArchiveManagementPage (行 375-388)

```dart
Future<void> _handleBatchDelete() async {
  final presenter = locator<FilePresenter>();
  final viewModel = context.read<FileViewModel>();
  
  final batchService = BatchOperationsService(
    viewModel: viewModel,
    presenter: presenter,
    onRefresh: _scanArchives,
    onExitSelectionMode: () {
      _selectionController.clear();
    },
  );
  
  if (!mounted) return;
  
  await batchService.batchDelete(
    context,
    _selectionController.selected,
  );
}
```

#### 评价

✅ **正确复用！**
- 使用标准的 BatchOperationsService
- 正确处理了 `onExitSelectionMode` 回调
- 无重复代码

---

### 已正确复用：SelectionController

#### ArchiveManagementPage (行 39-42)

```dart
late final SelectionController _selectionController;

@override
void initState() {
  super.initState();
  _selectionController = SelectionController();
  _selectionController.selectedNotifier.addListener(_onSelectionChanged);
}
```

#### 评价

✅ **正确复用！**
- 使用了通用的 SelectionController
- 与 CategoryFilePage 使用完全相同
- 自动获得编辑模式管理能力

---

## 📋 需要统一的编码习惯

### 习惯 1: 搜索状态命名

| 代码库 | 搜索状态变量 | 搜索查询变量 |
|-------|-----------|-----------|
| ArchiveManagementPage | `_isSearching` (bool) | 无（从 controller 获取） |
| CategoryFilePage | `_isSearchMode` (bool) | `_searchQuery` (String) |

**建议统一为**:
```dart
// 推荐做法
late final TextEditingController _searchController;

String get searchQuery => _searchController.text;

bool get isSearching => searchQuery.isNotEmpty;
```

### 习惯 2: 排序状态管理

| 代码库 | 排序方式 |
|-------|--------|
| ArchiveManagementPage | 字符串 + switch-case (`'name'`, `'size'`, `'time'`) |
| CategoryFilePage | SortType 枚举 + PageSettingsService |

**建议统一为**:
```dart
// 推荐做法
SortType _sortType = SortType.name;

void setSortType(SortType type) {
  setState(() {
    _sortType = type;
    final pageId = _getPageId();
    PageSettingsService().setSortType(pageId, type);
  });
}
```

### 习惯 3: 文件过滤方式

| 代码库 | 筛选方式 |
|-------|--------|
| ArchiveManagementPage | 字符串 + switch-case (`'all'`, `'zip'`, `'rar'`) |
| CategoryFilePage | 枚举 + 对象方法 (DocumentFileType.matches) |

**建议统一为**:
```dart
// 推荐做法
enum ArchiveFormat {
  all,
  zip,
  rar,
  sevenZ,
  other;

  bool matches(String filename) {
    // 实现筛选逻辑
  }
}
```

---

## 🛠️ 快速修复方案

### 方案 A: 最小改动（1h）

```dart
// 仅修改 ArchiveManagementPage，不创建新的 Mixin

// 1. 删除 _isSearching，使用 getter
bool get _isSearching => _searchController.text.isNotEmpty;

// 2. 简化 _clearSearch()
void _clearSearch() {
  _searchController.clear();
  setState(() => _applyFilterAndSort());
}

// 3. 改进排序逻辑
void _applySorting() {
  setState(() {
    final sortType = _getSortType();
    applySorting(filteredFiles, sortType, ascending: _sortAscending);
  });
}

// 4. 使用 FileCollectionView
return FileCollectionView(
  items: filteredFiles,
  // ... 其他配置
);
```

**工作量**: 1 小时  
**优点**: 快速见效  
**缺点**: 不是从根本上解决代码重复问题

### 方案 B: 完全重构（7.5h）

实施完整的 CategoryLikePageMixin + ArchiveFileDataSource 方案（见重构指南）

**工作量**: 7.5 小时  
**优点**: 完全消除代码重复，建立可维护的架构  
**缺点**: 时间成本高

### 方案 C: 渐进式重构（推荐）

**阶段 1** (1h): 方案 A 的快速改进  
**阶段 2** (2h): 创建 CategoryLikePageMixin  
**阶段 3** (2h): 迁移到新 Mixin  
**阶段 4** (2.5h): 使用 FileCollectionView + PageSettingsService

---

## ✅ 完成标志检查表

- [ ] 搜索逻辑与 CategoryFilePage 保持一致
- [ ] 排序逻辑使用 FileComparatorUtil
- [ ] 排序偏好通过 PageSettingsService 保存
- [ ] 列表构建使用 FileCollectionView
- [ ] 长按进入编辑模式（调用 enterEditMode()）
- [ ] 编辑模式状态使用 EditModeMixin
- [ ] 代码重复度 < 10%
- [ ] ArchiveManagementPage < 380 行
- [ ] 所有测试通过

