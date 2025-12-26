# 数据源抽象层使用指南

## 一、架构概览

```
┌─────────────────────────────────────────────────────┐
│           RecommendAggregatePage                     │
│           CategoryFilePage                           │
│           (页面层)                                    │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│           DataSourceFactory                          │
│           (工厂层 - 创建数据源实例)                   │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│           FileListDataSource (接口)                  │
│           (抽象层 - 统一查询接口)                     │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│           具体数据源实现                              │
│  ┌─────────────────────────────────────────────┐   │
│  │ AppFilesDataSource                          │   │
│  │ - UnifiedAppScanner                         │   │
│  │ - AppDetectionService                       │   │
│  └─────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────┐   │
│  │ TimeMemoryDataSource                        │   │
│  │ - MediaStoreScannerChannel                  │   │
│  │ - scanCameraPackagePhotos()                 │   │
│  └─────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────┐   │
│  │ LifeMomentsDataSource                       │   │
│  │ - MediaStoreScannerChannel                  │   │
│  │ - scanCameraPackageVideos()                 │   │
│  └─────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────┐   │
│  │ AudioRecordsDataSource                      │   │
│  │ - MediaStoreScannerChannel                  │   │
│  │ - scanRecordings()                          │   │
│  └─────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────┐   │
│  │ LargeFilesDataSource                        │   │
│  │ - MediaStoreScannerChannel (多类型扫描)      │   │
│  └─────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────┐   │
│  │ CategoryFileDataSource (适配器)             │   │
│  │ - FilePresenter.scanFilesByCategory()       │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

## 二、快速开始

### 2.1 基础用法

```dart
import 'package:easyfile/core/data_sources/data_sources.dart';

// 1. 创建工厂
final factory = DataSourceFactory(
  scanner: unifiedScanner,        // UnifiedAppScanner 实例
  detectionService: detectionService,  // AppDetectionService 实例
  presenter: filePresenter,       // FilePresenter 实例（可选）
);

// 2. 创建数据源
final dataSource = factory.create('app_files');

// 3. 查询文件
final files = await dataSource.queryFiles({
  'appKey': 'wechat',
});

print('微信文件: ${files.length} 个');
```

### 2.2 从 RecommendationType 创建

```dart
// 便捷方法：直接从推荐类型创建数据源
final dataSource = factory.createFromRecommendationType(
  RecommendationType.wechat,
);

final files = await dataSource.queryFiles({
  'appKey': 'wechat',
});
```

## 三、各数据源详细用法

### 3.1 AppFilesDataSource（应用文件）

**适用场景：** 微信、QQ、Telegram、WPS 等应用文件推荐

```dart
final dataSource = factory.create('app_files');

// 场景1：查询所有微信文件
final allWechatFiles = await dataSource.queryFiles({
  'appKey': 'wechat',
  'useMediaStore': true,
});

// 场景2：查询微信图片（Tab 功能）
final wechatImages = await dataSource.queryFiles({
  'appKey': 'wechat',
  'fileTypes': ['jpg', 'jpeg', 'png', 'gif', 'webp'],
});

// 场景3：查询微信视频
final wechatVideos = await dataSource.queryFiles({
  'appKey': 'wechat',
  'fileTypes': ['mp4', 'avi', 'mkv', '3gp'],
});

// 场景4：查询微信文档
final wechatDocs = await dataSource.queryFiles({
  'appKey': 'wechat',
  'fileTypes': ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'],
});
```

**缓存键示例：**
- 所有文件：`app_files_wechat_all`
- 图片：`app_files_wechat_jpg_jpeg_png_gif_webp`
- 视频：`app_files_wechat_mp4_avi_mkv_3gp`

**缓存过期：** 6小时

### 3.2 TimeMemoryDataSource（时光记忆）

**适用场景：** 一年前今天的照片、历史照片回顾

```dart
final dataSource = factory.create('time_memory');

// 场景1：所有相机照片
final allPhotos = await dataSource.queryFiles({});

// 场景2：一年前今天（前后7天）
final oneYearAgo = await dataSource.queryFiles({
  'daysAgo': 365,
  'tolerance': 7,
});

