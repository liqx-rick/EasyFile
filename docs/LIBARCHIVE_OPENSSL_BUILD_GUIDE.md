# libarchive 重新编译指南（启用 OpenSSL 加密支持）

## 问题说明

当前的 `libarchive.so` **缺少加密库支持**，无法处理加密的 7z 文件：
- 加密的 7z 头部无法被识别（显示 "unknown" 格式）
- 密码回调从不被调用
- 需要重新编译并静态链接 OpenSSL

## 验证当前状态

```powershell
# 检查 libarchive.so 依赖（应该看到 libcrypto.so）
$NDK = "C:\Users\rli\AppData\Local\Android\Sdk\ndk\27.0.12077973"
& "$NDK\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe" -d `
  android\src\main\jniLibs\arm64-v8a\libarchive.so | Select-String "NEEDED"
```

**当前输出（问题）**：
```
NEEDED libm.so
NEEDED libdl.so
NEEDED libc.so
```

**预期输出（修复后）**：
```
NEEDED libcrypto.so    # ← 应该包含此项（或静态链接后不出现）
NEEDED libm.so
NEEDED libdl.so
NEEDED libc.so
```

---

## 方案 A：使用 Android NDK 自带的 OpenSSL（推荐⭐）

Android NDK 27 已经包含了 OpenSSL，无需额外安装。

### 1. 设置环境变量

```powershell
$NDK = "C:\Users\rli\AppData\Local\Android\Sdk\ndk\27.0.12077973"
$TOOLCHAIN = "$NDK\toolchains\llvm\prebuilt\windows-x86_64"
$SYSROOT_ARM64 = "$TOOLCHAIN\sysroot"

# NDK OpenSSL 头文件和库
$OPENSSL_INCLUDE = "$SYSROOT_ARM64\usr\include"
$OPENSSL_LIB_ARM64 = "$SYSROOT_ARM64\usr\lib\aarch64-linux-android"
$OPENSSL_LIB_ARM = "$SYSROOT_ARM64\usr\lib\arm-linux-androideabi"
```

### 2. 编译 libarchive (arm64-v8a)

```powershell
cd C:\dev\libarchive  # 您的 libarchive 源码目录
Remove-Item build-android-arm64 -Recurse -Force -ErrorAction SilentlyContinue
New-Item build-android-arm64 -ItemType Directory
cd build-android-arm64

cmake .. `
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" `
  -DANDROID_ABI=arm64-v8a `
  -DANDROID_PLATFORM=android-24 `
  -DCMAKE_BUILD_TYPE=Release `
  -DBUILD_SHARED_LIBS=ON `
  -DENABLE_BZ2=ON `
  -DENABLE_LZMA=ON `
  -DENABLE_LZ4=OFF `
  -DENABLE_ZSTD=OFF `
  -DENABLE_ZLIB=ON `
  -DENABLE_OPENSSL=ON `
  -DENABLE_MBEDTLS=OFF `
  -DENABLE_NETTLE=OFF `
  -DENABLE_CNG=OFF `
  -DOPENSSL_ROOT_DIR="$OPENSSL_LIB_ARM64" `
  -DOPENSSL_INCLUDE_DIR="$OPENSSL_INCLUDE" `
  -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_LIB_ARM64/libcrypto.so" `
  -DOPENSSL_SSL_LIBRARY="$OPENSSL_LIB_ARM64/libssl.so"

cmake --build . --config Release -j8
```

### 3. 编译 libarchive (armeabi-v7a)

```powershell
cd C:\dev\libarchive
Remove-Item build-android-arm -Recurse -Force -ErrorAction SilentlyContinue
New-Item build-android-arm -ItemType Directory
cd build-android-arm

