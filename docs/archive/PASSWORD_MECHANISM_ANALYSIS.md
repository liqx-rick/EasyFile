# 【模版E】加密压缩包密码机制分析报告

## 📋 执行摘要

**分析目标**：RAR、ZIP 加密压缩包的密码输入机制，评估是否可推广到其他格式（7z、tar.gz 等）

**核心发现**：
- ✅ RAR/ZIP 已有完整的密码处理机制
- ⚠️ 7z/tar 等格式**技术上支持**密码，但未实现密码传递
- 🔧 **可以统一**：所有格式采用相同的密码输入流程

**推荐方案**：扩展现有机制到 libarchive 格式，实现统一密码处理

---

## 1️⃣ 现状分析 - 已实现的密码机制

### 1.1 RAR 格式密码处理

#### 架构流程
```
用户点击解压
  ↓
ExtractionProgressDialog._startExtraction()
  ↓
ArchiveService.extractToInBackground()
  ↓ (Isolate)
_extractInIsolate() → UnrarFFI.extract(password)
  ↓
解压失败 → status=22 (ERAR_MISSING_PASSWORD)
  ↓ (返回主线程)
检测错误消息包含 "password" / "密码"
  ↓
显示 PasswordInputDialog
  ↓
用户输入密码 → 重试（最多3次）
```

#### 关键代码位置

**1. UnRAR 密码传递**：
```dart
// lib/core/services/archive_service.dart: Line 291
final result = unrar.extract(
  params.archivePath,
  fullPath,
  password: params.password,  // ✅ 支持密码参数
);
```

**2. 错误检测**：
```dart
// Line 318
if (result.status == 22) {  // ERAR_MISSING_PASSWORD
  errorMsg = params.password == null || params.password!.isEmpty
      ? '压缩包需要密码'
      : '密码错误或压缩包已损坏';
}
```

**3. 密码输入对话框**：
```dart
// lib/ui/dialogs/extraction_progress_dialog.dart: Line 208-217
password = await showDialog<String>(
  context: context,
  builder: (context) => PasswordInputDialog(
    remainingAttempts: maxAttempts - attempts,
  ),
);
```

**4. 重试机制**：
```dart
// Line 121-148
while (attempts < maxAttempts && needRetry) {
  // 解压尝试
  if (!result.success && _needsPassword(result.errorMessage)) {
    attempts++;
    password = await showDialog<String>(...);
  }
}
```

### 1.2 ZIP 格式密码处理

#### 架构流程
```
用户点击解压
  ↓
ExtractionProgressDialog._startExtraction()
  ↓
ArchiveService.extractToInBackground()
  ↓ (检测到 ZIP → 直接主线程执行)
extractTo() → _extractZipFile()
  ↓
_listZipContents() → 获取文件列表（编码转换）
  ↓
逐个文件提取
MinizipFFI.extractSingleFile(password)
  ↓
失败 → errorMessage 包含 "password" / "encrypted"
  ↓
显示 PasswordInputDialog（同 RAR）
  ↓
用户输入密码 → 重试
```

#### 关键代码位置

**1. Minizip 密码传递**：
```dart
// lib/core/services/archive_service.dart: Line 546
final result = _minizip.extractSingleFile(
  archivePath,
  entry.rawPathname!,
  outputPath,
  password: password,  // ✅ 支持密码参数
);
```

**2. 错误检测**：
```dart
// Line 568-572
if (extractedFiles == 0 && totalFiles > 0) {
  String errorMsg = password == null || password.isEmpty 
      ? '压缩包需要密码' 
      : '密码错误或文件损坏';
}
```

### 1.3 密码输入 UI 组件

#### PasswordInputDialog 特性
```dart
// lib/ui/widgets/password_input_dialog.dart
class PasswordInputDialog {
  final String? title;              // 标题（默认"需要密码"）
  final String? message;            // 提示文本
  final int? remainingAttempts;     // 剩余尝试次数
}
```

