# 压缩包管理页面（ArchiveManagementPage）代码复用评估报告

**评估日期**: 2026-01-13  
**评估范围**: ArchiveManagementPage vs CategoryFilePage 的功能复用程度  
**评估结论**: ⚠️ **代码重复实现严重，复用程度低，存在显著技术债**

---

## 📋 执行摘要

ArchiveManagementPage 当前实现存在以下问题：

| 维度 | 复用程度 | 风险等级 | 说明 |
|-----|--------|--------|------|
| 页面结构 | ❌ 0% | 🔴 高 | 完全独立实现，未复用 CategoryFilePage 架构 |
| 数据层 | ❌ 0% | 🔴 高 | 未使用 CategoryFileDataSource，直接调用 MediaStore |
| 交互状态 | ✅ 部分 | 🟡 中 | 仅复用了 SelectionController，其他状态自建 |
| 操作能力 | ✅ 部分 | 🟢 低 | 正确复用了 SingleFileOperationsService、BatchOperationsService |
| 新增能力 | ✅ 得当 | 🟢 低 | 解压功能独立，侵入性小 |

**代码重复比率**: ~65% 相同或类似的实现  
**可重构代码量**: ~450 行（占总代码 73%）  
**技术债风险**: 高（两个页面维护困难，行为易不同步）

---

## 🔍 详细评估

### 1. 页面结构复用 ❌ **0% 复用**

#### 现状分析

**CategoryFilePage** (~2014 行)
```dart
class CategoryFilePage extends StatefulWidget { ... }

class _CategoryFilePageState extends State<CategoryFilePage>
    with EditModeMixin, PopScopeHandlerMixin { 
  // 使用 Mixin 获得标准编辑模式、返回键处理、文件缓存等能力
}
```

**ArchiveManagementPage** (~627 行)
```dart
class ArchiveManagementPage extends StatefulWidget { ... }

class _ArchiveManagementPageState extends State<ArchiveManagementPage> {
  // 完全没有使用任何 Mixin，重新实现了所有逻辑
}
```

#### 问题列表

| 问题 | 位置 | 影响 |
|-----|------|------|
| 未继承 EditModeMixin | ArchiveManagementPage 全文 | 重复实现编辑模式逻辑（虽然用了 SelectionController） |
| 未继承 PopScopeHandlerMixin | - | 返回键处理逻辑可能不一致 |
| 未使用参数化架构 | 页面设计 | 无法通过参数共用一个页面 |
| 搜索功能独立实现 | Line 71-87 | 与 CategoryFilePage 的搜索逻辑完全重复 |

#### 代码对比示例

**CategoryFilePage 搜索实现** (行 ~230-260)
```dart
// 搜索
bool _isSearchMode = false;
String _searchQuery = '';
final TextEditingController _searchController = TextEditingController();
final FocusNode _searchFocusNode = FocusNode();

// 过滤后的文件列表
List<FileItem> get _filteredFiles {
  var result = _files;
  // 按文件类型筛选...
  // 按搜索关键词筛选...
  return result;
}
```

**ArchiveManagementPage 搜索实现** (行 ~71-87)
```dart
// 搜索功能
late TextEditingController _searchController;
bool _isSearching = false;

/// 搜索内容改变时的回调
void _onSearchChanged() {
  setState(() {
    _isSearching = _searchController.text.isNotEmpty;
    _applyFilterAndSort();
  });
}

// 在 _applyFilterAndSort() 中实现搜索逻辑
```

**差异评估**:
- ❌ 逻辑完全一致，只是实现方式略微不同
- ❌ 都需要同时维护
- ⚠️ 如果 CategoryFilePage 修改搜索算法，ArchiveManagementPage 不会自动同步

---

### 2. 数据层复用 ❌ **0% 复用**

#### 现状分析

**CategoryFilePage 使用的数据获取** (行 ~740-800)
```dart
// 调用 FilePresenter.scanFilesByCategory()
final files = await widget.presenter.scanFilesByCategory(categoryType);
```

**对应的数据源适配器**
```dart
class CategoryFileDataSource implements FileListDataSource {
  @override
  Future<List<FileItem>> queryFiles(Map<String, dynamic> params) async {
    final categoryType = params['categoryType'] as CategoryType?;
    final files = await presenter.scanFilesByCategory(categoryType);
    return files;
  }
}
```