cmake .. `
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" `
  -DANDROID_ABI=armeabi-v7a `
  -DANDROID_PLATFORM=android-24 `
  -DCMAKE_BUILD_TYPE=Release `
  -DBUILD_SHARED_LIBS=ON `
  -DENABLE_BZ2=ON `
  -DENABLE_LZMA=ON `
  -DENABLE_LZ4=OFF `
  -DENABLE_ZSTD=OFF `
  -DENABLE_ZLIB=ON `
  -DENABLE_OPENSSL=ON `
  -DENABLE_MBEDTLS=OFF `
  -DENABLE_NETTLE=OFF `
  -DENABLE_CNG=OFF `
  -DOPENSSL_ROOT_DIR="$OPENSSL_LIB_ARM" `
  -DOPENSSL_INCLUDE_DIR="$OPENSSL_INCLUDE" `
  -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_LIB_ARM/libcrypto.so" `
  -DOPENSSL_SSL_LIBRARY="$OPENSSL_LIB_ARM/libssl.so"

cmake --build . --config Release -j8
```

### 4. 验证编译结果

```powershell
# 检查是否包含 OpenSSL 符号
strings build-android-arm64\libarchive\libarchive.so | Select-String -Pattern "AES|openssl|crypto" | Select-Object -First 10

# 检查动态库依赖
& "$NDK\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe" -d `
  build-android-arm64\libarchive\libarchive.so | Select-String "NEEDED"
```

**预期输出**：应该看到 `libcrypto.so` 依赖或 OpenSSL 相关符号。

### 5. 复制到项目

```powershell
# arm64-v8a
Copy-Item "build-android-arm64\libarchive\libarchive.so" `
          "C:\dev\flutter\easyfile\android\src\main\jniLibs\arm64-v8a\libarchive.so" -Force

# armeabi-v7a
Copy-Item "build-android-arm\libarchive\libarchive.so" `
          "C:\dev\flutter\easyfile\android\src\main\jniLibs\armeabi-v7a\libarchive.so" -Force
```

---

## 方案 B：使用 vcpkg 静态链接 OpenSSL（APK 更大但独立）

如果 NDK OpenSSL 不可用，可以使用 vcpkg 提供的静态库。

### 1. 安装 vcpkg 和依赖

```powershell
# 安装 vcpkg（如果没有）
cd C:\dev
git clone https://github.com/microsoft/vcpkg.git
cd vcpkg
.\bootstrap-vcpkg.bat

# 为 arm64-v8a 安装依赖
.\vcpkg install bzip2:arm64-android
.\vcpkg install liblzma:arm64-android
.\vcpkg install zlib:arm64-android
.\vcpkg install openssl:arm64-android

# 为 armeabi-v7a 安装依赖
.\vcpkg install bzip2:arm-android
.\vcpkg install liblzma:arm-android
.\vcpkg install zlib:arm-android
.\vcpkg install openssl:arm-android
```

### 2. 编译 libarchive (arm64-v8a) with 静态链接

```powershell
cd C:\dev\libarchive
Remove-Item build-android-arm64-static -Recurse -Force -ErrorAction SilentlyContinue
New-Item build-android-arm64-static -ItemType Directory
cd build-android-arm64-static

$VCPKG = "C:\dev\vcpkg\installed\arm64-android"

cmake .. `
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" `
  -DANDROID_ABI=arm64-v8a `
  -DANDROID_PLATFORM=android-24 `
  -DCMAKE_BUILD_TYPE=Release `
  -DBUILD_SHARED_LIBS=ON `
  -DENABLE_BZ2=ON `
  -DENABLE_LZMA=ON `
  -DENABLE_LZ4=OFF `
  -DENABLE_ZSTD=OFF `
  -DENABLE_ZLIB=ON `
  -DENABLE_OPENSSL=ON `
  -DENABLE_MBEDTLS=OFF `
  -DENABLE_NETTLE=OFF `
  -DENABLE_CNG=OFF `
  -DBZIP2_LIBRARIES="$VCPKG/lib/libbz2.a" `
  -DLIBLZMA_LIBRARIES="$VCPKG/lib/liblzma.a" `
  -DZLIB_LIBRARIES="$VCPKG/lib/libz.a" `
  -DOPENSSL_ROOT_DIR="$VCPKG" `
  -DOPENSSL_INCLUDE_DIR="$VCPKG/include" `
  -DOPENSSL_CRYPTO_LIBRARY="$VCPKG/lib/libcrypto.a" `
  -DOPENSSL_SSL_LIBRARY="$VCPKG/lib/libssl.a"

cmake --build . --config Release -j8
```