**功能**：
- ✅ 密码可见性切换
- ✅ 显示剩余尝试次数
- ✅ 自动聚焦输入框
- ✅ 支持回车提交
- ✅ 空密码验证

---

## 2️⃣ 问题识别 - 其他格式的局限

### 2.1 7z / tar.gz / bz2 等格式现状

#### libarchive 处理流程
```
用户点击解压
  ↓
ArchiveService.extractToInBackground()
  ↓ (Isolate)
_extractInIsolate() → ArchiveFFI.extractArchive()
  ↓
❌ 无密码参数传递
  ↓
解压失败 → 返回通用错误
  ↓
用户看到："解压失败"（无法区分是否需要密码）
```

#### 代码证据

**1. libarchive 调用无密码支持**：
```dart
// lib/core/services/archive_service.dart: Line 344-357
} else {
  // 其他格式（libarchive）
  final archive = ArchiveFFI();
  final result = archive.extractArchive(
    archivePath: params.archivePath,
    destPath: fullPath,
    // ❌ 缺少 password 参数！
  );
}
```

**2. FFI 接口未定义密码参数**：
```dart
// lib/ffi/archive_ffi.dart（推测）
class ArchiveFFI {
  ArchiveExtractResult extractArchive({
    required String archivePath,
    required String destPath,
    // ❌ 没有 String? password 参数
  });
}
```

**3. 用户提示不友好**：
```dart
// lib/ui/pages/archive_viewer_page.dart: Line 69, 545
_errorMessage = '此压缩格式的加密文件暂不支持查看\n（7z/tar等格式的密码保护功能尚未实现）';
```

### 2.2 预览功能的密码支持

#### 当前状态

**RAR 预览**：
```dart
// lib/core/services/archive_service.dart: Line 1110-1122
final success = _unrar.extractFile(
  archivePath,
  entryPath,
  tempDir.path,
  password: password,  // ✅ 支持密码
);
```

**ZIP 预览**：
```dart
// Line 1163
final result = _minizip.extractSingleFile(
  archivePath,
  rawPath,
  outputPath,
  password: password,  // ✅ 支持密码
);
```

**libarchive 预览**：
```dart
// Line 1184-1189
final result = _ffi.extractSingleFile(
  archivePath: archivePath,
  entryPath: entryPath,
  outputPath: outputPath,
  // ❌ 缺少 password 参数
);
```

#### 问题影响

| 格式 | 解压密码支持 | 预览密码支持 | 用户体验 |
|------|------------|------------|---------|
| RAR  | ✅ 完整 | ✅ 完整 | 优秀 |
| ZIP  | ✅ 完整 | ✅ 完整 | 优秀 |
| 7z   | ❌ 缺失 | ❌ 缺失 | 差劲 |
| tar.gz | ❌ 缺失 | ❌ 缺失 | 差劲 |
| bz2  | ❌ 缺失 | ❌ 缺失 | 差劲 |

---

## 3️⃣ 技术可行性分析

### 3.1 libarchive 密码支持能力

#### C API 调查

**libarchive 官方文档**：
```c
// libarchive 支持密码的 API
int archive_read_add_passphrase(struct archive *, const char *passphrase);
int archive_read_set_passphrase_callback(struct archive *, void *client_data, 
                                           archive_passphrase_callback *);
```

**支持的加密格式**：
- ✅ 7z（AES-256）
- ✅ ZIP（ZipCrypto / AES）
- ✅ RAR（仅读取，但已有 UnRAR SDK）
- ⚠️ tar.gz / bz2（通常不加密，但支持 GPG 加密）

#### FFI 集成难度

**改动点**：
1. **Dart FFI 绑定**（`lib/ffi/archive_ffi.dart`）
   ```dart
   class ArchiveFFI {
     ArchiveExtractResult extractArchive({
       required String archivePath,
       required String destPath,
       String? password,  // 🆕 添加密码参数
     });
     
     SingleFileExtractResult extractSingleFile({
       required String archivePath,
       required String entryPath,
       required String outputPath,
       String? password,  // 🆕 添加密码参数
     });
   }
   ```

