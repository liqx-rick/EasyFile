# 统一日志级别控制实现说明

## 概述

已实现 Flutter 端和原生端（Android）的统一日志级别控制，确保在不同构建模式下，Flutter 和原生代码使用相同的日志策略。

## 实现组件

### 1. Android 原生层

#### LogHelper.kt
原生日志工具类，提供与 Flutter 端一致的日志级别控制：

```kotlin
// 使用方式（替代 android.util.Log）
LogHelper.d(TAG, "debug message")   // DEBUG 级别
LogHelper.i(TAG, "info message")    // INFO 级别
LogHelper.w(TAG, "warning message") // WARN 级别
LogHelper.e(TAG, "error message")   // ERROR 级别

// 设置日志级别（由 Flutter 端控制）
LogHelper.setLevel(LogHelper.Level.WARN)
```

**支持的日志级别**：
- `DEBUG` (0) - 详细调试信息
- `INFO` (1) - 一般信息
- `WARN` (2) - 警告信息
- `ERROR` (3) - 错误信息
- `OFF` (4) - 关闭所有日志

#### MainActivity.kt
添加了日志配置通道（MethodChannel）：

```kotlin
// 通道名称: easyfile/log_config
// 支持的方法:
// - setLogLevel(level: String): 设置日志级别
// - getLogLevel(): 获取当前日志级别
// - setLogEnabled(enabled: Boolean): 启用/禁用日志
```

### 2. Flutter 层

#### NativeLogConfigChannel
Flutter 端的日志配置通道封装：

```dart
// 设置原生日志级别
await NativeLogConfigChannel.setLogLevel(LogLevel.warn);

// 获取当前日志级别
final level = await NativeLogConfigChannel.getLogLevel();

// 启用/禁用日志
await NativeLogConfigChannel.setLogEnabled(false);

// 同步日志配置（推荐在 main() 中调用）
await NativeLogConfigChannel.syncLogConfig(level: logLevel);
```

#### main.dart
应用启动时自动同步日志级别：

```dart
// 根据构建模式设置日志级别
late final LogLevel logLevel;
if (kReleaseMode) {
  logLevel = LogLevel.warn;   // Release: 只显示警告和错误
} else if (kProfileMode) {
  logLevel = LogLevel.info;   // Profile: 显示信息、警告和错误
} else {
  logLevel = LogLevel.debug;  // Debug: 显示所有日志
}

await logger.init(minLevel: logLevel);

// 🔄 同步到原生端
await NativeLogConfigChannel.syncLogConfig(level: logLevel);
```

## 使用效果

### Debug 模式（开发环境）
```
Flutter: LogLevel.debug
Native:  LogHelper.Level.DEBUG
结果:    显示所有日志（包括 MediaStore 的详细扫描日志）
```

### Profile 模式（Staging 环境）
```
Flutter: LogLevel.info
Native:  LogHelper.Level.INFO
结果:    显示 INFO/WARN/ERROR（隐藏 DEBUG 日志）
```

### Release 模式（生产环境）
```
Flutter: LogLevel.warn
Native:  LogHelper.Level.WARN
结果:    只显示 WARN/ERROR（隐藏所有调试和信息日志）
```

## 迁移指南

### 替换原生日志调用

**之前**：
```kotlin
import android.util.Log

Log.d(TAG, "调试信息")
Log.i(TAG, "普通信息")
Log.w(TAG, "警告信息")
Log.e(TAG, "错误信息")
```

**之后**：
```kotlin
// 不需要导入 android.util.Log

LogHelper.d(TAG, "调试信息")
LogHelper.i(TAG, "普通信息")
LogHelper.w(TAG, "警告信息")
LogHelper.e(TAG, "错误信息", exception)  // 可选异常参数
```

### 已迁移的文件

- ✅ `MediaStoreScanner.kt` - MediaStore 扫描日志已使用 LogHelper

### 待迁移的文件

其他使用 `android.util.Log` 的 Kotlin 文件应该逐步迁移到 `LogHelper`，包括：
- `AppFileScanner.kt`
- `MediaStoreTrashHelper.kt`
- `NewFilesNativeScanner.kt`
- `StorageStatsHelper.kt`
- 其他自定义的原生类

## 优势

1. **🔒 安全性**：Release 模式下自动隐藏敏感调试信息
2. **⚡ 性能**：减少不必要的日志输出，提升应用性能
3. **🎯 一致性**：Flutter 和原生使用统一的日志策略
4. **🔧 灵活性**：支持运行时动态调整日志级别
5. **📱 生产就绪**：生产环境只输出关键错误和警告

## 注意事项

1. **渐进式迁移**：不需要一次性替换所有 `Log.*` 调用，可以逐步迁移
2. **系统日志保留**：`LogHelper` 底层依然调用 `android.util.Log`，只是增加了级别过滤
3. **多平台支持**：当前只实现了 Android，iOS 端可以类似实现
4. **向后兼容**：未迁移的代码依然可以使用 `android.util.Log`

## 测试验证

### 验证步骤

1. **Debug 模式测试**：
   ```bash
   flutter run
   # 应该能看到所有 MediaStore 的 DEBUG 和 INFO 日志
   ```

2. **Release 模式测试**：
   ```bash
   flutter run --release
   # MediaStore 的 DEBUG 和 INFO 日志应该被隐藏
   # 只能看到 WARN 和 ERROR 日志
   ```

3. **日志级别查看**：
   ```bash
   adb logcat | grep "LogHelper"
   # 应该能看到: "日志级别已设置为: WARN"
   ```

## 示例输出

### Debug 模式
```
I/flutter: [2025-12-30T15:23:45.123] [INFO] 🔄 开始同步日志配置到原生端...
I/flutter: [2025-12-30T15:23:45.124] [DEBUG] 设置原生日志级别: debug
I/LogHelper: 日志级别已设置为: DEBUG
I/flutter: [2025-12-30T15:23:45.125] [INFO] ✓ 原生日志级别已同步: debug
D/MediaStoreScanner: 开始遍历 MediaStore 查询结果，总数: 1523
I/MediaStoreScanner: MediaStore 扫描完成: 1523 个图片, 耗时: 234ms
```

### Release 模式
```
I/flutter: [2025-12-30T15:23:45.123] [INFO] 🔄 开始同步日志配置到原生端...
I/LogHelper: 日志级别已设置为: WARN
I/flutter: [2025-12-30T15:23:45.125] [INFO] ✓ 原生日志级别已同步: warn
# 注意：MediaStore 的 DEBUG 和 INFO 日志不再出现
```

## 后续优化

1. **iOS 支持**：实现 iOS 端的日志级别控制
2. **日志转发**：关键原生日志可以选择性转发到 Flutter AppLogger
3. **远程控制**：通过远程配置动态调整生产环境的日志级别
4. **日志分析**：集成 Firebase Crashlytics 等日志分析服务
