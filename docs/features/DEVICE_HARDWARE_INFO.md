# 设备硬件环境统计功能

## 功能概述

本功能用于统计和显示运行 EasyFile 应用的硬件环境信息，包括：
- 设备信息（制造商、型号、品牌等）
- 系统信息（Android版本、语言区域等）
- 处理器信息（CPU架构、核心数）
- 内存信息（总内存、可用内存、使用率）
- 存储信息（总存储、可用存储、使用率）
- 屏幕信息（分辨率、密度等）

## 实现架构

### 1. Native端（Android/Kotlin）

**文件**: `android/app/src/main/kotlin/com/guangqi/easyfile/MainActivity.kt`

通过 `MethodChannel` 提供 `getDeviceInfo` 方法，返回以下信息：

```kotlin
val deviceInfo = mapOf(
    "make" to Build.MANUFACTURER,           // 制造商
    "model" to Build.MODEL,                 // 型号
    "brand" to Build.BRAND,                 // 品牌
    "device" to Build.DEVICE,               // 设备代号
    "androidVersion" to Build.VERSION.SDK_INT,  // Android版本
    "cpuAbi" to Build.SUPPORTED_ABIS[0],    // CPU架构
    "totalMemory" to memoryInfo.totalMem,   // 总内存
    "availableMemory" to memoryInfo.availMem, // 可用内存
    "totalStorage" to totalStorage,         // 总存储
    "availableStorage" to availableStorage, // 可用存储
    "screenWidth" to widthPixels,           // 屏幕宽度
    "screenHeight" to heightPixels,         // 屏幕高度
    "screenDensity" to densityDpi           // 屏幕密度
)
```

### 2. Flutter端（Dart）

#### 2.1 Platform Channel封装

**文件**: `lib/core/platform/device_info_channel.dart`

提供两个类：
- `DeviceInfoChannel`: 通道通信封装
- `DeviceInfo`: 设备信息数据模型
- `SystemInfo`: 系统完整信息数据模型

关键方法：
```dart
// 获取设备信息
final deviceInfo = await DeviceInfoChannel.getDeviceInfo();

// 获取完整系统信息（包含平台信息）
final systemInfo = await DeviceInfoChannel.getSystemInfo();
```

#### 2.2 控制台打印工具

**文件**: `lib/utils/device_info_printer.dart`

提供 `DeviceInfoPrinter` 工具类，用于在控制台打印设备信息：

```dart
// 打印完整信息
await DeviceInfoPrinter.print();

// 获取单行摘要
final summary = await DeviceInfoPrinter.getOneLine();
```

#### 2.3 UI展示页面

**文件**: `lib/ui/pages/device_info_page.dart`

提供完整的设备信息展示页面，包括：
- 应用信息卡片
- 设备信息卡片
- 系统信息卡片
- 处理器信息卡片
- 内存信息卡片（带使用率进度条）
- 存储信息卡片（带使用率进度条）
- 屏幕信息卡片
- 导出功能

## 使用方法

### 方法1: 应用启动时自动打印

应用在 `main.dart` 启动时会自动调用 `DeviceInfoPrinter.print()`，将硬件信息打印到控制台。

查看方式：
```bash
# 实时查看日志
adb logcat -s flutter:I

# 或使用过滤
adb logcat -s flutter:I | grep "设备硬件环境统计"
```

### 方法2: 在设置页面查看

导航路径：
```
设置 -> 开发者选项 -> 设备硬件信息
```

**注意**: 开发者选项需要在 `AppConfig` 中启用：
```dart
AppConfig.instance.feature.isDeveloperOptionsEnabled = true;
```

### 方法3: 代码中调用

在任何地方导入并调用：

```dart
import 'package:easyfile/core/platform/device_info_channel.dart';
import 'package:easyfile/utils/device_info_printer.dart';

// 打印到控制台
await DeviceInfoPrinter.print();

// 获取数据对象
final systemInfo = await DeviceInfoChannel.getSystemInfo();
print(systemInfo.deviceInfo.manufacturer);
print(systemInfo.deviceInfo.model);

// 格式化内存大小
print(systemInfo.deviceInfo.formatMemory(1024 * 1024 * 1024)); // "1.00 GB"
```

