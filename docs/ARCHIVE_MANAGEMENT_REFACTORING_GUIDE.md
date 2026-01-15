# 压缩包管理页面重构实施指南

**目标**: 将 ArchiveManagementPage 从"功能重复页面"重构为"分类页面能力的配置化使用"  
**预期工作量**: 7.5 小时  
**预期代码减少**: 277 行 (-44%)

---

## 📋 实施计划

### Phase 1: 基础设施建设 (2.5h)

#### 步骤 1.1: 创建 CategoryLikePageMixin (1h)

**文件**: `lib/ui/mixins/category_like_page_mixin.dart`

```dart
import 'package:flutter/material.dart';
import '../widgets/file_collection_view.dart';
import '../../utils/file_comparator_util.dart';
import '../../data/models/file_item.dart';

/// 分类页面及其他文件聚合页面的通用 Mixin
/// 
/// 提供统一的：
/// - 搜索、筛选、排序状态管理
/// - 过滤文件列表的计算属性
/// - 排序逻辑调用
/// 
/// 子类必须实现：
/// - [searchQuery] getter：当前搜索查询
/// - [filterFile] 方法：文件筛选谓词
/// - [selectionController] getter (来自 EditModeMixin)
/// 
/// 示例：
/// ```dart
/// class MyPage extends State with CategoryLikePageMixin {
///   String get searchQuery => _searchController.text;
///   
///   bool filterFile(FileItem file) {
///     // 返回 true 表示该文件应包含在结果中
///     return file.name.endsWith('.zip');
///   }
/// }
/// ```
mixin CategoryLikePageMixin<T extends StatefulWidget> on State<T> {
  /// 所有文件列表（原始，未过滤）
  /// 
  /// 子类应在加载数据后直接赋值
  @protected
  List<FileItem> allFiles = [];

  /// 当前搜索查询
  /// 
  /// 子类应通过 getter 实现，通常来自 TextEditingController
  @protected
  String get searchQuery;

  /// 文件筛选谓词
  /// 
  /// 子类覆盖此方法以实现特定的文件筛选逻辑
  /// 例如：按格式筛选、按类型筛选等
  @protected
  bool filterFile(FileItem file) => true;

  /// 过滤后的文件列表
  /// 
  /// 应用了文件筛选和搜索过滤的文件列表
  /// 这是一个计算属性，会自动重新计算
  @protected
  List<FileItem> get filteredFiles {
    var result = allFiles;

    // 第一步：应用文件筛选
    result = result.where(filterFile).toList();

    // 第二步：应用搜索过滤
    if (searchQuery.isNotEmpty) {
      result = result.where((f) {
        return f.name.toLowerCase().contains(searchQuery.toLowerCase());
      }).toList();
    }

    return result;
  }

  /// 应用排序到文件列表
  /// 
  /// 这是一个工具方法，使用 FileComparatorUtil 进行排序
  /// 子类应在 setState() 中调用此方法
  /// 
  /// 示例：
  /// ```dart
  /// setState(() {
  ///   applySorting(allFiles, SortType.name, ascending: true);
  /// });
  /// ```
  @protected
  void applySorting(
    List<FileItem> files,
    SortType sortType, {
    bool ascending = true,
  }) {
    FileComparatorUtil.sortFilesInPlace(
      files,
      sortType,
      ascending: ascending,
    );
  }

  /// 按文件名搜索和排序
  /// 
  /// 这是一个便捷方法，结合了搜索、筛选、排序
  /// 适用于简单场景
  @protected
  List<FileItem> getFilteredAndSortedFiles(SortType sortType,
      {bool ascending = true}) {
    var result = filteredFiles;
    applySorting(result, sortType, ascending: ascending);
    return result;
  }
}
```

#### 步骤 1.2: 创建 ArchiveFileDataSource (0.8h)

**文件**: `lib/core/data_sources/archive_file_data_source.dart`

```dart
import 'package:easyfile/core/data_sources/file_list_data_source.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/core/logger.dart';

/// 压缩包文件数据源
/// 
/// 功能：查询设备上的所有压缩包文件
/// 特点：
/// - 包装现有 FilePresenter.scanFilesByCategory(CategoryType.archive)
/// - 适配器模式，复用分类系统的数据获取能力
/// - 支持缓存和元数据
/// 
/// 使用示例：
/// ```dart
/// final dataSource = ArchiveFileDataSource(presenter: presenter);
/// final archives = await dataSource.queryFiles({});
/// ```
/// 
/// 与 CategoryFileDataSource 的关系：
/// - 完全同样的实现模式
/// - 仅改变目标分类为 CategoryType.archive
/// - 演示了数据源的可扩展性
class ArchiveFileDataSource implements FileListDataSource {
  final FilePresenter presenter;

