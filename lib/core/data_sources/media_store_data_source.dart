import 'package:easyfile/core/data_sources/file_list_data_source.dart';
import 'package:easyfile/core/platform/mediastore_scanner_channel.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';

/// MediaStore 媒体类型枚举
enum MediaStoreType {
  /// 相机照片（系统相机包名过滤）
  cameraPhotos('camera_photos', 'image'),
  
  /// 相机视频（系统相机包名过滤）
  cameraVideos('camera_videos', 'video'),
  
  /// 录音文件（MIME type 过滤）
  recordings('recordings', 'audio');

  const MediaStoreType(this.source, this.mediaType);
  
  final String source;
  final String mediaType;
}

/// 通用 MediaStore 数据源（极简版）
/// 
/// 功能：统一处理 MediaStore 查询，只支持时间过滤
/// 
/// 支持的媒体类型：
/// - `MediaStoreType.cameraPhotos` - 相机照片（时光记忆）
/// - `MediaStoreType.cameraVideos` - 相机视频（生活剪影）
/// - `MediaStoreType.recordings` - 录音文件（声音记录）
/// 
/// 查询参数：
/// ```dart
/// {
///   // 时间过滤（二选一）
///   'daysAgo': 365,        // 可选：多少天前（用于时光记忆：一年前今天）
///   'tolerance': 7,        // 可选：容差天数（配合 daysAgo 使用，前后范围）
///   'recentDays': 7,       // 可选：最近几天（用于生活剪影）
/// }
/// ```
/// 
/// 使用示例：
/// ```dart
/// // 场景1：时光记忆（一年前今天的照片，前后7天）
/// final timeMemory = MediaStoreDataSource(
///   type: MediaStoreType.cameraPhotos,
///   name: 'TimeMemory',
/// );
/// final photos = await timeMemory.queryFiles({
///   'daysAgo': 365,
///   'tolerance': 7,
/// });
/// 
/// // 场景2：生活剪影（最近7天的视频）
/// final lifeMoments = MediaStoreDataSource(
///   type: MediaStoreType.cameraVideos,
///   name: 'LifeMoments',
/// );
/// final videos = await lifeMoments.queryFiles({
///   'recentDays': 7,
/// });
/// 
/// // 场景3：声音记录（所有录音文件）
/// final audioRecords = MediaStoreDataSource(
///   type: MediaStoreType.recordings,
///   name: 'AudioRecords',
/// );
/// final audios = await audioRecords.queryFiles({});
/// ```
class MediaStoreDataSource implements FileListDataSource {
  /// 媒体类型
  final MediaStoreType type;
  
  /// 数据源名称（用于日志和缓存）
  final String sourceName;
  
  /// 缓存过期时间（秒）
  final int? cacheExpirationSeconds;
  
  MediaStoreDataSource({
    required this.type,
    String? name,
    this.cacheExpirationSeconds,
  }) : sourceName = name ?? type.name;
  
  @override
  String get name => '${sourceName}DataSource';
  
  @override
  Future<List<FileItem>> queryFiles(Map<String, dynamic> params) async {
    logger.i('$name.queryFiles - type: ${type.name}, params: $params');
    
    // 1. 根据类型扫描文件
    final files = await _scanFiles();
    logger.d('$name - 扫描完成: ${files.length} 个文件');
    
    // 2. 时间过滤（接口保留，暂不启用 - 未来功能）
    // var result = _applyTimeFilter(files, params);
    // logger.d('$name - 时间过滤后: ${result.length} 个文件');
    
    // 3. maxResults 限制（接口保留，暂不启用 - 未来功能）
    // final maxResults = params['maxResults'] as int?;
    // if (maxResults != null && result.length > maxResults) {
    //   result = result.take(maxResults).toList();
    //   logger.i('$name - 应用 maxResults 限制: ${result.length} 个文件（限制: $maxResults）');
    // }
    
    // 当前：直接返回所有文件
    logger.i('$name - 最终返回: ${files.length} 个文件（所有文件）');
    return files;
  }
  
  /// 根据类型扫描文件
  Future<List<FileItem>> _scanFiles() async {
    switch (type) {
      case MediaStoreType.cameraPhotos:
        return MediaStoreScannerChannel.scanCameraPackagePhotos();
      case MediaStoreType.cameraVideos:
        return MediaStoreScannerChannel.scanCameraPackageVideos();
      case MediaStoreType.recordings:
        return MediaStoreScannerChannel.scanRecordings();
    }
  }
  
  // 时间过滤方法（保留接口，暂不启用 - 未来功能）
  // List<FileItem> _applyTimeFilter(...)
  // List<FileItem> _filterByTimeRange(...)
  // List<FileItem> _filterByRecentDays(...)
  
  @override
  String getCacheKey(Map<String, dynamic> params) {
    final parts = <String>[sourceName.toLowerCase()];
    
    // 时间参数
    final daysAgo = params['daysAgo'] as int?;
    final tolerance = params['tolerance'] as int?;
    final recentDays = params['recentDays'] as int?;
    
    if (daysAgo != null) {
      parts.add('${daysAgo}_${tolerance ?? 0}');
    } else if (recentDays != null) {
      parts.add('recent_$recentDays');
    } else {
      parts.add('all');
    }
    
    return parts.join('_');
  }
  
  @override
  bool get supportsCaching => true;
  
  @override
  int get cacheExpiration {
    // 自定义过期时间优先
    if (cacheExpirationSeconds != null) {
      return cacheExpirationSeconds!;
    }
    
    // 默认缓存策略：
    // - 相机照片：1小时（时间敏感）
    // - 相机视频：30分钟（更实时）
    // - 录音文件：1小时
    switch (type) {
      case MediaStoreType.cameraPhotos:
        return 3600; // 1小时
      case MediaStoreType.cameraVideos:
        return 1800; // 30分钟
      case MediaStoreType.recordings:
        return 3600; // 1小时
    }
  }
  
  @override
  Map<String, dynamic> getMetadata(Map<String, dynamic> params) {
    return {
      'dataSourceType': 'content',
      'mediaType': type.mediaType,
      'source': type.source,
      'scanMethod': type == MediaStoreType.recordings
          ? 'MediaStore_MimeType'
          : 'MediaStore_PackageFilter',
    };
  }
}
