import 'package:easyfile/core/logger.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';
import 'app_initialization_service.dart';
import 'cache_service.dart';

/// 数据加载服务
/// 
/// 根据启动场景从不同源加载数据：
/// - 从缓存加载（重新安装）
/// - 从数据库加载（正常打开）
/// - 降级为完整初始化（缓存过期）
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

  /// 从缓存加载数据
  /// 
  /// 用于重新安装场景
  /// 如果缓存无效，自动降级为完整初始化
  /// 
  /// 流程：
  /// 1. 检查缓存有效性（7天内的缓存）
  /// 2. 如缓存有效，加载基础资源（快速访问、收藏等）
  /// 3. 如缓存无效，降级为完整初始化（阶段1+2+3）
  Future<void> loadFromCache() async {
    logger.i('[DataLoadService] Starting load from cache (reinstall scenario)...');

    try {
      // 检查缓存有效性
      final isValid = await isCacheValid();

      if (!isValid) {
        logger.i(
            '[DataLoadService] Cache invalid or expired, falling back to full initialization');
        // 缓存无效，降级为完整初始化
        await appInitService.initializeFromScratch();
        return;
      }

      // 缓存有效，加载基础资源（不扫描，仅加载已有数据）
      logger.i('[DataLoadService] Cache valid, loading basic resources from database...');

      // P0: 加载基础资源
      await _loadBasicResourcesFromDatabase();

      logger.i('[DataLoadService] Data loaded from cache successfully');
    } catch (e) {
      logger.e('[DataLoadService] Error loading from cache: $e');
      // 如果缓存加载失败，降级为完整初始化
      logger.w('[DataLoadService] Falling back to full initialization due to error');
      await appInitService.initializeFromScratch();
    }
  }

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
  Future<void> loadFromDatabase() async {
    logger.i('[DataLoadService] Starting load from database (normal open scenario)...');

    try {
      // 直接加载基础资源，无扫描
      await _loadBasicResourcesFromDatabase();

      logger.i('[DataLoadService] Data loaded from database successfully');
    } catch (e) {
      logger.e('[DataLoadService] Error loading from database: $e');
      // 如果数据库加载失败，降级为完整初始化
      logger.w('[DataLoadService] Falling back to full initialization due to error');
      await appInitService.initializeFromScratch();
    }
  }

  /// 从本地数据库加载基础资源
  /// 
  /// 这个方法被 loadFromCache() 和 loadFromDatabase() 都会调用
  /// 用于快速加载基础数据而无需扫描文件系统
  /// 注意：主题初始化在 FileBrowserPage._initializeAppWithPermission() 中已完成，
  /// 这里不再重复初始化，避免覆盖用户设置
  Future<void> _loadBasicResourcesFromDatabase() async {
    try {
      logger.i('[DataLoadService] Loading basic resources from database...');

      // 加载快速访问文件夹
      await quickAccessPresenter.loadQuickAccessFolders();
      logger.i('[DataLoadService] Quick access folders loaded');

      // 加载收藏夹
      await filePresenter.initializeFavorites();
      logger.i('[DataLoadService] Favorites loaded');

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

  /// 检查缓存是否有效
  Future<bool> isCacheValid() async {
    return await cacheService.isCacheValid();
  }
}
