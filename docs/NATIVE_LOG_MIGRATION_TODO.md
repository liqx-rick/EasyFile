# 原生日志迁移清单

## 问题说明

Profile 模式下看到 DEBUG 日志的原因：**大部分原生代码仍在使用 `android.util.Log` 直接输出，没有使用 `LogHelper`**。

## 需要迁移的文件

### ✅ 已迁移
1. **MediaStoreScanner.kt** - MediaStore 扫描日志

### ⚠️ 待迁移（高优先级）

以下文件包含大量 `Log.d()` 调用，会在 Profile/Release 模式下泄露调试信息：

#### 1. MainActivity.kt
- **位置**: `android/app/src/main/kotlin/com/guangqi/easyfile/MainActivity.kt`
- **问题**: 包含大量 `Log.d()` 调用（约 20+ 处）
- **影响**: UsageStats 查询的详细调试信息会在 Profile 模式泄露
- **迁移状态**: 部分迁移（onCreate 部分已完成）

#### 2. MediaStoreTrashHelper.kt
- **位置**: `android/app/src/main/kotlin/com/guangqi/easyfile/MediaStoreTrashHelper.kt`
- **问题**: 包含大量 `Log.d()` 调试日志（约 15+ 处）
- **影响**: 回收站查询的详细信息会泄露
- **迁移状态**: 未迁移

#### 3. NewFilesNativeScanner.kt
- **位置**: `android/app/src/main/kotlin/com/guangqi/easyfile/NewFilesNativeScanner.kt`
- **问题**: 所有 `Log.i()/Log.d()/Log.e()` 调用
- **影响**: 新文件扫描信息会在 Profile 模式泄露
- **迁移状态**: 未迁移

#### 4. StorageStatsHelper.kt
- **位置**: `android/app/src/main/kotlin/com/guangqi/easyfile/StorageStatsHelper.kt`
- **问题**: 包含 WeChat 存储统计的详细 `Log.i()` 调用（7 处）
- **影响**: 应用存储数据会泄露
- **迁移状态**: 未迁移

#### 5. AppFileScanner.kt
- **位置**: `android/app/src/main/kotlin/com/guangqi/easyfile/AppFileScanner.kt`
- **问题**: 可能包含应用文件扫描日志
- **迁移状态**: 未检查

## 快速替换方法

### 方法1：使用 Android Studio（推荐）

1. 打开 Android Studio
2. 打开待迁移的文件
3. 使用 **Find & Replace** (`Ctrl+R` / `Cmd+R`)
4. 依次替换：

```
查找：Log.d(
替换：LogHelper.d(

查找：Log.i(
替换：LogHelper.i(

查找：Log.w(
替换：LogHelper.w(

查找：Log.e(
替换：LogHelper.e(
```

5. **注意**：不要替换 `LogHelper.kt` 文件本身的 `Log.*` 调用

### 方法2：使用命令行（批量）

```powershell
# 进入 Android 原生代码目录
cd android/app/src/main/kotlin/com/guangqi/easyfile

# 批量替换（排除 LogHelper.kt）
$files = Get-ChildItem -Filter "*.kt" | Where-Object { $_.Name -ne "LogHelper.kt" }

foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $content = $content -replace 'Log\.d\(', 'LogHelper.d('
    $content = $content -replace 'Log\.i\(', 'LogHelper.i('
    $content = $content -replace 'Log\.w\(', 'LogHelper.w('
    $content = $content -replace 'Log\.e\(', 'LogHelper.e('
    Set-Content $file.FullName $content
}
```

### 方法3：使用 VS Code

1. 打开 `android/app/src/main/kotlin/com/guangqi/easyfile/` 目录
2. 使用全局搜索替换 (`Ctrl+Shift+H`)
3. 勾选 **Use Regular Expression**
4. 查找：`Log\.(d|i|w|e)\(`
5. 在每个文件中手动替换（跳过 LogHelper.kt）

## 验证方法

### 运行 Profile 模式
```bash
flutter run --profile
```

### 检查日志输出
```bash
# 只看 LogHelper 相关的配置日志
adb logcat -s LogHelper:*

# 应该看到：
# I/LogHelper: 日志级别已设置为: INFO

# 不应该看到：
# D/MainActivity: ========== batchGetUsageStats ==========
# D/MediaStoreTrashHelper: 开始查询回收站文件...
# D/NewFilesNativeScanner: 目录不存在: ...
```

### 预期结果

**Profile 模式（LogLevel.info）**：
- ✅ 应该看到：INFO/WARN/ERROR 日志
- ❌ 不应该看到：DEBUG 日志

**Release 模式（LogLevel.warn）**：
- ✅ 应该看到：WARN/ERROR 日志  
- ❌ 不应该看到：DEBUG/INFO 日志

## 当前状态总结

| 文件 | Log.d | Log.i | Log.e/w | 状态 | 优先级 |
|------|-------|-------|---------|------|--------|
| LogHelper.kt | ✅ 保留 | ✅ 保留 | ✅ 保留 | 不需要 | - |
| MediaStoreScanner.kt | ✅ 已迁移 | ✅ 已迁移 | ✅ 已迁移 | 完成 | - |
| MainActivity.kt | ⚠️ 部分 | ⚠️ 部分 | ❌ 未迁移 | 进行中 | 🔴 高 |
| MediaStoreTrashHelper.kt | ❌ 未迁移 | ❌ 未迁移 | ❌ 未迁移 | 待处理 | 🔴 高 |
| NewFilesNativeScanner.kt | ❌ 未迁移 | ❌ 未迁移 | ❌ 未迁移 | 待处理 | 🔴 高 |
| StorageStatsHelper.kt | N/A | ❌ 未迁移 | ❌ 未迁移 | 待处理 | 🟡 中 |
| AppFileScanner.kt | ❓ 未检查 | ❓ 未检查 | ❓ 未检查 | 待检查 | 🟡 中 |
| ShareHelper.kt | ❓ 未检查 | ❓ 未检查 | ❓ 未检查 | 待检查 | 🟢 低 |

## 建议

1. **立即处理**：迁移 MainActivity.kt 的剩余日志（包含敏感的 UsageStats 数据）
2. **次要处理**：迁移 MediaStoreTrashHelper.kt 和 NewFilesNativeScanner.kt
3. **可选处理**：StorageStatsHelper.kt 的 INFO 日志可以在 Profile 模式显示
4. **批量处理**：使用上述脚本一次性迁移所有文件

## 注意事项

- **不要**替换 `LogHelper.kt` 本身的 `Log.*` 调用
- **不要**替换 `import android.util.Log` 语句（LogHelper 内部依赖它）
- **验证**替换后代码编译通过
- **测试**在 Debug/Profile/Release 三种模式下的日志输出
