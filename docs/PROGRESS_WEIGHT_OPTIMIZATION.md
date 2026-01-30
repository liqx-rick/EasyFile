# 动态进度权重优化方案

## 🔍 问题分析

### 当前问题

**固定权重分配**（total = 1.0）:
```dart
P0: 2%  (p0_init)
P1.1: 68% (分类扫描: images 12% + video 10% + music 10% + documents 12% + downloads 8% + apk 8% + archive 8%)
P1.2: 20% (应用扫描: p1_apps)
P2: 10% (文件夹检测: p2_folders)
```

**场景1: 禁用分类扫描（enableP1CategoryScan = false）**
- 实际执行: P0(2%) → P1.2(20%) → P2(10%) = 32%
- **问题**: 68%的进度被跳过，进度条从2%跳到70%

**场景2: 快速启动（两个都禁用）**
- 实际执行: P0(2%) → P2(10%) = 12%
- **问题**: 88%的进度被跳过，进度条从2%跳到90%

**场景3: 禁用应用扫描（enableP1AppScan = false）**
- 实际执行: P0(2%) → P1.1(68%) → P2(10%) = 80%
- **问题**: 20%的进度被跳过，进度条从70%跳到90%

---

## 🎯 解决方案

### 方案1: 动态权重归一化（推荐）⭐⭐⭐⭐⭐

**核心思路**: 根据配置计算实际执行的阶段，重新分配权重使总和=1.0

#### 实现步骤

**Step 1: 修改 RobustProgressCalculator**

```dart
// robust_progress_calculator.dart

import 'initialization_config.dart'; // 添加import

class RobustProgressCalculator {
  /// 基础阶段权重（相对权重，用于计算比例）
  static const Map<String, double> _baseWeights = {
    'p0_init': 0.02,
    'p1_images': 0.12,
    'p1_video': 0.10,
    'p1_music': 0.10,
    'p1_documents': 0.12,
    'p1_downloads': 0.08,
    'p1_apk': 0.08,
    'p1_archive': 0.08,
    'p1_apps': 0.20,
    'p2_folders': 0.10,
  };

  /// 当前配置
  final InitializationConfig? _config;

  /// 有效权重（根据配置动态计算）
  late final Map<String, double> _effectiveWeights;

  RobustProgressCalculator({InitializationConfig? config})
      : _config = config {
    _effectiveWeights = _calculateEffectiveWeights();
  }

  /// 根据配置计算有效权重（归一化到1.0）
  Map<String, double> _calculateEffectiveWeights() {
    final weights = <String, double>{};

    // P0: 始终执行
    weights['p0_init'] = _baseWeights['p0_init']!;

    // P1.1: 根据配置决定
    if (_config?.enableP1CategoryScan ?? true) {
      weights['p1_images'] = _baseWeights['p1_images']!;
      weights['p1_video'] = _baseWeights['p1_video']!;
      weights['p1_music'] = _baseWeights['p1_music']!;
      weights['p1_documents'] = _baseWeights['p1_documents']!;
      weights['p1_downloads'] = _baseWeights['p1_downloads']!;
      weights['p1_apk'] = _baseWeights['p1_apk']!;
      weights['p1_archive'] = _baseWeights['p1_archive']!;
    }

    // P1.2: 根据配置决定
    if (_config?.enableP1AppScan ?? true) {
      weights['p1_apps'] = _baseWeights['p1_apps']!;
    }

    // P2: 始终执行
    weights['p2_folders'] = _baseWeights['p2_folders']!;

    // 归一化：确保总和为1.0
    return _normalizeWeights(weights);
  }

  /// 归一化权重（总和调整为1.0）
  Map<String, double> _normalizeWeights(Map<String, double> weights) {
    final sum = weights.values.reduce((a, b) => a + b);
    if (sum == 0) return weights;

    return weights.map((phase, weight) => MapEntry(phase, weight / sum));
  }

  /// 计算当前总进度（使用动态权重）
  double calculateProgress({
    List<String> completedPhases = const [],
    required String currentPhase,
    required double stageProgress,
  }) {
    // 1. 计算已完成阶段的权重总和（使用有效权重）
    double completedWeight = 0.0;
    for (final phase in completedPhases) {
      final weight = _effectiveWeights[phase];
      if (weight != null) {
        completedWeight += weight;
      }
    }

    // 2. 获取当前阶段权重（使用有效权重）
    final currentWeight = _effectiveWeights[currentPhase] ?? 0.0;

    // 3. 限制阶段内进度最大为0.95
    final clampedStageProgress = stageProgress.clamp(0.0, 0.95);

    // 4. 计算总进度
    final totalProgress = completedWeight + (currentWeight * clampedStageProgress);

    return totalProgress.clamp(0.0, 1.0);
  }

  /// 获取有效权重（用于调试）
  Map<String, double> get effectiveWeights => Map.unmodifiable(_effectiveWeights);

  @override
  String toString() {
    final buffer = StringBuffer('RobustProgressCalculator(\n');
    buffer.writeln('  config: $_config');
    buffer.writeln('  effectiveWeights:');
    _effectiveWeights.forEach((phase, weight) {
      buffer.writeln('    $phase: ${(weight * 100).toStringAsFixed(1)}%');
    });
    buffer.write(')');
    return buffer.toString();
  }
}
```

