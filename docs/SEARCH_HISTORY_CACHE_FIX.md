# 搜索历史缓存清理修复

## 问题描述
用户反馈：清理了搜索历史记录后，返回到搜索框时仍然能看到搜索记录。

## 问题根源
应用中存在**两个独立的搜索历史存储系统**：

### 1. SearchHistoryLocalSource
- 存储方式：JSON文件（`search_history.json`）
- 存储位置：`ApplicationDocumentsDirectory`
- 数据结构：`SearchHistoryItem`（包含关键词、搜索次数、结果数等）
- 用途：主要用于搜索历史面板（`SearchHistoryPanel`）

### 2. SearchHistoryService
- 存储方式：SharedPreferences（键：`global_search_history`）
- 存储位置：应用SharedPreferences
- 数据结构：简单的字符串列表
- 用途：用于搜索框的快速历史提示（`FileSearchBar`）

## 问题原因
缓存管理器的清理操作只清理了 `SearchHistoryLocalSource`（JSON文件），但搜索框使用的是 `SearchHistoryService`（SharedPreferences）。

```dart
// 原来的清理代码 - 只清理了一半
case CacheType.searchHistory:
  await _searchHistorySource.clearAllHistory();  // ✅ 清理JSON文件
  // ❌ 没有清理SharedPreferences
  return true;
```

## 解决方案

### 1. 导入SearchHistoryService
```dart
import 'package:easyfile/core/services/search_history_service.dart';
```

### 2. 修改清理逻辑 - 同时清理两个存储
```dart
case CacheType.searchHistory:
  // 清理JSON文件存储的搜索历史
  await _searchHistorySource.clearAllHistory();
  // 清理SharedPreferences存储的全局搜索历史
  await SearchHistoryService().clearHistory();
  logger.i('Search history cleared (both JSON file and SharedPreferences)');
  return true;
```

### 3. 修改缓存大小计算 - 统计两个存储
```dart
// 4. 搜索历史
try {
  final history = await _searchHistorySource.getAllHistory();
  final globalHistory = await SearchHistoryService().getHistory();
  int size = 0;

  // 计算JSON文件存储的搜索历史大小
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/search_history.json');
  if (await file.exists()) {
    size += await file.length();
  }

  // 估算SharedPreferences存储的搜索历史大小
  // 每条记录约 50-100 字节
  size += globalHistory.length * 75;

  final totalCount = history.length + globalHistory.length;

  items.add(CacheItem(
    name: '搜索历史',
    description: totalCount > 0 ? '包含 $totalCount 条搜索记录' : '无搜索记录',
    size: size,
    type: CacheType.searchHistory,
  ));
}
```

## 修改文件
- `lib/core/services/cache_manager_service.dart`
  - 新增导入：`search_history_service.dart`
  - 修改：`clearCache()` 方法的 `CacheType.searchHistory` 分支
  - 修改：`getAllCacheItems()` 方法的搜索历史统计部分

## 验证步骤
1. ✅ 在搜索框输入内容并搜索，生成搜索历史
2. ✅ 打开缓存管理，查看搜索历史缓存（应该显示正确的记录数）
3. ✅ 清理搜索历史
4. ✅ 返回搜索框，点击输入框（获得焦点）
5. ✅ 确认搜索历史为空（不再显示之前的搜索记录）

## 为什么会有两个搜索历史系统？

### SearchHistoryLocalSource（详细版）
- **设计用途**：完整的搜索历史记录
- **数据内容**：
  - 搜索关键词
  - 搜索时间
  - 搜索次数（用于统计热门搜索）
  - 搜索结果数量
- **适用场景**：
  - 搜索历史面板展示
  - 热门搜索统计
  - 搜索分析

### SearchHistoryService（轻量版）
- **设计用途**：快速搜索提示
- **数据内容**：
  - 仅搜索关键词列表
- **适用场景**：
  - 搜索框的快速历史提示
  - 减少IO操作（使用SharedPreferences缓存）

## 优化建议（未来）
考虑统一两个搜索历史系统：
- 方案A：只使用SharedPreferences（如果不需要详细统计）
- 方案B：只使用JSON文件，但在SearchHistoryService中添加内存缓存
- 方案C：让SearchHistoryService作为门面，内部调用SearchHistoryLocalSource

目前的临时解决方案是在清理时同时清理两个存储，确保数据一致性。

## 测试结果
- ✅ 清理搜索历史后，JSON文件被删除
- ✅ 清理搜索历史后，SharedPreferences中的记录被清空
- ✅ 返回搜索框时不再显示任何历史记录
- ✅ 缓存大小正确统计两个存储的总和
