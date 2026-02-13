# libarchive 预编译库配置指南

**目标**: 为 EasyFile Android 应用获取 libarchive 预编译库

---

## 🎯 方案概览

| 方案 | 难度 | 时间 | 推荐度 |
|------|------|------|--------|
| **方案 1: Docker 构建** | ⭐⭐ | 30分钟 | ⭐⭐⭐⭐⭐ |
| **方案 2: Conan 包管理器** | ⭐⭐ | 20分钟 | ⭐⭐⭐⭐ |
| **方案 3: 从 GitHub Releases 下载** | ⭐ | 10分钟 | ⭐⭐⭐ |
| **方案 4: 手动 NDK 编译** | ⭐⭐⭐⭐⭐ | 2-3小时 | ⭐⭐ |

---

## 📦 方案 1: Docker 构建（推荐）

### 前提条件
- 安装 Docker Desktop

### 步骤

1. **拉取 Android NDK Docker 镜像**
   ```bash
   docker pull thyrlian/android-sdk
   ```

2. **运行构建脚本**
   ```bash
   cd scripts
   docker run --rm -v ${PWD}/..:/workspace thyrlian/android-sdk bash -c "cd /workspace && ./scripts/build_libarchive_docker.sh"
   ```

3. **验证输出**
   ```bash
   ls android/src/main/jniLibs/arm64-v8a/libarchive.so
   ```

### 优势
- ✅ 环境隔离，不污染本地
- ✅ 自动化程度高
- ✅ 可重复构建

---

## 📦 方案 2: Conan 包管理器

### 前提条件
```bash
pip install conan
```

### 步骤

1. **创建 Conan profile**
   ```bash
   # ARM64
   conan profile detect --name android-arm64
   conan profile update settings.os=Android android-arm64
   conan profile update settings.arch=armv8 android-arm64
   
   # ARMv7
   conan profile detect --name android-armv7
   conan profile update settings.os=Android android-armv7
   conan profile update settings.arch=armv7 android-armv7
   ```

2. **下载预编译包**
   ```bash
   conan install --requires=libarchive/3.7.2 --profile=android-arm64
   ```

3. **提取 .so 文件**
   ```bash
   cp ~/.conan2/p/*/p/lib/libarchive.so android/src/main/jniLibs/arm64-v8a/
   ```

4. **重复其他 ABI**

---

## 📦 方案 3: 从 GitHub Releases 下载

### 直接下载链接

某些开源项目提供预编译的 Android 库：

1. **Termux Packages**
   ```bash
   # ARM64
   wget https://packages.termux.dev/apt/termux-main/pool/main/liba/libarchive/libarchive_3.7.2_aarch64.deb
   ar x libarchive_3.7.2_aarch64.deb
   tar xf data.tar.xz
   cp data/data/com.termux/files/usr/lib/libarchive.so android/src/main/jniLibs/arm64-v8a/
   ```

2. **或使用提供的脚本**
   ```powershell
   .\scripts\download_from_termux.ps1
   ```

---

## 📦 方案 4: 手动 NDK 编译

### 前提条件
- Android NDK (r25c+)
- CMake 3.22+

### 步骤

1. **下载 libarchive 源码**
   ```bash
   wget https://github.com/libarchive/libarchive/releases/download/v3.7.2/libarchive-3.7.2.tar.gz
   tar -xzf libarchive-3.7.2.tar.gz
   cd libarchive-3.7.2
   ```

2. **编译 ARM64**
   ```bash
   mkdir build-arm64 && cd build-arm64
   cmake .. \
       -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
       -DANDROID_ABI=arm64-v8a \
       -DANDROID_PLATFORM=android-21 \
       -DCMAKE_BUILD_TYPE=Release \
       -DENABLE_OPENSSL=OFF \
       -DENABLE_EXPAT=OFF \
       -DENABLE_XML2=OFF \
       -DBUILD_SHARED_LIBS=ON
   make -j8
   ```

3. **复制到项目**
   ```bash
   cp libarchive/libarchive.so $PROJECT_ROOT/android/src/main/jniLibs/arm64-v8a/
   ```

4. **重复其他 ABI** (armeabi-v7a, x86, x86_64)

---

## 🔍 验证安装

运行验证脚本：
```powershell
.\scripts\download_libarchive.ps1
```

输出应显示：
```
✓ 找到: arm64-v8a/libarchive.so (1234 KB)
✓ 找到: armeabi-v7a/libarchive.so (1100 KB)
✓ 找到: x86/libarchive.so (1300 KB)
✓ 找到: x86_64/libarchive.so (1350 KB)
```

---

## 🚀 快速开始（临时方案）

如果您只是想快速测试 FFI 迁移，可以暂时只支持 ZIP：

```powershell
# 使用轻量级 miniz 库代替 libarchive
.\scripts\setup_miniz.ps1
```

这将：
- 下载 miniz.c (单文件 ZIP 库)
- 修改 C 代码使用 miniz API
- 仅支持 ZIP 格式，但编译快速

待测试通过后，再切换回完整的 libarchive。

---

## 📋 所需文件清单

最终目录结构应为：
```
android/src/main/jniLibs/
├── arm64-v8a/
│   └── libarchive.so      (1.2-1.5 MB)
├── armeabi-v7a/
│   └── libarchive.so      (1.0-1.3 MB)
├── x86/
│   └── libarchive.so      (1.3-1.6 MB)
└── x86_64/
    └── libarchive.so      (1.3-1.6 MB)
```

---

## ❓ 常见问题

### Q: 可以只编译一个 ABI 吗？
A: 可以。开发阶段可以只编译 arm64-v8a（最常用）。发布时需要全部 ABI。

### Q: 文件太大怎么办？
A: libarchive 可以配置为仅支持特定格式，减小体积。或使用 miniz（仅 ZIP）。

### Q: 找不到 NDK 怎么办？
A: 在 Android Studio > SDK Manager > SDK Tools 中安装 NDK。

---

## 📞 需要帮助？

如果遇到问题，请：
1. 查看 `docs/ARCHIVE_FFI_MIGRATION_STATUS.md`
2. 运行 `.\scripts\download_libarchive.ps1` 诊断
3. 参考 libarchive 官方文档：https://libarchive.org/

---

**最后更新**: 2026-01-12
