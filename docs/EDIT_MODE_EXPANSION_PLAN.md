# 编辑模式功能扩展计划

## 📋 文档概述

**目标**: 将Storage Page中已实现的编辑模式功能扩展到其他页面（Category Page、Browser Page、Large Files Page）

**分析日期**: 2024-12-05

**当前状态**: Storage Page已完成编辑模式Stage 1实现

---

## 🔍 现有实现分析

### Storage Page 编辑模式核心特性

#### 1. **状态管理**
```dart
// 编辑模式状态
bool _isEditMode = false;

// 选择控制器（统一管理选择状态）
late final SelectionController _selectionController;
Set<String> _selectedItems = {};
```

#### 2. **核心功能**
- ✅ **编辑/完成按钮切换**: AppBar右侧显示编辑按钮，进入编辑模式后变为关闭按钮
- ✅ **新建文件夹功能**: 编辑模式下显示"新建文件夹"按钮
- ✅ **编辑模式视觉指示**: Leading显示蓝色圆形编辑图标
- ✅ **自动进入选择模式**: 单击文件/文件夹自动进入选择模式
- ✅ **与选择模式集成**: 编辑模式可以无缝切换到选择模式
- ✅ **返回键优先级处理**: PopScope正确处理返回键优先级（选择模式 > 编辑模式 > 搜索模式 > 导航返回）

#### 3. **交互流程**
```
普通浏览模式
    ↓ 点击编辑按钮
编辑模式（显示新建文件夹按钮 + 编辑图标）
    ↓ 单击任意文件/文件夹
选择模式（显示批量操作栏）
    ↓ 点击取消或完成
返回编辑模式 或 普通浏览模式
```

#### 4. **关键代码片段**
```dart
// 进入编辑模式
void _enterEditMode() {
  setState(() {
    _isEditMode = true;
  });
}

// 退出编辑模式
void _exitEditMode() {
  setState(() {
    _isEditMode = false;
    _selectionController.clear(); // 清除所有选中项
  });
}

// 文件点击处理（编辑模式下自动进入选择）
void _onFileTap(FileItem file) {
  if (_isEditMode && !_selectionController.isSelectionMode) {
    _selectionController.select(file.path);
    return;
  }
  // 选择模式下的切换逻辑
  if (_selectionController.isSelectionMode) {
    // 切换选择状态
  }
  // 普通模式下的预览/导航
}

// AppBar配置
leading: _selectionController.isSelectionMode
    ? IconButton(icon: Icon(Icons.close), ...) // 选择模式
    : _isEditMode
        ? Container(...) // 编辑模式指示器
        : IconButton(icon: Icon(Icons.home), ...), // 普通模式

actions: _selectionController.isSelectionMode
    ? [...] // 全选按钮
    : [
        FileToolbar(...),
        IconButton(
          icon: Icon(_isEditMode ? Icons.close : Icons.edit_outlined),
          onPressed: _isEditMode ? _exitEditMode : _enterEditMode,
        ),
      ],
```

---

## 📊 目标页面现状分析

### 1. Category File Page (分类文件页面)

#### **当前状态**
- ✅ 已有 `SelectionController` 和批量操作支持
- ✅ 已有搜索模式
- ✅ 已有文件类型筛选功能
- ❌ **缺少编辑模式**
- ❌ 无新建文件夹功能
- ❌ 无编辑/完成按钮切换

#### **适配难度**: ⭐⭐ (中等)

#### **特殊考虑**
- 分类页面是聚合视图，显示多个文件夹中的文件
- **新建文件夹功能可能不适用**（因为没有单一当前路径）
- 编辑模式应该主要用于**选择文件进行批量操作**
- 需要考虑**文件类型筛选**与编辑模式的交互

#### **建议功能调整**
```
编辑模式功能清单:
✅ 编辑/完成按钮切换
✅ 单击文件自动进入选择模式
✅ 编辑模式视觉指示
❌ 新建文件夹（不适用）
✅ 快速批量选择和操作
```

---

### 2. Browser Page (主页浏览页面)

#### **当前状态**
- ✅ 已有 `SelectionController` 和批量操作支持
- ✅ 已有搜索模式（浏览Tab和收藏Tab都有）
- ✅ 已有文件夹导航
- ✅ 已有多Tab切换（浏览/最近/收藏）
- ❌ **缺少编辑模式**
- ❌ 无新建文件夹功能（浏览Tab需要）
- ❌ 无编辑/完成按钮切换

#### **适配难度**: ⭐⭐⭐ (较高)