2. **Native 代码**（Android: `android/src/main/cpp/archive_ffi.cpp`）
   ```cpp
   JNIEXPORT jobject JNICALL
   Java_com_guangqi_easyfile_ArchiveFFI_extractArchive(
     JNIEnv* env, jobject obj,
     jstring archivePath,
     jstring destPath,
     jstring password  // 🆕 新增参数
   ) {
     const char* pwd = password ? env->GetStringUTFChars(password, 0) : NULL;
     
     struct archive* a = archive_read_new();
     if (pwd) {
       archive_read_add_passphrase(a, pwd);  // 🔧 设置密码
     }
     // ... 其余解压逻辑
   }
   ```

**预估工作量**：
- Dart FFI 绑定修改：**1 小时**
- Native C++ 代码修改：**2-3 小时**
- 测试和调试：**2 小时**
- **总计**：**5-6 小时**

### 3.2 UI 层统一性

#### 优势：已有完整流程

**无需新增 UI 组件**：
- ✅ `PasswordInputDialog` 已存在且成熟
- ✅ `_needsPassword()` 错误检测逻辑已完善
- ✅ 重试机制（3次）已实现

**仅需修改**：
```dart
// lib/core/services/archive_service.dart
// _extractInIsolate() 中添加 libarchive 密码支持

} else {
  // 其他格式（libarchive）
  final archive = ArchiveFFI();
  final result = archive.extractArchive(
    archivePath: params.archivePath,
    destPath: fullPath,
    password: params.password,  // 🆕 传递密码
  );
  
  // 🆕 检测密码错误
  if (!result.success && _isPasswordError(result.errorMessage)) {
    return ExtractionResultData(
      success: false,
      errorMessage: '压缩包需要密码',  // 触发密码输入对话框
      targetPath: fullPath,
    );
  }
}
```

---

## 4️⃣ 方案设计 - 统一密码机制

### 4.1 架构设计

#### 目标：所有格式统一流程

```
┌─────────────────────────────────────────────┐
│      ExtractionProgressDialog (UI)         │
│  - 密码输入对话框                            │
│  - 重试机制（3次）                           │
│  - 错误检测（_needsPassword）               │
└──────────────┬──────────────────────────────┘
               │
               ↓
┌─────────────────────────────────────────────┐
│       ArchiveService (业务逻辑)             │
│  - extractToInBackground(password)          │
│  - extractTo(password)                      │
│  - extractSingleFileForPreview(password)    │
└──────────────┬──────────────────────────────┘
               │
      ┌────────┴────────┬──────────────┐
      ↓                 ↓              ↓
┌──────────┐    ┌───────────┐   ┌──────────────┐
│UnrarFFI  │    │MinizipFFI │   │ArchiveFFI    │
│(RAR)     │    │(ZIP)      │   │(7z/tar/etc)  │
│          │    │           │   │              │
│✅密码支持 │    │✅密码支持  │   │🔧待添加密码  │
└──────────┘    └───────────┘   └──────────────┘
```

#### 关键点

1. **UI 层不变**：`ExtractionProgressDialog` 和 `PasswordInputDialog` 保持不变
2. **业务层统一**：`ArchiveService` 统一处理所有格式
3. **FFI 层扩展**：`ArchiveFFI` 添加密码参数

### 4.2 实现步骤

#### Phase 1: FFI 层改造（后端）

**Step 1.1**: 修改 Dart FFI 绑定
```dart
// lib/ffi/archive_ffi.dart
class ArchiveFFI {
  // 🆕 添加密码参数
  ArchiveExtractResult extractArchive({
    required String archivePath,
    required String destPath,
    bool overwrite = false,
    bool preservePermissions = false,
    String? password,  // 新增
    void Function(double progress, String filename)? onProgress,
  });

  SingleFileExtractResult extractSingleFile({
    required String archivePath,
    required String entryPath,
    required String outputPath,
    String? password,  // 新增
  });
}
```

