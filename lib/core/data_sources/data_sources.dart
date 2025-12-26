/// 数据源抽象层统一导出
///
/// 这个文件提供了所有数据源相关类的统一导入入口
///
/// 使用示例：
/// ```dart
/// import 'package:easyfile/core/data_sources/data_sources.dart';
///
/// // 创建工厂
/// final factory = DataSourceFactory(
///   scanner: scanner,
///   detectionService: detectionService,
/// );
/// 
/// // 使用数据源
/// final dataSource = factory.create('app_files');
/// final files = await dataSource.queryFiles({'appKey': 'wechat'});
/// ```
library;

// 核心抽象
export 'file_list_data_source.dart';

// 工具类
export 'data_source_helpers.dart';

// 通用实现
export 'media_store_data_source.dart';  // 通用 MediaStore 数据源（相机照片、视频、录音）

// 具体实现
export 'app_files_data_source.dart';
export 'large_files_data_source.dart';
export 'category_file_data_source.dart';

// 工厂
export 'data_source_factory.dart';
