import 'package:easyfile/core/data_sources/data_source_helpers.dart';
import 'package:easyfile/core/data_sources/file_list_data_source.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/data/models/file_item.dart';

/// 应用文件数据源（应用推荐模式专用）
///
/// 功能：查询指定应用的所有文件
/// 特点：
/// - 支持 MediaStore 和路径扫描双模式
/// - 内置应用安装检测
/// - 支持文件类型过滤（Tab 功能）
///
/// 查询参数：
/// ```dart
/// {
///   'appKey': 'wechat',              // 必需：应用标识
///   'fileTypes': ['jpg', 'png'],     // 可选：文件类型过滤
///   'useMediaStore': true,           // 可选：是否使用 MediaStore
/// }
/// ```
///
/// 使用示例：
/// ```dart
/// final dataSource = AppFilesDataSource(
///   scanner: unifiedScanner,
///   detectionService: detectionService,
/// );
///
/// final files = await dataSource.queryFiles({
///   'appKey': 'wechat',
///   'fileTypes': ['jpg', 'png', 'gif'], // 图片 Tab
/// });
/// ```
class AppFilesDataSource implements FileListDataSource {
  final UnifiedAppScanner scanner;
  final AppDetectionService detectionService;

  AppFilesDataSource({
    required this.scanner,
    required this.detectionService,
  });

  @override
  String get name => 'AppFilesDataSource';

  @override
  Future<List<FileItem>> queryFiles(Map<String, dynamic> params) async {
    // 1. 验证必需参数
    final appKey = params['appKey'] as String?;
    if (appKey == null || appKey.isEmpty) {
      throw ArgumentError('appKey is required');
    }

    // 2. 可选参数
    final fileTypes = params['fileTypes'] as List<String>?;
    final useMediaStore = params['useMediaStore'] as bool? ?? true;
    final forceRefresh = params['forceRefresh'] as bool? ?? false;

    logger.i('$name.queryFiles - appKey: $appKey, fileTypes: $fileTypes${forceRefresh ? ' (强制刷新)' : ''}');

    // 3. 快速路径：优先使用内存缓存（如果不是强制刷新）
    if (!forceRefresh) {
      final cachedResult = await scanner.getCachedScanResult(appKey: appKey);
      if (cachedResult != null && cachedResult.isInstalled) {
        logger.i('$name - ⚡ 使用内存缓存快速返回: ${cachedResult.totalCount} 个文件（未过滤）');

        // 应用过滤逻辑
        var files = cachedResult.allFiles;
        final originalCount = files.length;

        // 基础类型过滤
        files = DataSourceHelpers.filterBySupportedTypes(files);
        final filteredBySupport = originalCount - files.length;
        if (filteredBySupport > 0) {
          logger.d('$name - 内存缓存数据过滤: $originalCount -> ${files.length}');
        }

        // Tab类型过滤
        if (fileTypes != null && fileTypes.isNotEmpty) {
          final beforeTabFilter = files.length;
          files = DataSourceHelpers.filterByFileTypes(files, fileTypes: fileTypes);
          logger.d('$name - Tab 过滤: $beforeTabFilter -> ${files.length}');
        }

        logger.i('$name.queryFiles - ⚡ 内存缓存返回: ${files.length} 个文件 (原始: $originalCount)');
        return files;
      }

      // 内存缓存不存在，检查持久化缓存
      logger.d('$name - 内存缓存不存在，检查持久化缓存新鲜度');
    } else {
      logger.i('$name - 💪 forceRefresh=true，跳过内存缓存，执行完整扫描');
    }

    // 4. 慢速路径：执行完整扫描（用户强制刷新或无缓存时）
    logger.d('$name - 执行完整扫描获取最新数据');
    final scanResult = await scanner.scanApp(
      appKey: appKey,
      useMediaStore: useMediaStore,
      updateCache: true, // 始终更新文件数量缓存
      forceRefresh: forceRefresh, // 控制是否使用扫描结果缓存
    );

    // 5. 检查应用是否安装
    if (!scanResult.isInstalled) {
      logger.w('$name - 应用未安装: $appKey');
      return [];
    }

    var files = scanResult.allFiles;
    final originalCount = files.length;

    // 6. 基础文件类型过滤（使用 FileTypesConfig，确保只显示支持的文件类型）
    files = DataSourceHelpers.filterBySupportedTypes(files);
    final filteredBySupport = originalCount - files.length;
    if (filteredBySupport > 0) {
      logger.d('$name - FileTypesConfig 过滤: $originalCount -> ${files.length} (过滤 $filteredBySupport 个不支持的文件)');
    }

    // 7. Tab 文件类型过滤（如果指定了具体的文件类型）
    if (fileTypes != null && fileTypes.isNotEmpty) {
      final beforeTabFilter = files.length;
      files = DataSourceHelpers.filterByFileTypes(files, fileTypes: fileTypes);
      logger.d('$name - Tab 类型过滤: $beforeTabFilter -> ${files.length}');
    }

    logger.i('$name.queryFiles - 完成: ${files.length} 个文件 (原始: $originalCount)');
    return files;
  }

  @override
  String getCacheKey(Map<String, dynamic> params) {
    final appKey = params['appKey'] as String;
    final fileTypes = params['fileTypes'] as List<String>?;

    if (fileTypes == null || fileTypes.isEmpty) {
      return 'app_files_${appKey}_all';
    }

    final typesSuffix = fileTypes.join('_');
    return 'app_files_${appKey}_$typesSuffix';
  }

  @override
  bool get supportsCaching => true;

  @override
  int get cacheExpiration => 24 * 3600; // 24小时（与 UnifiedAppScanner 缓存一致）

  @override
  Map<String, dynamic> getMetadata(Map<String, dynamic> params) {
    final appKey = params['appKey'] as String?;
    return {
      'dataSourceType': 'application',
      'appKey': appKey,
      'scanMethod': 'UnifiedAppScanner',
      'supportMediaStore': true,
    };
  }
}
