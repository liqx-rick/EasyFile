import 'package:get_it/get_it.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/permission_service.dart';
import 'package:easyfile/core/services/cache_manager_service.dart';
import 'package:easyfile/core/services/junk_file_service.dart';
import 'package:easyfile/core/services/junk_file_cache_manager.dart';
import 'package:easyfile/core/services/trash_file_service.dart';
import 'package:easyfile/core/services/app_trash_manager.dart';
import 'package:easyfile/core/database/app_trash_database.dart';
import 'package:easyfile/core/settings/app_trash_settings.dart';
import 'package:easyfile/core/services/usage_stats_permission_service.dart';
import 'package:easyfile/core/services/usage_stats_service.dart';
import 'package:easyfile/core/services/app_storage_service.dart';
import 'package:easyfile/core/services/app_storage_cache_manager.dart';
import 'package:easyfile/core/services/app_management_service.dart';
import 'package:easyfile/core/services/system_intent_service.dart';
import 'package:easyfile/core/services/theme_settings_service.dart';
import 'package:easyfile/core/config/feature_config.dart';
import 'package:easyfile/core/config/file_scan_config.dart';
import 'package:easyfile/core/config/storage/config_storage.dart';
import 'package:easyfile/core/config/storage/local_config_storage.dart';
import 'package:easyfile/data/repositories/file_repository.dart';
import 'package:easyfile/data/sources/favorite_files_local_source.dart';
import 'package:easyfile/data/sources/local_file_source.dart';
import 'package:easyfile/data/sources/recent_files_local_source.dart';
import 'package:easyfile/data/sources/new_files_scanner.dart';
import 'package:easyfile/data/sources/new_files_local_source.dart';
import 'package:easyfile/data/sources/file_source_detector.dart';
import 'package:easyfile/data/sources/quick_access_local_source.dart';
import 'package:easyfile/data/services/folder_analyzer.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/viewmodel/splash_viewmodel.dart';
import 'package:easyfile/viewmodel/quick_access_viewmodel.dart';
import 'package:easyfile/ui/widgets/new_folder_notification.dart';
import 'package:easyfile/core/services/startup/startup_orchestrator.dart';
import 'package:easyfile/core/services/startup/app_initialization_service.dart';
import 'package:easyfile/core/services/startup/data_load_service.dart';
import 'package:easyfile/core/services/startup/first_install_service.dart';
import 'package:easyfile/core/services/startup/cache_service.dart';
import 'package:easyfile/core/services/category_file_cache_service.dart';

final locator = GetIt.instance;

