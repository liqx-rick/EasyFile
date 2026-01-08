# 智能算法配置使用指南

## 📋 概述

本文档说明如何使用和调整 EasyFile 中的智能算法配置参数，这些参数已被纳入统一配置管理系统，支持动态调整和远程配置下发。

---

## 🎯 推荐算法配置

### 配置位置
`lib/core/config/duplicate_files_recommendation_config.dart`

### 主要参数

#### 1. 时间衰减因子 (Time Decay Score Per Day)

**默认值**: 5分/天  
**作用**: 控制文件修改时间对推荐结果的影响程度

```dart
// 获取当前值
final decayScore = AppConfig.instance.duplicateFilesRec.timeDecayScorePerDay;

// 修改值（需要在1-20范围内）
await AppConfig.instance.duplicateFilesRec.setTimeDecayScorePerDay(10);
```

**使用场景**:
- **激进策略**: 设置为 10-15，快速淘汰旧文件
- **保守策略**: 设置为 2-3，重视历史文件
- **默认策略**: 5分/天，平衡新旧文件

#### 2. 大小相似度阈值 (Size Similarity Threshold)

**默认值**: 1024字节 (1KB)  
**作用**: 小于此差异认为文件大小相同，不参与评分

```dart
// 获取当前值
final threshold = AppConfig.instance.duplicateFilesRec.sizeSimilarityThreshold;

// 修改值
await AppConfig.instance.duplicateFilesRec.setSizeSimilarityThreshold(2048);
```

**调优建议**:
- 小文件场景: 512字节或更小
- 大文件场景: 10KB 或更大

#### 3. 时间相似度阈值 (Time Similarity Threshold)

**默认值**: 3600秒 (1小时)  
**作用**: 小于此差异认为修改时间相同，不参与评分

```dart
// 获取当前值
final threshold = AppConfig.instance.duplicateFilesRec.timeSimilarityThreshold;

// 修改值（设置为3小时）
await AppConfig.instance.duplicateFilesRec.setTimeSimilarityThreshold(3600 * 3);
```

#### 4. 路径深度阈值 (Path Depth Threshold)

**默认值**: 9层  
**作用**: 超过此深度认为路径过深，扣除分数

```dart
// 获取当前值
final depth = AppConfig.instance.duplicateFilesRec.pathDepthThreshold;

// 修改值
await AppConfig.instance.duplicateFilesRec.setPathDepthThreshold(12);
```

---

## 🔧 性能优化配置

### 配置位置
`lib/core/config/file_scan_config.dart`

### 主要参数

#### 1. 垃圾文件扫描深度

**作用**: 控制不同目录类型的扫描深度，平衡性能和覆盖范围

```dart
final config = AppConfig.instance.fileScan;

// 普通目录深度（默认：10层）
final defaultDepth = config.junkScanDepthDefault;

// 应用数据目录深度（默认：3层，浅扫描）
final appDataDepth = config.junkScanDepthAppData;

// 媒体目录深度（默认：5层，中等深度）
final mediaDepth = config.junkScanDepthMedia;
```

**调优策略**:

```dart
// 低端设备：减少扫描深度
await storage.setInt('scan_junk_scan_depth_default', 6);
await storage.setInt('scan_junk_scan_depth_app_data', 2);

// 高端设备：增加扫描深度
await storage.setInt('scan_junk_scan_depth_default', 15);
await storage.setInt('scan_junk_scan_depth_app_data', 5);
```

#### 2. 智能缓存大小限制

**默认值**: 50MB  
**作用**: 控制重复文件扫描缓存的最大大小

```dart
final maxSizeMB = AppConfig.instance.fileScan.smartCacheMaxSizeMB;
final maxSizeBytes = AppConfig.instance.fileScan.smartCacheMaxSizeBytes;
```

**设置方法**:
```dart
// 通过存储层直接设置（目前暂无专用API）
await storage.setInt('scan_smart_cache_max_size_mb', 100);
```

---

## 🧪 A/B 测试示例

### 场景1: 测试不同的推荐策略

```dart
// 策略A：激进推荐（快速淘汰旧文件）
await AppConfig.instance.duplicateFilesRec.setTimeDecayScorePerDay(10);
await AppConfig.instance.duplicateFilesRec.setSizeSimilarityThreshold(10240);

// 策略B：保守推荐（重视历史文件）
await AppConfig.instance.duplicateFilesRec.setTimeDecayScorePerDay(2);
await AppConfig.instance.duplicateFilesRec.setSizeSimilarityThreshold(512);
```

### 场景2: 设备性能优化

```dart
// 低端设备配置
final lowEndConfig = {
  'junk_scan_depth_default': 6,
  'junk_scan_depth_app_data': 2,
  'smart_cache_max_size_mb': 25,
};
await AppConfig.instance.fileScan.mergeWith(lowEndConfig);

// 高端设备配置
final highEndConfig = {
  'junk_scan_depth_default': 15,
  'junk_scan_depth_app_data': 5,
  'smart_cache_max_size_mb': 100,
};
await AppConfig.instance.fileScan.mergeWith(highEndConfig);
```

---

## 🚨 紧急配置下发

### 场景: 用户反馈扫描太慢

```dart
// 快速止血：降低所有扫描深度
final emergencyConfig = {
  'junk_scan_depth_default': 5,
  'junk_scan_depth_app_data': 2,
  'junk_scan_depth_media': 3,
  'large_file_scan_timeout': 30,
};

await AppConfig.instance.fileScan.mergeWith(emergencyConfig);
```

---

## 📊 配置监控建议

### 关键指标

1. **推荐准确率**: 用户是否接受推荐的删除建议
2. **扫描性能**: 扫描耗时是否在可接受范围
3. **缓存命中率**: 智能缓存的有效性
4. **用户满意度**: 通过反馈收集

### 监控代码示例

```dart
// 记录配置使用情况
logger.i('Current algorithm config:');
logger.i('  Time decay: ${config.timeDecayScorePerDay} per day');
logger.i('  Size threshold: ${config.sizeSimilarityThreshold} bytes');
logger.i('  Scan depth (default): ${config.junkScanDepthDefault}');
logger.i('  Cache size limit: ${config.smartCacheMaxSizeMB} MB');
```

---

## 🔄 配置重置

### 重置所有配置为默认值

```dart
// 重置推荐算法配置
await AppConfig.instance.duplicateFilesRec.reset();

// 重置扫描配置
await AppConfig.instance.fileScan.reset();

// 重置所有配置
await AppConfig.instance.resetToDefaults();
```

---

## 💡 最佳实践

1. **渐进式调整**: 每次只调整一个参数，观察效果
2. **灰度发布**: 先在小部分用户中测试新配置
3. **保留回退方案**: 记录原始配置，出问题时快速回退
4. **数据驱动**: 基于真实数据和用户反馈做决策
5. **文档同步**: 每次修改配置时更新文档

---

## 📞 技术支持

如遇配置相关问题，请查看：
- [配置系统设计文档](./CONFIG_MANAGEMENT_SYSTEM_DESIGN.md)
- [推荐算法技术文档](./DUPLICATE_FILE_RECOMMENDATION_ALGORITHM.md)
- 单元测试: `test/core/config/duplicate_files_recommendation_config_test.dart`

---

**最后更新**: 2026-01-08  
**版本**: v1.0.0
