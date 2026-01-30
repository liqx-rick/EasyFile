## 🎯 实际测试执行指南

**目标**: 在真实 Android 设备上验证启动场景的实现

**准备状态**: ✅ 代码已编译，依赖已解析，设备已连接

> ⚠️ **重要变更（2026-01-31）**: `reinstall`场景已从代码库中移除（P1高优先级清理任务）。
> 原因：Android卸载/清除数据会删除SharedPreferences，实际中该场景无法达到（<1%概率）。
> **当前仅支持两个场景**: `freshInstall` 和 `normalOpen`。本文档中的场景2(reinstall)相关内容仅供历史参考。

---

## 📱 设备信息

**连接的 Android 设备**:
- 设备型号: REA AN00
- Android 版本: Android 15 (API 35)
- 设备 ID: AADMVB3630000895
- 状态: ✅ 已连接并就绪

---

## 🚀 快速开始

### 方式1: 使用测试脚本（推荐）

```bash
cd c:\dev\flutter\easyfile
test_scenarios.bat
```

然后按照菜单选择要执行的测试。

### 方式2: 手动执行命令

选择下面任一场景开始测试。

---

## 📍 测试场景详细步骤

### 🔹 场景 1️⃣: 首次安装 (freshInstall)

**目的**: 验证全新安装时的三阶段初始化完整流程

#### 步骤 1: 清理设备
```bash
# 终端1: 进入项目目录
cd c:\dev\flutter\easyfile

# 卸载应用
adb uninstall com.example.easyfile

# 等待卸载完成
echo 应用已卸载，请按Enter继续...
pause
```

#### 步骤 2: 启动日志监控
```bash
# 新终端2: 监控应用日志
cd c:\dev\flutter\easyfile
flutter logs
```

你会看到类似的日志输出:
```
I/Dart     ( 1234): [AppInitService] Starting full initialization...
I/Dart     ( 1234): [AppInitService] Loading basic resources...
I/Dart     ( 1234): [AppInitService] Basic resources loading completed
I/Dart     ( 1234): [AppInitService] Loading category statistics cache...
I/Dart     ( 1234): [AppInitService] Category statistics: images = X files
...
I/Dart     ( 1234): [AppInitService] Full initialization completed
I/Dart     ( 1234): [FirstInstallService] Marked as initialized
```

#### 步骤 3: 启动应用
```bash
# 终端1: 继续执行
flutter run
```

#### 步骤 4: 验证
在设备屏幕上观察:

**UI 预期**:
- [ ] 应用启动后显示进度条 UI（FirstScanCardOverlay）
- [ ] 进度条从 0% 开始逐步增加
- [ ] 进度条分为几个明显的阶段
- [ ] 约 37 秒后进度完成，应用完全加载

**进度条阶段**:
1. **0-35%**: 基础资源加载 + 分类统计缓存 (~4-5秒)
2. **35-100%**: 文件系统完整扫描 (~30秒)
3. **100%**: 初始化完成，应用完全可用

**功能预期**:
- [ ] 进度完成后，UI 完全响应
- [ ] 快速访问菜单已加载
- [ ] 所有分类（图片、视频、音乐、文档等）已显示
- [ ] 可以浏览文件和文件夹
- [ ] 没有任何错误消息或崩溃

**时间指标**:
- 记录实际耗时: **___ 秒** (预期: 35-40秒)

**性能检查**:
```bash
# 在终端中观察输出
# 查找这些时间戳来计算阶段耗时:
[AppInitService] Starting full initialization... <- 开始时间
[AppInitService] Basic resources loading completed <- P0 完成
[AppInitService] Category statistics loading completed <- P1 完成
[AppInitService] Full file system scan completed <- P2 完成
[AppInitService] Full initialization completed <- 总耗时
```

**日志检查清单**:
- [ ] 看到 "[AppInitService] Starting full initialization..."
- [ ] 看到 "[AppInitService] Loading basic resources..."
- [ ] 看到 "[AppInitService] Loading category statistics cache..."
- [ ] 看到各个分类的统计数字（images=?, video=?, 等）
- [ ] 看到 "[AppInitService] Executing full file system scan..."
- [ ] 看到 "[AppInitService] Full initialization completed"
- [ ] 看到 "[FirstInstallService] Marked as initialized"
- [ ] 没有看到 ERROR 或 FATAL 日志

---

### 🔹 场景 2️⃣: 缓存重装 (reinstall)

**前置条件**:
- ✅ 场景1 (freshInstall) 已完成
- ✅ 看到 "Full initialization completed" 消息
- ✅ 应用已完全加载

**目的**: 验证缓存有效时的快速加载

#### 步骤 1: 准备场景
```bash
# 在 flutter logs 的终端中，继续监控日志
# 确保能看到后续的日志输出
```

#### 步骤 2: 卸载应用（保留数据）
```bash
# 终端1:
adb uninstall com.example.easyfile

# 等待卸载完成
echo 应用已卸载，请按Enter继续...
pause
```