// 场景3：半年前今天（前后3天）
final halfYearAgo = await dataSource.queryFiles({
  'daysAgo': 180,
  'tolerance': 3,
});

// 场景4：限制结果数量
final limitedPhotos = await dataSource.queryFiles({
  'daysAgo': 365,
  'tolerance': 7,
  'maxResults': 50,
});
```

**缓存键示例：**
- 所有照片：`time_memory_all`
- 一年前：`time_memory_365_7`
- 半年前：`time_memory_180_3`

**缓存过期：** 1小时

### 3.3 LifeMomentsDataSource（生活剪影）

**适用场景：** 最近拍摄的视频、视频回顾

```dart
final dataSource = factory.create('life_moments');

// 场景1：所有相机视频
final allVideos = await dataSource.queryFiles({});

// 场景2：最近7天的视频
final recentVideos = await dataSource.queryFiles({
  'recentDays': 7,
});

// 场景3：最近30天的视频
final monthlyVideos = await dataSource.queryFiles({
  'recentDays': 30,
  'maxResults': 50,
});
```

**缓存键示例：**
- 所有视频：`life_moments_all`
- 最近7天：`life_moments_recent_7`
- 最近30天：`life_moments_recent_30`

**缓存过期：** 30分钟

### 3.4 AudioRecordsDataSource（声音记录）

**适用场景：** 录音文件管理

```dart
final dataSource = factory.create('audio_records');

// 场景1：所有录音
final allRecordings = await dataSource.queryFiles({});

// 场景2：最近30天的录音
final recentRecordings = await dataSource.queryFiles({
  'recentDays': 30,
});

// 场景3：大于1MB的录音
final largeRecordings = await dataSource.queryFiles({
  'minSize': 1024 * 1024,
});

// 场景4：按大小排序
final sortedBySize = await dataSource.queryFiles({
  'sortBy': 'size',
  'maxResults': 50,
});

// 场景5：按名称排序
final sortedByName = await dataSource.queryFiles({
  'sortBy': 'name',
});
```

**缓存键示例：**
- 所有录音：`audio_records`
- 最近30天：`audio_records_recent_30`
- 最小1MB：`audio_records_recent_30_minsize_1024kb`

**缓存过期：** 1小时

### 3.5 LargeFilesDataSource（大文件清理）

**适用场景：** 存储空间清理、大文件管理

```dart
final dataSource = factory.create('large_files');

// 场景1：大于100MB的所有文件
final largeFiles = await dataSource.queryFiles({
  'minSize': 100 * 1024 * 1024,
});

// 场景2：大于500MB的文件
final veryLargeFiles = await dataSource.queryFiles({
  'minSize': 500 * 1024 * 1024,
});

// 场景3：只扫描视频和文档
final largeVideoDocs = await dataSource.queryFiles({
  'minSize': 100 * 1024 * 1024,
  'includeTypes': ['video', 'document'],
});

// 场景4：限制结果数量（性能优化）
final limitedLargeFiles = await dataSource.queryFiles({
  'minSize': 100 * 1024 * 1024,
  'maxResults': 50,
});
```

**缓存键示例：**
- 100MB所有类型：`large_files_100mb_all`
- 500MB所有类型：`large_files_500mb_all`
- 100MB视频文档：`large_files_100mb_video_document`

**缓存过期：** 30分钟

### 3.6 CategoryFileDataSource（分类文件）

**适用场景：** 复用现有分类页逻辑

```dart
final dataSource = factory.create('category_files');

// 查询所有图片
final images = await dataSource.queryFiles({
  'categoryType': CategoryType.images,
});

// 查询所有视频
final videos = await dataSource.queryFiles({
  'categoryType': CategoryType.video,
});

// 查询所有音频
final audio = await dataSource.queryFiles({
  'categoryType': CategoryType.music,
});

// 查询所有文档
final documents = await dataSource.queryFiles({
  'categoryType': CategoryType.documents,
});
```

**缓存键示例：**
- 图片：`category_cache_images`
- 视频：`category_cache_video`
- 音频：`category_cache_music`

**缓存过期：** 24小时

## 四、与 RecommendConfig 集成

### 4.1 使用映射器

```dart
import 'package:easyfile/core/data_sources/recommend_config_mapper.dart';

