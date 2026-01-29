# 埋点实施清单

## ✅ 已完成模块

### P0 核心埋点 - 100% 完成

1. **应用生命周期** ✅
   - 文件：`lib/app.dart`
   - 事件：
     - `app_launch` - 应用启动（在 main.dart）
     - `app_foreground` - 进入前台
     - `app_background` - 进入后台

2. **首页推荐模块** ✅
   - 文件：`lib/ui/pages/recommend_aggregate_page.dart`
   - 事件：
     - `home_recommend_view` - 推荐卡片浏览

3. **扫描 & 清理功能** ✅
   - 文件：
     - `lib/ui/pages/large_files_page.dart` - 大文件扫描
     - `lib/ui/pages/duplicate_files_page.dart` - 重复文件扫描
     - `lib/ui/pages/junk_files_page.dart` - 垃圾文件清理
     - `lib/ui/pages/apk_management_page.dart` - APK管理
   - 事件：
     - `scan_start` - 扫描开始
     - `scan_finish` - 扫描完成（含时长、文件数、大小）
     - `clean_action` - 清理操作（含类型、文件数、大小）

4. **隐私空间** ✅
   - 文件：`lib/ui/pages/privacy_space_page.dart`
   - 事件：
     - `privacy_space_enter` - 进入隐私空间

5. **压缩包管理** ✅
   - 文件：`lib/ui/pages/archive_management_page.dart`
   - 事件：
     - `archive_management_enter` - 进入页面

6. **快速访问** ✅
   - 文件：
     - `lib/ui/pages/quick_access_manage_page.dart` - 管理页面
     - `lib/ui/widgets/quick_access_section.dart` - 主页卡片
     - `lib/presenter/quick_access_presenter.dart` - 业务逻辑
   - 事件：
     - `quick_access_enter` - 进入管理页面
     - `quick_access_card_click` - 点击推荐卡片
     - `quick_access_rename` - 重命名文件夹

---

## ✅ P1 重要埋点 - 100% 完成

### 7. 分类聚合页面 ✅
- 文件：`lib/ui/pages/category_file_page.dart`
- 事件：
  - `category_enter` - 进入分类（含分类类型）

### 8. 文件浏览模块 ✅
- 文件：`lib/ui/pages/file_browser_root_page.dart`
- 事件：
  - `file_browse_enter` - 进入浏览（含入口类型）

### 9. 回收站 ✅
- 文件：`lib/ui/pages/trash_page.dart`
- 事件：
  - `trash_view` - 查看回收站
  - `trash_restore` - 恢复文件
  - `trash_permanent_delete` - 永久删除（含文件数）

---

## ✅ P2 次要埋点 - 100% 完成

### 10. 应用管理模块 ✅
- 文件：`lib/ui/pages/app_management_page.dart`
- 事件：
  - `app_management_enter` - 进入应用管理
  - `app_settings_open` - 打开应用设置（用户可能卸载应用）

### 11. 设置模块 ✅
- 文件：`lib/ui/pages/settings_page.dart`
- 事件：
  - `settings_enter` - 进入设置页面
  - `settings_change` - 关键设置修改（主题、隐藏空文件夹、最小文件大小）

---

## 🟡 待完善模块（可选）

### P2 低优先级（已完成）

~~#### 1. 应用管理模块~~ ✅
~~#### 2. 设置模块~~ ✅

---

## 📊 埋点覆盖统计

### 已实现事件数量
- **P0 核心**: 13 个事件 ✅
  - 应用生命周期: 3 events
  - 首页推荐: 1 event
  - 扫描入口: 4 events (large/duplicate/junk/apk)
  - 隐私空间: 1 event
  - 压缩包管理: 1 event
  - 快速访问: 3 events

- **P1 重要**: 12 个事件 ✅
  - 扫描生命周期: 6 events (start/finish × 3 modules)
  - 清理操作: 1 event (large_files clean)
  - 分类页面: 1 event
  - 文件浏览: 1 event
  - 回收站: 3 events (view/restore/delete)

- **P2 次要**: 5 个事件 ✅
  - 应用管理: 2 events (enter/settings_open)
  - 设置页面: 3 events (enter/change主题/change其他设置)

- **总计**: ~30 个埋点事件已实现
 - **总计**: 38 个埋点事件已实现

### 核心指标捕获
- ✅ 扫描时长（duration_ms）
- ✅ 文件数量（item_count）
- ✅ 文件大小（total_size_mb / size_mb）
- ✅ 扫描类型（scan_type: large_file / duplicate / junk / apk）
- ✅ 清理类型（clean_type）
- ✅ 入口类型（entry_point）
- ✅ 分类类型（category_type）

---

## 🔍 测试验证方法

### 快速验证步骤

1. **热重载应用**
   ```bash
   # 在 flutter run 终端按 'r'
   ```

2. **监控 logcat 日志**
   ```bash
   adb logcat -s UmengAnalyticsChannel:D
   ```

