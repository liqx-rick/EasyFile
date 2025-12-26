import 'package:easyfile/data/models/file_item.dart';

/// 文件列表数据源抽象（策略模式）
/// 
/// 职责：定义"如何查询文件"的统一接口
/// 实现类：根据不同场景提供具体查询策略
/// 
/// 设计原则：
/// - 接口统一：所有数据源实现相同的查询接口
/// - 参数灵活：通过 Map 传递查询参数，支持扩展
/// - 缓存可控：支持启用/禁用缓存，自定义过期时间
/// - 错误透明：异常向上抛出，由调用方处理
abstract class FileListDataSource {
  /// 数据源名称（用于日志和调试）
  String get name;
  
  /// 查询文件列表
  /// 
  /// [params] 查询参数（由具体实现类定义）
  /// 返回：文件列表
  ///
  /// 实现要求：
  /// - 必须返回 `List<FileItem>`，即使结果为空
  /// - 如果查询失败，应抛出异常（Exception 或子类）
  /// - 不应在此方法内部处理缓存逻辑（由 Controller 处理）
  Future<List<FileItem>> queryFiles(Map<String, dynamic> params);
  
  /// 获取缓存键（用于页面级缓存）
  /// 
  /// 不同的查询参数应该产生不同的缓存键，避免冲突
  /// 
  /// 示例：
  /// - 'app_files_wechat'
  /// - 'time_memory_365_7'
  /// - 'recent_media_7'
  String getCacheKey(Map<String, dynamic> params);
  
  /// 是否支持缓存
  /// 
  /// 某些实时查询可能不适合缓存
  /// 默认值：true
  bool get supportsCaching => true;
  
  /// 缓存有效期（秒）
  /// 
  /// 默认：24小时
  /// 实时性要求高的数据源应设置较短的过期时间
  int get cacheExpiration => 24 * 3600;
  
  /// 获取元数据（可选，用于统计和调试）
  /// 
  /// 返回数据源的描述信息，如：
  /// - 数据源类型
  /// - 查询范围
  /// - 预估数据量
  /// 
  /// 默认返回空 Map
  Map<String, dynamic> getMetadata(Map<String, dynamic> params) => {};
}
