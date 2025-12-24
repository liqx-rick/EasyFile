import 'package:easyfile/core/data_sources/file_list_data_source.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/core/logger.dart';

/// 分类文件数据源（复用现有分类页逻辑）
/// 
/// 功能：查询指定类型的所有文件（图片、视频、音频、文档等）
/// 特点：
/// - 包装现有 FilePresenter.scanFilesByCategory()
/// - 适配器模式，不修改原有实现
/// - 支持所有分类类型
/// 
/// 查询参数：
/// ```dart
/// {
///   'categoryType': CategoryType.images,  // 必需：分类类型
/// }
/// ```
/// 
/// 使用示例：
/// ```dart
/// final dataSource = CategoryFileDataSource(presenter: filePresenter);
/// 
/// // 查询所有图片
/// final images = await dataSource.queryFiles({
///   'categoryType': CategoryType.images,
/// });
/// 
/// // 查询所有视频
/// final videos = await dataSource.queryFiles({
///   'categoryType': CategoryType.video,
/// });
/// ```
class CategoryFileDataSource implements FileListDataSource {
  final FilePresenter presenter;
  
  CategoryFileDataSource({required this.presenter});
  
  @override
  String get name => 'CategoryFileDataSource';
  
  @override
  Future<List<FileItem>> queryFiles(Map<String, dynamic> params) async {
    // 1. 验证必需参数
    final categoryType = params['categoryType'] as CategoryType?;
    if (categoryType == null) {
      throw ArgumentError('categoryType is required');
    }
    
    logger.i('$name.queryFiles - categoryType: ${categoryType.name}');
    
    // 2. 调用现有扫描方法（完全复用）
    final files = await presenter.scanFilesByCategory(categoryType);
    
    logger.i('$name.queryFiles - 完成: ${files.length} 个文件');
    
    return files;
  }
  
  @override
  String getCacheKey(Map<String, dynamic> params) {
    final categoryType = params['categoryType'] as CategoryType;
    return 'category_cache_${categoryType.name}';
  }
  
  @override
  bool get supportsCaching => true;
  
  @override
  int get cacheExpiration => 24 * 3600; // 24小时（与分类页一致）
  
  @override
  Map<String, dynamic> getMetadata(Map<String, dynamic> params) {
    final categoryType = params['categoryType'] as CategoryType?;
    
    return {
      'dataSourceType': 'category',
      'categoryType': categoryType?.name,
      'scanMethod': 'FilePresenter.scanFilesByCategory',
      'isAdapter': true,
    };
  }
}