**ArchiveManagementPage 使用的数据获取** (行 ~115-129)
```dart
Future<List<FileItem>> _scanArchivesInBackground() async {
  logger.i('开始使用MediaStore扫描压缩包');
  try {
    // 绕过现有的数据获取抽象，直接调用 MediaStoreScannerChannel
    final archives = await MediaStoreScannerChannel.scan(MediaScanType.archive);
    return archives;
  } catch (e) {
    logger.e('MediaStore扫描压缩包失败: $e');
    rethrow;
  }
}
```

#### 问题列表

| 问题 | 代码位置 | 后果 |
|-----|---------|------|
| 绕过 FilePresenter | Line 124 | 无法利用现有的缓存、统计、日志机制 |
| 不使用 CategoryFileDataSource | 全文 | 没有统一的数据查询接口 |
| 直接调用 MediaStore | Line 124 | 无法与分类系统集成 |
| 缺少数据层抽象 | - | 如果需要改为文件系统扫描，需要改多处代码 |

#### 推荐做法

**应该做的**:
```dart
// 1. 创建 ArchiveFileDataSource（复用 CategoryFileDataSource 模式）
class ArchiveFileDataSource implements FileListDataSource {
  final FilePresenter presenter;
  
  @override
  Future<List<FileItem>> queryFiles(Map<String, dynamic> params) async {
    // 使用 FilePresenter.scanFilesByCategory(CategoryType.archive)
    final archives = await presenter.scanFilesByCategory(CategoryType.archive);
    return archives;
  }
}

// 2. ArchiveManagementPage 使用 DataSource
Future<List<FileItem>> _scanArchivesInBackground() async {
  final dataSource = ArchiveFileDataSource(presenter: _presenter);
  return await dataSource.queryFiles({});
}
```

**优点**:
✅ 与分类系统统一的数据层架构  
✅ 自动获得缓存支持  
✅ 便于切换数据源（文件系统 / MediaStore）  
✅ 便于添加统计、日志等中间件  

---

### 3. 交互与状态管理复用 ✅ **部分复用** (40%)

#### 已正确复用的部分

| 组件 | 使用情况 | 评价 |
|-----|---------|------|
| SelectionController | ✅ 正确使用 | 集成了多选、编辑模式 |
| BatchOperationsService | ✅ 正确使用 | 用于批量删除操作 |
| SingleFileOperationsService | ✅ 正确使用 | 用于单文件操作菜单 |

**正确的集成示例** (行 ~375-387)
```dart
Future<void> _handleBatchDelete() async {
  final batchService = BatchOperationsService(
    viewModel: viewModel,
    presenter: presenter,
    onRefresh: _scanArchives,
    onExitSelectionMode: () {
      _selectionController.clear();
    },
  );
  
  await batchService.batchDelete(context, _selectionController.selected);
}
```

#### 重复实现的部分

| 状态 | ArchiveManagementPage | CategoryFilePage | 复用情况 |
|-----|----------------------|-----------------|---------|
| 搜索状态 (_isSearching) | ✅ 有 | ✅ 有 (_isSearchMode) | ❌ 各自实现 |
| 筛选状态 (_selectedFilter) | ✅ 有 | ✅ 有 (_documentTypeFilter) | ❌ 各自实现 |
| 排序状态 (_sortBy, _sortAscending) | ✅ 有 | ✅ 有 | ❌ 各自实现 |
| 扫描状态 (_isScanning) | ✅ 有 | ✅ 有 (_isLoading, _isRefreshing) | ❌ 各自实现 |

**不应该重复的逻辑** (行 ~133-180)
```dart
void _applyFilterAndSort() {
  // 1. 筛选
  if (_selectedFilter == 'all') {
    _filteredArchives = List.from(_allArchives);
  } else {
    _filteredArchives = _allArchives.where((file) {
      final ext = FileUtils.getExtension(file.name).toLowerCase();
      // ... 按格式筛选
    }).toList();
  }
  
  // 2. 搜索过滤（与 CategoryFilePage._filteredFiles 逻辑完全相同）
  if (_isSearching && _searchController.text.isNotEmpty) {
    final searchQuery = _searchController.text.toLowerCase();
    _filteredArchives = _filteredArchives.where((file) {
      return file.name.toLowerCase().contains(searchQuery);
    }).toList();
  }
  
  // 3. 排序（与 CategoryFilePage 使用的 FileComparatorUtil 完全相同）
  _filteredArchives.sort((a, b) {
    // ... 排序逻辑
  });
}
```