void setupLocator() {
  logger.i('Setting up dependency injection...');

  // 如果已经注册过，先重置
  if (locator.isRegistered<FilePresenter>()) {
    logger.w('Locator already initialized, resetting...');
    locator.reset();
  }

  // Core
  locator.registerLazySingleton<AppLogger>(() {
    logger.d('Registering AppLogger singleton');
    return logger;
  });

  // Configuration
  locator.registerLazySingletonAsync<ConfigStorage>(() async {
    logger.d('Creating ConfigStorage (LocalConfigStorage)');
    return await LocalConfigStorage.create();
  });

  locator.registerLazySingletonAsync<FeatureConfig>(() async {
    logger.d('Creating FeatureConfig');
    final storage = await locator.getAsync<ConfigStorage>();
    return FeatureConfig(storage);
  });

  locator.registerLazySingletonAsync<FileScanConfig>(() async {
    logger.d('Creating FileScanConfig');
    final storage = await locator.getAsync<ConfigStorage>();
    return FileScanConfig(storage);
  });

  // Data Sources
  locator.registerLazySingleton<FavoriteFilesLocalSource>(() {
    logger.d('Creating FavoriteFilesLocalSource');
    return FavoriteFilesLocalSource();
  });

  locator.registerLazySingleton<RecentFilesLocalSource>(() {
    logger.d('Creating RecentFilesLocalSource');
    return RecentFilesLocalSource();
  });

  locator.registerLazySingleton<ThemeSettingsService>(() {
    logger.d('Creating ThemeSettingsService');
    return ThemeSettingsService();
  });

  locator.registerLazySingleton<QuickAccessLocalSource>(() {
    logger.d('Creating QuickAccessLocalSource');
    return QuickAccessLocalSource();
  });

  locator.registerLazySingleton<FileSourceDetector>(() {
    logger.d('Creating FileSourceDetector');
    return FileSourceDetector();
  });

  locator.registerLazySingleton<NewFilesLocalSource>(() {
    logger.d('Creating NewFilesLocalSource');
    return NewFilesLocalSource();
  });

  locator.registerLazySingleton<NewFilesScanner>(() {
    logger.d('Creating NewFilesScanner');
    return NewFilesScanner();
  });

  // Services
  locator.registerLazySingleton<PermissionService>(() {
    logger.d('Creating PermissionService');
    return PermissionService();
  });

  locator.registerLazySingleton<CacheManagerService>(() {
    logger.d('Creating CacheManagerService');
    return CacheManagerService();
  });

  locator.registerLazySingleton<JunkFileCacheManager>(() {
    logger.d('Creating JunkFileCacheManager');
    return JunkFileCacheManager();
  });

  locator.registerLazySingletonAsync<JunkFileService>(() async {
    logger.d('Creating JunkFileService');
    final filePresenter = await locator.getAsync<FilePresenter>();
    return JunkFileService(
      filePresenter: filePresenter,
      cacheManager: locator<JunkFileCacheManager>(),
    );
  });

  locator.registerLazySingletonAsync<TrashFileService>(() async {
    logger.d('Creating TrashFileService');
    final filePresenter = await locator.getAsync<FilePresenter>();
    return TrashFileService(
      filePresenter: filePresenter,
    );
  });

  // App Trash Services (Phase 1)
  locator.registerLazySingleton<AppTrashDatabase>(() {
    logger.d('Creating AppTrashDatabase');
    return AppTrashDatabase();
  });

  locator.registerLazySingletonAsync<AppTrashSettings>(() async {
    logger.d('Creating AppTrashSettings');
    final config = await locator.getAsync<FileScanConfig>();
    return AppTrashSettings(config);
  });

  locator.registerLazySingletonAsync<AppTrashManager>(() async {
    logger.d('Creating AppTrashManager');
    final database = locator<AppTrashDatabase>();
    final settings = await locator.getAsync<AppTrashSettings>();
    final manager = AppTrashManager(
      database: database,
      settings: settings,
    );
    await manager.initialize();
    return manager;
  });

  // App Management Services
  locator.registerLazySingleton<SystemIntentService>(() {
    logger.d('Creating SystemIntentService');
    return SystemIntentService();
  });

  locator.registerLazySingleton<UsageStatsPermissionService>(() {
    logger.d('Creating UsageStatsPermissionService');
    return UsageStatsPermissionService();
  });

  locator.registerLazySingleton<AppStorageCacheManager>(() {
    logger.d('Creating AppStorageCacheManager');
    return AppStorageCacheManager();
  });

  locator.registerLazySingleton<AppStorageService>(() {
    logger.d('Creating AppStorageService');
    return AppStorageService();
  });

  locator.registerLazySingleton<UsageStatsService>(() {
    logger.d('Creating UsageStatsService');
    return UsageStatsService();
  });

  locator.registerLazySingleton<AppManagementService>(() {
    logger.d('Creating AppManagementService');
    return AppManagementService(
      locator<AppStorageService>(),
      locator<AppStorageCacheManager>(),
      locator<UsageStatsService>(),
    );
  });

  locator.registerLazySingleton<FolderAnalyzer>(() {
    logger.d('Creating FolderAnalyzer');
    return FolderAnalyzer();
  });

  // Repository
  locator.registerLazySingleton<FileRepository>(() {
    logger.d('Creating FileRepository (LocalFileRepository)');
    return LocalFileRepository();
  });

  // ViewModels - 注册为单例，确保整个应用使用同一个实例
  locator.registerLazySingleton<FileViewModel>(() {
    logger.d('Creating FileViewModel (Singleton)');
    return FileViewModel();
  });

  locator.registerLazySingleton<SplashViewModel>(() {
    logger.d('Creating SplashViewModel (Singleton)');
    return SplashViewModel();
  });

  locator.registerLazySingleton<QuickAccessViewModel>(() {
    logger.d('Creating QuickAccessViewModel (Singleton)');
    return QuickAccessViewModel();
  });

  locator.registerLazySingleton<NewFolderNotificationService>(() {
    logger.d('Creating NewFolderNotificationService (Singleton)');
    return NewFolderNotificationService();
  });

  // Presenter - 使用单例的 ViewModel 和数据源
  locator.registerLazySingletonAsync<FilePresenter>(() async {
    logger.d('Creating FilePresenter (Singleton)');
    final repository = locator<FileRepository>();
    final viewModel = locator<FileViewModel>();
    final favoriteFilesSource = locator<FavoriteFilesLocalSource>();
    final recentFilesSource = locator<RecentFilesLocalSource>();
    final newFilesScanner = locator<NewFilesScanner>();
    final newFilesLocalSource = locator<NewFilesLocalSource>();
    final themeSettingsService = locator<ThemeSettingsService>();
    final trashDatabase = locator<AppTrashDatabase>();

    logger.d(
      'FilePresenter dependencies: repository=$repository, viewModel=$viewModel, favoriteFilesSource=$favoriteFilesSource, recentFilesSource=$recentFilesSource, themeSettingsService=$themeSettingsService, trashDatabase=$trashDatabase',
    );

    return FilePresenter(
      repository: repository,
      viewModel: viewModel,
      favoriteFilesSource: favoriteFilesSource,
      recentFilesSource: recentFilesSource,
      newFilesScanner: newFilesScanner,
      newFilesLocalSource: newFilesLocalSource,
      themeSettingsService: themeSettingsService,
      trashDatabase: trashDatabase,
    );
  });

  locator.registerLazySingleton<QuickAccessPresenter>(() {
    logger.d('Creating QuickAccessPresenter (Singleton)');
    final localSource = locator<QuickAccessLocalSource>();
    final viewModel = locator<QuickAccessViewModel>();

    logger.d(
      'QuickAccessPresenter dependencies: localSource=$localSource, viewModel=$viewModel',
    );

    return QuickAccessPresenter(
      localSource: localSource,
      viewModel: viewModel,
    );
  });

  // 启动服务注册
  locator.registerLazySingleton<FirstInstallService>(() {
    logger.d('Creating FirstInstallService (Singleton)');
    return FirstInstallService();
  });

  locator.registerLazySingleton<CacheService>(() {
    logger.d('Creating CacheService (Singleton)');
    return CacheService();
  });

  locator.registerLazySingleton<CategoryFileCacheService>(() {
    logger.d('Creating CategoryFileCacheService (Singleton)');
    return CategoryFileCacheService();
  });

  locator.registerLazySingletonAsync<AppInitializationService>(() async {
    logger.d('Creating AppInitializationService (Singleton)');
    final filePresenter = await locator.getAsync<FilePresenter>();
    final quickAccessPresenter = locator<QuickAccessPresenter>();
    final firstInstallService = locator<FirstInstallService>();
    final cacheService = locator<CacheService>();

    return AppInitializationService(
      filePresenter: filePresenter,
      quickAccessPresenter: quickAccessPresenter,
      firstInstallService: firstInstallService,
      cacheService: cacheService,
    );
  });

  locator.registerLazySingletonAsync<DataLoadService>(() async {
    logger.d('Creating DataLoadService (Singleton)');
    final appInitService = await locator.getAsync<AppInitializationService>();
    final cacheService = locator<CacheService>();
    final filePresenter = await locator.getAsync<FilePresenter>();
    final quickAccessPresenter = locator<QuickAccessPresenter>();

    return DataLoadService(
      appInitService: appInitService,
      cacheService: cacheService,
      filePresenter: filePresenter,
      quickAccessPresenter: quickAccessPresenter,
    );
  });

  locator.registerLazySingletonAsync<StartupOrchestrator>(() async {
    logger.d('Creating StartupOrchestrator (Singleton)');
    final appInitService = await locator.getAsync<AppInitializationService>();
    final dataLoadService = await locator.getAsync<DataLoadService>();
    final firstInstallService = locator<FirstInstallService>();

    return StartupOrchestrator(
      appInitService: appInitService,
      dataLoadService: dataLoadService,
      firstInstallService: firstInstallService,
    );
  });

  logger.i('Dependency injection setup complete');
}
