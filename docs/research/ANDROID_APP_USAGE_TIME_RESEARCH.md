# Android应用使用时间获取方法研究

## 📋 研究目的

研究并验证在Android平台上获取应用最近使用时间的各种方法，解决华为/荣耀设备上使用统计数据只保留7-10天的限制问题。

## 🔍 问题背景

### 当前发现的问题

在华为REA AN00设备上测试发现：
- ✅ 查询参数：`daysBack=365`（请求365天数据）
- ✅ 查询时间范围：`2024-12-03` 到 `2025-12-03`（完整的365天）
- ❌ **实际返回数据**：系统只返回了最近**7-10天**的使用记录
- ❌ **统计结果**：
  - 0-7天: 263条记录
  - 8-30天: 60条记录（实际都是8-9天）
  - 31-180天: 0条记录
  - >180天: 0条记录

### 影响

用户在应用管理页面只能看到"刚刚"、"几分钟前"、"几小时前"、"昨天"、"X天前"、"1周前"，无法看到"2周前"、"1个月前"、"3个月前"等更久远的时间标记。

## 🎯 研究目标

1. **验证不同Android版本和设备厂商的数据保留策略**
   - 华为/荣耀设备的限制
   - 小米、OPPO、vivo等其他厂商
   - 原生Android系统

2. **探索替代方案**
   - UsageStatsManager的不同查询方式
   - PackageManager的安装时间信息
   - 文件系统的最后访问时间
   - 自建数据库记录使用历史

3. **设计最优解决方案**
   - 结合多种数据源
   - 提供降级策略
   - 用户体验优化

## 📊 研究方法

### 方法1: UsageStatsManager深度研究

#### 1.1 不同查询间隔（INTERVAL）测试

Android的UsageStatsManager提供了不同的查询间隔：
```kotlin
- INTERVAL_DAILY: 按天统计
- INTERVAL_WEEKLY: 按周统计
- INTERVAL_MONTHLY: 按月统计
- INTERVAL_YEARLY: 按年统计
- INTERVAL_BEST: 最佳间隔（当前使用）
```

**测试计划**：
- [ ] 测试INTERVAL_DAILY能否获取更久远的数据
- [ ] 测试INTERVAL_WEEKLY的数据范围
- [ ] 测试INTERVAL_MONTHLY的数据范围
- [ ] 对比不同间隔返回的数据差异

#### 1.2 分段查询策略

**假设**：系统可能限制了单次查询的数据量，尝试分段查询可能获取更多历史数据。

**测试计划**：
- [ ] 查询最近30天
- [ ] 查询30-60天前
- [ ] 查询60-90天前
- [ ] 查询90-180天前
- [ ] 查询180-365天前

#### 1.3 UsageEvents API

除了UsageStats，Android还提供了UsageEvents API，可能包含更详细的事件信息。

```kotlin
val usageEvents = usageStatsManager.queryEvents(startTime, endTime)
while (usageEvents.hasNextEvent()) {
    val event = UsageEvents.Event()
    usageEvents.getNextEvent(event)
    // 分析事件类型和时间戳
}
```

**测试计划**：
- [ ] 查询UsageEvents的数据范围
- [ ] 对比UsageEvents与UsageStats的差异
- [ ] 验证事件类型（ACTIVITY_RESUMED, ACTIVITY_PAUSED等）

### 方法2: PackageManager元数据

#### 2.1 安装和更新时间

PackageInfo包含以下时间信息：
```kotlin
- firstInstallTime: 首次安装时间
- lastUpdateTime: 最后更新时间
```

**使用场景**：
- 如果应用从未使用，可以显示"安装后从未使用"
- 如果lastTimeUsed为null，但安装很久了，可推断为"长期未使用"

**测试计划**：
- [ ] 获取所有应用的安装时间
- [ ] 对比安装时间和使用时间
- [ ] 设计合理的展示逻辑

#### 2.2 应用文件最后修改时间

应用的数据目录可能包含最后访问信息：
```kotlin
val appDataDir = packageInfo.applicationInfo.dataDir
val lastModified = File(appDataDir).lastModified()
```

**限制**：
- 需要存储权限
- 可能不准确（系统后台任务可能修改文件）

**测试计划**：
- [ ] 测试是否能访问应用数据目录
- [ ] 验证lastModified的准确性
- [ ] 评估可行性

### 方法3: 自建使用记录数据库

#### 3.1 本地数据库方案

在我们的应用中维护一个数据库，记录：
- 应用首次被查询的时间
- 应用每次使用时间更新
- 长期历史记录

**优点**：
- 不受系统限制
- 可以保存完整历史
- 可以添加自定义字段

**缺点**：
- 无法获取安装本应用之前的历史
- 占用存储空间
- 需要定期同步

**测试计划**：
- [ ] 设计数据库表结构
- [ ] 实现数据同步逻辑
- [ ] 测试长期使用效果

### 方法4: 系统级别查询（需要ROOT或系统权限）

#### 4.1 直接查询系统数据库

