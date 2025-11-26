# 其他缓存清理需求分析

**分析日期**: 2025-11-26  
**分析方法**: 模板E - 探索性分析流程  
**分析目标**: 全面排查应用中是否还有其他需要清理的缓存

---

## 一、问题定义 (Problem Definition)

### 1.1 核心问题
当前应用已实现基本缓存清理功能（缩略图、日志、分类扫描），需要系统性地排查是否还有其他遗漏的缓存类型需要纳入清理范围。

### 1.2 分析范围
- **数据持久化机制**: SharedPreferences、文件系统存储（JSON）
- **临时数据**: 临时文件、运行时缓存
- **用户数据**: 搜索历史、播放进度等
- **智能扫描缓存**: 应用扫描、用户目录检测等

---

## 二、数据收集 (Data Collection)

### 2.1 已排查的存储机制

#### SharedPreferences 使用情况
通过代码扫描发现以下 SharedPreferences 键：

**1. 视频播放相关** (`video_player_widget.dart`)
- `video_position_{videoId}` - 视频播放进度记忆
- `video_duration_{videoPath}` - 视频时长缓存

**2. 分类文件缓存** (`category_file_page.dart`, `file_browser_page.dart`)
- `category_cache_images` - 图片分类文件列表 ✅ **已清理**
- `category_cache_video` - 视频分类文件列表 ✅ **已清理**
- `category_cache_music` - 音乐分类文件列表 ✅ **已清理**
- `category_cache_documents` - 文档分类文件列表 ✅ **已清理**
- `category_cache_downloads` - 下载分类文件列表 ✅ **已清理**
- `category_file_counts` - 分类统计数据 ✅ **已清理**
- `category_last_scan_time` - 最后扫描时间 ✅ **已清理**
- `category_total_files` - 总文件数 ✅ **已清理**

**3. 用户界面设置** (`file_viewmodel.dart`)
- `current_tab` - 当前标签页
- `last_browse_path` - 最后浏览路径
- `theme_mode` - 主题模式

**4. 显示设置** (`file_display_settings_service.dart`)
- `file_display_grid_show_info` - 网格显示文件信息
- `file_display_show_hidden` - 显示隐藏文件
- `file_display_show_system` - 显示系统文件
- `file_display_show_full_path` - 显示完整路径

**5. 页面设置** (`page_settings_service.dart`, `view_mode_service.dart`)
- `page_visibility_{pageId}` - 各页面可见性
- `view_mode_{pageId}` - 各页面视图模式（列表/网格）

**6. 分类显示设置** (`category_sort_service.dart`, `category_group_service.dart`, `category_file_page.dart`)
- `category_sort_type` - 分类排序类型
- `category_group_mode` - 分类分组模式
- `category_file_type_filter_documents` - 文档筛选
- `category_file_type_filter_downloads` - 下载筛选

**7. 智能扫描缓存** (`smart_app_scanner.dart`)
- `smart_scan_last_time` - 应用扫描时间
- `smart_scan_apps` - 已扫描的应用路径

**8. 用户目录检测** (`user_folder_detector.dart`)
- `user_folder_last_detection` - 用户目录检测时间
- `user_folder_detected_paths` - 已检测的目录路径

**9. 首次扫描标记** (`first_scan_service.dart`)
- `first_scan_completed_v2` - 首次扫描完成标记

#### 文件系统存储 (JSON Files)
位于 `getApplicationDocumentsDirectory()`:

**1. 用户数据文件**
- `favorites.json` - 收藏夹数据
- `favorite_files.json` - 收藏文件数据
- `recent_files.json` - 最近访问文件（最多20条）
- `quick_access_folders.json` - 快速访问文件夹

**2. 搜索与主题**
- `search_history.json` - 搜索历史记录（最多50条）
- `theme_settings.json` - 主题设置

**3. 日志文件**
- `app.log` - 应用运行日志 ✅ **已清理**

**4. 缓存目录**
- `media_thumbnails/` - 缩略图缓存目录 ✅ **已清理**

