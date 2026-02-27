# libarchive 加密支持检查和修复指南

## 问题确认

**现象**：
- 无密码 7z ✅ 可以解压
- 加密 7z ❌ 格式显示 "unknown"，密码回调不被调用

**根本原因**：
libarchive 编译时**缺少加密库支持**，无法识别加密的 7z 头部。

---

## 验证当前 libarchive 的加密支持

```bash
# 检查 libarchive.so 是否链接了加密库
$NDK_PATH = "C:\Users\rli\AppData\Local\Android\Sdk\ndk\27.0.12077973"
& "$NDK_PATH\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe" -d android\src\main\jniLibs\arm64-v8a\libarchive.so | Select-String -Pattern "NEEDED"

# 预期输出应包含以下之一：
# NEEDED libcrypto.so (OpenSSL)
# NEEDED libmbedcrypto.so (mbedTLS)
# NEEDED libnettle.so (Nettle)
```

如果**没有**看到加密库，说明需要重新编译。

---

## 快速修复方案 1：使用 vcpkg 安装 OpenSSL

Android NDK 自带 OpenSSL，但 vcpkg 提供更简单的集成：

```bash
# 安装 OpenSSL for Android
cd C:\dev\vcpkg
.\vcpkg install openssl:arm64-android
.\vcpkg install openssl:arm-android
```

---

## 快速修复方案 2：重新编译 libarchive

### 1. 安装依赖（使用 vcpkg）

```bash
cd C:\dev\vcpkg

# 为 arm64-v8a 安装
.\vcpkg install bzip2:arm64-android
.\vcpkg install liblzma:arm64-android
.\vcpkg install lz4:arm64-android
.\vcpkg install zstd:arm64-android
.\vcpkg install zlib:arm64-android
.\vcpkg install openssl:arm64-android

# 为 armeabi-v7a 安装
.\vcpkg install bzip2:arm-android
.\vcpkg install liblzma:arm-android
.\vcpkg install lz4:arm-android
.\vcpkg install zstd:arm-android
.\vcpkg install zlib:arm-android
.\vcpkg install openssl:arm-android
```

### 2. 编译 libarchive (arm64-v8a)

```bash
cd C:\dev\libarchive
rm -r build-android-arm64 -Force -ErrorAction SilentlyContinue
mkdir build-android-arm64
cd build-android-arm64

$NDK = "C:\Users\rli\AppData\Local\Android\Sdk\ndk\27.0.12077973"
$VCPKG = "C:\dev\vcpkg\installed\arm64-android"

cmake .. `
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" `
  -DANDROID_ABI=arm64-v8a `
  -DANDROID_PLATFORM=android-24 `
  -DCMAKE_BUILD_TYPE=Release `
  -DBUILD_SHARED_LIBS=ON `
  -DENABLE_BZ2=ON `
  -DENABLE_LZMA=ON `
  -DENABLE_LZ4=ON `
  -DENABLE_ZSTD=ON `
  -DENABLE_ZLIB=ON `
  -DENABLE_OPENSSL=ON `
  -DENABLE_MBEDTLS=OFF `
  -DENABLE_NETTLE=OFF `
  -DENABLE_CNG=OFF `
  -DBZIP2_LIBRARIES="$VCPKG/lib/libbz2.a" `
  -DLIBLZMA_LIBRARIES="$VCPKG/lib/liblzma.a" `
  -DLZ4_LIBRARIES="$VCPKG/lib/liblz4.a" `
  -DZSTD_LIBRARIES="$VCPKG/lib/libzstd.a" `
  -DZLIB_LIBRARIES="$VCPKG/lib/libz.a" `
  -DOPENSSL_ROOT_DIR="$VCPKG" `
  -DOPENSSL_CRYPTO_LIBRARY="$VCPKG/lib/libcrypto.a" `
  -DOPENSSL_SSL_LIBRARY="$VCPKG/lib/libssl.a"

cmake --build . --config Release
```

### 3. 验证编译结果

```bash
# 检查是否包含加密支持
strings libarchive/libarchive.so | Select-String -Pattern "AES|crypto|openssl" | Select-Object -First 10

# 检查动态库依赖（应该只有系统库）
& "$NDK\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe" -d libarchive/libarchive.so | Select-String -Pattern "NEEDED"

# 预期输出：
# NEEDED libc.so
# NEEDED libm.so
# NEEDED libdl.so
# (不应该有 libcrypto.so，因为是静态链接)
```

### 4. 复制到项目

```bash
# arm64-v8a
Copy-Item "libarchive\libarchive.so" `
          "C:\dev\flutter\easyfile\android\src\main\jniLibs\arm64-v8a\libarchive.so" -Force

# 重复步骤2-4 为 armeabi-v7a (将 arm64-v8a 改为 armeabi-v7a)
```

### 5. 测试

```bash
cd C:\dev\flutter\easyfile
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

---

## 测试加密 7z 支持

1. 清空日志：`adb logcat -c`
2. 解压 **Needpwds.7z**
3. 查看日志：
   ```bash
   adb logcat -d | Select-String -Pattern "ArchiveWrapper"
   ```

**预期输出**（修复后）：
```
D ArchiveWrapper: [Native] Archive format: 7-Zip
D ArchiveWrapper: [Native] passphrase_callback called, returning password
```

---

## 常见问题

### Q1: CMake 找不到 OpenSSL
**解决**：明确指定路径
```bash
-DOPENSSL_ROOT_DIR="C:/dev/vcpkg/installed/arm64-android"
-DOPENSSL_INCLUDE_DIR="C:/dev/vcpkg/installed/arm64-android/include"
```

### Q2: 编译后仍然无法识别加密 7z
**可能原因**：
1. 使用了错误的 libarchive 版本（< 3.3）
2. 7z 文件使用了不支持的加密算法（如 AES-256-SHA256）
3. libarchive 的 7z 模块本身有 bug

**验证方法**：
```bash
# 在 PC 上测试
7z t Needpwds.7z -p<password>
# 查看加密方法
```

### Q3: 为什么无密码 7z 可以但加密 7z 不行？
- **无密码 7z**：头部未加密，libarchive 能识别格式
- **加密 7z**：头部可能加密，需要加密库才能读取头部

---

## 临时解决方案：使用预编译的 libarchive

如果编译困难，可以尝试：
1. 从 Termux 提取 libarchive.so（已包含加密支持）
2. 使用 [libarchive 官方预编译包](https://github.com/libarchive/libarchive/releases)

```bash
# 从 Termux 提取
adb shell "pkg install libarchive"
adb shell "find /data/data/com.termux/files/usr/lib -name 'libarchive.so*'"
adb pull /data/data/com.termux/files/usr/lib/libarchive.so.19
```

---

## 参考链接

- [libarchive CMake 选项](https://github.com/libarchive/libarchive/blob/master/CMakeLists.txt)
- [7-Zip 加密算法](https://www.7-zip.org/7z.html)
- [vcpkg Android 支持](https://learn.microsoft.com/en-us/vcpkg/users/platforms/android)