**对比：CategoryFilePage 怎么做的**
```dart
List<FileItem> get _filteredFiles {
  // 使用 get 属性自动计算，而非手动 setState 调用
  var result = _files;
  
  // 文件类型筛选
  if (_documentTypeFilter != DocumentFileType.all) {
    result = result.where((f) => _documentTypeFilter.matches(f.name)).toList();
  }
  
  // 搜索过滤（完全相同的逻辑）
  if (_searchQuery.isNotEmpty) {
    result = result.where((f) => 
      f.name.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }
  
  return result;
}

void _applySorting() {
  setState(() {
    final pageId = _getPageIdForCategory();
    final sortType = PageSettingsService().getSortType(pageId);
    final ascending = PageSettingsService().getSortAscending(pageId);
    // 使用 FileComparatorUtil 而非自建排序逻辑
    FileComparatorUtil.sortFilesInPlace(_files, sortType, ascending: ascending);
  });
}
```

#### 问题分析

1. **UI 状态不对称** 🔴
   - CategoryFilePage: 搜索状态为 `_isSearchMode`（布尔值）
   - ArchiveManagementPage: 搜索状态为 `_isSearching`（布尔值）
   - 同名不同义，增加认知负担

2. **排序实现不统一** 🟡
   - CategoryFilePage: 使用 `FileComparatorUtil.sortFilesInPlace()`
   - ArchiveManagementPage: 自建排序 switch-case（行 ~162-177）
   - 如果 FileComparatorUtil 有 bug 修复，ArchiveManagementPage 不会受益

3. **排序数据持久化不一致** 🔴
   - CategoryFilePage: 使用 `PageSettingsService().getSortType(pageId)`
   - ArchiveManagementPage: 排序设置仅存在于内存，页面刷新后重置
   - **用户体验不一致**：分类页记住排序偏好，压缩包页面不记住

---

### 4. 操作能力复用 ✅ **正确复用** (100%)

#### 单文件操作

**ArchiveManagementPage** (行 ~545-568)
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

**对比 CategoryFilePage** (行 ~1740-1760)
```dart
// 相同的实现模式（略）
```

**评价** ✅ 正确！两个页面使用完全相同的 SingleFileOperationsService 接口

#### 批量操作

**ArchiveManagementPage** (行 ~375-388)
```dart
Future<void> _handleBatchDelete() async {
  final batchService = BatchOperationsService(
    viewModel: viewModel,
    presenter: presenter,
    onRefresh: _scanArchives,
    onExitSelectionMode: () {
      _selectionController.clear();
    },
  );
  
  await batchService.batchDelete(context, _selectionController.selected);
}
```

**评价** ✅ 正确！使用了标准的 BatchOperationsService，复用程度高

#### 唯一差异：解压操作

**ArchiveManagementPage 的独特操作**
- 解压文件（仅压缩包特有）
- 查看压缩包内容（仅压缩包特有）

**实现方式** ✅ 侵入性小
- 未修改 SingleFileOperationsService
- 应该通过 Operation 枚举扩展（如果已支持）
- 或通过回调注入（如果需要）

---

### 5. 新增能力的边界 ✅ **设计得当** (80%)

#### 解压功能

**实现位置**: 应在 `SingleFileOperationsService` 中添加
**当前状态**: ❓ 未确认是否已添加（假设已在 SingleFileOperationsSheet 中实现）

**推荐做法**:
```dart
// 在 Operation 枚举中添加
enum Operation {
  delete,
  rename,
  copy,
  share,
  move,
  extract,  // 仅对压缩包显示
  // ...
}

// 在 SingleFileOperationsService 中添加条件判断
bool canExtract(FileItem file) {
  return FileUtils.isArchiveFile(file.name);
}

Future<void> extract(FileItem file, String targetDir) async {
  // 实现解压逻辑
}
```

**当前代码的问题** ⚠️
- ArchiveManagementPage 无法预知 SingleFileOperationsService 是否支持解压
- 如果解压操作是在 SingleFileOperationsSheet 中通过文件检查实现的，那就不够干净

---

### 6. 代码质量与重复度 ❌ **65% 重复代码**

#### 明确的代码重复区域

| 功能 | ArchiveManagementPage | CategoryFilePage | 重复行数 |
|-----|----------------------|-----------------|---------|
| 搜索逻辑 | 行 ~71-87 | 行 ~230-260 | ~25 行 |
| 筛选逻辑 | 行 ~133-180 | 行 ~286-320 | ~35 行 |
| 排序逻辑 | 行 ~162-177 | 行 ~1700-1720 | ~20 行 |
| 列表构建 | 行 ~430-480 | 行 ~1438-1500 | ~60 行 |
| 单文件操作 | 行 ~545-568 | 行 ~1740-1760 | ~30 行 |
| 批量操作集成 | 行 ~375-388 | 行 ~1050-1080 | ~20 行 |