  ArchiveFileDataSource({required this.presenter});

  @override
  String get name => 'ArchiveFileDataSource';

  @override
  Future<List<FileItem>> queryFiles(Map<String, dynamic> params) async {
    logger.i('$name: 开始扫描压缩包');

    try {
      // 完全复用现有的分类扫描逻辑
      // 这样可以：
      // 1. 获得 FilePresenter 的缓存机制
      // 2. 获得 FilePresenter 的日志能力
      // 3. 如果未来改为 MediaStore 扫描，只需改这一处
      final files =
          await presenter.scanFilesByCategory(CategoryType.archive);

      logger.i('$name: 扫描完成，找到 ${files.length} 个压缩包');
      return files;
    } catch (e) {
      logger.e('$name: 扫描失败 - $e');
      rethrow;
    }
  }

  @override
  String getCacheKey(Map<String, dynamic> params) {
    return 'archive_cache';
  }

  @override
  bool get supportsCaching => true;

  /// 缓存有效期：24 小时（与分类页一致）
  @override
  int get cacheExpiration => 24 * 3600;

  @override
  Map<String, dynamic> getMetadata(Map<String, dynamic> params) {
    return {
      'dataSourceType': 'archive',
      'categoryType': 'archive',
      'scanMethod':
          'FilePresenter.scanFilesByCategory(CategoryType.archive)',
      'isAdapter': true,
      'description': '压缩包文件数据源，复用分类系统的扫描逻辑',
    };
  }
}
```

#### 步骤 1.3: 在 PageId 枚举中添加压缩包管理页 ID (0.7h)

**文件**: `lib/core/models/page_id.dart` (或相应的 PageId 定义文件)

```dart
enum PageId {
  categoryImages,
  categoryDocuments,
  categoryMusic,
  categoryVideo,
  categoryDownloads,
  archiveManagement,  // 添加这一行
  // ... 其他页面
}
```

这样做的好处：
- 压缩包页面可以通过 `PageSettingsService` 保存排序、视图模式等偏好
- 与其他分类页面的偏好管理一致

---

### Phase 2: ArchiveManagementPage 重构 (3.5h)

#### 步骤 2.1: 添加 Mixin 继承 (0.5h)

**修改**: `lib/ui/pages/archive_management_page.dart`

```dart
// 添加导入
import 'package:easyfile/ui/mixins/category_like_page_mixin.dart';
import 'package:easyfile/ui/mixins/edit_mode_mixin.dart';
import 'package:easyfile/ui/mixins/pop_scope_handler_mixin.dart';
import 'package:easyfile/core/data_sources/archive_file_data_source.dart';

// 修改类定义
class _ArchiveManagementPageState extends State<ArchiveManagementPage>
    with CategoryLikePageMixin, EditModeMixin, PopScopeHandlerMixin {
  
  // ... 其他代码
  
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
}
```

#### 步骤 2.2: 重构数据层 (1h)

**修改**: initState() 方法

```dart
@override
void initState() {
  super.initState();
  
  // 初始化依赖
  _presenter = locator<FilePresenter>();
  _viewModel = locator<FileViewModel>();
  _dataSource = ArchiveFileDataSource(presenter: _presenter);
  
  // 初始化搜索控制器
  _searchController = TextEditingController();
  _searchController.addListener(() {
    setState(() {
      // searchQuery getter 会自动返回新的查询文本
      // filteredFiles 属性会自动重新计算
    });
  });
  
  // 初始化选择控制器
  _selectionController = SelectionController();
  _selectionController.selectedNotifier.addListener(() {
    setState(() {});
  });
  
  // 加载排序偏好
  _loadSortPreferences();
  
  // 加载压缩包列表
  _scanArchives();
}

