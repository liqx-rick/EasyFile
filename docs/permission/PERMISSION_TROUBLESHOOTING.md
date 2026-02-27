# 权限问题排查和解决方案

## 问题描述
点击"授予权限"按钮后，系统没有弹出权限请求对话框。

日志显示：
```
D/permissions_handler(10074): No permissions found in manifest for: []9
D/permissions_handler(10074): No permissions found in manifest for: []32
I/flutter (10074): [WARN] PermissionService: Permission denied
```

## 根本原因
AndroidManifest.xml 中缺少 Android 13+ (API 33+) 的分离媒体权限声明。

## 已修复的内容

### 1. 更新 AndroidManifest.xml
添加了 Android 13+ 的分离媒体权限：

```xml
<!-- Android 13+ (API 33+) 分离媒体权限 -->
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
```

同时为旧版本权限添加了 `maxSdkVersion` 限制：
```xml
<!-- 存储权限 (Android 12 及以下) -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" 
    android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" 
    android:maxSdkVersion="32" />
```

## 测试步骤

### 1. 清理并重新构建
```bash
cd c:\dev\flutter\easyfile
flutter clean
flutter pub get
flutter build apk --debug
# 或者直接运行
flutter run
```

### 2. 卸载旧应用
**重要**：必须完全卸载旧版本，否则权限声明不会更新！

在模拟器或设备上：
```bash
adb uninstall com.example.easyfile
```

或手动长按应用图标 → 卸载

### 3. 安装新版本
```bash
flutter install
```

### 4. 测试权限流程
1. 启动应用（首次启动会在 Splash 显示系统权限弹窗）
2. 如果拒绝权限，主页会显示空状态引导
3. 点击"授予权限"按钮
4. 应该弹出系统权限对话框，选择以下选项之一：
   - **允许访问所有媒体** (推荐)
   - 仅此一次
   - 拒绝

## Android 版本适配说明

### Android 12 及以下 (API ≤ 32)
使用传统存储权限：
- `READ_EXTERNAL_STORAGE`
- `WRITE_EXTERNAL_STORAGE`

### Android 13+ (API 33+)
使用分离媒体权限：
- `READ_MEDIA_IMAGES` - 读取图片
- `READ_MEDIA_VIDEO` - 读取视频
- `READ_MEDIA_AUDIO` - 读取音频

我们的代码同时声明了两套权限，系统会根据 Android 版本自动选择合适的权限类型。

## 权限逻辑说明

### PermissionService 检查逻辑
```dart
// 检查存储权限
final storageStatus = await Permission.storage.status;

// Android 13+ 需要额外检查媒体权限
final photosStatus = await Permission.photos.status;
final videosStatus = await Permission.videos.status;

// 判断整体权限状态
if (storageStatus.isGranted ||
    (photosStatus.isGranted && videosStatus.isGranted)) {
  // 有权限
}
```

### 权限请求逻辑
```dart
// 请求存储权限
final storageStatus = await Permission.storage.request();

// Android 13+ 请求媒体权限
final photosStatus = await Permission.photos.request();
final videosStatus = await Permission.videos.request();
```

## 预期行为

### 情况 1：Android 12 及以下
- 弹出传统存储权限对话框
- 选项：允许 / 拒绝

### 情况 2：Android 13+
- 弹出新的媒体权限对话框
- 选项：
  - ✅ 允许访问所有媒体
  - 🔒 选择部分媒体
  - ❌ 拒绝

### 情况 3：永久拒绝后
- 应用显示"前往设置"按钮
- 点击后打开系统设置页面
- 用户可以在"权限"部分手动开启

## 调试命令

### 查看当前权限状态
```bash
adb shell dumpsys package com.example.easyfile | Select-String "permission"
```

### 重置应用权限
```bash
adb shell pm reset-permissions com.example.easyfile
```

### 手动授予权限（测试用）
```bash
# Android 12 及以下
adb shell pm grant com.example.easyfile android.permission.READ_EXTERNAL_STORAGE
adb shell pm grant com.example.easyfile android.permission.WRITE_EXTERNAL_STORAGE

# Android 13+
adb shell pm grant com.example.easyfile android.permission.READ_MEDIA_IMAGES
adb shell pm grant com.example.easyfile android.permission.READ_MEDIA_VIDEO
adb shell pm grant com.example.easyfile android.permission.READ_MEDIA_AUDIO
```

## 验证清单

- [x] AndroidManifest.xml 已更新
- [x] 添加了 Android 13+ 权限声明
- [x] 旧版本权限添加了 maxSdkVersion
- [ ] 执行 `flutter clean`
- [ ] 卸载旧版本应用
- [ ] 重新安装应用
- [ ] 测试权限请求流程
- [ ] 验证文件扫描功能

## 如果问题仍然存在

### 1. 检查 build.gradle 配置
确保 `minSdkVersion` 和 `targetSdkVersion` 正确：
```kotlin
defaultConfig {
    minSdk = 21  // 最低支持 Android 5.0
    targetSdk = 34  // 或更高
}
```

### 2. 检查 permission_handler 版本
确保使用最新版本：
```yaml
dependencies:
  permission_handler: ^12.0.1  # 或更新版本
```

### 3. 查看完整日志
```bash
flutter run --verbose
```

查找包含以下关键词的日志：
- `permission_handler`
- `AndroidManifest`
- `READ_MEDIA`
- `EXTERNAL_STORAGE`

### 4. 检查模拟器 Android 版本
```bash
adb shell getprop ro.build.version.sdk
```

输出说明：
- `32` = Android 12
- `33` = Android 13
- `34` = Android 14
- `36` = Android 16 (Beta)

## 参考资料

- [permission_handler 文档](https://pub.dev/packages/permission_handler)
- [Android 13 权限变更](https://developer.android.com/about/versions/13/behavior-changes-13#granular-media-permissions)
- [Android 存储权限指南](https://developer.android.com/training/data-storage)

---

**重要提示**：修改 AndroidManifest.xml 后，必须卸载旧应用并重新安装，否则权限声明不会生效！