#### 临时文件
- 视频截图临时文件: `Directory.systemTemp.createTemp()` 用于视频截图，使用后立即删除

---

## 三、模式识别 (Pattern Recognition)

### 3.1 缓存数据分类

| 类型 | 数据项 | 清理需求 | 数据量 | 清理风险 |
|------|--------|----------|--------|----------|
| **性能缓存** | 视频时长、播放进度 | 🟡 可选 | 小 | 低 |
| **用户数据** | 收藏、最近文件 | 🔴 不应清理 | 小-中 | 高 |
| **搜索历史** | 搜索记录 | 🟢 应独立清理 | 小 | 低 |
| **智能扫描** | 应用扫描、目录检测 | 🟡 可选 | 极小 | 中 |
| **UI设置** | 界面偏好设置 | 🔴 不应清理 | 极小 | 高 |
| **已实现清理** | 缩略图、日志、分类扫描 | ✅ 已完成 | 大 | 低 |

### 3.2 数据特征分析

#### 🟢 应该清理的缓存
1. **搜索历史** (`search_history.json`)
   - 性质: 用户行为痕迹
   - 大小: 50条记录 × ~100字节 ≈ 5KB
   - 用户诉求: 隐私保护、清理痕迹
   - 清理影响: 无，可重新积累

#### 🟡 可选清理的缓存
2. **视频播放进度** (`video_position_*`)
   - 性质: 播放记忆缓存
   - 大小: ~100条 × 20字节 ≈ 2KB
   - 用户诉求: 重置观看状态
   - 清理影响: 中等，用户需重新定位

3. **视频时长缓存** (`video_duration_*`)
   - 性质: 性能优化缓存
   - 大小: ~1000条 × 20字节 ≈ 20KB
   - 用户诉求: 空间释放
   - 清理影响: 低，会自动重建

4. **智能扫描缓存** (`smart_scan_*`, `user_folder_*`, `first_scan_*`)
   - 性质: 智能功能缓存
   - 大小: 5-10KB
   - 用户诉求: 重新扫描、修正检测
   - 清理影响: 中，需重新扫描（耗时）

#### 🔴 不应清理的数据
5. **收藏数据** (`favorites.json`, `favorite_files.json`)
   - 性质: 核心用户数据
   - 原因: 数据丢失不可恢复

6. **最近文件** (`recent_files.json`)
   - 性质: 功能性数据
   - 原因: 影响"最近访问"功能

7. **快速访问** (`quick_access_folders.json`)
   - 性质: 用户配置数据
   - 原因: 用户手动管理

8. **UI设置** (所有显示、排序、分组设置)
   - 性质: 用户偏好设置
   - 原因: 重置会破坏用户体验

---

## 四、场景探索 (Scenario Exploration)

### 场景1: 隐私保护用户
**用户画像**: 关注隐私，定期清理使用痕迹
**需求**: 
- ✅ 清理搜索历史
- ✅ 清理视频播放进度（可选）
- ❌ 不清理收藏和快速访问

**解决方案**: 添加"搜索历史"清理项

### 场景2: 空间敏感用户
**用户画像**: 存储空间紧张，寻求最大化释放空间
**需求**:
- ✅ 清理所有缓存（缩略图、日志最重要）
- 🟡 视频时长缓存可清理（20KB微小收益）
- ❌ UI设置不清理

**解决方案**: 当前实现已满足，视频时长缓存收益太小可不加

### 场景3: 功能重置用户
**用户画像**: 遇到问题或希望恢复初始状态
**需求**:
- 🟡 重置智能扫描（重新检测应用和目录）
- 🟡 重置首次扫描标记（重新执行初始化流程）
- ❌ 不清理用户数据

**解决方案**: 添加"智能扫描缓存"清理项（高级功能）

### 场景4: 视频观看习惯重置
**用户画像**: 希望重新观看所有视频，清除观看记忆
**需求**:
- ✅ 清除所有视频播放进度
- 🟡 可选清除视频时长缓存

**解决方案**: 添加"视频播放数据"清理项

---

## 五、洞察总结 (Insight Summary)

### 5.1 核心发现