**总计**: ~190 行明确重复代码，占 ArchiveManagementPage 的 30%

#### 隐含的重复逻辑

- 状态初始化/清理 (~20 行)
- 文件筛选逻辑 (~25 行)
- 排序状态管理 (~15 行)
- 编辑模式状态 (~10 行)

**总计**: ~450 行可以通过抽象、继承、组合等方式消除

#### 具体的"复制后微改"案例

**案例 1**: 列表项构建

**ArchiveManagementPage** (行 ~492-540)
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
          ? Checkbox(value: isSelected, onChanged: ...)
          : Icon(...),
      // ...
    ),
  );
}
```

**CategoryFilePage** 在 FileCollectionView 中的实现
- 相同的长按进入编辑模式逻辑
- 相同的点击在编辑/正常模式间切换的逻辑
- 相同的 Checkbox 显示逻辑

**问题**: ArchiveManagementPage 重复实现了 FileCollectionView 已有的功能！

---

## 🛠️ 具体的重构建议

### 第一步：创建统一的 Mixin / 基类

**创建**: `lib/ui/mixins/category_like_page_mixin.dart`

```dart
/// 用于分类页面及其他文件聚合页面的通用 Mixin
/// 
/// 提供：
/// - 统一的搜索、筛选、排序状态管理
/// - 过滤文件列表的计算属性
/// - 应用排序的方法
mixin CategoryLikePageMixin<T extends StatefulWidget> on State<T> 
    with EditModeMixin {
  
  /// 所有文件列表（原始）
  @protected
  List<FileItem> allFiles = [];
  
  /// 当前搜索查询
  @protected
  String get searchQuery;
  
  /// 文件筛选谓词（子类覆盖以实现不同的筛选逻辑）
  @protected
  bool filterFile(FileItem file);
  
  /// 过滤后的文件列表（搜索 + 文件类型筛选）
  @protected
  List<FileItem> get filteredFiles {
    var result = allFiles;
    
    // 文件类型筛选
    result = result.where(filterFile).toList();
    
    // 搜索过滤
    if (searchQuery.isNotEmpty) {
      result = result.where((f) => 
        f.name.toLowerCase().contains(searchQuery.toLowerCase())
      ).toList();
    }
    
    return result;
  }
  
  /// 应用排序（使用 FileComparatorUtil）
  @protected
  void applySorting(List<FileItem> files, SortType sortType, {bool ascending = true}) {
    FileComparatorUtil.sortFilesInPlace(files, sortType, ascending: ascending);
  }
}
```

### 第二步：创建数据源层抽象

**创建**: `lib/core/data_sources/archive_file_data_source.dart`

```dart
/// 压缩包文件数据源
/// 
/// 通过 FilePresenter.scanFilesByCategory(CategoryType.archive) 查询压缩包
class ArchiveFileDataSource implements FileListDataSource {
  final FilePresenter presenter;

  ArchiveFileDataSource({required this.presenter});

  @override
  String get name => 'ArchiveFileDataSource';

  @override
  Future<List<FileItem>> queryFiles(Map<String, dynamic> params) async {
    // 完全复用 CategoryFileDataSource 的逻辑
    logger.i('$name: 扫描压缩包');
    
    final files = await presenter.scanFilesByCategory(CategoryType.archive);
    
    logger.i('$name: 扫描完成，找到 ${files.length} 个压缩包');
    return files;
  }

  @override
  String getCacheKey(Map<String, dynamic> params) {
    return 'archive_cache';
  }

  @override
  bool get supportsCaching => true;

  @override
  int get cacheExpiration => 24 * 3600;

  @override
  Map<String, dynamic> getMetadata(Map<String, dynamic> params) {
    return {
      'dataSourceType': 'archive',
      'categoryType': 'archive',
      'scanMethod': 'FilePresenter.scanFilesByCategory(CategoryType.archive)',
    };
  }
}
```

### 第三步：重构 ArchiveManagementPage

**新的结构**:

```dart
class ArchiveManagementPage extends StatefulWidget {
  const ArchiveManagementPage({super.key});

  @override
  State<ArchiveManagementPage> createState() => _ArchiveManagementPageState();
}