3. **测试场景**

   **P0 核心测试**:
   - ✅ 应用启动 → 查看 `app_launch`
   - ✅ 切换后台/前台 → 查看 `app_background` / `app_foreground`
   - ✅ 首页推荐卡片 → 查看 `home_recommend_view`
   - ✅ 进入隐私空间 → 查看 `privacy_space_enter`
   - ✅ 进入快速访问 → 查看 `quick_access_enter`

   **P1 扫描生命周期测试**:
   - ✅ 大文件扫描 → 查看 `scan_start` + `scan_finish` 含 duration_ms/item_count/total_size_mb
   - ✅ 重复文件扫描 → 查看扫描埋点含分组统计
   - ✅ 垃圾文件扫描 → 查看扫描埋点含垃圾文件指标
   - ✅ 大文件清理 → 查看 `clean_action` 含 size_mb

   **P1 其他功能测试**:
   - ✅ 打开图片分类 → 查看 `category_enter` 含 category_type
   - ✅ 打开文件浏览器 → 查看 `file_browse_enter` 含 entry_point
   - ✅ 回收站操作 → 查看 `trash_view` / `trash_restore` / `trash_permanent_delete`

4. **预期日志示例**
   ```
   D/UmengAnalyticsChannel: Logged event: scan_start with params: {type=large_file}
   D/UmengAnalyticsChannel: Logged event: scan_finish with params: {type=large_file, duration_ms=5234, item_count=120, total_size_mb=1024.5}
   D/UmengAnalyticsChannel: Logged event: clean_action with params: {type=large_file, item_count=5, size_mb=156.7}
   ```

---

## ✅ 实施进度追踪
---

## ✅ 实施进度追踪

### Phase 1-5: 基础架构 ✅
- ✅ AnalyticsManager + AnalyticsService 抽象
- ✅ UmengAnalyticsService 实现
- ✅ Android Native Bridge (Kotlin)
- ✅ AnalyticsHelper 便捷方法封装
- ✅ 配置管理系统集成

### Phase 6: P0 核心埋点 ✅
- ✅ 应用生命周期事件（3个）
- ✅ 首页推荐浏览
- ✅ 隐私空间入口
- ✅ 扫描功能入口（4个）
- ✅ 压缩包管理入口
- ✅ 快速访问（3个）
- ✅ Bug修复：File → rootBundle 初始化

### Phase 7: SDK合规 ✅
- ✅ Umeng preInit 实现
- ✅ Privacy authorization 配置

### Phase 8: P1 详细埋点 ✅
- ✅ 大文件扫描生命周期（start/finish/clean）
- ✅ 重复文件扫描生命周期（start/finish）
- ✅ 垃圾文件扫描生命周期（start/finish）
- ✅ 分类页面入口
- ✅ 文件浏览器入口
- ✅ 回收站操作（view/restore/delete）

### Phase 9: P2 次要埋点 ✅
- ✅ 应用管理（enter/settings_open）
- ✅ 设置页面（enter/change）

**总计**: ~30 个事件，P0+P1+P2 100% 完成 ✅

---

## 🎯 后续建议

### 1. 立即测试（推荐）
通过热重载验证新增埋点：
```bash
# 在 flutter run 终端按 'r'
# 监控日志：adb logcat -s UmengAnalyticsChannel:D
```

### 3. 生产部署准备
- ✅ 检查 Umeng 后台数据接收（5-10分钟延迟）
- ✅ 考虑添加用户同意弹窗（GDPR合规）
- ✅ 验证埋点指标质量（duration/size/count）

---

## 📊 当前覆盖率

- ✅ **P0 核心**: 100% 完成（13个事件）
- ✅ **P1 重要**: 100% 完成（12个事件）
- ✅ **P2 次要**: 100% 完成（5个事件）

**总埋点数**: ~30 个事件已实现
**覆盖场景**: 应用生命周期、扫描清理、隐私空间、快速访问、分类浏览、文件管理、回收站、应用管理、设置

- 埋点辅助类：`lib/analytics/analytics_helper.dart`
- 埋点管理器：`lib/analytics/analytics_manager.dart`
 - 埋点示例：请使用 `AnalyticsHelper` 中的方法作为调用示例（`lib/analytics/analytics_helper.dart`）
 - 配置文件：`config/analytics_config.yaml`（由 `AnalyticsConfig` 读取）

**实现说明（基于当前代码）**:
- `FirebaseAnalyticsService` 为占位 no-op（未集成 Firebase SDK），不会上报事件。
- `UmengAnalyticsService` 通过 `MethodChannel('easyfile/analytics')` 与原生交互，原生需实现方法：`preInit`, `grantPrivacy`, `init`, `logEvent`。
- `AnalyticsManager` 当前没有在运行时提供 `enable` / `disable` / `clear` API；若需要运行时切换或清理，需要在代码中新增相应方法。

---

## 🔗 相关文档

- [P0埋点实施完成报告](P0_ANALYTICS_IMPLEMENTATION_COMPLETE.md)
- [埋点架构设计](ANALYTICS_ARCHITECTURE.md)
- [友盟SDK集成指南](UMENG_INTEGRATION.md)