**Step 2: 修改 AppInitializationService**

```dart
// app_initialization_service.dart

class AppInitializationService {
  // ... 现有字段 ...

  /// 进度计算器（根据配置动态创建）
  RobustProgressCalculator? _progressCalculator;

  Future<void> initializeFromScratch({InitializationConfig? config}) async {
    // 加载配置
    _config = config ?? await InitializationConfig.load();
    logger.i('[AppInitService] Starting full initialization with config: $_config');

    // 创建基于配置的进度计算器
    _progressCalculator = RobustProgressCalculator(config: _config);
    logger.d('[AppInitService] Progress calculator initialized:\n$_progressCalculator');

    try {
      // ... 其余代码保持不变 ...
    }
  }

  // 使用 _progressCalculator! 替代原来的 _progressCalculator
  void _reportProgress(double progress, InitializationStage? stage) {
    logger.d('[AppInitService] Progress: ${(progress * 100).toStringAsFixed(1)}%');
    onProgress?.call(progress, stage);
  }
}
```

#### 效果演示

**完整模式**（全部启用）:
```
P0:  15% (归一化后)
P1.1: 60% (归一化后)
P1.2: 15% (归一化后)
P2:  10% (归一化后)
进度: 0% → 15% → 75% → 90% → 100% ✅ 平滑
```

**禁用分类扫描**:
```
P0:  40% (归一化: 0.02/(0.02+0.20+0.10))
P1.2: 50% (归一化: 0.20/(0.02+0.20+0.10))
P2:  10% (归一化: 0.10/(0.02+0.20+0.10))
进度: 0% → 40% → 90% → 100% ✅ 平滑
```

**快速启动**（全部禁用）:
```
P0:  17% (归一化: 0.02/(0.02+0.10))
P2:  83% (归一化: 0.10/(0.02+0.10))
进度: 0% → 17% → 100% ✅ 平滑
```

---

### 方案2: 固定阶段比例（简单）⭐⭐⭐

**核心思路**: 不管启用多少阶段，始终按固定比例分配

#### 实现

```dart
class RobustProgressCalculator {
  final InitializationConfig? _config;

  /// 固定比例分配
  Map<String, double> _calculateFixedWeights() {
    final weights = <String, double>{};

    // P0: 10%
    weights['p0_init'] = 0.10;

    // P1: 80%（根据配置细分）
    if (_config?.enableP1CategoryScan ?? true) {
      if (_config?.enableP1AppScan ?? true) {
        // 两个都启用: 分类60% + 应用20%
        weights.addAll({
          'p1_images': 0.09, 'p1_video': 0.075, 'p1_music': 0.075,
          'p1_documents': 0.09, 'p1_downloads': 0.06, 'p1_apk': 0.06,
          'p1_archive': 0.06, 'p1_apps': 0.20,
        });
      } else {
        // 只启用分类: 占全部80%
        weights.addAll({
          'p1_images': 0.12, 'p1_video': 0.10, 'p1_music': 0.10,
          'p1_documents': 0.12, 'p1_downloads': 0.08, 'p1_apk': 0.08,
          'p1_archive': 0.08,
        });
      }
    } else if (_config?.enableP1AppScan ?? true) {
      // 只启用应用: 占全部80%
      weights['p1_apps'] = 0.80;
    }
    // 都不启用: P1占0%

    // P2: 10%
    weights['p2_folders'] = 0.10;

    return weights;
  }
}
```

**优点**:
- ✅ 实现简单
- ✅ 逻辑清晰

**缺点**:
- ⚠️ 需要为每种配置组合手写权重
- ⚠️ 不够灵活

---

### 方案3: 时间估算权重（精准）⭐⭐⭐⭐

**核心思路**: 根据实际耗时估算权重