// 1. 获取 queryStrategy
final strategy = RecommendConfigDataSourceMapper.getQueryStrategy(
  RecommendationType.wechat,
);
// 返回: 'app_files'

// 2. 获取默认查询参数
final params = RecommendConfigDataSourceMapper.getDefaultQueryParams(
  RecommendationType.memories,
);
// 返回: {'daysAgo': 365, 'tolerance': 7, 'maxResults': 100}

// 3. 获取 Tab 查询参数
final tabParams = RecommendConfigDataSourceMapper.getTabQueryParams(
  RecommendationType.wechat,
  fileTypes: ['jpg', 'png'],
);
// 返回: {'appKey': 'wechat', 'fileTypes': ['jpg', 'png']}
```

### 4.2 完整流程示例

```dart
// 从 RecommendConfig 到数据查询的完整流程
Future<List<FileItem>> queryFromRecommendConfig(
  RecommendationType type,
  DataSourceFactory factory,
) async {
  // 1. 获取 queryStrategy
  final strategy = RecommendConfigDataSourceMapper.getQueryStrategy(type);
  
  // 2. 创建数据源
  final dataSource = factory.create(strategy);
  
  // 3. 获取查询参数
  final params = RecommendConfigDataSourceMapper.getDefaultQueryParams(type);
  
  // 4. 执行查询
  final files = await dataSource.queryFiles(params);
  
  return files;
}

// 使用示例
final wechatFiles = await queryFromRecommendConfig(
  RecommendationType.wechat,
  factory,
);
```

## 五、性能优化建议

### 5.1 缓存策略

所有数据源默认支持缓存，缓存由上层 Controller 管理：

```dart
// 数据源提供缓存元数据
dataSource.supportsCaching;        // 是否支持缓存
dataSource.cacheExpiration;        // 过期时间（秒）
dataSource.getCacheKey(params);    // 缓存键
```

### 5.2 并发查询

多个独立查询可以并发执行：

```dart
final results = await Future.wait([
  dataSource1.queryFiles(params1),
  dataSource2.queryFiles(params2),
  dataSource3.queryFiles(params3),
]);
```

### 5.3 结果数量限制

通过 `maxResults` 参数限制结果数量，提升性能：

```dart
// 推荐值
final files = await dataSource.queryFiles({
  'appKey': 'wechat',
  'maxResults': 100,  // 避免返回过多数据
});
```

## 六、错误处理

### 6.1 参数验证错误

```dart
try {
  await dataSource.queryFiles({});  // 缺少必需参数
} on ArgumentError catch (e) {
  print('参数错误: ${e.message}');
}
```

### 6.2 扫描失败

```dart
try {
  final files = await dataSource.queryFiles(params);
} catch (e) {
  print('扫描失败: $e');
  // 返回空列表或显示错误提示
}
```

## 七、扩展新数据源

### 7.1 创建新数据源

```dart
class MyCustomDataSource implements FileListDataSource {
  @override
  String get name => 'MyCustomDataSource';
  
  @override
  Future<List<FileItem>> queryFiles(Map<String, dynamic> params) async {
    // 实现自定义查询逻辑
    return [];
  }
  
  @override
  String getCacheKey(Map<String, dynamic> params) {
    return 'my_custom_${params['someKey']}';
  }
  
  @override
  bool get supportsCaching => true;
  
  @override
  int get cacheExpiration => 3600;
}
```

### 7.2 注册到工厂

```dart
// 在 DataSourceFactory.create() 中添加新分支
case 'my_custom':
  return MyCustomDataSource();
```

## 八、总结

### 优势
✅ **统一接口**：所有数据源实现相同接口，易于替换和扩展  
✅ **参数灵活**：通过 Map 传递参数，支持任意扩展  
✅ **缓存可控**：每个数据源独立配置缓存策略  
✅ **依赖清晰**：通过工厂模式管理依赖注入  
✅ **性能优化**：复用现有扫描机制，无额外开销  
✅ **类型安全**：枚举和常量确保类型正确性  

### 使用场景
- ✅ RecommendAggregatePage（推荐聚合页）
- ✅ CategoryFilePage（分类页面，可选改造）
- ✅ 任何需要查询文件列表的页面