⚠️ **重要**: 此步骤卸载应用，但 `/data/data/com.example.easyfile/shared_prefs/` 中的数据会被保留

#### 步骤 3: 重新安装应用
```bash
# 终端1:
flutter install
```

#### 步骤 4: 启动应用
```bash
# 终端1:
flutter run
```

#### 步骤 5: 验证
在设备屏幕上观察:

**UI 预期**:
- [ ] **应该 NO 进度 UI 显示**（这是关键差异！）
- [ ] 应用极快地启动（2-4秒）
- [ ] 快速访问菜单立即可见
- [ ] 之前的收藏夹和快速访问项目已恢复

**日志检查**:
```
[Orchestrator] Detected startup scene: reinstall
[DataLoadService] Starting load from cache (reinstall scenario)...
[DataLoadService] Cache valid, loading basic resources from database...
[DataLoadService] Quick access folders loaded
[DataLoadService] Favorites loaded
[DataLoadService] Favorite files loaded
[DataLoadService] Theme initialized
[DataLoadService] Data loaded from cache successfully
```

**关键验证点**:
- [ ] 日志中出现 "Detected startup scene: reinstall"
- [ ] 日志中出现 "Cache valid, loading..."
- [ ] **不应该**出现 "Starting full initialization..."
- [ ] **不应该**出现进度条相关的日志
- [ ] 加载时间小于 5 秒

**时间指标**:
- 记录实际耗时: **___ 秒** (预期: 2-4秒)

**性能对比**:
- 场景1耗时: ___ 秒 (freshInstall)
- 场景2耗时: ___ 秒 (reinstall 缓存)
- **性能提升**: ___ x 倍

---

### 🔹 场景 3️⃣: 正常打开 (normalOpen)

**前置条件**:
- ✅ 场景1 (freshInstall) 已完成

- ✅ 应用已初始化完成

**目的**: 验证初始化完成后的正常启动速度

#### 步骤 1: 准备场景
```bash
# 在 flutter logs 的终端中，继续监控日志
```

#### 步骤 2: 关闭应用进程
```bash
# 终端1:
adb shell am force-stop com.example.easyfile

# 等待进程关闭
timeout /t 2 /nobreak
```

#### 步骤 3: 重新启动应用
```bash
# 终端1:
flutter run

# 或在设备上点击应用图标
```

#### 步骤 4: 验证
在设备屏幕上观察:

**UI 预期**:
- [ ] **应该 NO 进度 UI 显示**
- [ ] 应用极快地启动（1-3秒）
- [ ] 所有数据完整可用
- [ ] UI 立即响应

**日志检查**:
```
[Orchestrator] Detected startup scene: normalOpen
[DataLoadService] Starting load from database (normal open scenario)...
[DataLoadService] Loading basic resources from database...
[DataLoadService] Quick access folders loaded
[DataLoadService] Favorites loaded
[DataLoadService] Favorite files loaded
[DataLoadService] Theme initialized
[DataLoadService] Data loaded from database successfully
```

**关键验证点**:
- [ ] 日志中出现 "Detected startup scene: normalOpen"
- [ ] 日志中出现 "load from database"
- [ ] **不应该**出现 "Cache valid" 消息
- [ ] **不应该**出现进度条相关的日志
- [ ] 加载时间小于 3 秒

**时间指标**:
- 记录实际耗时: **___ 秒** (预期: 1-3秒)

**性能对比**:
- 场景1耗时: ___ 秒 (freshInstall)
- 场景3耗时: ___ 秒 (normalOpen DB)
- **性能对比**: ___ x 倍

---

## 📊 测试结果汇总表

填写以下表格来记录测试结果:

### 功能验证

| 验证项 | 场晦1<br>(freshInstall) | 场晦2<br>(normalOpen) | 备注 |
|--------|:-----:|:-----:|------|
| 场景检测正确 | [ ] | [ ] | 日志中显示正确的场景名 |
| 进度 UI 显示 | [ ] | [ ] | 仅场晦1应显示 |
| 进度 UI 隐藏 | [ ] | [ ] | 场晦2应隐藏 |
| 应用完全加载 | [ ] | [ ] | 所有UI和数据可用 |
| 数据完整性 | [ ] | [ ] | 菜单、收藏、分类 |
| 无崩溃/错误 | [ ] | [ ] | 日志中无ERROR |
| 无加载失败 | [ ] | [ ] | 全部资源加载成功 |

### 性能指标

| 指标 | 预期 | 场景1 实际 | 场景2 实际 | 场景3 实际 |
|------|------|----------|----------|----------|
| 初始化时间 | 37秒 | ___ | N/A | N/A |
| 缓存加载时间 | N/A | N/A | 3秒 | N/A |
| DB加载时间 | N/A | N/A | N/A | 2秒 |
| 进度完成速度 | 逐步 | [ ] | N/A | N/A |
| **总体性能评分** | ⭐⭐⭐⭐⭐ | ___ | ___ | ___ |

