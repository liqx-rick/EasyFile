# 三屏新功能埋点方案

**版本**: v1.0
**日期**: 2026-03-11
**适用功能**: Hash校验、文件夹大小计算、文件类型识别、二维码工具
**基于文档**: ANALYTICS_IMPLEMENTATION_FINAL.md

---

## 一、现有埋点总结

### 1.1 已实现事件（14个）

| 工具 | 事件数 | 事件列表 |
|------|--------|---------|
| Hash校验 | 3 | `hash_checker_enter`, `hash_calculate_finish`, `hash_copy` |
| 文件夹大小 | 2 | `folder_size_calculator_enter`, `folder_size_calculate_finish` |
| 文件类型识别 | 2 | `file_type_detector_enter`, `file_type_detect_finish` |
| 二维码工具 | 7 | `qr_code_tool_enter`, `qr_code_generate`, `qr_code_save`, `qr_code_scan`, `qr_code_scan_from_image`, `qr_code_copy_scan_result`, `qr_code_open_url` |

### 1.2 参数设计

**Hash校验**:
```dart
// 计算完成
{
  'file_size_bytes': 10485760,  // 文件大小
  'duration_ms': 2345           // 计算耗时
}

// 复制哈希
{
  'hash_type': 'MD5'  // MD5/SHA1/SHA256
}
```

**文件夹大小**:
```dart
{
  'folder_size_bytes': 524288000,  // 文件夹大小
  'file_count': 1234,              // 文件数量
  'duration_ms': 3456              // 计算耗时
}
```

**文件类型识别**:
```dart
{
  'file_count': 5  // 识别文件数量
}
```

**二维码工具**:
```dart
// 生成/扫描
{
  'content_length': 128  // 内容长度
}
```

---

## 二、建议补充埋点

### 2.1 核心增强埋点（P0 - 必须实现）

#### A. Hash校验工具

**新增事件**:
```dart
/// 1. 选择Hash算法
static Future<void> logHashAlgorithmSelect(String algorithm) async {
  await AnalyticsManager.log('hash_algorithm_select', params: {
    'algorithm': algorithm  // MD5/SHA1/SHA256
  });
}

/// 2. Hash计算失败
static Future<void> logHashCalculateFail({
  required String errorType,  // permission_denied/file_not_found/io_error
  required int fileSizeBytes,
}) async {
  await AnalyticsManager.log('hash_calculate_fail', params: {
    'error_type': errorType,
    'file_size_bytes': fileSizeBytes,
  });
}

/// 3. Hash对比功能使用（如果后续添加）
static Future<void> logHashCompare({
  required String algorithm,
  required bool isMatch,
}) async {
  await AnalyticsManager.log('hash_compare', params: {
    'algorithm': algorithm,
    'is_match': isMatch,
  });
}
```

**埋点位置**:
- 用户切换算法选项时 → `logHashAlgorithmSelect`
- 计算失败时（catch块） → `logHashCalculateFail`

---

#### B. 文件夹大小计算

**新增事件**:
```dart
/// 1. 文件夹选择失败
static Future<void> logFolderSelectFail(String reason) async {
  await AnalyticsManager.log('folder_select_fail', params: {
    'reason': reason  // permission_denied/user_cancel
  });
}

/// 2. 计算失败
static Future<void> logFolderSizeCalculateFail({
  required String errorType,  // permission_denied/path_not_found
  required int scannedFiles,  // 已扫描文件数
}) async {
  await AnalyticsManager.log('folder_size_calculate_fail', params: {
    'error_type': errorType,
    'scanned_files': scannedFiles,
  });
}

/// 3. 超大文件夹计算
static Future<void> logLargeFolderCalculate({
  required int fileCount,
  required int folderSizeGb,  // 超过1GB的文件夹
}) async {
  await AnalyticsManager.log('large_folder_calculate', params: {
    'file_count': fileCount,
    'folder_size_gb': folderSizeGb,
  });
}
```

**埋点位置**:
- 文件夹选择器返回null → `logFolderSelectFail`
- 计算过程中异常 → `logFolderSizeCalculateFail`
- 计算完成且超过1GB → `logLargeFolderCalculate`

---

#### C. 文件类型识别器