/// 加载排序偏好
Future<void> _loadSortPreferences() async {
  try {
    final pageId = PageId.archiveManagement;
    final sortType = PageSettingsService().getSortType(pageId);
    final ascending = PageSettingsService().getSortAscending(pageId);
    
    setState(() {
      _sortBy = sortType.name.toLowerCase();
      _sortAscending = ascending;
    });
    
    logger.d('Loaded archive page preferences: $sortType, ascending=$ascending');
  } catch (e) {
    logger.w('Failed to load sort preferences: $e');
    // 使用默认值
  }
}
```

**修改**: _scanArchives() 方法

```dart
Future<void> _scanArchives() async {
  setState(() {
    _isScanning = true;
  });

  try {
    // 使用数据源而非直接调用 MediaStore
    allFiles = await _dataSource.queryFiles({});
    
    // 应用排序
    _applySorting();
    
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  } catch (e) {
    logger.e('扫描压缩包失败: $e');
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描失败: $e')),
      );
    }
  }
}
```

**移除**: _scanArchivesInBackground() 方法（已不需要）

#### 步骤 2.3: 简化状态管理 (0.8h)

**修改**: _applyFilterAndSort() 方法

```dart
/// 应用排序
void _applySorting() {
  setState(() {
    // 使用 Mixin 提供的排序方法
    // filteredFiles 已经自动处理了搜索和筛选
    final sortType = _getSortType();
    applySorting(filteredFiles, sortType, ascending: _sortAscending);
    
    // 保存排序偏好到 PageSettingsService
    final pageId = PageId.archiveManagement;
    PageSettingsService().setSortType(pageId, sortType);
    if (_sortAscending) {
      PageSettingsService().setSortAscending(pageId, true);
    } else {
      PageSettingsService().toggleSortDirection(pageId);
    }
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
```

**修改**: _clearSearch() 方法

```dart
void _clearSearch() {
  _searchController.clear();
  // 搜索状态改变会自动触发 setState
  // 无需手动调用 _applyFilterAndSort()
}
```

**修改**: _changeFilter() 方法

```dart
void _changeFilter(String filter) {
  setState(() {
    _selectedFormat = filter;
    // filteredFiles 会自动重新计算
  });
}
```

#### 步骤 2.4: 简化 UI 构建 (1.2h)

**修改**: build() 方法中对文件列表的引用

```dart
// 旧代码：
if (_filteredArchives.isEmpty) { ... }

// 新代码：
if (filteredFiles.isEmpty) { ... }

// 旧代码：
itemCount: _filteredArchives.length,

// 新代码：
itemCount: filteredFiles.length,

// 旧代码：
final archive = _filteredArchives[index];

// 新代码：
final archive = filteredFiles[index];
```

**修改**: build() 方法 AppBar

```dart
if (!_isScanning)
  Text(
    '${filteredFiles.length} 个文件',  // 使用 filteredFiles
    style: theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    ),
  ),
```

**修改**: _buildBody() 方法

```dart
Widget _buildBody(ThemeData theme) {
  if (_isScanning) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '正在扫描压缩包...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  if (filteredFiles.isEmpty) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_zip_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _selectedFormat == 'all' ? '未找到压缩包' : '未找到该格式的压缩包',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // 旧做法：ListView.builder
  // 新做法：应考虑使用 FileCollectionView（见第三阶段）
  return ListView.builder(
    itemCount: filteredFiles.length,
    itemBuilder: (context, index) {
      final archive = filteredFiles[index];
      return _buildArchiveItem(archive, theme);
    },
  );
}
```

**修改**: _buildSelectionBottomBar() 方法中的计数

```dart
final totalCount = filteredFiles.length;  // 使用 filteredFiles
```

---

### Phase 3: UI 现代化 (1.5h)

#### 步骤 3.1: 使用 FileCollectionView (1.5h)

**修改**: _buildBody() 方法

```dart
Widget _buildBody(ThemeData theme) {
  if (_isScanning) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('正在扫描压缩包...'),
        ],
      ),
    );
  }

  if (filteredFiles.isEmpty) {
    return _buildEmptyState(theme);
  }

  // 使用 FileCollectionView
  return FileCollectionView(
    items: filteredFiles,
    gridMode: false, // 压缩包管理页总是列表模式
    config: UnifiedViewConfig.fromContext(context),
    selectionController: _selectionController,
    showCheckbox: isEditMode, // 编辑模式下显示复选框
    onItemTap: (file) {
      if (isEditMode) {
        _selectionController.toggle(file.path);
      } else {
        _showOperationsMenu(file);
      }
    },
    onItemLongPress: (file) {
      if (!isEditMode) {
        enterEditMode();
        _selectionController.select(file.path);
      }
    },
    padding: const EdgeInsets.symmetric(vertical: 0),
  );
}

Widget _buildEmptyState(ThemeData theme) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.folder_zip_outlined,
          size: 64,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          _selectedFormat == 'all' ? '未找到压缩包' : '未找到该格式的压缩包',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
