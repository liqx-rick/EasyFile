# 7z 密码解压问题检查清单

## ✅ 已完成的修复

### 🧨 坑 1：7z 格式支持
**问题**: 7z 打不开，但 ZIP 可以  
**原因**: ZIP 会自动 fallback，7z 不会  
**修复状态**: ✅ **已修复**
- `archive_read_support_format_all()` - 支持所有格式包括 7z
- `archive_read_support_filter_all()` - 支持所有压缩算法包括 LZMA

**文件**: `native/src/archive_wrapper.c` Line 101-102

---

### 🧨 坑 2：密码传递问题
**问题**: 传了密码但仍失败  
**常见原因**:
1. 密码不是 UTF-8
2. archive 实例已被使用过
3. 没重新 open archive

**修复状态**: ✅ **已修复**

#### 2.1 密码编码（UTF-8）
- Dart 的 `String.toNativeUtf8()` 已经保证 UTF-8 编码
- **文件**: `lib/ffi/archive_ffi.dart` Line 43

#### 2.2 Archive 实例重用问题
代码中有两次打开 archive：
1. **第一次**: 扫描文件列表（Line 123-158）
2. **第二次**: 实际解压（Line 183-195）

✅ **已确认**: 重新打开时创建了新的 archive 实例  
✅ **已确认**: 重新打开时也设置了密码回调  
**文件**: `native/src/archive_wrapper.c` Line 183-195

---

### 🧨 坑 3：后台解压卡死
**问题**: libarchive 在等密码，但没有 set_passphrase  
**修复状态**: ✅ **已修复**

**关键修复**: 添加了密码回调函数（对 7z **必需**）

```c
// 密码回调数据结构
typedef struct {
    const char* password;
} PasswordCallbackData;

// 密码回调函数
static const char* passphrase_callback(struct archive* a, void* client_data) {
    PasswordCallbackData* data = (PasswordCallbackData*)client_data;
    if (data != NULL && data->password != NULL) {
        fprintf(stderr, "[Native] passphrase_callback called, returning password\n");
        return data->password;
    }
    return NULL;
}
```

**使用位置**:
1. ✅ 第一次打开 (Line 105-115)
   ```c
   archive_read_add_passphrase(a, options->password);
   password_data = malloc(sizeof(PasswordCallbackData));
   password_data->password = options->password;
   archive_read_set_passphrase_callback(a, password_data, passphrase_callback);
   ```

2. ✅ 重新打开 (Line 190-194)
   ```c
   archive_read_add_passphrase(a, options->password);
   archive_read_set_passphrase_callback(a, password_data, passphrase_callback);
   ```

3. ✅ 单文件提取 (Line 519-525)
   ```c
   archive_read_add_passphrase(a, password);
   password_data = malloc(sizeof(PasswordCallbackData));
   password_data->password = password;
   archive_read_set_passphrase_callback(a, password_data, passphrase_callback);
   ```

**文件**: `native/src/archive_wrapper.c`

---

### 🧨 坑 4：libarchive 版本要求
**要求**:
- libarchive ≥ 3.3
- 启用了 7zip 支持
- 没被裁剪 LZMA / AES

**当前状态**: ⚠️ **需要验证**

**检查方法**:
```bash
# 检查 libarchive.so 版本
strings android/src/main/jniLibs/arm64-v8a/libarchive.so | grep -i "libarchive"

# 检查依赖（应该包含 LZMA 支持）
$env:ANDROID_NDK_HOME\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe -d android/src/main/jniLibs/arm64-v8a/libarchive.so
```

**编译要求**（参考 `docs/LIBARCHIVE_STATIC_BUILD_GUIDE.md`）:
```cmake
-DENABLE_LZMA=ON      # 7z 必需
-DENABLE_AES=ON       # 加密必需（如果有此选项）
-DCMAKE_BUILD_TYPE=Release
```

---

## 🔍 调试日志

已添加的调试日志：

### Native 层 (C)
1. 密码设置: `[Native] Password set: length=X`
2. 无密码: `[Native] No password provided`
3. 回调调用: `[Native] passphrase_callback called, returning password`
4. 重新打开: `[Native] Reopen: Password reset`

### Dart 层
1. 密码对话框返回: `[密码对话框] 返回值: 已输入密码`
2. 密码参数: `[密码调试] password参数: 已提供(长度X)`
3. 错误检测: `[密码调试] _isPasswordError检测结果: true/false`

---

## 📝 测试步骤

1. **清空日志**:
   ```bash
   adb logcat -c
   ```

2. **安装新 APK**:
   ```bash
   adb install -r build\app\outputs\flutter-apk\app-debug.apk
   ```

3. **执行解压操作** (Needpwds.7z)

4. **导出日志**:
   ```bash
   adb logcat -d | Select-String -Pattern "\[Native\]|\[密码" > test_log.txt
   ```

5. **检查关键日志**:
   - ✅ `[Native] Password set: length=X`
   - ✅ `[Native] passphrase_callback called`
   - ✅ `[密码调试] password参数: 已提供`

---

## 🎯 预期行为

1. 用户打开加密的 7z 文件
2. 系统弹出密码输入框
3. 用户输入正确密码
4. **Native 层接收密码**: `[Native] Password set`
5. **libarchive 调用回调**: `[Native] passphrase_callback called`
6. 解压成功

---

## ❌ 如果仍然失败

### 可能原因 1: libarchive 版本过低或未启用 7z
**验证**:
```bash
# 检查是否有 LZMA 符号
strings android/src/main/jniLibs/arm64-v8a/libarchive.so | grep -i lzma
```

**解决**: 重新编译 libarchive，确保 `-DENABLE_LZMA=ON`

### 可能原因 2: 密码回调未被调用
**症状**: 日志中没有 `passphrase_callback called`  
**原因**: libarchive 版本不支持回调，或编译时被禁用  
**解决**: 升级 libarchive 到 3.6+

### 可能原因 3: 7z 文件本身有问题
**验证**:
```bash
# 在电脑上用 7-Zip 测试
7z t Needpwds.7z -p<password>
```

---

## 📚 参考资料

1. **libarchive 密码 API**:
   - `archive_read_add_passphrase()` - 添加密码到密码池
   - `archive_read_set_passphrase_callback()` - 设置密码回调（7z 必需）

2. **7z 加密算法**:
   - Header encryption: AES-256
   - Data encryption: AES-256

3. **相关文档**:
   - `docs/LIBARCHIVE_STATIC_BUILD_GUIDE.md` - 编译指南
   - `native/src/archive_wrapper.c` - Native 实现
   - `lib/core/services/archive_service.dart` - Dart 服务层