#### **特殊考虑**
- 这是**最复杂的页面**，有3个Tab（Browse、Recent、Favorite）
- 每个Tab有不同的交互需求：
  - **Browse Tab**: 需要新建文件夹功能
  - **Recent Tab**: 只需要选择和批量操作
  - **Favorite Tab**: 只需要选择和批量操作
- 已有复杂的UI结构（CategoryNavBar、QuickAccessSection、分类筛选栏等）
- **建议分Tab实现编辑模式**

#### **建议实现策略**
```
Browse Tab 编辑模式:
✅ 编辑/完成按钮切换
✅ 单击文件/文件夹自动进入选择模式
✅ 编辑模式视觉指示
✅ 新建文件夹功能
✅ 快速批量操作

Recent Tab 编辑模式:
✅ 编辑/完成按钮切换
✅ 单击文件自动进入选择模式
✅ 编辑模式视觉指示
❌ 新建文件夹（不适用）
✅ 批量清除最近记录

Favorite Tab 编辑模式:
✅ 编辑/完成按钮切换
✅ 单击文件自动进入选择模式
✅ 编辑模式视觉指示
❌ 新建文件夹（不适用）
✅ 批量取消收藏
```

#### **技术挑战**
1. **状态隔离**: 每个Tab应该有独立的编辑模式状态
2. **UI协调**: 编辑模式工具栏需要与现有复杂UI协调
3. **滑动手势冲突**: 已有左右滑动切换Tab的手势，需要避免冲突

---

### 3. Large Files Page (大文件查找页面)

#### **当前状态**
- ✅ 已有 `SelectionController` 和批量操作支持
- ✅ 已有扫描配置和差异扫描
- ✅ 已有批量删除功能
- ✅ 已有操作提示栏
- ❌ **缺少编辑模式**
- ❌ 无新建文件夹功能（不需要）
- ❌ 无编辑/完成按钮切换

#### **适配难度**: ⭐ (简单)

#### **特殊考虑**
- 这是**最简单的适配场景**
- 页面主要用于**查找和清理大文件**
- 不需要新建文件夹功能
- 已有完善的批量操作支持
- 已有操作提示栏，可以复用提示逻辑

#### **建议功能调整**
```
编辑模式功能清单:
✅ 编辑/完成按钮切换
✅ 单击文件自动进入选择模式
✅ 编辑模式视觉指示
❌ 新建文件夹（不需要）
✅ 快速批量删除大文件
✅ 与现有提示栏协同工作
```

---

## 🎯 实施优先级建议

### **Phase 1: Large Files Page** (推荐优先实现)
- **难度**: ⭐ 简单
- **工作量**: 1-2小时
- **收益**: 快速验证编辑模式模式，积累经验
- **风险**: 低

**理由**: 
- 页面结构简单，没有复杂的Tab切换
- 不需要新建文件夹功能，功能范围小
- 已有完善的批量操作支持，集成简单
- 可以作为**模式验证**，为后续复杂页面提供参考

---

### **Phase 2: Category File Page** (次优先)
- **难度**: ⭐⭐ 中等
- **工作量**: 2-4小时
- **收益**: 提升分类页面的操作效率
- **风险**: 中等（需要考虑聚合视图的特殊性）

**理由**:
- 页面结构相对清晰，没有多Tab切换
- 需要特别处理聚合视图的特殊性（无单一当前路径）
- 可以验证**无新建文件夹场景**的编辑模式
- 为Browser Page的Recent/Favorite Tab提供参考

---

### **Phase 3: Browser Page** (最后实现)
- **难度**: ⭐⭐⭐ 较高
- **工作量**: 6-10小时
- **收益**: 全面提升主页操作体验
- **风险**: 高（UI复杂度高，需要分Tab实现）

**理由**:
- 页面结构最复杂，有3个Tab
- 需要分别为每个Tab实现不同的编辑模式
- UI已经很丰富，需要仔细协调编辑模式工具栏
- 建议**分阶段实现**：
  1. **Stage 1**: Browse Tab（与Storage Page最相似）
  2. **Stage 2**: Recent Tab（参考Category Page经验）
  3. **Stage 3**: Favorite Tab（参考Recent Tab经验）

---

## 📐 统一实现规范

### 1. **状态管理模式**
所有页面应遵循相同的状态管理模式：

```dart
// 编辑模式状态
bool _isEditMode = false;

// 选择控制器（复用现有的）
late final SelectionController _selectionController;

// 进入编辑模式
void _enterEditMode() {
  setState(() {
    _isEditMode = true;
  });
}

// 退出编辑模式
void _exitEditMode() {
  setState(() {
    _isEditMode = false;
    _selectionController.clear();
  });
}
```

### 2. **AppBar配置模式**
统一的AppBar配置逻辑：