**Step 1.2**: 修改 Native 实现（Android）
```cpp
// android/src/main/cpp/archive_ffi.cpp

// 辅助函数：密码回调
static int password_callback(struct archive *a, void *client_data) {
  const char* password = (const char*)client_data;
  if (password) {
    return archive_read_add_passphrase(a, password);
  }
  return ARCHIVE_OK;
}

JNIEXPORT jobject JNICALL
Java_com_guangqi_easyfile_ArchiveFFI_extractArchive(
  JNIEnv* env, jobject obj,
  jstring j_archive_path,
  jstring j_dest_path,
  jstring j_password  // 🆕 新增参数
) {
  const char* archive_path = env->GetStringUTFChars(j_archive_path, 0);
  const char* dest_path = env->GetStringUTFChars(j_dest_path, 0);
  const char* password = j_password ? env->GetStringUTFChars(j_password, 0) : NULL;

  struct archive* a = archive_read_new();
  archive_read_support_filter_all(a);
  archive_read_support_format_all(a);

  // 🔧 设置密码
  if (password && strlen(password) > 0) {
    archive_read_add_passphrase(a, password);
  }

  int r = archive_read_open_filename(a, archive_path, 10240);
  
  if (r != ARCHIVE_OK) {
    // 🆕 检测密码错误
    const char* error = archive_error_string(a);
    if (strstr(error, "encrypted") || strstr(error, "password")) {
      // 返回特殊错误码
      return createErrorResult(env, "需要密码或密码错误");
    }
  }
  
  // ... 其余解压逻辑 ...
  
  // 清理
  if (password) env->ReleaseStringUTFChars(j_password, password);
  env->ReleaseStringUTFChars(j_archive_path, archive_path);
  env->ReleaseStringUTFChars(j_dest_path, dest_path);
}
```

**Step 1.3**: 错误消息标准化
```cpp
// 密码相关错误消息统一格式
const char* ERROR_NEED_PASSWORD = "压缩包需要密码";
const char* ERROR_WRONG_PASSWORD = "密码错误或压缩包已损坏";
const char* ERROR_ENCRYPTED = "此压缩包已加密";
```

#### Phase 2: 业务层集成（中间层）

**Step 2.1**: 修改 `_extractInIsolate`
```dart
// lib/core/services/archive_service.dart: Line 344-370
} else {
  // 其他格式（libarchive）
  final archive = ArchiveFFI();
  final result = archive.extractArchive(
    archivePath: params.archivePath,
    destPath: fullPath,
    password: params.password,  // 🔧 传递密码
  );

  if (result.success) {
    return ExtractionResultData(
      success: true,
      targetPath: fullPath,
      totalFiles: result.totalFiles,
      extractedFiles: result.extractedFiles,
      handleId: result.handleId,
    );
  } else {
    // 🆕 检测密码错误
    String errorMsg = result.errorMessage;
    if (_isPasswordError(errorMsg)) {
      errorMsg = params.password == null || params.password!.isEmpty
          ? '压缩包需要密码'
          : '密码错误或压缩包已损坏';
    }
    
    return ExtractionResultData(
      success: false,
      errorMessage: errorMsg,
      targetPath: fullPath,
      totalFiles: result.totalFiles,
      extractedFiles: result.extractedFiles,
      handleId: result.handleId,
    );
  }
}

// 🆕 辅助方法：检测密码错误
static bool _isPasswordError(String errorMsg) {
  final lower = errorMsg.toLowerCase();
  return lower.contains('password') ||
         lower.contains('encrypted') ||
         lower.contains('密码') ||
         lower.contains('加密');
}
```

**Step 2.2**: 修改 `_extractWithLibarchive`
```dart
// Line 580-630
Future<ExtractResult> _extractWithLibarchive({
  required String archivePath,
  required String fullPath,
  String? password,  // 🆕 添加密码参数
  void Function(double progress)? onProgress,
}) async {
  try {
    logger.i('使用 libarchive 解压: $archivePath');

    final result = _ffi.extractArchive(
      archivePath: archivePath,
      destPath: fullPath,
      overwrite: false,
      preservePermissions: false,
      password: password,  // 🔧 传递密码
      onProgress: (progress, filename) {
        logger.d('Progress: ${(progress * 100).toStringAsFixed(1)}% - $filename');
        onProgress?.call(progress);
      },
    );

    // ... 后续逻辑保持不变 ...
  }
}
```