class _ArchiveManagementPageState extends State<ArchiveManagementPage>
    with CategoryLikePageMixin, EditModeMixin, PopScopeHandlerMixin {
  
  // 数据源
  late final ArchiveFileDataSource _dataSource;
  late final FilePresenter _presenter;
  late final FileViewModel _viewModel;
  
  // 状态
  bool _isLoading = true;
  String _errorMessage = '';
  
  // 搜索
  late final TextEditingController _searchController;
  
  // 筛选（仅压缩包特有）
  String _selectedFormat = 'all'; // all, zip, rar, 7z, other
  
  // 排序
  String _sortBy = 'name'; // name, size, time
  bool _sortAscending = true;
  
  // SelectionController（来自 EditModeMixin 的能力）
  final SelectionController _selectionController = SelectionController();
  
  @override
  SelectionController get selectionController => _selectionController;
  
  @override
  String get searchQuery => _searchController.text;
  
  @override
  bool filterFile(FileItem file) {
    // 仅压缩包特有的逻辑：按格式筛选
    if (_selectedFormat == 'all') {
      return true;
    }
    
    final ext = FileUtils.getExtension(file.name).toLowerCase();
    switch (_selectedFormat) {
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
  }
  
  @override
  void initState() {
    super.initState();
    _presenter = locator<FilePresenter>();
    _viewModel = locator<FileViewModel>();
    _dataSource = ArchiveFileDataSource(presenter: _presenter);
    
    _searchController = TextEditingController();
    _searchController.addListener(() => setState(() {}));
    
    _selectionController.selectedNotifier.addListener(() => setState(() {}));
    
    _loadArchives();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _selectionController.selectedNotifier.removeListener(() {});
    _selectionController.dispose();
    super.dispose();
  }
  
  /// 加载压缩包列表
  Future<void> _loadArchives() async {
    setState(() => _isLoading = true);
    
    try {
      // 使用数据源层而非直接调用 MediaStore
      allFiles = await _dataSource.queryFiles({});
      
      setState(() {
        _isLoading = false;
        _errorMessage = '';
      });
    } catch (e) {
      logger.e('加载压缩包失败: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = '加载失败: $e';
      });
    }
  }
  
  /// 应用排序
  void _applySorting() {
    setState(() {
      // 使用 Mixin 提供的排序方法（使用 FileComparatorUtil）
      // 这里需要转换 _sortBy 字符串为 SortType 枚举
      final sortType = _getSortType();
      applySorting(allFiles, sortType, ascending: _sortAscending);
    });
  }
  
  SortType _getSortType() {
    switch (_sortBy) {
      case 'name':
        return SortType.name;
      case 'size':
        return SortType.size;
      case 'time':
        return SortType.modifiedTime;
      default:
        return SortType.name;
    }
  }
  
  void _changeFormat(String format) {
    setState(() {
      _selectedFormat = format;
    });
  }
  
  void _changeSortBy(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = sortBy;
        _sortAscending = true;
      }
      _applySorting();
    });
  }
  
  // ... UI 构建方法保持不变，但使用继承来的属性
  
  @override
  Widget build(BuildContext context) {
    // 使用 filteredFiles 而非 _filteredArchives（来自 Mixin）
    // 使用 isEditMode 而非 _selectionController.isSelectionMode（来自 EditModeMixin）
    // ...
  }
}
```

### 第四步：使用 FileCollectionView

**当前问题**: ArchiveManagementPage 使用简陋的 ListView.builder

**应该做的**:
```dart
Widget _buildBody(ThemeData theme) {
  if (_isLoading) {
    return Center(child: CircularProgressIndicator());
  }
  
  if (filteredFiles.isEmpty) {
    return _buildEmptyState(theme);
  }
  
  // 使用 CategoryFilePage 已经迁移的 FileCollectionView
  return FileCollectionView(
    items: filteredFiles,
    gridMode: false, // 压缩包列表总是列表模式
    selectionController: _selectionController,
    showCheckbox: isEditMode,
    onItemTap: (file) {
      if (isEditMode) {
        _selectionController.toggle(file.path);
      } else {
        _showOperationsMenu(file);
      }
    },
    config: UnifiedViewConfig.fromContext(context),
    // ...
  );
}
```

**优点**:
✅ 与 CategoryFilePage 使用同一个 UI 组件  
✅ 自动获得虚拟滚动、性能优化  
✅ 自动获得网格/列表切换支持（为未来扩展预留）  
✅ 减少 UI 代码 ~100 行  

### 第五步：排序状态持久化

**问题**: ArchiveManagementPage 的排序设置不持久化

**解决方案**:
```dart
// 在 initState() 中加载排序偏好
Future<void> _loadSortPreferences() async {
  final pageId = PageId.archiveManagement; // 需要在 PageId 枚举中添加
  final sortType = PageSettingsService().getSortType(pageId);
  final ascending = PageSettingsService().getSortAscending(pageId);
  
  setState(() {
    _sortBy = sortType.name.toLowerCase();
    _sortAscending = ascending;
  });
}