```dart
AppBar(
  leading: _selectionController.isSelectionMode
      ? IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _selectionController.clear(),
        )
      : _isEditMode
          ? Container(
              // 编辑模式指示器
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.edit,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : IconButton(
              icon: const Icon(Icons.home),
              onPressed: () => Navigator.of(context).pop(),
            ),
  title: _selectionController.isSelectionMode
      ? Text('已选中 ${_selectedItems.length} 项')
      : Text('页面标题'),
  actions: _selectionController.isSelectionMode
      ? [
          // 全选按钮
          Checkbox(...),
        ]
      : [
          // 工具栏
          FileToolbar(...),
          // 编辑/完成按钮
          IconButton(
            icon: Icon(_isEditMode ? Icons.close : Icons.edit_outlined),
            onPressed: _isEditMode ? _exitEditMode : _enterEditMode,
            tooltip: _isEditMode ? '完成' : '编辑',
          ),
        ],
)
```

### 3. **返回键优先级处理**
统一的PopScope配置：

```dart
PopScope(
  canPop: !_selectionController.isSelectionMode && !_isEditMode && !_isSearchMode,
  onPopInvokedWithResult: (didPop, result) {
    if (didPop) return;
    
    // 优先级1: 退出选择模式
    if (_selectionController.isSelectionMode) {
      _selectionController.clear();
      return false;
    }
    
    // 优先级2: 退出编辑模式
    if (_isEditMode) {
      _exitEditMode();
      return false;
    }
    
    // 优先级3: 退出搜索模式
    if (_isSearchMode) {
      // 退出搜索
      return false;
    }
    
    // 优先级4: 其他情况允许返回
    return true;
  },
)
```

### 4. **文件点击处理**
统一的点击逻辑：

```dart
void _onFileTap(FileItem file) {
  // 编辑模式下：单击自动进入选择模式
  if (_isEditMode && !_selectionController.isSelectionMode) {
    _selectionController.select(file.path);
    return;
  }
  
  // 选择模式下：切换选择状态
  if (_selectionController.isSelectionMode) {
    if (_selectionController.isSelected(file.path)) {
      _selectionController.deselect(file.path);
    } else {
      _selectionController.select(file.path);
    }
    return;
  }
  
  // 普通模式：预览或导航
  if (file.isDirectory) {
    // 导航到文件夹
  } else {
    // 预览文件
  }
}
```

### 5. **编辑模式工具栏**
有条件显示新建文件夹按钮（仅适用于有导航的页面）：

```dart
// 编辑模式工具栏（适用于Storage Page、Browser Browse Tab）
if (_isEditMode)
  Padding(
    padding: const EdgeInsets.all(16),
    child: FilledButton.icon(
      onPressed: _showCreateFolderDialog,
      icon: const Icon(Icons.create_new_folder),
      label: const Text('新建文件夹'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  ),
```

---

## 🎨 视觉设计规范

### 编辑模式视觉指示
- **Leading图标**: 蓝色圆形背景 + 编辑图标
- **编辑/完成按钮**: 
  - 编辑模式: 显示关闭图标（Icons.close）
  - 普通模式: 显示编辑图标（Icons.edit_outlined）
- **新建文件夹按钮**: Material You风格FilledButton，圆角12px

### 颜色使用
```dart
// 编辑模式指示器
Container(
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.primaryContainer,
    shape: BoxShape.circle,
  ),
  child: Icon(
    Icons.edit,
    color: Theme.of(context).colorScheme.primary,
  ),
)
```

---

## ✅ 实施检查清单

### Phase 1: Large Files Page
- [ ] 添加 `_isEditMode` 状态变量
- [ ] 实现 `_enterEditMode()` 和 `_exitEditMode()` 方法
- [ ] 修改AppBar配置（添加编辑/完成按钮）
- [ ] 添加编辑模式视觉指示（leading）
- [ ] 修改文件点击逻辑（编辑模式下自动进入选择）
- [ ] 更新PopScope返回键处理
- [ ] 测试编辑模式与选择模式的切换
- [ ] 测试返回键优先级
- [ ] 更新用户文档

### Phase 2: Category File Page
- [ ] 添加 `_isEditMode` 状态变量
- [ ] 实现 `_enterEditMode()` 和 `_exitEditMode()` 方法
- [ ] 修改AppBar配置（添加编辑/完成按钮）
- [ ] 添加编辑模式视觉指示（leading）
- [ ] 修改文件点击逻辑（编辑模式下自动进入选择）
- [ ] 更新PopScope返回键处理
- [ ] 测试编辑模式与文件类型筛选的交互
- [ ] 测试编辑模式与选择模式的切换
- [ ] 更新用户文档

