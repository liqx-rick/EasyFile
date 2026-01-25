# libarchive 静态链接编译指南

## 问题背景

当前编译的 libarchive.so 动态链接了 libbz2.so、liblzma.so 等库，导致运行时错误：
```
dlopen failed: library "libbz2.so" not found
```

**解决方案**：静态链接所有依赖库到 libarchive.so 中。

---

## 编译环境要求

- **Android NDK**: r21+（已安装在 `C:\Users\xxx\AppData\Local\Android\Sdk\ndk\27.0.12077973`）
- **CMake**: 3.18+
- **工具**: Git, Python 3.6+

---

## 方法1：使用 vcpkg（推荐 - 最简单）

### 步骤1：安装 vcpkg

```bash
# Windows PowerShell
cd C:\dev
git clone https://github.com/microsoft/vcpkg.git
cd vcpkg
.\bootstrap-vcpkg.bat
```

### 步骤2：安装静态依赖库（Android版本）

```bash
# 设置 NDK 路径
$env:ANDROID_NDK_HOME = "C:\Users\rli\AppData\Local\Android\Sdk\ndk\27.0.12077973"

# 安装静态库（每个ABI需要分别编译）
.\vcpkg install bzip2:arm64-android --triplet=arm64-android
.\vcpkg install liblzma:arm64-android --triplet=arm64-android
.\vcpkg install lz4:arm64-android --triplet=arm64-android
.\vcpkg install zstd:arm64-android --triplet=arm64-android
.\vcpkg install zlib:arm64-android --triplet=arm64-android

# 重复以上步骤，替换为 arm-android（armeabi-v7a）
```

### 步骤3：编译 libarchive

```bash
cd C:\dev
git clone https://github.com/libarchive/libarchive.git
cd libarchive
git checkout v3.8.1

# 创建构建目录
mkdir build-android-arm64
cd build-android-arm64

# CMake 配置（静态链接 + 加密支持）
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$env:ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DENABLE_BZ2=ON \
  -DENABLE_LZMA=ON \
  -DENABLE_LZ4=ON \
  -DENABLE_ZSTD=ON \
  -DENABLE_ZLIB=ON \
  -DENABLE_OPENSSL=ON \
  -DENABLE_MBEDTLS=ON \
  -DENABLE_NETTLE=ON \
  -DENABLE_CNG=OFF \
  -DBZIP2_LIBRARIES=C:/dev/vcpkg/installed/arm64-android/lib/libbz2.a \
  -DLIBLZMA_LIBRARIES=C:/dev/vcpkg/installed/arm64-android/lib/liblzma.a \
  -DLZ4_LIBRARIES=C:/dev/vcpkg/installed/arm64-android/lib/liblz4.a \
  -DZSTD_LIBRARIES=C:/dev/vcpkg/installed/arm64-android/lib/libzstd.a \
  -DZLIB_LIBRARIES=C:/dev/vcpkg/installed/arm64-android/lib/libz.a \
  -DOPENSSL_ROOT_DIR=C:/dev/vcpkg/installed/arm64-android

# 注意：加密支持需要以下任一库
# - OpenSSL (推荐，Android NDK 已包含)
# - mbedTLS
# - Nettle
# 至少启用一个以支持加密 7z/RAR

# 编译
cmake --build . --config Release

# 结果：libarchive.so（包含所有依赖）
```

### 步骤4：验证静态链接

```bash
# 检查依赖（应该只看到系统库）
$env:ANDROID_NDK_HOME\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe -d libarchive.so

# 预期输出（不包含 libbz2.so, liblzma.so 等）：
# NEEDED libc.so
# NEEDED libm.so
# NEEDED libdl.so
```

### 步骤5：复制到项目

```bash
# 复制编译好的库
Copy-Item "build-android-arm64\libarchive\libarchive.so" \
          "C:\dev\flutter\easyfile\android\src\main\jniLibs\arm64-v8a\libarchive.so"

# 重复步骤3-5，为 armeabi-v7a 编译
```

---

## 方法2：手动编译依赖（复杂但可控）

### 步骤1：编译 bzip2 静态库

```bash
cd C:\dev
git clone https://gitlab.com/bzip2/bzip2.git
cd bzip2

# 为 arm64-v8a 编译
mkdir build-android-arm64
cd build-android-arm64

cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$env:ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF

cmake --build . --config Release
# 输出：libbz2.a
```