**新增事件**:
```dart
/// 1. 扩展名不匹配检出
static Future<void> logFileTypeMismatchDetected({
  required int mismatchCount,  // 不匹配数量
  required int totalCount,     // 总文件数
}) async {
  await AnalyticsManager.log('file_type_mismatch_detected', params: {
    'mismatch_count': mismatchCount,
    'total_count': totalCount,
    'mismatch_rate': (mismatchCount / totalCount * 100).toStringAsFixed(2),
  });
}

/// 2. 特定文件类型分布
static Future<void> logFileTypeDistribution({
  required Map<String, int> typeCountMap,  // {'ZIP': 3, 'DOCX': 2}
}) async {
  await AnalyticsManager.log('file_type_distribution', params: typeCountMap);
}

/// 3. 识别失败
static Future<void> logFileTypeDetectFail({
  required int failedCount,
  required String errorType,
}) async {
  await AnalyticsManager.log('file_type_detect_fail', params: {
    'failed_count': failedCount,
    'error_type': errorType,
  });
}
```

**埋点位置**:
- 识别完成后，统计不匹配数量 → `logFileTypeMismatchDetected`
- 识别完成后，统计类型分布 → `logFileTypeDistribution`
- 识别过程异常 → `logFileTypeDetectFail`

---

#### D. 二维码工具

**新增事件**:
```dart
/// 1. Tab切换
static Future<void> logQrCodeTabSwitch(String tabName) async {
  await AnalyticsManager.log('qr_code_tab_switch', params: {
    'tab_name': tabName  // generate/scan
  });
}

/// 2. 生成失败
static Future<void> logQrCodeGenerateFail(String reason) async {
  await AnalyticsManager.log('qr_code_generate_fail', params: {
    'reason': reason  // empty_content/invalid_data
  });
}

/// 3. 保存失败
static Future<void> logQrCodeSaveFail(String errorType) async {
  await AnalyticsManager.log('qr_code_save_fail', params: {
    'error_type': errorType  // permission_denied/io_error
  });
}

/// 4. 扫描失败
static Future<void> logQrCodeScanFail({
  required String scanSource,  // camera/image
  required String errorType,   // no_qr_found/camera_denied/invalid_image
}) async {
  await AnalyticsManager.log('qr_code_scan_fail', params: {
    'scan_source': scanSource,
    'error_type': errorType,
  });
}

/// 5. 内容类型识别
static Future<void> logQrCodeContentType(String contentType) async {
  await AnalyticsManager.log('qr_code_content_type', params: {
    'content_type': contentType  // url/text/wifi/contact
  });
}

/// 6. 扫描成功率统计
static Future<void> logQrCodeScanSuccess({
  required String scanSource,
  required int attemptCount,  // 第几次尝试成功
}) async {
  await AnalyticsManager.log('qr_code_scan_success', params: {
    'scan_source': scanSource,
    'attempt_count': attemptCount,
  });
}
```

**埋点位置**:
- TabController切换 → `logQrCodeTabSwitch`
- 生成/保存/扫描失败 → 对应的fail事件
- 扫描成功后分析内容类型 → `logQrCodeContentType`

---

### 2.2 用户体验埋点（P1 - 建议实现）

#### E. 性能监控

```dart
/// 1. 页面加载耗时
static Future<void> logPageLoadDuration({
  required String pageName,
  required int durationMs,
}) async {
  await AnalyticsManager.log('page_load_duration', params: {
    'page_name': pageName,
    'duration_ms': durationMs,
  });
}

/// 2. 用户停留时长
static Future<void> logPageStayDuration({
  required String pageName,
  required int durationSec,
}) async {
  await AnalyticsManager.log('page_stay_duration', params: {
    'page_name': pageName,
    'duration_sec': durationSec,
  });
}
```

#### F. 功能发现路径

```dart
/// 工具页面入口点击
static Future<void> logToolEntryClick({
  required String toolName,
  required String entrySource,  // tools_page/search/quick_access
}) async {
  await AnalyticsManager.log('tool_entry_click', params: {
    'tool_name': toolName,
    'entry_source': entrySource,
  });
}
```

---

### 2.3 高级分析埋点（P2 - 可选）

#### G. 用户行为路径

```dart
/// 功能组合使用
static Future<void> logToolCombinationUsage({
  required List<String> toolSequence,  // ['hash_checker', 'qr_code_tool']
  required int sessionDurationMin,
}) async {
  await AnalyticsManager.log('tool_combination_usage', params: {
    'tool_sequence': toolSequence.join(' -> '),
    'session_duration_min': sessionDurationMin,
  });
}
```

---

## 三、数据分析维度

### 3.1 功能使用分析