**Step 2.3**: 修改 `extractSingleFileForPreview`
```dart
// Line 1184-1200
} else {
  // 使用libarchive提取其他格式
  logger.d('Using libarchive to extract single file');
  final result = _ffi.extractSingleFile(
    archivePath: archivePath,
    entryPath: entryPath,
    outputPath: outputPath,
    password: password,  // 🔧 传递密码
  );

  if (result.success) {
    // ... 成功逻辑 ...
  } else {
    // 🆕 检测密码错误
    String errorMsg = result.errorMessage;
    if (_isPasswordError(errorMsg)) {
      errorMsg = password == null || password.isEmpty
          ? '压缩包需要密码'
          : '密码错误或压缩包已损坏';
    }
    
    logger.w('提取失败: $errorMsg');
    return SingleFileExtractResult(
      success: false,
      extractedSize: 0,
      errorMessage: errorMsg,
    );
  }
}
```

#### Phase 3: UI 层优化（前端）

**Step 3.1**: 移除硬编码的格式限制
```dart
// lib/ui/pages/archive_viewer_page.dart: Line 69
// ❌ 删除这行
_errorMessage = '此压缩格式的加密文件暂不支持查看\n（7z/tar等格式的密码保护功能尚未实现）';

// ✅ 改为通用提示（让后端返回错误）
// 不再前端判断格式，让 ArchiveService 统一处理
```

**Step 3.2**: 预览缓存管理器保持不变
```dart
// lib/core/services/archive_preview_cache_manager.dart
// ✅ 无需修改，已支持 password 参数传递
static Future<String?> extractForPreview({
  required String archivePath,
  required String entryPath,
  required void Function(String message) onError,
  String? password,  // 已有
})
```

---

## 5️⃣ 测试策略

### 5.1 单元测试

#### 测试用例矩阵

| 格式 | 无密码 | 正确密码 | 错误密码 | 空密码 |
|------|-------|---------|---------|-------|
| RAR  | ✅ P0 | ✅ P0   | ✅ P0   | ✅ P1 |
| ZIP  | ✅ P0 | ✅ P0   | ✅ P0   | ✅ P1 |
| 7z   | ✅ P0 | ✅ P0   | ✅ P0   | ✅ P1 |
| tar.gz | ✅ P1 | N/A    | N/A     | N/A   |

**测试代码示例**：
```dart
// test/services/archive_service_password_test.dart
void main() {
  group('加密7z文件解压', () {
    test('无密码解压应提示需要密码', () async {
      final result = await archiveService.extractTo(
        archivePath: 'test_data/encrypted.7z',
        targetDir: tempDir.path,
        folderName: 'output',
        password: null,
      );
      
      expect(result.success, isFalse);
      expect(result.errorMessage.toLowerCase(), contains('password'));
    });
    
    test('正确密码应成功解压', () async {
      final result = await archiveService.extractTo(
        archivePath: 'test_data/encrypted.7z',
        targetDir: tempDir.path,
        folderName: 'output',
        password: 'test123',
      );
      
      expect(result.success, isTrue);
      expect(result.extractedFiles, greaterThan(0));
    });
    
    test('错误密码应提示密码错误', () async {
      final result = await archiveService.extractTo(
        archivePath: 'test_data/encrypted.7z',
        targetDir: tempDir.path,
        folderName: 'output',
        password: 'wrong_password',
      );
      
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('密码错误'));
    });
  });
}
```

### 5.2 集成测试