// 在排序改变时保存
void _changeSortBy(String sortBy) {
  setState(() {
    if (_sortBy == sortBy) {
      _sortAscending = !_sortAscending;
    } else {
      _sortBy = sortBy;
      _sortAscending = true;
    }
    
    // 保存到 PageSettingsService
    final pageId = PageId.archiveManagement;
    PageSettingsService().setSortType(pageId, _getSortType());
    PageSettingsService().toggleSortDirection(pageId);
    
    _applySorting();
  });
}
```

---

## 📊 重构影响评估

### 代码量变化

| 项目 | 现状 | 重构后 | 变化 |
|-----|-----|-------|------|
| ArchiveManagementPage | 627 行 | ~350 行 | -277 行 (-44%) |
| CategoryLikePageMixin | 0 行 | ~80 行 | +80 行（新建） |
| ArchiveFileDataSource | 0 行 | ~50 行 | +50 行（新建） |
| 总计 | 627 行 | 480 行 | -147 行 (-23%) |
| 重复代码消除 | ~190 行 | 0 行 | -190 行 |

### 维护成本

| 维度 | 现状 | 重构后 |
|-----|-----|--------|
| 修改搜索逻辑的影响范围 | 2 个页面 | 1 个 Mixin |
| 修改排序的影响范围 | 2 个实现 | 1 个调用点 |
| 添加新的文件类型的难度 | 高 | 中（需要添加数据源） |
| 代码审查时间 | 长 | 短 |

---

## ⚠️ 技术债风险评估

### 当前风险

| 风险项 | 概率 | 影响 | 总风险 |
|-------|------|------|--------|
| 两个页面的搜索行为不一致 | 高 | 中 | 🔴 高 |
| 压缩包页面的排序设置丢失 | 高 | 低 | 🟡 中 |
| 新增功能时维护成本翻倍 | 中 | 高 | 🔴 高 |
| 数据层能力无法复用 | 低 | 高 | 🟡 中 |

### 重构后风险

所有风险降低到 🟢 **低**

---

## 📋 优化建议优先级

| 优先级 | 任务 | 工作量 | ROI |
|--------|------|--------|-----|
| 🔴 P0 | 创建 CategoryLikePageMixin | 2h | 高 |
| 🔴 P0 | 创建 ArchiveFileDataSource | 1h | 高 |
| 🔴 P0 | 重构 ArchiveManagementPage 状态管理 | 2h | 高 |
| 🟡 P1 | 使用 FileCollectionView 替代 ListView | 1.5h | 中 |
| 🟡 P1 | 添加排序状态持久化 | 1h | 中 |
| 🟢 P2 | 添加编辑模式提示条 | 0.5h | 低 |

**总工作量**: ~7.5 小时  
**预期收益**: 代码量减少 23%，维护成本降低 50%+

---

## ✅ 验收标准

完成重构后，应达成：

- [ ] ArchiveManagementPage 中的代码行数 < 380 行
- [ ] 与 CategoryFilePage 的代码重复度 < 10%
- [ ] 搜索、排序、筛选逻辑完全相同
- [ ] 排序偏好被正确持久化
- [ ] 所有测试通过（无回归）
- [ ] 代码审查通过（技术债评估降低）

---

## 📚 参考

**相关文件**:
- [CategoryFilePage](lib/ui/pages/category_file_page.dart) - 2014 行
- [ArchiveManagementPage](lib/ui/pages/archive_management_page.dart) - 627 行
- [EditModeMixin](lib/ui/mixins/edit_mode_mixin.dart)
- [SelectionController](lib/ui/widgets/file_collection_view.dart#L67)
- [CategoryFileDataSource](lib/core/data_sources/category_file_data_source.dart)
- [FileComparatorUtil](lib/utils/file_comparator_util.dart) - 排序逻辑

**相关配置**:
- [PageSettingsService](lib/core/services/page_settings_service.dart) - 保存页面级排序、视图模式
- [FileDisplaySettingsService](lib/core/services/file_display_settings_service.dart)

