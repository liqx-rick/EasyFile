# 权限流程修复 - 完整访问权限支持

## 修复日期
2025-11-19

## 修复的问题

### 问题 1：授予权限后未触发文件扫描
**原因**：用户从系统设置返回应用时，应用没有重新检查权限状态。

**解决方案**：
- 在 `didChangeAppLifecycleState` 中添加 `AppLifecycleState.resumed` 监听
- 当应用从后台恢复时，自动重新检查权限
- 如果权限状态从"拒绝"变为"已授权"，自动触发文件扫描

### 问题 2：访问系统文件夹需要额外权限
**原因**：Android 11+ 引入了 `MANAGE_EXTERNAL_STORAGE` 权限（"All files access"），普通存储权限无法访问某些系统目录。

**解决方案**：
- 在 `PermissionService` 中添加 `Permission.manageExternalStorage` 检查
- 优先请求完整文件访问权限
- 如果用户不授予完整权限，降级使用媒体权限

## 核心修改

### 1. PermissionService 增强

#### checkPermission() 方法
```dart
// 首先检查 MANAGE_EXTERNAL_STORAGE (最高权限)
final manageStorageStatus = await Permission.manageExternalStorage.status;

if (manageStorageStatus.isGranted) {
  // 有完整文件访问权限
  _setState(PermissionState.granted);
} else if (storageStatus.isGranted || 
    (photosStatus.isGranted && videosStatus.isGranted)) {
  // 有基本存储/媒体权限
  _setState(PermissionState.granted);
}
```

#### requestPermission() 方法
```dart
// 先尝试请求完整文件访问权限
final manageStorageStatus = await Permission.manageExternalStorage.request();

if (manageStorageStatus.isGranted) {
  // 获得完整访问权限，直接返回
  return PermissionState.granted;
}

// 否则请求基本存储权限
// ...
```

### 2. FileBrowserPage 生命周期监听

新增 `_checkPermissionAfterResume()` 方法：

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    _checkPermissionAfterResume();
  }
}

Future<void> _checkPermissionAfterResume() async {
  // 如果当前是无权限状态，重新检查
  if (_permissionState != PermissionState.granted) {
    final newState = await _permissionService.checkPermission();
    
    if (newState.isGranted && newState != _permissionState) {
      // 权限状态改变为已授权，开始初始化
      setState(() {
        _permissionState = newState;
      });
      await _initializeApp();
    }
  }
}
```

### 3. SplashPresenter 权限请求更新

```dart
// 首先请求 MANAGE_EXTERNAL_STORAGE
final manageStorageStatus = await Permission.manageExternalStorage.status;
if (manageStorageStatus.isDenied) {
  Permission.manageExternalStorage.request();
}
```

### 4. 空状态提示文案优化

更新了 `EmptyStatePermission` 的说明文字：
- 未授权状态：建议选择"允许访问所有媒体"
- 永久拒绝状态：引导打开"允许管理所有文件"开关

## 权限层级说明

### Android 权限层级（从高到低）

1. **MANAGE_EXTERNAL_STORAGE** (完整文件访问)
   - 显示为："All files access" / "所有文件访问"
   - 需要用户在特殊设置页面手动开启
   - 可以访问所有文件和目录
   - 适用于文件管理器应用

2. **READ_MEDIA_* 权限** (Android 13+ 媒体权限)
   - `READ_MEDIA_IMAGES` - 图片
   - `READ_MEDIA_VIDEO` - 视频
   - `READ_MEDIA_AUDIO` - 音频
   - 只能访问媒体文件，无法访问文档和系统目录

3. **READ_EXTERNAL_STORAGE** (Android 12 及以下)
   - 传统存储权限
   - 可以访问外部存储的大部分内容

## 用户体验流程

### 场景 1：首次启动并授予完整权限
```
1. Splash 弹出权限对话框
2. 用户点击"允许"
3. 系统跳转到 "All files access" 设置页面
4. 用户打开开关
5. 返回应用 → 自动触发扫描 → 显示文件
```

### 场景 2：首次启动拒绝权限
```
1. Splash 弹出权限对话框
2. 用户点击"拒绝"
3. 进入主页 → 显示空状态引导
4. 用户点击"授予权限"按钮
5. 再次弹出权限对话框
6. 用户选择"允许访问所有媒体"
7. 自动开始扫描 → 显示文件
```

### 场景 3：访问系统文件夹被拒绝
```
1. 用户已有媒体权限，但未授予完整文件访问
2. 访问系统目录时触发 "All files access" 请求
3. 用户跳转到设置页面
4. 打开开关后返回应用
5. 应用自动检测权限变化 → 刷新文件列表
```

## 测试验证

### 测试步骤

1. **卸载旧版本并重新安装**
   ```bash
   flutter clean
   flutter run
   ```

2. **测试完整权限流程**
   - [ ] 首次启动拒绝权限 → 显示空状态
   - [ ] 点击"授予权限" → 弹出对话框
   - [ ] 选择"允许访问所有媒体" → 自动扫描
   - [ ] 验证文件列表显示正常

3. **测试生命周期恢复**
   - [ ] 进入应用（空状态）
   - [ ] 手动进入系统设置 → 授予权限
   - [ ] 返回应用 → 自动检测并开始扫描

4. **测试完整文件访问**
   - [ ] 尝试访问系统目录（如 /storage/emulated/0/Android/data）
   - [ ] 触发 "All files access" 请求
   - [ ] 授权后验证可以访问

## 日志关键点

权限检查时的日志输出：

```
[DEBUG] PermissionService: Checking permission status...
[DEBUG] Permission status - manage: granted, storage: granted, photos: granted, videos: granted
[INFO] PermissionService: Permission state: granted
```

生命周期恢复时的日志：

```
[DEBUG] FileBrowserPage: App lifecycle changed to resumed
[INFO] App resumed, rechecking permission...
[INFO] Permission granted after resume, initializing...
[INFO] Initializing app data...
```

## 注意事项

### 1. MANAGE_EXTERNAL_STORAGE 的限制
- 需要在 Google Play 提交时说明用途
- 某些应用类型可能不被批准使用此权限
- 用户可以随时在设置中撤销

### 2. 权限请求时机
- Splash 阶段：尝试请求所有权限
- 主页阶段：根据实际需求请求
- 访问特定目录时：按需请求

### 3. 降级方案
如果用户不授予完整文件访问权限：
- 仍可正常浏览媒体文件
- 访问受限目录时会提示权限不足
- 引导用户授予更高权限

## 相关文件

- `lib/core/services/permission_service.dart` - 权限管理服务
- `lib/ui/pages/file_browser_page.dart` - 主页面生命周期处理
- `lib/presenter/splash_presenter.dart` - 启动时权限请求
- `lib/ui/widgets/empty_state_permission.dart` - 空状态引导
- `android/app/src/main/AndroidManifest.xml` - 权限声明

## 参考资料

- [MANAGE_EXTERNAL_STORAGE 权限](https://developer.android.com/training/data-storage/manage-all-files)
- [Android 存储权限最佳实践](https://developer.android.com/training/data-storage)
- [permission_handler 插件文档](https://pub.dev/packages/permission_handler)

---

**测试建议**：卸载旧版本后重新安装，完整测试从"拒绝权限"到"授予权限"的整个流程。
