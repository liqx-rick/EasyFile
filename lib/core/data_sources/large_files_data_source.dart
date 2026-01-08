import 'package:easyfile/core/data_sources/file_list_data_source.dart';
import 'package:easyfile/core/data_sources/data_source_helpers.dart';
import 'package:easyfile/core/platform/mediastore_scanner_channel.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';

/// 大文件数据源（清理推荐模式）
///
/// 功能：查询大于指定大小的文件
/// 特点：
/// - 扫描所有媒体类型（图片、视频、音频、文档）
/// - 按大小降序排序
/// - 支持自定义大小阈值
/// - 适合大文件清理场景
///
/// 查询参数：
/// ```dart
/// {
///   'minSize': 100 * 1024 * 1024,  // 必需：最小文件大小（字节），默认100MB
///   'maxResults': 100,              // 可选：最大结果数量
///   'includeTypes': ['image', 'video', 'audio', 'document'],  // 可选：包含的类型
/// }
/// ```
///
/// 使用示例：
/// ```dart
/// // 场景1：大于100MB的文件
/// final largeFiles = await dataSource.queryFiles({
///   'minSize': 100 * 1024 * 1024,
/// });
///
/// // 场景2：大于500MB的视频和文档
/// final veryLargeFiles = await dataSource.queryFiles({
///   'minSize': 500 * 1024 * 1024,
///   'includeTypes': ['video', 'document'],
/// });
/// ```
class LargeFilesDataSource implements FileListDataSource {
  LargeFilesDataSource();

  @override
  String get name => 'LargeFilesDataSource';

  @override
  Future<List<FileItem>> queryFiles(Map<String, dynamic> params) async {
    // 1. 获取参数
    final minSize = params['minSize'] as int? ?? (100 * 1024 * 1024); // 默认100MB
    final includeTypes = params['includeTypes'] as List<String>? ??
        ['image', 'video', 'audio', 'document'];

    logger.i(
        '$name.queryFiles - minSize: ${DataSourceHelpers.formatSize(minSize)}, types: $includeTypes');

    // 2. 扫描所有媒体类型
    final List<FileItem> allMedia = [];

    if (includeTypes.contains('image')) {
      try {
        final images = await MediaStoreScannerChannel.scanImages();
        allMedia.addAll(images);
        logger.d('$name - 图片扫描: ${images.length} 个');
      } catch (e) {
        logger.e('$name - 图片扫描失败: $e');
      }
    }

    if (includeTypes.contains('video')) {
      try {
        final videos = await MediaStoreScannerChannel.scanVideos();
        allMedia.addAll(videos);
        logger.d('$name - 视频扫描: ${videos.length} 个');
      } catch (e) {
        logger.e('$name - 视频扫描失败: $e');
      }
    }

    if (includeTypes.contains('audio')) {
      try {
        final audio = await MediaStoreScannerChannel.scanAudio();
        allMedia.addAll(audio);
        logger.d('$name - 音频扫描: ${audio.length} 个');
      } catch (e) {
        logger.e('$name - 音频扫描失败: $e');
      }
    }

    if (includeTypes.contains('document')) {
      try {
        final documents = await MediaStoreScannerChannel.scanDocuments();
        allMedia.addAll(documents);
        logger.d('$name - 文档扫描: ${documents.length} 个');
      } catch (e) {
        logger.e('$name - 文档扫描失败: $e');
      }
    }

    logger.i('$name - 总媒体文件: ${allMedia.length} 个');

    // 3. 过滤大文件
    final largeFiles = DataSourceHelpers.filterBySize(
      allMedia,
      minSize: minSize,
    ).where((file) => !file.isDirectory).toList();

    logger.i(
        '$name - 大文件过滤: ${allMedia.length} -> ${largeFiles.length} (> ${DataSourceHelpers.formatSize(minSize)})');

    // 4. 按大小降序排序（大的在前）
    DataSourceHelpers.sortFilesBySize(largeFiles, descending: true);
    logger.d('$name - 按大小降序排序');

    return largeFiles;
  }

  @override
  String getCacheKey(Map<String, dynamic> params) {
    final minSize = params['minSize'] as int? ?? (100 * 1024 * 1024);
    final minSizeMB = minSize ~/ (1024 * 1024);

    final includeTypes = params['includeTypes'] as List<String>?;
    final typesSuffix = includeTypes?.join('_') ?? 'all';

    return 'large_files_${minSizeMB}mb_$typesSuffix';
  }

  @override
  bool get supportsCaching => true;

  @override
  int get cacheExpiration => 1800; // 30分钟（文件大小变化较快）

  @override
  Map<String, dynamic> getMetadata(Map<String, dynamic> params) {
    final minSize = params['minSize'] as int? ?? (100 * 1024 * 1024);

    return {
      'dataSourceType': 'cleanup',
      'minSize': minSize,
      'minSizeFormatted': DataSourceHelpers.formatSize(minSize),
      'scanMethod': 'MediaStore_AllTypes',
      'purpose': 'large_file_cleanup',
    };
  }
}