#### UI 自动化测试
```dart
// test_integration/archive_extraction_password_test.dart
testWidgets('7z加密文件解压流程', (WidgetTester tester) async {
  // 1. 打开加密的7z文件
  await tester.tap(find.text('encrypted_test.7z'));
  await tester.pump();
  
  // 2. 点击解压
  await tester.tap(find.byIcon(Icons.folder_zip));
  await tester.pump();
  
  // 3. 等待密码对话框出现
  await tester.pumpAndSettle();
  expect(find.text('需要密码'), findsOneWidget);
  
  // 4. 输入错误密码
  await tester.enterText(find.byType(TextField), 'wrong_password');
  await tester.tap(find.text('确定'));
  await tester.pumpAndSettle();
  
  // 5. 应显示密码错误提示
  expect(find.text('剩余尝试次数: 2'), findsOneWidget);
  
  // 6. 输入正确密码
  await tester.enterText(find.byType(TextField), 'test123');
  await tester.tap(find.text('确定'));
  await tester.pumpAndSettle(const Duration(seconds: 5));
  
  // 7. 应成功解压
  expect(find.text('解压完成！'), findsOneWidget);
});
```

### 5.3 手工测试清单

#### 关键场景
- [ ] 7z 加密文件解压（AES-256）
- [ ] 7z 加密文件预览（提取单个文件）
- [ ] ZIP 加密文件（ZipCrypto）
- [ ] ZIP 加密文件（AES-256）
- [ ] RAR 加密文件（保持兼容）
- [ ] 密码输入对话框显示/隐藏
- [ ] 密码错误重试3次后取消
- [ ] 解压中途取消（密码对话框点击取消）

---

## 6️⃣ 风险评估与缓解

### 6.1 技术风险

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| libarchive 密码API不稳定 | 低 | 高 | 查阅官方文档，使用稳定API |
| Native 代码内存泄漏 | 中 | 高 | 严格测试，Valgrind检查 |
| JNI 字符串编码问题 | 中 | 中 | 使用 UTF-8，测试中文密码 |
| 不同加密算法支持不一致 | 高 | 中 | 文档说明支持范围，优雅降级 |

### 6.2 兼容性风险

| 场景 | 风险 | 缓解措施 |
|------|------|---------|
| 旧版libarchive不支持密码 | 低 | 运行时检查API可用性 |
| Android不同版本行为差异 | 中 | 在Android 7-14测试 |
| 某些7z文件格式不支持 | 中 | 捕获异常，友好提示 |

### 6.3 用户体验风险

| 问题 | 影响 | 解决方案 |
|------|------|---------|
| 密码输入无反馈 | 中 | 添加进度指示器 |
| 错误提示不明确 | 高 | 标准化错误消息 |
| 多次输入密码繁琐 | 中 | 考虑密码缓存（安全性评估后） |

---

## 7️⃣ 实施路线图

### 时间线（总计 2-3 天）

#### Day 1: FFI 层改造
- [ ] **上午**：修改 `archive_ffi.dart` Dart 绑定（2h）
- [ ] **下午**：修改 Android Native 代码（3h）
  - 添加密码参数
  - 实现 `archive_read_add_passphrase`
  - 错误消息标准化
- [ ] **晚上**：编译测试，修复编译错误（1h）

#### Day 2: 业务层集成
- [ ] **上午**：修改 `_extractInIsolate` 和 `_extractWithLibarchive`（2h）
- [ ] **下午**：修改 `extractSingleFileForPreview`（1h）
- [ ] **下午**：编写单元测试（2h）
- [ ] **晚上**：手工测试基本场景（1h）

#### Day 3: 测试与优化
- [ ] **上午**：集成测试（2h）
- [ ] **下午**：边缘情况测试（中文密码、特殊字符等）（2h）
- [ ] **晚上**：性能测试、内存泄漏检查（2h）

### 里程碑

✅ **M1 (Day 1 结束)**：Native 代码编译通过，FFI 绑定完成
✅ **M2 (Day 2 结束)**：7z 加密文件成功解压，UI 流程打通
✅ **M3 (Day 3 结束)**：所有测试通过，代码合并到主分支

---

## 8️⃣ 推荐方案与优先级

### 推荐方案：**方案 A - 全格式统一**