#### 实现

```dart
class RobustProgressCalculator {
  /// 估算的阶段耗时（秒）
  static const Map<String, double> _estimatedDurations = {
    'p0_init': 2,        // 2秒
    'p1_images': 8,      // 8秒
    'p1_video': 7,       // 7秒
    'p1_music': 6,       // 6秒
    'p1_documents': 8,   // 8秒
    'p1_downloads': 5,   // 5秒
    'p1_apk': 5,         // 5秒
    'p1_archive': 5,     // 5秒
    'p1_apps': 20,       // 20秒
    'p2_folders': 5,     // 5秒
  };

  Map<String, double> _calculateTimeBasedWeights() {
    final durations = <String, double>{};

    // 收集启用阶段的耗时
    durations['p0_init'] = _estimatedDurations['p0_init']!;

    if (_config?.enableP1CategoryScan ?? true) {
      durations.addAll({
        'p1_images': _estimatedDurations['p1_images']!,
        'p1_video': _estimatedDurations['p1_video']!,
        'p1_music': _estimatedDurations['p1_music']!,
        'p1_documents': _estimatedDurations['p1_documents']!,
        'p1_downloads': _estimatedDurations['p1_downloads']!,
        'p1_apk': _estimatedDurations['p1_apk']!,
        'p1_archive': _estimatedDurations['p1_archive']!,
      });
    }

    if (_config?.enableP1AppScan ?? true) {
      durations['p1_apps'] = _estimatedDurations['p1_apps']!;
    }

    durations['p2_folders'] = _estimatedDurations['p2_folders']!;

    // 归一化为权重
    return _normalizeWeights(durations);
  }
}
```

**优点**:
- ✅ 最准确，反映实际耗时
- ✅ 进度条速度均匀

**缺点**:
- ⚠️ 需要实测耗时数据
- ⚠️ 不同设备差异大

---

## 📊 方案对比

| 方案 | 准确度 | 实现复杂度 | 维护成本 | 推荐度 |
|------|--------|----------|---------|--------|
| **方案1: 动态归一化** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| **方案2: 固定比例** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **方案3: 时间估算** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |

---

## 🎯 最终推荐

### 推荐方案: **动态归一化（方案1）**

**理由**:
1. ✅ 自动适应任何配置组合
2. ✅ 权重分配合理（基于原始设计）
3. ✅ 实现难度适中
4. ✅ 易于维护和扩展

### 实施步骤

#### Step 1: 修改 RobustProgressCalculator（核心）

添加配置参数和动态权重计算逻辑。

#### Step 2: 修改 AppInitializationService

在 `initializeFromScratch` 中传入配置创建进度计算器。

#### Step 3: 测试验证

```dart
// 测试代码
void testProgressCalculator() {
  // 完整模式
  final calc1 = RobustProgressCalculator(
    config: InitializationConfig.full(),
  );
  print('Full mode weights: ${calc1.effectiveWeights}');

  // 快速模式
  final calc2 = RobustProgressCalculator(
    config: InitializationConfig.quickStart(),
  );
  print('Quick mode weights: ${calc2.effectiveWeights}');

  // 自定义模式
  final calc3 = RobustProgressCalculator(
    config: InitializationConfig(
      enableP1CategoryScan: false,
      enableP1AppScan: true,
    ),
  );
  print('Custom mode weights: ${calc3.effectiveWeights}');
}
```

---

## 📝 关键要点

### 1. 权重归一化公式

```
归一化权重 = 原始权重 / 有效权重总和

示例（快速模式）:
原始: P0=0.02, P2=0.10, 总和=0.12
归一化: P0=0.02/0.12≈0.17, P2=0.10/0.12≈0.83
```

### 2. 向后兼容

如果不传 config 参数，默认使用完整模式：
```dart
RobustProgressCalculator({InitializationConfig? config})
    : _config = config ?? InitializationConfig.full();
```

### 3. 调试支持

添加 `toString()` 方法，方便查看当前权重分配：
```dart
logger.d('[AppInitService] Progress calculator:\n$_progressCalculator');
```

输出示例：
```
RobustProgressCalculator(
  config: InitializationConfig(P0: ✓, P1.1: ✗, P1.2: ✓, P2: ✓, quickMode: ✗)
  effectiveWeights:
    p0_init: 6.3%
    p1_apps: 62.5%
    p2_folders: 31.3%
)
```

---

## 🚀 完整实现代码

详见下一个文件：`PROGRESS_WEIGHT_IMPLEMENTATION.md`