### 3. 验证（静态链接应该不显示 libcrypto）

```powershell
# 检查动态库依赖（静态链接后只有系统库）
& "$NDK\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe" -d `
  libarchive\libarchive.so | Select-String "NEEDED"

# 预期输出（没有 libcrypto.so，因为已静态链接）
# NEEDED libc.so
# NEEDED libm.so
# NEEDED libdl.so

# 检查是否包含 OpenSSL 符号（应该有）
strings libarchive\libarchive.so | Select-String -Pattern "OpenSSL" | Select-Object -First 5
```

---

## 测试加密 7z 支持

### 1. 编译并安装 APK

```powershell
cd C:\dev\flutter\easyfile
flutter clean
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

### 2. 清空日志并测试

```powershell
adb logcat -c
# 在 App 中解压 Needpwds.7z（输入密码）
adb logcat -d | Select-String -Pattern "ArchiveWrapper|libarchive|password"
```

### 3. 预期日志（修复后）

```
D ArchiveWrapper: [Native] Archive format: 7-Zip           ← 能识别格式！
D ArchiveWrapper: [Native] passphrase_callback called      ← 密码回调被调用！
D ArchiveWrapper: [Native] Password provided: <masked>
I ArchiveService: 解压成功: X 个文件
```

---

## 常见问题

### Q1: CMake 找不到 OpenSSL

**方案 A（NDK OpenSSL）**：
- 确保 NDK 版本 ≥ 23（OpenSSL 1.1.1 内置）
- 路径：`$NDK/toolchains/llvm/prebuilt/windows-x86_64/sysroot/usr/lib/aarch64-linux-android/libcrypto.so`

**方案 B（vcpkg）**：
```powershell
# 明确指定路径
-DOPENSSL_ROOT_DIR="C:/dev/vcpkg/installed/arm64-android"
-DOPENSSL_INCLUDE_DIR="C:/dev/vcpkg/installed/arm64-android/include"
```

### Q2: 编译后仍然无法识别加密 7z

**可能原因**：
1. 使用了错误的 libarchive 版本（< 3.3）
   ```powershell
   # 检查版本
   strings libarchive.so | Select-String -Pattern "libarchive [0-9]"
   ```

2. 7z 文件使用了不支持的加密算法
   ```powershell
   # 在 PC 上验证
   7z l Needpwds.7z
   # 查看输出中的 "Method" 字段
   ```

3. libarchive 的 7z 模块有 bug（需要更新到最新版本）

### Q3: APK 体积增大多少？

- **方案 A（动态链接 NDK OpenSSL）**：+0 KB（系统已有）
- **方案 B（静态链接 vcpkg OpenSSL）**：+1.5 MB（包含完整 OpenSSL）

推荐方案 A！

### Q4: 是否需要同时支持 mbedTLS？

**不需要**。只需要其中一个加密库：
- OpenSSL ✅（推荐，兼容性好）
- mbedTLS（更小，但可能有兼容性问题）
- Nettle（不推荐）

---

## 参考文档