**关键指标**:
- **DAU/MAU**: 各工具的日活/月活用户数
- **使用频次**: 每个工具的日均使用次数
- **留存率**: 首次使用后7日/30日留存
- **功能渗透率**: 各工具在总用户中的使用占比

**分析方法**:
```sql
-- Umeng后台自定义事件分析
-- 事件: hash_checker_enter, folder_size_calculator_enter, etc.
-- 维度: 日期、用户ID、渠道、设备型号
```

### 3.2 性能分析

| 指标 | 事件 | 阈值 |
|------|------|------|
| Hash计算时长 | `hash_calculate_finish.duration_ms` | >5秒标记为慢 |
| 文件夹扫描时长 | `folder_size_calculate_finish.duration_ms` | >10秒标记为慢 |
| 二维码生成时长 | `qr_code_generate.duration_ms` | >1秒标记为慢 |
| 二维码扫描成功率 | `qr_code_scan_success` / `qr_code_scan_fail` | <80%需优化 |

### 3.3 错误率监控

**关键错误事件**:
- `hash_calculate_fail` - Hash计算失败率
- `folder_select_fail` - 文件夹选择失败率
- `file_type_detect_fail` - 文件识别失败率
- `qr_code_scan_fail` - 二维码扫描失败率
- `qr_code_save_fail` - 二维码保存失败率

**告警规则**:
```yaml
alerts:
  - event: hash_calculate_fail
    condition: error_rate > 5%
    action: 通知开发团队

  - event: qr_code_scan_fail
    condition:
      error_type: camera_denied
      count > 100/day
    action: 优化权限引导流程
```

### 3.4 用户画像

**分析维度**:
- **功能偏好**: 最常用的工具排序
- **使用时段**: 工具使用的高峰时段
- **使用场景**: 单一工具 vs 组合使用
- **设备特征**: Android版本、设备型号对功能使用的影响

---

## 四、实施计划

### 4.1 第一阶段（P0 - 本周完成）

**任务**:
1. ✅ 核心埋点已实现（14个事件）
2. 🔄 添加补充埋点（8个高优事件）:
   - `hash_calculate_fail`
   - `folder_select_fail`
   - `folder_size_calculate_fail`
   - `file_type_mismatch_detected`
   - `qr_code_tab_switch`
   - `qr_code_generate_fail`
   - `qr_code_scan_fail`
   - `qr_code_content_type`

**代码修改**:
```dart
// lib/analytics/analytics_helper.dart
// 在现有Hash相关方法后添加：

/// Hash计算失败
static Future<void> logHashCalculateFail({
  required String errorType,
  required int fileSizeBytes,
}) async {
  await AnalyticsManager.log('hash_calculate_fail', params: {
    'error_type': errorType,
    'file_size_bytes': fileSizeBytes,
  });
}

// ... 其他补充方法
```

### 4.2 第二阶段（P1 - 下周完成）

**任务**:
1. 添加性能监控埋点
2. 添加功能发现路径埋点
3. 配置Umeng后台仪表盘

**Umeng配置**:
- 创建自定义事件分组: "实用小工具"
- 设置关键事件监控
- 配置错误率告警

### 4.3 第三阶段（P2 - 迭代优化）

**任务**:
1. 添加高级分析埋点
2. 基于第一周数据优化埋点策略
3. 补充遗漏场景

---

## 五、验证方法

### 5.1 本地测试

**Android logcat 监控**:
```bash
adb logcat -s UmengAnalyticsChannel:D | grep -E "hash_|folder_|file_type_|qr_code_"
```

**测试用例**:
```
【Hash校验】
1. 进入页面 → 看到 hash_checker_enter
2. 选择文件并计算 → 看到 hash_calculate_finish (含duration_ms)
3. 复制MD5值 → 看到 hash_copy (hash_type=MD5)
4. 尝试无权限文件 → 看到 hash_calculate_fail (error_type=permission_denied)

【文件夹大小】
1. 进入页面 → 看到 folder_size_calculator_enter
2. 选择Download文件夹 → 看到 folder_size_calculate_finish
3. 取消选择 → 看到 folder_select_fail (reason=user_cancel)

【文件类型识别】
1. 进入页面 → 看到 file_type_detector_enter
2. 选择5个文件 → 看到 file_type_detect_finish (file_count=5)
3. 结果有2个不匹配 → 看到 file_type_mismatch_detected (mismatch_count=2)

【二维码工具】
1. 进入页面 → 看到 qr_code_tool_enter
2. 点击生成Tab → 看到 qr_code_tab_switch (tab_name=generate)
3. 输入URL生成 → 看到 qr_code_generate, qr_code_content_type (content_type=url)
4. 保存二维码 → 看到 qr_code_save
5. 点击扫描Tab → 看到 qr_code_tab_switch (tab_name=scan)
6. 扫描成功 → 看到 qr_code_scan
7. 从相册选择 → 看到 qr_code_scan_from_image
8. 复制结果 → 看到 qr_code_copy_scan_result
9. 打开链接 → 看到 qr_code_open_url
```