### 步骤2：编译 liblzma 静态库

```bash
cd C:\dev
git clone https://github.com/tukaani-project/xz.git
cd xz

mkdir build-android-arm64
cd build-android-arm64

cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$env:ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF

cmake --build . --config Release
# 输出：liblzma.a
```

### 步骤3：编译 lz4 静态库

```bash
cd C:\dev
git clone https://github.com/lz4/lz4.git
cd lz4\build\cmake

mkdir build-android-arm64
cd build-android-arm64

cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$env:ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF

cmake --build . --config Release
# 输出：liblz4.a
```

### 步骤4：编译 zstd 静态库

```bash
cd C:\dev
git clone https://github.com/facebook/zstd.git
cd zstd\build\cmake

mkdir build-android-arm64
cd build-android-arm64

cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$env:ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DZSTD_BUILD_PROGRAMS=OFF \
  -DZSTD_BUILD_TESTS=OFF

cmake --build . --config Release
# 输出：libzstd.a
```

### 步骤5：编译 libarchive（链接静态库）

```bash
cd C:\dev\libarchive
mkdir build-android-arm64
cd build-android-arm64

cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$env:ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DENABLE_BZ2=ON \
  -DENABLE_LZMA=ON \
  -DENABLE_LZ4=ON \
  -DENABLE_ZSTD=ON \
  -DENABLE_ZLIB=ON \
  -DENABLE_ACL=OFF \
  -DENABLE_OPENSSL=OFF \
  -DENABLE_TAR=OFF \
  -DENABLE_CPIO=OFF \
  -DENABLE_CAT=OFF \
  -DENABLE_TEST=OFF \
  -DBZIP2_INCLUDE_DIR=C:/dev/bzip2/build-android-arm64 \
  -DBZIP2_LIBRARIES=C:/dev/bzip2/build-android-arm64/libbz2.a \
  -DLIBLZMA_INCLUDE_DIR=C:/dev/xz/src/liblzma/api \
  -DLIBLZMA_LIBRARIES=C:/dev/xz/build-android-arm64/src/liblzma/liblzma.a \
  -DLZ4_INCLUDE_DIR=C:/dev/lz4/lib \
  -DLZ4_LIBRARIES=C:/dev/lz4/build/cmake/build-android-arm64/liblz4.a \
  -DZSTD_INCLUDE_DIR=C:/dev/zstd/lib \
  -DZSTD_LIBRARIES=C:/dev/zstd/build/cmake/build-android-arm64/lib/libzstd.a

cmake --build . --config Release
```

---

## 方法3：使用预编译的静态库包（最快）

### 下载预编译静态库

```bash
# 从第三方仓库下载（例如 Android NDK 预编译包）
# 或者使用 Conan 包管理器

# Conan 方式
pip install conan

# 配置 Android profile
conan profile detect

# 安装依赖
conan install bzip2/1.0.8@ -pr:h=android-arm64 -s build_type=Release --build=missing
conan install xz_utils/5.4.5@ -pr:h=android-arm64 -s build_type=Release --build=missing
conan install lz4/1.9.4@ -pr:h=android-arm64 -s build_type=Release --build=missing
conan install zstd/1.5.5@ -pr:h=android-arm64 -s build_type=Release --build=missing
```

---

## 验证编译结果

### 检查符号是否完整

```bash
$nm = "$env:ANDROID_NDK_HOME\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-nm.exe"

# 检查 archive_write_disk 符号
& $nm "android\src\main\jniLibs\arm64-v8a\libarchive.so" | Select-String "write_disk"

# 预期输出：
# 0000000000096b40 T archive_write_disk_new
# 00000000000968fc T archive_write_disk_set_options
# ...
```

### 检查动态依赖

```bash
$readelf = "$env:ANDROID_NDK_HOME\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe"

# 检查依赖库
& $readelf -d "android\src\main\jniLibs\arm64-v8a\libarchive.so" | Select-String "NEEDED"

# 预期输出（不应包含 libbz2.so, liblzma.so 等）：
# NEEDED libc.so
# NEEDED libm.so
# NEEDED libdl.so
```

### 检查文件大小