1. **搜索历史是重要遗漏点** ⭐⭐⭐
   - 性质: 明确的"痕迹数据"
   - 需求: 隐私保护场景明确
   - 实现: 已有清理API (`SearchHistoryLocalSource.clearAllHistory()`)
   - 优先级: **高**

2. **视频播放数据具有清理价值** ⭐⭐
   - 数据量: 小（2-20KB）
   - 场景: 观看记忆重置、隐私保护
   - 实现: 需遍历SharedPreferences清理 `video_position_*` 和 `video_duration_*`
   - 优先级: **中**

3. **智能扫描缓存可作为高级功能** ⭐
   - 数据量: 极小（5-10KB）
   - 场景: 功能重置、修正检测错误
   - 实现: 已有清理API (`SmartAppScanner.clearScanCache()`, `UserFolderDetector.clearDetectionCache()`)
   - 优先级: **中-低**

4. **其他数据不应纳入清理**
   - 收藏/快速访问: 用户核心数据
   - UI设置: 影响体验
   - 最近文件: 功能性数据

### 5.2 技术可行性

| 缓存类型 | 清理API | 技术难度 | 测试复杂度 |
|----------|---------|----------|-----------|
| 搜索历史 | `SearchHistoryLocalSource.clearAllHistory()` | ⭐ 低 | ⭐ 低 |
| 视频播放进度 | 需实现通配符清理 | ⭐⭐ 中 | ⭐⭐ 中 |
| 智能扫描 | `clearScanCache()` + `clearDetectionCache()` | ⭐ 低 | ⭐⭐ 中 |

---

## 六、可行性评估 (Feasibility Assessment)

### 方案A: 仅添加搜索历史清理 ⭐⭐⭐⭐⭐
**描述**: 在当前缓存管理中增加"搜索历史"清理项

**优点**:
- ✅ 需求明确（隐私保护）
- ✅ 实现简单（API已存在）
- ✅ 风险极低（可重新积累）
- ✅ 用户价值高

**缺点**:
- ❌ 功能相对单一

**实现成本**: 极低（1小时）
**用户价值**: 高
**技术风险**: 无

**推荐指数**: ⭐⭐⭐⭐⭐ (9.2/10)

---

### 方案B: 添加搜索历史 + 视频播放数据清理 ⭐⭐⭐⭐
**描述**: 在方案A基础上增加视频播放进度和时长清理

**优点**:
- ✅ 覆盖更多场景（隐私+观看重置）
- ✅ 功能完整性高
- ✅ 实现难度可控

**缺点**:
- ⚠️ 需实现通配符清理逻辑
- ⚠️ 清理后用户需重新定位播放位置（有一定影响）

**实现成本**: 中（2-3小时）
**用户价值**: 中-高
**技术风险**: 低

**推荐指数**: ⭐⭐⭐⭐ (8.0/10)

---

### 方案C: 完整清理系统（搜索历史 + 视频数据 + 智能扫描） ⭐⭐⭐
**描述**: 添加所有可清理的缓存类型

**优点**:
- ✅ 功能最全面
- ✅ 满足高级用户需求
- ✅ 提供"恢复出厂设置"级别的选项

**缺点**:
- ⚠️ 智能扫描清理后需重新扫描（耗时5-30秒）
- ⚠️ UI复杂度增加（需分组或高级选项）
- ⚠️ 测试工作量大

**实现成本**: 高（4-5小时）
**用户价值**: 中（大多数用户用不到智能扫描清理）
**技术风险**: 中

**推荐指数**: ⭐⭐⭐ (6.5/10)

---

## 七、最终建议 (Recommendations)

### 推荐方案: **方案A（仅搜索历史）**

**理由**:
1. **需求明确**: 搜索历史清理是标准的隐私保护功能
2. **实现简单**: API完备，改动最小
3. **风险可控**: 清理后无副作用
4. **性价比最高**: 1小时实现，高用户价值

### 实现优先级