#### 理由
1. **用户体验一致性**：所有格式使用相同的密码输入流程
2. **技术债务最小**：基于现有 RAR/ZIP 机制扩展，代码重用度高
3. **工作量可控**：预估 2-3 天完成，风险可控
4. **未来可扩展**：为其他加密格式（如 GPG）奠定基础

#### 对比方案 B（不推荐）

**方案 B**：仅提示用户使用第三方工具
- ❌ 用户体验差
- ❌ 功能不完整（竞品支持）
- ✅ 无开发成本

**对比结论**：方案 A 投入产出比更高

### 优先级矩阵

| 任务 | 优先级 | 依赖 | 预估时间 |
|------|-------|------|---------|
| FFI 层密码参数添加 | **P0** | 无 | 2h |
| Native 密码API集成 | **P0** | FFI层 | 3h |
| 业务层密码传递 | **P0** | Native | 2h |
| 单元测试 | **P1** | 业务层 | 2h |
| 集成测试 | **P1** | 单元测试 | 2h |
| 性能优化 | **P2** | 集成测试 | 2h |
| 密码缓存功能 | **P3** | 全部完成 | 4h |

---

## 9️⃣ 附录

### A. 密码错误消息规范

#### 标准错误消息（所有格式统一）

| 场景 | 英文消息 | 中文消息 |
|------|---------|---------|
| 需要密码 | "Password required" | "压缩包需要密码" |
| 密码错误 | "Incorrect password" | "密码错误或压缩包已损坏" |
| 加密不支持 | "Encryption not supported" | "不支持此加密算法" |
| 密码为空 | "Empty password" | "密码不能为空" |

### B. libarchive 密码 API 参考

```c
// 添加密码
int archive_read_add_passphrase(struct archive *a, const char *passphrase);

// 设置密码回调（高级用法）
int archive_read_set_passphrase_callback(
  struct archive *a,
  void *client_data,
  archive_passphrase_callback *callback
);

// 错误检测
const char* archive_error_string(struct archive *a);
int archive_errno(struct archive *a);

// 常见错误码
#define ARCHIVE_EOF     1   // Found end of archive
#define ARCHIVE_OK      0   // Operation was successful
#define ARCHIVE_RETRY (-10) // Retry might succeed
#define ARCHIVE_WARN  (-20) // Partial success
#define ARCHIVE_FAILED (-25) // Current operation cannot complete
#define ARCHIVE_FATAL (-30)  // No more operations are possible
```

### C. 测试数据准备

#### 创建加密测试文件

**7z 加密**：
```bash
7z a -p"test123" -mhe=on encrypted_test.7z test_files/
```

**ZIP 加密（ZipCrypto）**：
```bash
zip -e -P "test123" encrypted_test.zip test_files/*
```

**ZIP 加密（AES-256）**：
```bash
7z a -tzip -mem=AES256 -p"test123" encrypted_aes.zip test_files/
```

---

## 📌 总结与行动项

### 核心发现
1. ✅ **RAR/ZIP 已有完整密码机制**，UI 和业务逻辑成熟
2. ❌ **7z/tar 等格式缺少密码传递**，仅FFI层需扩展
3. 🔧 **技术可行性高**，libarchive 原生支持密码
4. ⏱️ **工作量可控**，预估 2-3 天完成

### 推荐方案
**统一密码机制到所有格式**（方案 A），理由：
- 用户体验一致性
- 代码重用度高
- 风险可控
- 未来可扩展

### 立即行动项
1. **评审通过本方案**（管理层决策）
2. **准备测试数据**（创建加密测试文件）
3. **开始 FFI 层改造**（Day 1 任务）
4. **持续跟踪进度**（每日站会汇报）

### 成功指标
- ✅ 7z 加密文件可正常解压
- ✅ 密码输入流程与 RAR/ZIP 一致
- ✅ 所有单元测试通过
- ✅ 用户反馈积极（Beta 测试）

---

**报告日期**：2026-01-19  
**分析人员**：GitHub Copilot (Claude Sonnet 4.5)  
**审核状态**：待评审  
**建议优先级**：P1（高优先级，建议在下一个版本实现）