```bash
Get-ChildItem "android\src\main\jniLibs\*\libarchive.so" | Select-Object Name, @{Name='Size(MB)';Expression={[math]::Round($_.Length/1MB, 2)}}

# 预期输出（静态链接后会更大）：
# arm64-v8a/libarchive.so: 6.5 MB （之前3.8MB）
# armeabi-v7a/libarchive.so: 4.8 MB （之前2.8MB）
```

---

## 常见问题

### Q1：编译时找不到依赖库？
**A**：确保静态库路径正确，使用绝对路径：
```cmake
-DBZIP2_LIBRARIES=C:/full/path/to/libbz2.a
```

### Q2：编译成功但运行时还是报错？
**A**：检查是否真的静态链接了：
```bash
llvm-readelf -d libarchive.so | findstr libbz2
# 如果有输出，说明还是动态链接
```

### Q3：需要为每个 ABI 单独编译吗？
**A**：是的，Android 需要：
- arm64-v8a（64位ARM）
- armeabi-v7a（32位ARM）

每个架构需要单独编译所有依赖和 libarchive。

### Q4：编译时间太长？
**A**：
1. 使用 `-j$(nproc)` 并行编译
2. 只编译 Release 版本
3. 禁用不需要的功能（`-DENABLE_TEST=OFF`）

### Q5：如何加快后续编译？
**A**：
1. 保留编译好的静态库（.a 文件）
2. 使用 CMake 缓存（`-C initial-cache.cmake`）
3. 考虑使用 Docker 镜像保存编译环境

---

## 快速验证脚本

将以下内容保存为 `scripts\verify_libarchive_static.ps1`：

```powershell
$ErrorActionPreference = "Stop"

$NDK = "$env:ANDROID_NDK_HOME"
if (-not $NDK) {
    $NDK = "C:\Users\$env:USERNAME\AppData\Local\Android\Sdk\ndk\27.0.12077973"
}

$READELF = "$NDK\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe"
$NM = "$NDK\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-nm.exe"

Write-Host "Verifying libarchive static linking..." -ForegroundColor Cyan

foreach ($abi in @("arm64-v8a", "armeabi-v7a")) {
    $lib = "android\src\main\jniLibs\$abi\libarchive.so"
    
    if (-not (Test-Path $lib)) {
        Write-Host "  ✗ $abi: File not found" -ForegroundColor Red
        continue
    }
    
    Write-Host "`n$abi:" -ForegroundColor Yellow
    
    # Check size
    $size = [math]::Round((Get-Item $lib).Length / 1MB, 2)
    Write-Host "  Size: $size MB" -ForegroundColor Gray
    
    # Check dynamic dependencies
    Write-Host "  Dynamic dependencies:" -ForegroundColor Gray
    $deps = & $READELF -d $lib | Select-String "NEEDED"
    $hasBadDeps = $false
    foreach ($dep in $deps) {
        $depName = $dep -replace '.*\[(.*?)\].*', '$1'
        if ($depName -match "bz2|lzma|lz4|zstd") {
            Write-Host "    ✗ $depName (should be static)" -ForegroundColor Red
            $hasBadDeps = $true
        } else {
            Write-Host "    ✓ $depName" -ForegroundColor Green
        }
    }
    
    # Check symbols
    $symbols = & $NM $lib | Select-String "archive_write_disk_new"
    if ($symbols) {
        Write-Host "  ✓ Symbols present" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Missing archive_write_disk symbols" -ForegroundColor Red
    }
    
    if (-not $hasBadDeps) {
        Write-Host "  ✓ Static linking verified" -ForegroundColor Green
    }
}

Write-Host "`nVerification complete!" -ForegroundColor Cyan
```

运行验证：
```bash
.\scripts\verify_libarchive_static.ps1
```

---

## 推荐方案总结

**如果你熟悉 C/C++ 编译**：
→ 使用方法2（手动编译）- 完全可控

**如果追求快速解决**：
→ 使用方法1（vcpkg）- 自动化程度高

**如果编译困难**：
→ 联系我，我可以帮你编译或提供预编译版本

---

## 下一步

完成编译后：

1. 替换 `android/src/main/jniLibs/` 下的 libarchive.so
2. 运行验证脚本
3. 编译 APK：`flutter build apk --debug`
4. 测试解压功能

需要帮助吗？告诉我你选择哪种编译方法！
