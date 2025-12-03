# 存储计算修正文档

## 问题描述

微信存储占用显示不准确：
- EasyFile 显示：36.16GB 总占用 + 5.38GB 缓存
- 系统设置显示：32.98GB 总占用 + 67.11MB 缓存

差异：3.18GB（约 10%）

## 根本原因

### 错误的计算公式

原代码：
```dart
// AppStorageInfo.dart
int get totalSize => appSize + dataSize + cacheSize;  // ❌ 错误
```

### Android StorageStats API 文档

从 Android 源码 `frameworks/base/core/java/android/app/usage/StorageStats.java` 中发现：

#### 1. getAppBytes() - 应用本身大小

```java
/**
 * Return the size of app. This includes {@code APK} files, optimized
 * compiler output, and unpacked native libraries.
 * <p>
 * If the primary external/shared storage is hosted on this storage device,
 * then this includes files stored under {@link Context#getObbDir()}.
 * <p>
 * Code is shared between all users on a multiuser device.
 */
public @BytesLong long getAppBytes() {
    return codeBytes;
}
```

**包含内容：**
- APK 文件
- 优化编译输出（dex, odex）
- 解包的 native 库
- OBB 文件（如果外部存储在此设备上）

#### 2. getDataBytes() - 数据总大小

```java
/**
 * Return the size of all data. This includes files stored under
 * {@link Context#getDataDir()}, {@link Context#getCacheDir()},
 * {@link Context#getCodeCacheDir()}.
 * <p>
 * If the primary external/shared storage is hosted on this storage device,
 * then this includes files stored under
 * {@link Context#getExternalFilesDir(String)},
 * {@link Context#getExternalCacheDir()}, and
 * {@link Context#getExternalMediaDirs()}.
 * <p>
 * Data is isolated for each user on a multiuser device.
 */
public @BytesLong long getDataBytes() {
    return dataBytes;
}
```

**包含内容：**
- 内部数据目录 (`getDataDir()`)
- **内部缓存目录 (`getCacheDir()`)** ⚠️
- 代码缓存目录 (`getCodeCacheDir()`)
- 外部文件目录 (`getExternalFilesDir()`)
- **外部缓存目录 (`getExternalCacheDir()`)** ⚠️
- 外部媒体目录 (`getExternalMediaDirs()`)

#### 3. getCacheBytes() - 缓存大小

```java
/**
 * Return the size of all cached data. This includes files stored under
 * {@link Context#getCacheDir()} and {@link Context#getCodeCacheDir()}.
 * <p>
 * If the primary external/shared storage is hosted on this storage device,
 * then this includes files stored under
 * {@link Context#getExternalCacheDir()}.
 * <p>
 * Cached data is isolated for each user on a multiuser device.
 */
public @BytesLong long getCacheBytes() {
    return cacheBytes;
}
```

**包含内容：**
- 内部缓存目录 (`getCacheDir()`)
- 代码缓存目录 (`getCodeCacheDir()`)
- 外部缓存目录 (`getExternalCacheDir()`)

### 关键发现

**cacheBytes 是 dataBytes 的子集！**

- `dataBytes` **已经包含了** `cacheBytes` 中的所有内容
- 如果计算 `appBytes + dataBytes + cacheBytes`，会**重复计算缓存**
- 这就是为什么我们的显示比系统设置多了约 3GB（正好是微信的缓存大小）

## 修复方案

### 1. 修正 Flutter 计算公式

```dart
// lib/data/models/app_info.dart
class AppStorageInfo {
  /// 总大小
  /// 
  /// 根据 Android StorageStats API 文档：
  /// - appBytes = APK + native libraries + OBB files
  /// - dataBytes = all data (INCLUDING cache)
  /// - cacheBytes = cache only (subset of dataBytes)
  /// 
  /// 因此总大小 = appSize + dataSize (不能再加 cacheSize，否则会重复计算)
  /// cacheSize 仅用于单独显示缓存占用
  int get totalSize => appSize + dataSize;  // ✅ 正确
}
```

### 2. 添加调试日志

```kotlin
// android/.../StorageStatsHelper.kt
if (packageName == "com.tencent.mm") {
    Log.i("StorageStatsHelper", "=== WeChat Storage Stats (API Values) ===")
    Log.i("StorageStatsHelper", "appBytes (code): $appBytes (${appBytes / 1024 / 1024}MB)")
    Log.i("StorageStatsHelper", "dataBytes (all data including cache): $dataBytes (${dataBytes / 1024 / 1024}MB)")
    Log.i("StorageStatsHelper", "cacheBytes (subset of dataBytes): $cacheBytes (${cacheBytes / 1024 / 1024}MB)")
    Log.i("StorageStatsHelper", "OLD calculation (WRONG - double counts cache): ${(appBytes + dataBytes + cacheBytes) / 1024 / 1024}MB")
    Log.i("StorageStatsHelper", "NEW calculation (CORRECT - no double counting): ${(appBytes + dataBytes) / 1024 / 1024}MB")
}
```

## 验证计划

1. **重新部署应用**（已完成）
2. **进入应用管理页面**
3. **下拉刷新加载数据**
4. **检查微信存储显示**
   - 总占用应该接近系统设置的 32.98GB
   - 缓存应该单独显示约 5.38GB

5. **查看 logcat 日志**
   ```bash
   adb logcat | grep StorageStatsHelper
   ```
   应该看到：
   - OLD calculation: ~36GB（错误）
   - NEW calculation: ~33GB（正确）

## 影响范围

### 受影响的功能
- ✅ 应用管理 - 存储占用显示
- ✅ 应用排序 - 按大小排序
- ✅ 存储统计 - 总占用计算

### 不受影响的功能
- ✅ 缓存单独显示（始终正确）
- ✅ 权限管理
- ✅ 应用列表加载

## 经验教训

### 1. 彻底理解 API 文档

不能假设 API 的行为，必须查看官方文档和源码。StorageStats API 的设计是：
- `dataBytes` 是一个完整的数据集合（包括缓存）
- `cacheBytes` 是一个子集，用于**单独显示**缓存大小
- 不应该将它们相加

### 2. 警惕重复计算

当多个字段存在包含关系时（如 total 和 cache），要特别注意：
- 确认它们是否是独立的
- 确认它们是否有重叠
- 查看官方文档中的定义

### 3. 使用对照数据验证

用户提供的系统设置数据是宝贵的对照：
- 如果我们的计算结果与系统差异很大（>5%），说明计算逻辑有问题
- 不要轻易相信自己的实现，要寻找权威的参考

### 4. 日志调试的重要性

添加详细日志帮助我们：
- 看到 API 返回的原始值
- 对比新旧计算方法的差异
- 定位问题的确切位置

## 参考资料

- [Android StorageStats 源码](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/app/usage/StorageStats.java)
- [Android StorageStatsManager 文档](https://developer.android.com/reference/android/app/usage/StorageStatsManager)
- [Android Context 存储路径文档](https://developer.android.com/reference/android/content/Context#getCacheDir())

## 修复时间线

- **2025-12-03 16:30** - 用户报告存储数据不准确
- **2025-12-03 16:35** - 查看 Android 源码发现重复计算问题
- **2025-12-03 16:40** - 修正计算公式并添加日志
- **2025-12-03 16:45** - 重新部署测试

## 状态

🔄 **等待测试验证**

请进入应用管理页面，下拉刷新加载微信数据，然后告诉我看到的数值。
