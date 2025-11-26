# 缓存管理流程重新设计

## 概述
重新设计了缓存管理的UI流程，修复了"视频缓存清理一直显示正在清理..."的问题。

## 问题根源
原先的实现流程存在设计缺陷：
```
设置页 → 缓存管理对话框 → 点击清理 → 关闭缓存管理对话框 → 显示loading对话框 
→ 清理完成 → 关闭loading对话框(context失效❌) → 显示结果
```

**核心问题**：
1. 在清理时关闭了缓存管理对话框，导致后续操作的context失效
2. 用户体验差：每次清理都要重新打开缓存管理面板
3. 无法连续清理多个缓存项

## 新的实现流程
```
设置页 → 缓存管理对话框(保持打开✅) → 点击清理 → 在对话框上显示loading 
→ 清理完成 → 刷新缓存列表 → 显示结果 → 可继续清理其他项
```

**改进点**：
1. ✅ 缓存管理对话框始终保持打开状态
2. ✅ 使用StatefulWidget管理对话框内的状态
3. ✅ 清理时在当前项显示CircularProgressIndicator
4. ✅ 清理完成后自动刷新缓存列表
5. ✅ 支持连续清理多个缓存项
6. ✅ 全部清理时显示全屏loading overlay

## 技术实现

### 1. 对话框结构
创建了 `_CacheManagementSheet` 作为 StatefulWidget：
- 管理缓存列表数据（`_cacheItems`）
- 管理loading状态（`_isClearing`, `_clearingItemName`）
- 在对话框内完成所有操作

### 2. 单项清理流程
```dart
Future<void> _clearCache(CacheItem item) async {
  // 1. 显示确认对话框
  final confirmed = await showDialog<bool>(...);
  
  // 2. 设置loading状态
  setState(() {
    _isClearing = true;
    _clearingItemName = item.name;
  });
  
  // 3. 执行清理操作
  bool success = await widget.cacheManager.clearCache(item.type);
  
  // 4. 更新状态并刷新列表
  setState(() {
    _isClearing = false;
    _clearingItemName = null;
  });
  
  // 5. 显示结果
  ScaffoldMessenger.of(context).showSnackBar(...);
  
  // 6. 重新加载缓存数据
  await _loadCacheData();
}
```

### 3. 全部清理流程
```dart
Future<void> _clearAllCache() async {
  // 1. 显示确认对话框
  final confirmed = await showDialog<bool>(...);
  
  // 2. 设置loading状态（全屏overlay）
  setState(() {
    _isClearing = true;
    _clearingItemName = '全部缓存';
  });
  
  // 3. 执行清理操作
  ClearAllResult? result = await widget.cacheManager.clearAllCache();
  
  // 4. 更新状态并刷新列表
  setState(() {
    _isClearing = false;
    _clearingItemName = null;
  });
  
  // 5. 显示结果
  ScaffoldMessenger.of(context).showSnackBar(...);
  
  // 6. 重新加载缓存数据
  await _loadCacheData();
}
```

### 4. UI状态管理
```dart
// 单项清理：显示小的loading indicator
if (isClearing)
  const SizedBox(
    width: 60,
    height: 32,
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  )

// 全部清理：显示全屏overlay
if (_isClearing && _clearingItemName == '全部缓存')
  Container(
    color: Colors.black26,
    child: const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在清理全部缓存...'),
            ],
          ),
        ),
      ),
    ),
  ),
```

## 用户体验改进
1. **更直观**：可以看到清理进度和结果，无需重新打开面板
2. **更高效**：支持连续清理多个缓存项
3. **更稳定**：避免了context失效的问题
4. **更友好**：每个缓存项都有详细的说明和警告提示

## 测试要点
1. ✅ 单项清理功能正常
2. ✅ 清理完成后列表自动刷新
3. ✅ 可以连续清理多个项
4. ✅ 全部清理功能正常
5. ✅ Loading状态正确显示
6. ✅ 清理中禁止其他操作
7. ✅ 清理完成后显示结果消息

## 相关文件
- `lib/ui/pages/settings_page.dart` - 主要修改文件
  - 新增 `_CacheManagementSheet` StatefulWidget
  - 新增 `_CacheManagementSheetState` 状态管理
  - 移除旧的 `_performClearCache` 和 `_performClearAllCache` 方法

- `lib/core/services/cache_manager_service.dart` - 缓存服务（未改动）
  - 清理逻辑保持不变
  - 日志追踪保持不变

## 总结
通过将缓存管理对话框改为StatefulWidget，并在对话框内管理所有状态和操作，成功解决了context失效的问题，同时显著提升了用户体验。
