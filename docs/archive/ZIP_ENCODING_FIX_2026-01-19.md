# ZIP解压乱码问题修复报告

## 问题描述

用户报告：解压 `/storage/emulated/0/Download/WeiXin/高考口语在线体验系统客户端-考生.zip` 后，解压目录中文件名出现乱码。

**症状**：
- 预期文件名：`3【高考口语在线体验系统客户端-考生/2026年普通高考口语模拟练习系统_用高考技术.exe`
- 实际文件名：`3���߿�������������ϵͳ�ͻ���-����/2026���������ͨ�߿����������������������ģ����ϰϵͳ_���߿�����.exe`

## 问题根因

### 日志分析

从 consolelog.txt Line 126-164 可以看到：

```
I/MinizipWrapper: 开始列出ZIP内容
D/MinizipWrapper: 原始文件名字节 (前20字节):
  [0] = 0x33 (3)
  [1] = 0xA1 (·)   ← GBK编码的"【"
  [2] = 0xA2 (·)
  [3] = 0xB8 (·)   ← GBK编码的"高"
  ...
D/MinizipWrapper: 条目 0: 3���߿�������... (乱码)
```

**原始字节 `0xA1 0xA2` 是 GBK 编码的"【"，但被当作 UTF-8 解析导致乱码。**

### 代码回归分析

之前我们已经实现过 charset_converter 来解决这个问题，但在**最近的代码重构中丢失了编码转换逻辑**。

#### 旧代码（正确）：
```dart
// 之前的实现（已丢失）
final gbkDecoded = await CharsetConverter.decode("GBK", entry.rawPathname);
final decodedName = gbkDecoded ?? entry.name;
```

#### 新代码（问题代码）：
```dart
// archive_service.dart Line 768-773
final entries = result.entries.map((entry) {
  return ArchiveEntryInfo(
    name: entry.name,        // ❌ 直接使用乱码字符串
    path: entry.pathname,    // ❌ 直接使用乱码字符串
    rawPathname: entry.rawPathname,  // ✅ 保留了原始GBK字节，但未使用
```

### 根本原因

在 `_listZipContents` 方法中：
1. minizip-ng 读取到 GBK 编码的原始字节（`rawPathname`）
2. minizip 尝试用 UTF-8 解码，失败后生成乱码字符串（`entry.name`）
3. **代码直接使用乱码字符串**，而不是进行 GBK → UTF-8 转换
4. 解压时使用乱码路径创建文件，导致文件系统中出现乱码文件名

## 解决方案

### 修复代码

**文件**：`lib/core/services/archive_service.dart`

**修改 1**：添加 charset_converter 导入
```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:charset_converter/charset_converter.dart';  // ✅ 新增
```

**修改 2**：在 `_listZipContents` 中添加编码转换逻辑

```dart
// Line 758-804 (替换原有代码)
if (result.success) {
  logger.i('minizip 读取成功: ${result.entries.length} 个条目');

  // 转换为 ArchiveEntryInfo 列表，并进行编码转换
  final entries = await Future.wait(result.entries.map((entry) async {
    // 尝试将 GBK 编码转换为 UTF-8
    String decodedName = entry.name;
    String decodedPath = entry.pathname;
    
    if (entry.rawPathname != null && entry.rawPathname!.isNotEmpty) {
      try {
        // 检测是否包含中文乱码（0x80-0xFF范围的字节）
        final hasNonAscii = entry.rawPathname!.any((b) => b > 0x7F);
        
        if (hasNonAscii) {
          // 尝试使用 GBK 解码
          final gbkDecoded = await CharsetConverter.decode(
            "GBK",
            Uint8List.fromList(entry.rawPathname!),
          );
          
          if (gbkDecoded != null && gbkDecoded.isNotEmpty) {
            decodedName = gbkDecoded.split('/').last;
            decodedPath = gbkDecoded;
            logger.d('GBK -> UTF-8: ${entry.name} -> $decodedPath');
          }
        }
      } catch (e) {
        logger.w('编码转换失败，使用原始名称: $e');
      }
    }
    
    return ArchiveEntryInfo(
      name: decodedName,      // ✅ 使用转换后的UTF-8字符串
      path: decodedPath,      // ✅ 使用转换后的UTF-8字符串
      rawPathname: entry.rawPathname,  // 保存原始字节用于提取
      // ... 其他字段
    );
  }));

  return ArchiveListResult(entries: entries, errorMessage: null);
}
```