- [libarchive 官方文档](https://www.libarchive.org/)
- [FIX_ENCRYPTED_7Z.md](./FIX_ENCRYPTED_7Z.md) - 原始问题分析
- [7Z_PASSWORD_CHECKLIST.md](./7Z_PASSWORD_CHECKLIST.md) - 密码处理检查清单
- [Android NDK OpenSSL](https://developer.android.com/ndk/guides/stable_apis#libcrypto)

---

## 完整脚本（一键编译）

```powershell
# === 配置 ===
$NDK = "C:\Users\rli\AppData\Local\Android\Sdk\ndk\27.0.12077973"
$LIBARCHIVE_SRC = "C:\dev\libarchive"
$PROJECT_ROOT = "C:\dev\flutter\easyfile"
$TOOLCHAIN = "$NDK\toolchains\llvm\prebuilt\windows-x86_64"
$SYSROOT = "$TOOLCHAIN\sysroot"

# === 编译 arm64-v8a ===
Write-Host "编译 arm64-v8a..." -ForegroundColor Cyan
cd $LIBARCHIVE_SRC
Remove-Item build-android-arm64 -Recurse -Force -ErrorAction SilentlyContinue
New-Item build-android-arm64 -ItemType Directory | Out-Null
cd build-android-arm64

cmake .. `
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" `
  -DANDROID_ABI=arm64-v8a `
  -DANDROID_PLATFORM=android-24 `
  -DCMAKE_BUILD_TYPE=Release `
  -DBUILD_SHARED_LIBS=ON `
  -DENABLE_BZ2=ON `
  -DENABLE_LZMA=ON `
  -DENABLE_ZLIB=ON `
  -DENABLE_OPENSSL=ON `
  -DOPENSSL_INCLUDE_DIR="$SYSROOT/usr/include" `
  -DOPENSSL_CRYPTO_LIBRARY="$SYSROOT/usr/lib/aarch64-linux-android/libcrypto.so"

cmake --build . --config Release -j8

# === 编译 armeabi-v7a ===
Write-Host "编译 armeabi-v7a..." -ForegroundColor Cyan
cd $LIBARCHIVE_SRC
Remove-Item build-android-arm -Recurse -Force -ErrorAction SilentlyContinue
New-Item build-android-arm -ItemType Directory | Out-Null
cd build-android-arm

cmake .. `
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" `
  -DANDROID_ABI=armeabi-v7a `
  -DANDROID_PLATFORM=android-24 `
  -DCMAKE_BUILD_TYPE=Release `
  -DBUILD_SHARED_LIBS=ON `
  -DENABLE_BZ2=ON `
  -DENABLE_LZMA=ON `
  -DENABLE_ZLIB=ON `
  -DENABLE_OPENSSL=ON `
  -DOPENSSL_INCLUDE_DIR="$SYSROOT/usr/include" `
  -DOPENSSL_CRYPTO_LIBRARY="$SYSROOT/usr/lib/arm-linux-androideabi/libcrypto.so"

cmake --build . --config Release -j8

# === 复制到项目 ===
Write-Host "复制 libarchive.so 到项目..." -ForegroundColor Cyan
Copy-Item "$LIBARCHIVE_SRC\build-android-arm64\libarchive\libarchive.so" `
          "$PROJECT_ROOT\android\src\main\jniLibs\arm64-v8a\libarchive.so" -Force
Copy-Item "$LIBARCHIVE_SRC\build-android-arm\libarchive\libarchive.so" `
          "$PROJECT_ROOT\android\src\main\jniLibs\armeabi-v7a\libarchive.so" -Force

# === 验证 ===
Write-Host "验证 libarchive.so 依赖..." -ForegroundColor Cyan
& "$TOOLCHAIN\bin\llvm-readelf.exe" -d `
  "$PROJECT_ROOT\android\src\main\jniLibs\arm64-v8a\libarchive.so" | Select-String "NEEDED"

Write-Host "`n完成！现在可以编译 Flutter APK 了。" -ForegroundColor Green
Write-Host "运行: cd $PROJECT_ROOT; flutter build apk --debug" -ForegroundColor Yellow
```

保存为 `build_libarchive_with_openssl.ps1` 然后运行：
```powershell
.\build_libarchive_with_openssl.ps1
```