### 5.2 Umeng后台验证

**检查清单**:
- [ ] 24小时内看到所有14个核心事件至少1次
- [ ] 事件参数正确传递（查看事件详情）
- [ ] 用户去重正确（DAU计数准确）
- [ ] 渠道归因正确（多渠道包测试）

**数据延迟**: Umeng实时数据约15分钟延迟，完整报表T+1

---

## 六、关键指标Dashboard

### 6.1 实用小工具总览

**核心指标**:
- 总UV: 使用过任一工具的独立用户数
- 总PV: 所有工具的总使用次数
- 人均使用次数: PV/UV
- 最受欢迎工具: 按 `*_enter` 事件排序

### 6.2 各工具健康度

| 工具 | 使用率 | 成功率 | 平均耗时 | 错误率 |
|------|--------|--------|----------|--------|
| Hash校验 | `hash_checker_enter` / DAU | `hash_calculate_finish` / `hash_checker_enter` | AVG(duration_ms) | `hash_calculate_fail` / total |
| 文件夹大小 | `folder_size_calculator_enter` / DAU | `folder_size_calculate_finish` / `folder_size_calculator_enter` | AVG(duration_ms) | `folder_size_calculate_fail` / total |
| 文件类型识别 | `file_type_detector_enter` / DAU | `file_type_detect_finish` / `file_type_detector_enter` | - | `file_type_detect_fail` / total |
| 二维码工具 | `qr_code_tool_enter` / DAU | (`qr_code_scan_success` + `qr_code_generate`) / `qr_code_tool_enter` | - | (`qr_code_scan_fail` + `qr_code_generate_fail`) / total |

### 6.3 用户行为漏斗

**Hash校验漏斗**:
```
进入页面 (hash_checker_enter) 100%
  ↓
选择文件并计算 (hash_calculate_finish) ?%
  ↓
复制哈希值 (hash_copy) ?%
```

**二维码工具漏斗**:
```
进入页面 (qr_code_tool_enter) 100%
  ├─ 生成分支:
  │   生成二维码 (qr_code_generate) ?%
  │     ↓
  │   保存二维码 (qr_code_save) ?%
  │
  └─ 扫描分支:
      扫描成功 (qr_code_scan / qr_code_scan_from_image) ?%
        ↓
      复制结果 (qr_code_copy_scan_result) ?%
        ↓
      打开链接 (qr_code_open_url) ?%
```

---

## 七、优化建议

### 7.1 基于数据的优化方向

**如果发现**:
- Hash计算耗时 >10秒 → 考虑异步分块计算
- 文件夹选择失败率 >20% → 优化权限引导
- 二维码扫描失败率 >30% → 优化相机参数/增加提示
- 文件类型不匹配率 >50% → 说明功能价值高，可深化

### 7.2 A/B测试建议

**测试场景**:
- 工具卡片排序: Hash在前 vs 二维码在前
- 二维码扫描框样式: 方形 vs 圆角矩形
- 文件夹大小显示格式: MB vs GB自适应

---

## 八、总结

### 8.1 当前状态
- ✅ 核心埋点已全部实现（14个事件）
- ✅ 符合友盟三步初始化规范
- ✅ 参数设计合理，可扩展性强

### 8.2 待补充
- 🔄 错误埋点（4个fail事件）
- 🔄 内容分析埋点（content_type等）
- 🔄 Tab切换埋点

### 8.3 预期收益
- **用户洞察**: 了解哪些工具最受欢迎
- **性能优化**: 基于耗时数据优化算法
- **错误定位**: 快速发现和修复问题
- **产品迭代**: 数据驱动功能优先级

---

**文档维护**: 本方案基于代码实现和友盟最佳实践编写，如有变更请同步更新。

**联系人**: 开发团队
**审核**: 产品经理、数据分析师
