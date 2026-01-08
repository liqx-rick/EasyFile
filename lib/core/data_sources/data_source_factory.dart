import 'package:easyfile/core/data_sources/file_list_data_source.dart';
import 'package:easyfile/core/data_sources/media_store_data_source.dart';
import 'package:easyfile/core/data_sources/app_files_data_source.dart';
import 'package:easyfile/core/data_sources/large_files_data_source.dart';
import 'package:easyfile/core/data_sources/category_file_data_source.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/data/models/recommendation_card.dart';

/// 数据源工厂
///
/// 职责：
/// - 根据推荐类型或标识符创建对应的数据源实例
/// - 管理数据源的依赖注入
/// - 提供类型安全的数据源创建方法
///
/// 使用示例：
/// ```dart
/// // 创建工厂
/// final factory = DataSourceFactory(
///   scanner: unifiedScanner,
///   detectionService: detectionService,
///   presenter: filePresenter,
/// );
///
/// // 根据推荐类型创建数据源
/// final dataSource = factory.createFromRecommendationType(
///   RecommendationType.wechat
/// );
///
/// // 根据 queryStrategy 创建数据源
/// final dataSource2 = factory.create('app_files');
/// ```
class DataSourceFactory {
  final UnifiedAppScanner? scanner;
  final AppDetectionService? detectionService;
  final FilePresenter? presenter;

  DataSourceFactory({
    this.scanner,
    this.detectionService,
    this.presenter,
  });

  /// 根据 queryStrategy 标识符创建数据源
  ///
  /// 支持的标识符：
  /// - 'app_files': AppFilesDataSource
  /// - 'time_memory': TimeMemoryDataSource
  /// - 'life_moments': LifeMomentsDataSource
  /// - 'audio_records': AudioRecordsDataSource
  /// - 'large_files': LargeFilesDataSource
  /// - 'category_files': CategoryFileDataSource
  FileListDataSource create(String queryStrategy) {
    switch (queryStrategy) {
      case 'app_files':
        if (scanner == null || detectionService == null) {
          throw StateError(
              'AppFilesDataSource 需要 UnifiedAppScanner 和 AppDetectionService');
        }
        return AppFilesDataSource(
          scanner: scanner!,
          detectionService: detectionService!,
        );

      case 'time_memory':
        return MediaStoreDataSource(
          type: MediaStoreType.cameraPhotos,
          name: 'TimeMemory',
        );

      case 'life_moments':
        return MediaStoreDataSource(
          type: MediaStoreType.cameraVideos,
          name: 'LifeMoments',
        );

      case 'audio_records':
        return MediaStoreDataSource(
          type: MediaStoreType.recordings,
          name: 'AudioRecords',
        );

      case 'large_files':
        return LargeFilesDataSource();

      case 'category_files':
        if (presenter == null) {
          throw StateError('CategoryFileDataSource 需要 FilePresenter');
        }
        return CategoryFileDataSource(presenter: presenter!);

      default:
        throw ArgumentError('未知的 queryStrategy: $queryStrategy');
    }
  }

  /// 根据 RecommendationType 创建数据源
  ///
  /// 便捷方法，直接从推荐类型映射到数据源
  FileListDataSource createFromRecommendationType(RecommendationType type) {
    // 应用类推荐
    if (type == RecommendationType.wechat ||
        type == RecommendationType.qq ||
        type == RecommendationType.telegram ||
        type == RecommendationType.wps) {
      return create('app_files');
    }

    // 系统类推荐
    switch (type) {
      case RecommendationType.memories:
        return create('time_memory');

      case RecommendationType.videos:
        return create('life_moments');

      case RecommendationType.recordings:
        return create('audio_records');

      case RecommendationType.largeFiles:
        return create('large_files');

      default:
        throw ArgumentError('未支持的推荐类型: $type');
    }
  }

  /// 批量创建数据源
  ///
  /// [strategies] queryStrategy 列表
  /// 返回数据源映射表（strategy -> dataSource）
  Map<String, FileListDataSource> createBatch(List<String> strategies) {
    final result = <String, FileListDataSource>{};

    for (final strategy in strategies) {
      result[strategy] = create(strategy);
    }

    return result;
  }

  /// 获取所有支持的 queryStrategy
  static List<String> getSupportedStrategies() {
    return [
      'app_files',
      'time_memory',
      'life_moments',
      'audio_records',
      'large_files',
      'category_files',
    ];
  }

  /// 获取 queryStrategy 的描述信息
  static Map<String, String> getStrategyDescriptions() {
    return {
      'app_files': '应用文件扫描（微信、QQ等）',
      'time_memory': '时光记忆（系统相机照片）',
      'life_moments': '生活剪影（系统相机视频）',
      'audio_records': '声音记录（录音文件）',
      'large_files': '大文件扫描（>100MB）',
      'category_files': '分类文件扫描（图片、视频等）',
    };
  }
}
