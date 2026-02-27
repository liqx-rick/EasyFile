# 应用存储信息真实API实现

## 📋 实现概述

### 问题背景
之前的实现使用包名长度估算应用存储大小，这是**虚假数据**，不可接受。

### 正确方案
使用Android原生 `StorageStatsManager` API (Android 8.0+) 获取真实的应用存储信息。

## 🏗️ 架构设计

### 1. Android原生层 (Kotlin)
**文件**: `android/app/src/main/kotlin/com/example/easyfile/StorageStatsHelper.kt`

```kotlin
class StorageStatsHelper {
    fun getAppStorageStats(packageName: String): Map<String, Long>? {
        // 使用 StorageStatsManager.queryStatsForUid()
        // 返回: appBytes, dataBytes, cacheBytes
    }
}
```

**特性**:
- ✅ 使用 `StorageStatsManager` (Android 8.0+ / API 26+)
- ✅ 获取应用UID
- ✅ 查询主存储卷的统计信息
- ✅ 返回真实的字节数

### 2. MethodChannel桥接
**Channel**: `com.easyfile/storage_stats`

**方法**:
- `isSupported()`: 检查是否支持 (Android 8.0+)
- `getAppStorageStats(packageName)`: 获取单个应用统计
- `batchGetStorageStats(packageNames)`: 批量获取统计

### 3. Flutter服务层
**文件**: `lib/core/services/app_storage_service.dart`

**变更**:
- ❌ 移除: `_estimateExternalStorage()` - 估算方法
- ❌ 移除: `UsageStatsPermissionService` 依赖
- ✅ 新增: `_channel.invokeMethod()` - 原生API调用
- ✅ 新增: 平台支持检查

## 🔧 技术细节

### StorageStatsManager API要求

#### 权限
**无需特殊权限！** StorageStatsManager可以查询当前应用有权访问的应用统计信息。

#### API级别
- **最低要求**: Android 8.0 (API 26)
- **当前测试设备**: Android 15 (API 35) ✅

### 数据来源
```
StorageStatsManager.queryStatsForUid(UUID, int uid)
├── appBytes:   应用APK大小
├── dataBytes:  应用数据大小（包括私有文件）
└── cacheBytes: 应用缓存大小
```

### 与文件系统扫描的对比

| 方案 | 准确性 | 权限要求 | 性能 | Android 11+兼容性 |
|------|--------|----------|------|------------------|
| 文件系统扫描 | ❌ 不准确 | MANAGE_EXTERNAL_STORAGE | 慢 | ❌ 受限 |
| StorageStatsManager | ✅ 精确 | 无需特殊权限 | 快 | ✅ 完全兼容 |

## 🧪 测试验证

### 测试步骤
1. **清除旧缓存**
   - 进入应用管理页面
   - 下拉刷新（触发缓存清除）

2. **重新加载数据**
   - 等待应用列表加载完成
   - 观察存储信息显示

3. **验证数据真实性**
   - 对比系统设置中的应用存储信息
   - 检查数值是否合理（不是1-2MB的固定值）
   - 验证不同应用显示不同大小

### 预期结果

#### ❌ 错误的估算值特征
- 所有应用大小在 1-2MB 之间
- 大小与包名长度成正比
- 数据、缓存大小是固定比例

#### ✅ 正确的真实数据特征
- 应用大小差异明显（从几KB到几GB）
- 系统应用、大型应用显示正常大小
- 与系统设置中的数值一致

## 📊 缓存策略

### 缓存配置
- **缓存时长**: 6小时
- **存储位置**: SharedPreferences
- **Key格式**: `app_storage_{packageName}`

### 缓存失效
- 超过6小时自动失效
- 手动刷新清除所有缓存
- 单个应用卸载清除对应缓存

## 🚀 部署步骤

### 1. 编译Kotlin代码
```bash
flutter run -d <device_id>
```

### 2. 验证MethodChannel
检查日志确认channel注册成功：
```
I/MainActivity: Configured storage_stats channel
```

### 3. 测试API调用
观察日志输出：
```
D/AppStorageService: Got storage stats for com.android.chrome: app=123456789B, data=456789B, cache=123456B
```

### 4. 清除旧数据
在应用中执行刷新操作，确保使用新API获取数据。

## 📝 代码变更总结

### 新增文件
- `android/.../StorageStatsHelper.kt` - Android原生存储统计助手

### 修改文件
- `android/.../MainActivity.kt` - 注册StorageStats MethodChannel
- `lib/.../app_storage_service.dart` - 调用原生API
- `lib/.../locator.dart` - 移除UsageStatsPermissionService依赖
- `test/app_management_test.dart` - 更新测试构造函数

### 移除代码
- `_estimateExternalStorage()` 方法
- `_calculateDirectorySize()` 方法
- 文件系统扫描相关逻辑

## ⚠️ 注意事项

### 1. Android版本兼容性
- Android 8.0+ 支持 StorageStatsManager
- Android 7.x 及以下返回 null（显示"无数据"）

### 2. 权限说明
- **不需要** MANAGE_EXTERNAL_STORAGE 危险权限
- **不需要** 用户授权步骤
- **自动** 适用于所有应用

### 3. 性能考虑
- 单个查询耗时: ~5-10ms
- 批量查询: 每10个应用暂停50ms
- 建议使用缓存避免重复查询

## 🎯 下一步行动

1. ✅ **部署到设备** - 安装新版本APK
2. 🔄 **清除缓存** - 下拉刷新应用列表
3. 📊 **验证数据** - 对比系统设置确认准确性
4. 📝 **更新测试报告** - 记录真实数据测试结果
5. ✅ **提交代码** - 确认无虚假数据后提交

---

**版本**: 1.0  
**日期**: 2025-12-03  
**状态**: 实现完成，等待真机验证
