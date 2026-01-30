import 'package:easyfile/core/logger.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';

import 'app_initialization_service.dart';
import 'cache_service.dart';

/// 数据加载服务
///
/// 根据启动场景从不同源加载数据：
/// - 从数据库加载（正常打开）
class DataLoadService {
  final AppInitializationService appInitService;
  final CacheService cacheService;
  final FilePresenter filePresenter;
  final QuickAccessPresenter quickAccessPresenter;

  DataLoadService({
    required this.appInitService,
    required this.cacheService,
    required this.filePresenter,
    required this.quickAccessPresenter,
  });

  /// 从数据库加载数据
  ///
  /// 用于正常打开场景
  /// 最快的加载方式，直接读取本地数据库
  ///
  /// 流程：
  /// 1. 加载快速访问文件夹
  /// 2. 加载收藏夹
  /// 3. 加载主题
  /// 无需扫描文件系统
  ///
  /// 注意：异常由内部 _loadBasicResourcesFromDatabase() 处理，使用默认值继续
  Future<void> loadFromDatabase() async {
    logger.i('[DataLoadService] Starting load from database (normal open scenario)...');

    await _loadBasicResourcesFromDatabase();

    logger.i('[DataLoadService] Data loaded from database successfully');
  }

  /// 从本地数据库加载基础资源
  ///
  /// 用于快速加载基础数据而无需扫描文件系统
  /// 注意：主题初始化在 FileBrowserPage._initializeAppWithPermission() 中已完成，
  /// 这里不再重复初始化，避免覆盖用户设置
  Future<void> _loadBasicResourcesFromDatabase() async {
    try {
      logger.i('[DataLoadService] Loading basic resources from database...');

      // 加载快速访问文件夹
      await quickAccessPresenter.loadQuickAccessFolders();
      logger.i('[DataLoadService] Quick access folders loaded');

      // 加载收藏文件
      await filePresenter.initializeFavoriteFiles();
      logger.i('[DataLoadService] Favorite files loaded');

      logger.i('[DataLoadService] Basic resources loaded successfully');
    } catch (e) {
      logger.e('[DataLoadService] Error loading basic resources: $e');
      // 基础资源加载失败时使用默认值继续
      logger.w('[DataLoadService] Using default values for basic resources');
    }
  }
}