| 优先级 | 缓存类型 | 实现阶段 | 原因 |
|--------|----------|----------|------|
| **P0** | 搜索历史 | 立即实现 | 隐私需求明确，实现简单 |
| **P1** | 视频播放数据 | 后续迭代 | 有场景价值，但优先级次之 |
| **P2** | 智能扫描缓存 | 按需实现 | 高级功能，用户需求不强 |

---

## 八、实现细节 (Implementation Details)

### 8.1 方案A实现清单

#### 1. 修改 `CacheManagerService`

**添加枚举值**:
```dart
enum CacheType {
  thumbnail,
  log,
  categoryScan,
  searchHistory,  // 新增
}
```

**添加清理逻辑**:
```dart
case CacheType.searchHistory:
  final source = SearchHistoryLocalSource();
  await source.clearAllHistory();
  logger.i('Search history cleared');
  return true;
```

**添加缓存信息获取**:
```dart
// 4. 搜索历史
try {
  final source = SearchHistoryLocalSource();
  final history = await source.getAllHistory();
  
  // 计算文件大小
  int size = 0;
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/search_history.json');
  if (await file.exists()) {
    size = await file.length();
  }
  
  items.add(CacheItem(
    name: '搜索历史',
    description: history.isNotEmpty 
        ? '包含 ${history.length} 条搜索记录' 
        : '无搜索记录',
    size: size,
    type: CacheType.searchHistory,
  ));
} catch (e) {
  logger.e('Failed to get search history info: $e');
  items.add(CacheItem(
    name: '搜索历史',
    description: '获取信息失败',
    size: 0,
    type: CacheType.searchHistory,
  ));
}
```

#### 2. UI无需修改
当前 `settings_page.dart` 的缓存管理UI会自动显示新增的缓存项。

#### 3. 测试用例

**添加到 `cache_manager_service_test.dart`**:
```dart
test('清理搜索历史', () async {
  // 添加测试数据
  final source = SearchHistoryLocalSource();
  await source.addSearchRecord('test keyword', resultCount: 10);
  
  // 验证数据存在
  final before = await source.getAllHistory();
  expect(before.length, 1);
  
  // 清理
  final result = await service.clearCache(CacheType.searchHistory);
  expect(result, true);
  
  // 验证清理成功
  final after = await source.getAllHistory();
  expect(after.length, 0);
});
```

### 8.2 工作量估算

| 任务 | 时间 |
|------|------|
| 修改 `CacheManagerService` | 30分钟 |
| 编写测试用例 | 15分钟 |
| 手动测试验证 | 15分钟 |
| **总计** | **1小时** |

---

## 九、决策建议 (Decision Framework)

### 如何决策是否实现其他方案？

**实现方案B（视频播放数据）的条件**:
- ✅ 用户反馈有清理视频观看记忆的需求
- ✅ 有用户报告隐私顾虑（播放历史）
- ✅ 有开发空闲时间（优先级P1）

**实现方案C（智能扫描缓存）的条件**:
- ✅ 用户报告智能扫描功能异常需要重置
- ✅ 设计"高级设置"或"故障排除"功能区
- ✅ 明确的用户需求反馈

---

## 十、总结 (Summary)

### 关键结论
1. **搜索历史是唯一应该立即添加的清理项**（优先级P0）
2. 视频播放数据和智能扫描缓存可作为后续优化（优先级P1-P2）
3. 其他数据（收藏、UI设置、最近文件等）不应纳入清理范围

### 推荐的实施路径
```
阶段1（立即）: 实现方案A - 搜索历史清理 ✅
阶段2（迭代）: 根据用户反馈考虑方案B - 视频播放数据 ⏳
阶段3（按需）: 根据需求考虑方案C - 智能扫描缓存 📋
```

### 最终评分
- **方案A可行性**: ⭐⭐⭐⭐⭐ (9.2/10)
- **实现紧急度**: ⭐⭐⭐⭐ (8.0/10)
- **用户价值**: ⭐⭐⭐⭐ (8.5/10)

**建议**: 立即实现方案A（搜索历史清理），后续根据用户反馈迭代。

---

**分析完成时间**: 2025-11-26  
**分析师**: GitHub Copilot  
**复审状态**: 待用户确认
