# 扫描管理器架构说明

## 📊 当前架构（v2.0 - 按需扫描）

### 核心设计
- **单例模式**: `DuplicateFileScanManager` 全局单例
- **按需扫描**: 只扫描目标文件类型，不扫描所有类型
- **独立缓存**: 每个配置独立的持久化缓存

### 缓存隔离
```
完整检测(100KB)  → duplicate_scan_cache_full_all_100
文档分类(100KB)  → duplicate_scan_cache_category_document_100
视频分类(100KB)  → duplicate_scan_cache_category_video_100
文档分类(200KB)  → duplicate_scan_cache_category_document_200
```

✅ **完全隔离**: 不同配置的缓存互不影响

---

## 🔄 当前扫描行为

### 场景1: 同配置召回
```
文档扫描中 → 用户返回 → 再进入文档页面
↓
检测: scanManager正在扫描文档配置 ✅ 匹配
↓
行为: 召回扫描状态，显示进度
↓
结果: ✅ 用户看到扫描继续进行
```

### 场景2: 不同配置切换（当前限制）
```
文档扫描中 → 用户切换到视频页面
↓
检测: scanManager正在扫描文档配置 ❌ 不匹配
↓
行为: 返回视频缓存（如果有）
↓
结果: ⚠️ 用户看到视频的静态结果，文档扫描继续在后台
```

**限制**: 由于单例设计，一次只能有一个活跃扫描任务

### 场景3: 无缓存启动扫描
```
首次扫描文档 → 点击开始
↓
检测: scanManager空闲 ✅
↓
行为: 启动文档扫描
↓
结果: ✅ 显示扫描进度
```

---

## ⚠️ 当前限制

### 1. 单任务限制
- **问题**: 一次只能执行一个扫描任务
- **影响**: 切换分类时，无法同时维护多个扫描状态
- **表现**: 
  - 文档扫描中 → 启动视频扫描 → 文档扫描状态丢失
  - 用户返回文档页面，看不到扫描进度

### 2. 状态覆盖
- **问题**: scanManager的状态会被新扫描覆盖
- **影响**: 
  ```
  _state: scanning          → 只能存一个状态
  _cachedGroups: [...]      → 只能存一份结果
  _currentConfig: config    → 只能记录一个配置
  ```

---

## 🎯 期望行为

### 用户期望
1. **不同分类独立**: 文档和视频扫描互不影响，可以同时进行
2. **同分类召回**: 文档扫描中，切换到其他地方再回来，继续显示进度
3. **配置变化重扫**: 调整minSize，中断旧扫描，启动新扫描

---

## 🚀 改进方案

### 方案A: 多状态管理（推荐）

**设计思路**: 将单例的状态改为Map存储

```dart
class DuplicateFileScanManager {
  // 改造前（单状态）
  DuplicateScanState _state;
  List<DuplicateFileGroup> _cachedGroups;
  DuplicateFileScanConfig? _currentConfig;
  
  // 改造后（多状态）
  final Map<String, _ConfigScanState> _scanStates = {};
  
  _ConfigScanState _getState(DuplicateFileScanConfig config) {
    final key = _getCacheKey(config);
    return _scanStates.putIfAbsent(key, () => _ConfigScanState());
  }
}

class _ConfigScanState {
  DuplicateScanState state = DuplicateScanState.idle;
  List<DuplicateFileGroup> cachedGroups = [];
  ScanProgress? currentProgress;
  DateTime? scanStartTime;
  // ...
}
```

**优点**:
- ✅ 支持多个配置同时维护状态
- ✅ 每个配置独立进度和缓存
- ✅ 改动相对可控（主要在scanManager）

**实施步骤**:
1. 创建 `_ConfigScanState` 类
2. 将所有状态字段移到该类
3. 使用 Map<String, _ConfigScanState> 存储
4. 修改所有访问状态的方法
5. 测试验证

**工作量**: 中等（2-4小时）

---

### 方案B: 完全独立实例

**设计思路**: 每个配置独立的manager实例

```dart
class EnhancedDuplicateFileScanService {
  final Map<String, DuplicateFileScanManager> _managers = {};
  
  DuplicateFileScanManager _getManager(DuplicateFileScanConfig config) {
    final key = _getCacheKey(config);
    return _managers.putIfAbsent(
      key, 
      () => DuplicateFileScanManager.create() // 非单例
    );
  }
}
```

**优点**:
- ✅ 完全独立，逻辑最清晰
- ✅ 无需改造现有manager代码

**缺点**:
- ❌ 需要移除单例模式
- ❌ 工作量大

**工作量**: 大（4-6小时）

---

### 方案C: UI层过滤（当前实现）

**设计思路**: 保持单例，UI自己判断是否响应

```dart
void _onScanComplete(List<DuplicateFileGroup> groups) {
  final managerConfig = scanManager.currentConfig;
  
  // ✅ 只响应匹配当前配置的回调
  if (managerConfig == null || !managerConfig.isEquivalent(_config)) {
    return; // 忽略其他配置的回调
  }
  
  setState(() => _allGroups = groups);
}
```

**优点**:
- ✅ 改动最小
- ✅ 已经实现

**缺点**:
- ❌ 仍然是单任务，不能真正独立
- ❌ 切换分类会丢失扫描状态

**当前状态**: ✅ 已实施

---

## 📝 实施建议

### 短期（当前）
- ✅ 使用方案C（UI过滤）
- ✅ 完善日志，方便调试
- ✅ 用户测试，收集反馈

### 中期（如需改进）
- 📋 实施方案A（多状态管理）
- 📋 支持真正的多配置独立扫描
- 📋 每个配置维护自己的进度

### 长期（可选）
- 📋 考虑真正的并行扫描（需要评估性能影响）
- 📋 优化内存占用（多个扫描任务同时进行）

---

## 🧪 测试场景

### 基础功能
- [ ] 首次扫描文档
- [ ] 文档扫描完成后再次进入（召回缓存）
- [ ] 调整minSize，触发重新扫描
- [ ] 扫描中途返回，再进入（召回扫描状态）

### 跨配置切换
- [ ] 文档扫描中 → 切换到视频 → 视频显示缓存
- [ ] 视频扫描中 → 切换到文档 → 文档显示缓存
- [ ] 文档扫描中 → 切换到视频 → 启动视频扫描 → 文档扫描被中断

### 边界情况
- [ ] 无缓存时切换配置
- [ ] 扫描失败后重试
- [ ] 多次快速切换配置

---

## 📚 相关文档
- [缓存管理策略](./CACHE_CLEANUP_IMPLEMENTATION.md)
- [增量更新实现](./INSTANT_RENAME_OPTIMIZATION.md)
- [性能优化指南](./PERFORMANCE_OPTIMIZATION_REPORT.md)

---

**最后更新**: 2025-12-01
**版本**: v2.0 (按需扫描方案)