## 输出示例

### 控制台输出

```
========================================
        设备硬件环境统计
========================================

【应用信息】
  应用名称: EasyFile
  包名: com.guangqi.easyfile
  版本: 1.0.0 (1)

【设备信息】
  制造商: Samsung
  型号: SM-G973F
  品牌: samsung
  设备代号: beyond1

【系统信息】
  操作系统: android
  系统版本: Android 13 (API 33)
  Android SDK: API 33
  语言区域: zh_CN

【处理器信息】
  CPU架构: arm64-v8a
  CPU核心数: 8核

【内存信息】
  总内存: 8.00 GB
  可用内存: 3.21 GB
  已用内存: 4.79 GB
  使用率: 59.9%

【存储信息】
  总存储: 128.00 GB
  可用存储: 45.67 GB
  已用存储: 82.33 GB
  使用率: 64.3%

【屏幕信息】
  分辨率: 1080 x 2400
  屏幕密度: 420 dpi
  屏幕等级: XXHDPI

========================================
           统计完成
========================================
```

## 测试脚本

运行测试脚本：
```powershell
.\scripts\test_device_info.ps1
```

该脚本会：
1. 检查设备连接
2. 启动应用
3. 提取并显示设备信息日志

## 注意事项

1. **权限要求**: 无需任何特殊权限，使用的都是公开的系统API
2. **平台支持**: 目前仅支持 Android 平台
3. **最低版本**: Android 7.0 (API 24) 及以上
4. **性能影响**: 信息获取是异步的，不会阻塞主线程
5. **数据精度**: 内存和存储大小使用字节精确计算

## 扩展功能

### 添加新的硬件信息

1. 在 `MainActivity.kt` 的 `getDeviceInfo` 方法中添加新字段
2. 在 `DeviceInfo` 类中添加对应属性
3. 更新 `fromMap` 方法来解析新字段
4. 在 `DeviceInfoPage` 中添加UI展示

示例：添加电池信息
```kotlin
// MainActivity.kt
val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
val batteryLevel = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)

deviceInfo["batteryLevel"] = batteryLevel
```

```dart
// device_info_channel.dart
class DeviceInfo {
  final int batteryLevel;

  factory DeviceInfo.fromMap(Map<String, dynamic> map) {
    return DeviceInfo(
      // ... 其他字段
      batteryLevel: map['batteryLevel'] as int? ?? 0,
    );
  }
}
```

## 故障排查

### 问题1: 获取信息失败

**症状**: 日志显示 "获取设备信息失败"

**解决方法**:
1. 检查 MethodChannel 名称是否匹配
2. 确认 Native 层方法正确注册
3. 查看详细错误信息：`adb logcat -s MainActivity:E`

### 问题2: 信息显示不全

**症状**: 某些字段显示为 "Unknown" 或 0

**解决方法**:
1. 检查设备 API 级别是否满足要求
2. 某些信息可能需要特定权限
3. 查看 `DeviceInfo.fromMap` 中的默认值处理

### 问题3: 在设置页面找不到入口

**症状**: 设置页面没有"设备硬件信息"选项

**解决方法**:
1. 确认开发者选项已启用
2. 检查 `AppConfig.instance.feature.isDeveloperOptionsEnabled`
3. 重新编译应用

## 相关文件

- `android/app/src/main/kotlin/com/guangqi/easyfile/MainActivity.kt` - Native实现
- `lib/core/platform/device_info_channel.dart` - Platform Channel封装
- `lib/ui/pages/device_info_page.dart` - UI页面
- `lib/utils/device_info_printer.dart` - 控制台打印工具
- `lib/main.dart` - 启动时自动调用
- `lib/ui/pages/settings_page.dart` - 设置页面入口
- `scripts/test_device_info.ps1` - 测试脚本

## 更新日志

### 2026-02-14
- ✅ 初始实现
- ✅ 添加完整的设备信息获取
- ✅ 实现UI展示页面
- ✅ 添加控制台打印工具
- ✅ 集成到设置页面
- ✅ 创建测试脚本
- ✅ 编写完整文档