### 工作原理

1. **检测非ASCII字符**：
   - 检查 `rawPathname` 是否包含 `> 0x7F` 的字节
   - 如果有，说明可能是 GBK 编码

2. **GBK 解码**：
   - 使用 `CharsetConverter.decode("GBK", bytes)` 将 GBK 字节转换为 UTF-8 字符串
   - 成功后使用转换结果，失败则回退到原始名称

3. **保留原始字节**：
   - `rawPathname` 仍保存在 `ArchiveEntryInfo` 中
   - 用于 `_extractZipFile` 中的 `extractSingleFile()` 调用

4. **异步处理**：
   - 使用 `Future.wait()` 并发处理所有条目的编码转换
   - 提高性能，避免阻塞

### 技术细节

**GBK 编码示例**：
| 字符 | GBK 字节 | UTF-8 字节 |
|------|----------|------------|
| 【 | 0xA1 0xA2 | 0xE3 0x80 0x90 |
| 高 | 0xB8 0xDF | 0xE9 0xAB 0x98 |
| 考 | 0xBF 0xBC | 0xE8 0x80 0x83 |

**乱码原因**：
- GBK 两字节编码（`0xA1 0xA2`）被当作 UTF-8 单字节解析
- UTF-8 解析器遇到无效字节，生成替换字符（`�`）

**修复效果**：
- GBK 字节 `0x33 0xA1 0xA2 0xB8 0xDF...`
- 正确解码为：`3【高考口语...`

## 测试验证

### 测试场景 1：中文文件名ZIP
1. 解压 `高考口语在线体验系统客户端-考生.zip`
2. **验证**：文件名正确显示中文，无乱码

### 测试场景 2：英文文件名ZIP
1. 解压纯英文文件名的ZIP
2. **验证**：跳过编码转换（hasNonAscii = false），直接使用原始名称

### 测试场景 3：混合编码ZIP
1. 解压包含中英文混合文件名的ZIP
2. **验证**：中文部分正确解码，英文部分保持不变

## 预期日志输出

**修复前**：
```
D/MinizipWrapper: 条目 0: 3���߿�������������ϵͳ�ͻ���-����/ (乱码)
```

**修复后**：
```
D/MinizipWrapper: 条目 0: 3���߿�������������ϵͳ�ͻ���-����/ (原始乱码)
I/flutter: GBK -> UTF-8: 3���... -> 3【高考口语在线体验系统客户端-考生/
I/flutter: 解压文件: 3【高考口语在线体验系统客户端-考生/2026年普通高考口语模拟练习系统.exe
```

## 防止回归

### 代码审查检查点
- ✅ 所有使用 minizip-ng 的地方都要进行编码转换
- ✅ 使用 `rawPathname`（原始字节）而非 `name`（乱码字符串）
- ✅ 保留 charset_converter 依赖

### 单元测试（待添加）
```dart
test('GBK编码的ZIP文件名应正确解码', () async {
  final archivePath = 'test_data/chinese_filename.zip';
  final result = await archiveService.listArchiveContents(archivePath);
  
  expect(result.entries[0].name, equals('中文文件名.txt'));
  expect(result.entries[0].name, isNot(contains('�')));
});
```

## 相关文件

- ✅ **已修复**：`lib/core/services/archive_service.dart`
- ⚠️ **依赖**：`pubspec.yaml` 中的 `charset_converter: ^2.1.1`
- 📝 **日志**：`docs/consolelog.txt` (Line 126-214)

## 修复日期
2026-01-19

## 修复人员
GitHub Copilot (Claude Sonnet 4.5)

---

## 附录：为什么问题会"回来"？

这是一个典型的**代码回归（Regression）**案例：

1. **第一次修复**（之前）：
   - 实现了 charset_converter 编码转换
   - 测试通过，问题解决

2. **重构导致丢失**（最近）：
   - 重构 archive_service 以支持多种格式（RAR/ZIP/7z）
   - 为了统一接口，重写了 `_listZipContents`
   - **忘记保留编码转换逻辑**

3. **根本原因**：
   - ❌ 缺少单元测试覆盖此功能
   - ❌ 代码审查时未注意到编码转换逻辑丢失
   - ❌ 重构时未参考原有实现

4. **预防措施**：
   - ✅ 添加单元测试（带GBK编码的ZIP样本文件）
   - ✅ 代码审查清单：检查字符编码处理
   - ✅ 本文档作为知识库，供未来参考