```

**好处**:
✅ 自动虚拟滚动（大量文件时性能更好）  
✅ 自动支持长按编辑模式  
✅ 自动处理编辑模式的 UI 切换  
✅ 为未来网格模式预留空间  
✅ 减少列表构建代码 ~80 行  

---

### Phase 4: 清理和验收 (0.5h)

#### 步骤 4.1: 移除不需要的属性

**删除**:
```dart
// 这些不再需要
List<FileItem> _allArchives = [];          // 改用 allFiles
List<FileItem> _filteredArchives = [];     // 改用 filteredFiles
bool _isSearching = false;                 // 改用 searchQuery 判断
```

#### 步骤 4.2: 更新导入

```dart
// 添加新导入
import 'package:easyfile/ui/mixins/category_like_page_mixin.dart';
import 'package:easyfile/core/data_sources/archive_file_data_source.dart';
import 'package:easyfile/core/services/page_settings_service.dart';

// 移除不再需要的
// import 'package:easyfile/core/platform/mediastore_scanner_channel.dart';
```

#### 步骤 4.3: 代码统计

```bash
# 重构前
wc -l lib/ui/pages/archive_management_page.dart
# 输出：627

# 重构后（预期）
wc -l lib/ui/pages/archive_management_page.dart
# 输出：~380 (-247, -39%)

# 新增代码
wc -l lib/ui/mixins/category_like_page_mixin.dart
# 输出：~80

wc -l lib/core/data_sources/archive_file_data_source.dart
# 输出：~55

# 总计减少
# 627 + 0 + 0 = 627 (原状)
# 380 + 80 + 55 = 515 (重构后)
# 净减少：112 行 (-18%)
# 代码复用：消除 ~190 行重复
```

---

## 🧪 测试清单

完成重构后，应执行以下测试：

- [ ] **搜索功能**
  - [ ] 输入文本时，列表正确过滤
  - [ ] 清除搜索时，显示所有文件
  - [ ] 搜索结果中的编辑模式正常工作

- [ ] **筛选功能**
  - [ ] 切换格式筛选（全部/ZIP/RAR/7Z/其他）时，列表正确更新
  - [ ] 与搜索同时工作（搜索+筛选组合）

- [ ] **排序功能**
  - [ ] 按名称/大小/时间排序
  - [ ] 升序/降序切换
  - [ ] 页面关闭后重新打开，排序偏好被保留

- [ ] **编辑模式**
  - [ ] 长按文件进入编辑模式
  - [ ] 编辑模式下显示复选框
  - [ ] 点击复选框/文件行切换选中状态
  - [ ] 底部工具栏显示正确的选中计数

- [ ] **批量操作**
  - [ ] 全选/反选工作正常
  - [ ] 删除选中文件成功
  - [ ] 刷新后列表更新

- [ ] **单文件操作**
  - [ ] 点击文件打开操作菜单
  - [ ] 菜单中的各项操作（删除、分享等）可用

- [ ] **性能**
  - [ ] 列表滚动平滑（使用 FileCollectionView 后）
  - [ ] 大量文件情况下（>1000）不卡顿

- [ ] **UI 一致性**
  - [ ] 空状态显示文案正确
  - [ ] 加载状态显示正确
  - [ ] 与 CategoryFilePage 的 UI 风格一致

---

## 📚 参考代码段

### 如果需要回退，保留原始实现

原始 _applyFilterAndSort() 方法：
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
}
```

### 常见问题

**Q: 使用 FileCollectionView 后，_buildArchiveItem() 还需要吗？**  
A: 不需要。FileCollectionView 会自动处理列表项的构建。只保留 _showOperationsMenu() 用于操作菜单。

**Q: 如何在编辑模式下自定义长按行为？**  
A: 在 ArchiveManagementPage 中通过 onItemLongPress 回调：
```dart
onItemLongPress: (file) {
  if (!isEditMode) {
    enterEditMode();
    _selectionController.select(file.path);
  }
},
```

**Q: 排序偏好保存在哪里？**  
A: 通过 PageSettingsService 保存在 SharedPreferences 中，key 为 `sort_type_archiveManagement`。

---

## ✅ 完成标志

重构完成标志：

1. ✅ 创建 CategoryLikePageMixin（包含 filteredFiles、applySorting 等）
2. ✅ 创建 ArchiveFileDataSource（复用 FilePresenter.scanFilesByCategory）
3. ✅ ArchiveManagementPage 继承 CategoryLikePageMixin 和 EditModeMixin
4. ✅ 移除所有重复的搜索/筛选/排序逻辑
5. ✅ 使用 FileCollectionView 替代 ListView.builder
6. ✅ 排序偏好通过 PageSettingsService 持久化
7. ✅ 所有测试通过（无回归）
8. ✅ 代码审查通过
9. ✅ ArchiveManagementPage < 380 行
10. ✅ 代码重复度 < 10%