### 日志质量

| 检查项 | 场景1 | 场景2 | 场景3 | 备注 |
|--------|:----:|:----:|:----:|------|
| 日志清晰完整 | [ ] | [ ] | [ ] | 能清楚看到执行流程 |
| 进度报告准确 | [ ] | [ ] | [ ] | 百分比逐步增加 |
| 错误处理明确 | [ ] | [ ] | [ ] | 失败有明确日志 |
| 降级提示清晰 | N/A | N/A | N/A | 如果需要降级 |

---

## 🔍 常见问题排查

### 问题1: 应用启动崩溃

**症状**: 应用启动后立即崩溃

**解决步骤**:
1. 检查日志中的 ERROR 和 FATAL 消息
2. 查看 DI 容器初始化是否失败
3. 验证权限是否被正确授予

```bash
# 查看详细的崩溃日志
adb logcat -s "AndroidRuntime" | head -50

# 重新安装并清理缓存
adb shell pm clear com.example.easyfile
flutter install
```

### 问题2: 进度 UI 不显示（场景1中）

**症状**: freshInstall 时没有进度条显示

**可能原因**:
- FirstInstallService 检测失败
- StartupOrchestrator 场景检测错误
- FileBrowserPage 未正确集成

**检查步骤**:
```bash
# 查看日志中是否有这些消息
# [Orchestrator] Detected startup scene: freshInstall
# [AppInitService] Starting full initialization...

# 如果没有，检查日志
flutter logs | grep "Orchestrator\|AppInitService"
```

### 问题3: 缓存没有被使用（场景2中）

**症状**: 场景2中仍然显示进度 UI 或使用了完整初始化

**可能原因**:
- 初始化标志未正确设置
- SharedPreferences 数据未保留
- 缓存时间戳检查失败

**检查步骤**:
```bash
# 查看 SharedPreferences
adb shell pm dump com.example.easyfile | grep shared_pref

# 或直接查看文件
adb shell cat /data/data/com.example.easyfile/shared_prefs/com.example.easyfile_preferences.xml

# 寻找这两个键:
# is_initialization_complete (应为 true)
# last_full_scan_time (应为最近的时间戳)
```

### 问题4: 性能指标不符预期

**症状**: 加载时间超过预期值

**可能原因**:
- 设备存储性能问题
- 文件系统中有大量文件
- 网络 I/O 阻塞

**解决步骤**:
1. 检查设备存储空间
2. 检查文件系统中的文件数量
3. 尝试在不同设备上测试

```bash
# 检查设备存储
adb shell df

# 检查应用文件夹大小
adb shell du -h /data/data/com.example.easyfile/
```

---

## ✅ 测试完成检查清单

所有以下项都打勾时，表示测试完成：

### 代码质量
- [ ] 所有代码已编译，0 个错误
- [ ] flutter analyze 已运行，新代码无警告
- [ ] 所有服务已正确注入
- [ ] 日志记录清晰完整

### 功能验证
- [ ] 场景1 (freshInstall) 已测试
  - [ ] 进度 UI 正确显示
  - [ ] 初始化流程完整
  - [ ] 时间在预期范围内
- [ ] 场晦2 (normalOpen) 已测试
  - [ ] 进度 UI 正确隐藏
  - [ ] DB 直接加载
  - [ ] 极速启动

### 数据完整性
- [ ] 快速访问菜单已正确加载
- [ ] 收藏夹已正确恢复（场景2/3）
- [ ] 文件分类已正确显示
- [ ] 文件浏览功能正常

### 错误处理
- [ ] 没有程序崩溃
- [ ] 错误消息清晰有用
- [ ] 降级流程正常工作
- [ ] 日志中无隐藏错误

---

## 📝 测试记录

```
测试日期: ________________
测试者: ________________
设备型号: REA AN00 (Android 15)

场景1 (freshInstall):
  状态: [ ] Pass [ ] Fail
  实际时间: ___ 秒
  备注: ___________________________

场晦2 (normalOpen):
  状态: [ ] Pass [ ] Fail
  实际时间: ___ 秒
  备注: ___________________________

总体评价:
___________________________________________________
___________________________________________________

问题和建议:
___________________________________________________
___________________________________________________
```

---

## 🚀 下一步

**测试完成后**:
1. 记录所有结果到上面的表格
2. 保存测试日志文件用于分析
3. 如发现问题，记录详细信息
4. 考虑在不同 Android 版本上测试
5. 运行长期稳定性测试（多次重复启动）

**可选的高级测试**:
- [ ] 内存泄漏检测（Android Profiler）
- [ ] 电池消耗分析
- [ ] 网络流量监控
- [ ] CPU 使用率分析
- [ ] 不同网络状态下的性能

---

**准备开始测试？按照 "快速开始" 部分的步骤开始！** 🎯