### Phase 3: Browser Page
#### Stage 1: Browse Tab
- [ ] 为Browse Tab添加 `_isBrowseEditMode` 状态
- [ ] 实现Browse Tab的 `_enterBrowseEditMode()` 和 `_exitBrowseEditMode()`
- [ ] 修改Browse Tab的AppBar配置
- [ ] 添加新建文件夹功能
- [ ] 修改Browse Tab的文件点击逻辑
- [ ] 测试Browse Tab编辑模式

#### Stage 2: Recent Tab
- [ ] 为Recent Tab添加 `_isRecentEditMode` 状态
- [ ] 实现Recent Tab的编辑模式方法
- [ ] 修改Recent Tab的AppBar配置
- [ ] 添加批量清除最近记录功能
- [ ] 测试Recent Tab编辑模式

#### Stage 3: Favorite Tab
- [ ] 为Favorite Tab添加 `_isFavoriteEditMode` 状态
- [ ] 实现Favorite Tab的编辑模式方法
- [ ] 修改Favorite Tab的AppBar配置
- [ ] 添加批量取消收藏功能
- [ ] 测试Favorite Tab编辑模式

#### 整合测试
- [ ] 测试Tab切换时编辑模式状态的隔离
- [ ] 测试与CategoryNavBar、QuickAccessSection的UI协调
- [ ] 测试与滑动手势的兼容性
- [ ] 更新用户文档

---

## 🔧 技术注意事项

### 1. **状态隔离**
Browser Page需要为每个Tab维护独立的编辑模式状态：
```dart
// Browser Page多Tab状态
bool _isBrowseEditMode = false;
bool _isRecentEditMode = false;
bool _isFavoriteEditMode = false;

// 根据当前Tab返回对应的编辑模式状态
bool get _currentEditMode {
  switch (viewModel.currentTab) {
    case TabView.browse:
      return _isBrowseEditMode;
    case TabView.recent:
      return _isRecentEditMode;
    case TabView.favorite:
      return _isFavoriteEditMode;
  }
}
```

### 2. **SelectionController复用**
所有页面已经有 `SelectionController`，直接复用即可，无需重新创建。

### 3. **FileCollectionView集成**
所有页面已使用 `FileCollectionView` 组件，该组件已支持选择模式，只需传递 `selectionController` 参数。

### 4. **批量操作服务**
复用现有的 `BatchOperationsService`，该服务已提供完善的批量操作支持。

---

## 📈 预期收益

### 用户体验提升
- ✅ **操作效率**: 编辑模式下单击即可选择，无需长按
- ✅ **功能可见性**: 编辑/完成按钮清晰指示编辑模式
- ✅ **一致性**: 所有页面统一的编辑模式交互
- ✅ **灵活性**: 可快速在浏览和编辑之间切换

### 开发效率
- ✅ **代码复用**: 复用Storage Page的实现模式
- ✅ **统一规范**: 统一的状态管理和交互逻辑
- ✅ **渐进实施**: 分阶段实施，降低风险

---

## 🚀 下一步行动

### 立即开始: Large Files Page
1. **创建功能分支**: `feature/edit-mode-large-files`
2. **参考Storage Page实现**: 复制核心逻辑
3. **简化功能**: 移除新建文件夹相关代码
4. **测试验证**: 确保编辑模式与批量删除的集成
5. **提交PR**: 作为Phase 1的成果

### 准备下一阶段: Category File Page
1. **分析特殊需求**: 研究聚合视图的特殊性
2. **设计功能边界**: 明确哪些功能适用
3. **准备测试用例**: 特别关注文件类型筛选的交互

### 规划最终阶段: Browser Page
1. **详细设计**: 每个Tab的功能清单
2. **UI设计评审**: 确保与现有UI协调
3. **分阶段计划**: 制定Stage 1/2/3的详细计划

---

## 📝 文档维护

本文档将在每个Phase完成后更新：
- 记录实施过程中的问题和解决方案
- 更新检查清单的完成状态
- 补充新发现的注意事项

**文档版本**: v1.0  
**最后更新**: 2024-12-05  
**维护者**: AI Assistant

---

## 🤝 参考资料

- [Storage Page Implementation](../lib/ui/pages/storage_page.dart)
- [Category File Page](../lib/ui/pages/category_file_page.dart)
- [Browser Page](../lib/ui/pages/file_browser_page.dart)
- [Large Files Page](../lib/ui/pages/large_files_page.dart)
- [SelectionController](../lib/ui/widgets/file_collection_view.dart)
- [BatchOperationsService](../lib/ui/services/batch_operations_service.dart)