Android系统在以下位置存储使用统计：
```
/data/system/usagestats/
```

**限制**：
- 需要ROOT权限
- 不适合普通应用

**研究价值**：
- 了解系统数据结构
- 确认数据确实不存在还是查询方式问题

### 方法5: 云端同步方案

如果用户在多设备使用，可以考虑云端同步应用使用记录。

**优点**：
- 跨设备同步
- 不受单设备限制
- 可以保存完整历史

**缺点**：
- 需要用户登录
- 涉及隐私问题
- 实现复杂度高

## 🧪 实验设计

### 实验1: 不同INTERVAL的数据范围测试

**目标**：验证不同查询间隔是否影响数据保留时长

**步骤**：
1. 分别使用5种INTERVAL查询同样的时间范围
2. 统计每种方式返回的最远记录
3. 对比差异

**代码位置**：
- Android: `MainActivity.kt` - 添加测试方法
- Flutter: `usage_stats_service.dart` - 添加不同查询方法

### 实验2: 分段查询测试

**目标**：验证是否可以通过分段查询获取更久远数据

**步骤**：
1. 将365天分为多个时间段
2. 分别查询每个时间段
3. 合并结果并统计

**代码位置**：
- Android: `MainActivity.kt` - 实现分段查询
- Flutter: 添加测试页面展示结果

### 实验3: UsageEvents API测试

**目标**：验证UsageEvents是否保留更长历史

**步骤**：
1. 查询365天的UsageEvents
2. 过滤应用相关事件
3. 统计最远事件时间

**代码位置**：
- Android: `MainActivity.kt` - 添加UsageEvents查询
- Flutter: 对比两种API的结果

### 实验4: 多设备对比测试

**目标**：验证是否是厂商特定限制

**步骤**：
1. 在不同品牌设备上测试
2. 记录每个设备的数据保留时长
3. 总结规律

**测试设备**：
- ✅ 华为 REA AN00 (当前测试设备)
- [ ] 小米设备
- [ ] OPPO设备
- [ ] vivo设备
- [ ] 原生Android设备（如Google Pixel）

## 📝 研究记录

### 2025-12-03 初始调查

**设备**: 华为 REA AN00
**Android版本**: 待确认
**测试方法**: UsageStatsManager with INTERVAL_BEST

**结果**:
- 查询参数: daysBack=365
- 系统返回: 1796条记录
- 时间分布:
  - 0-7天: 263条
  - 8-9天: 60条
  - 10天及以上: 0条

**结论**: 华为设备确实存在7-10天的数据保留限制

### 后续实验结果

_待补充..._

## 💡 解决方案设计

### 方案A: 混合数据源（推荐）

结合多种数据源提供最佳用户体验：

1. **优先使用UsageStats**（7-10天内）
   - 显示准确的使用时间

2. **降级使用安装时间**（10天以上）
   - 如果应用安装超过10天且无使用记录
   - 显示"安装后从未使用"或"长期未使用"

3. **启用本地记录**（可选）
   - 用户可选择启用长期记录功能
   - 保存完整的使用历史

**实现优先级**: 高

### 方案B: 自建完整记录系统

从第一次使用本应用开始，记录所有应用的使用情况。

**优点**: 数据完整、不受系统限制
**缺点**: 无法获取历史数据、占用存储

**实现优先级**: 中

### 方案C: 接受系统限制

只显示系统提供的数据，对于超过保留期的应用显示特殊标记。

**优点**: 实现简单、符合系统设计
**缺点**: 用户体验受限

**实现优先级**: 低（当前方案）

## 📚 参考资料

### Android官方文档

- [UsageStatsManager](https://developer.android.com/reference/android/app/usage/UsageStatsManager)
- [UsageStats](https://developer.android.com/reference/android/app/usage/UsageStats)
- [UsageEvents](https://developer.android.com/reference/android/app/usage/UsageEvents)
- [PackageInfo](https://developer.android.com/reference/android/content/pm/PackageInfo)

### 相关讨论

- Stack Overflow: "UsageStats data retention period"
- GitHub Issues: 各个ROM的使用统计限制讨论
- XDA Forums: 厂商定制系统的差异

## ✅ 任务清单

### 阶段1: 深度研究（本分支）

- [ ] 实现不同INTERVAL的测试代码
- [ ] 实现分段查询测试
- [ ] 实现UsageEvents API测试
- [ ] 收集多设备测试数据
- [ ] 分析测试结果
- [ ] 编写结论报告

### 阶段2: 方案实现

- [ ] 设计最优方案
- [ ] 实现混合数据源逻辑
- [ ] 更新UI展示逻辑
- [ ] 添加用户设置选项
- [ ] 完善文档

### 阶段3: 测试验证

- [ ] 单元测试
- [ ] 集成测试
- [ ] 多设备真机测试
- [ ] 用户反馈收集

## 🎓 学习成果

_研究过程中的发现和总结..._

---

**分支**: research/android-app-usage-time
**创建时间**: 2025-12-03
**负责人**: GitHub Copilot + User
**状态**: 🔬 研究进行中
