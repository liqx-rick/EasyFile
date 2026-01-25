import 'package:easyfile/core/data_sources/file_list_data_source.dart';
import 'package:easyfile/core/data_sources/data_source_helpers.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';

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

    logger.i('$name.queryFiles - appKey: $appKey, fileTypes: $fileTypes');

    // 3. 执行扫描（默认使用缓存，除非forceRefresh=true）
    final scanResult = await scanner.scanApp(
      appKey: appKey,
      useMediaStore: useMediaStore,
      updateCache: true,     // 始终更新文件数量缓存
      forceRefresh: forceRefresh, // 控制是否使用扫描结果缓存
    );

    // 4. 检查应用是否安装
    if (!scanResult.isInstalled) {
      logger.w('$name - 应用未安装: $appKey');
      return [];
    }

    var files = scanResult.allFiles;
    final originalCount = files.length;

    // 5. 基础文件类型过滤（使用 FileTypesConfig，确保只显示支持的文件类型）
    files = DataSourceHelpers.filterBySupportedTypes(files);
    final filteredBySupport = originalCount - files.length;
    if (filteredBySupport > 0) {
      logger.d(
          '$name - FileTypesConfig 过滤: $originalCount -> ${files.length} (过滤 $filteredBySupport 个不支持的文件)');
    }

    // 6. Tab 文件类型过滤（如果指定了具体的文件类型）
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
  int get cacheExpiration => 6 * 3600; // 6小时（与 UnifiedAppScanner 缓存一致）

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
