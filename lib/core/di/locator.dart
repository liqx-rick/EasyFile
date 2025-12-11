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
import 'package:easyfile/data/repositories/file_repository.dart';
import 'package:easyfile/data/sources/favorites_local_source.dart';
import 'package:easyfile/data/sources/favorite_files_local_source.dart';
import 'package:easyfile/data/sources/local_file_source.dart';
import 'package:easyfile/data/sources/recent_files_local_source.dart';
import 'package:easyfile/data/sources/new_files_scanner.dart';
import 'package:easyfile/data/sources/new_files_local_source.dart';
import 'package:easyfile/data/sources/file_source_detector.dart';
import 'package:easyfile/data/sources/theme_local_source.dart';
import 'package:easyfile/data/sources/quick_access_local_source.dart';
import 'package:easyfile/data/models/new_files_settings.dart';
import 'package:easyfile/data/services/folder_analyzer.dart';
import 'package:easyfile/data/services/smart_app_scanner.dart';
import 'package:easyfile/data/services/user_folder_detector.dart';
import 'package:easyfile/data/services/alias_recommendation_service.dart';
import 'package:easyfile/data/services/data_migration_service.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/viewmodel/splash_viewmodel.dart';
import 'package:easyfile/viewmodel/quick_access_viewmodel.dart';
import 'package:easyfile/ui/widgets/new_folder_notification.dart';

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

  // Data Sources
  locator.registerLazySingleton<FavoritesLocalSource>(() {
    logger.d('Creating FavoritesLocalSource');
    return FavoritesLocalSource();
  });

  locator.registerLazySingleton<FavoriteFilesLocalSource>(() {
    logger.d('Creating FavoriteFilesLocalSource');
    return FavoriteFilesLocalSource();
  });

  locator.registerLazySingleton<RecentFilesLocalSource>(() {
    logger.d('Creating RecentFilesLocalSource');
    return RecentFilesLocalSource();
  });

  locator.registerLazySingleton<ThemeLocalSource>(() {
    logger.d('Creating ThemeLocalSource');
    return ThemeLocalSource();
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

  locator.registerLazySingletonAsync<NewFilesSettings>(() async {
    logger.d('Creating NewFilesSettings');
    return await NewFilesSettings.load();
  });

  locator.registerLazySingletonAsync<NewFilesScanner>(() async {
    logger.d('Creating NewFilesScanner');
    final settings = await locator.getAsync<NewFilesSettings>();
    return NewFilesScanner(settings: settings);
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
    return await AppTrashSettings.create();
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

  locator.registerLazySingleton<SmartAppScanner>(() {
    logger.d('Creating SmartAppScanner');
    return SmartAppScanner();
  });

  locator.registerLazySingleton<UserFolderDetector>(() {
    logger.d('Creating UserFolderDetector');
    return UserFolderDetector();
  });

  locator.registerLazySingleton<AliasRecommendationService>(() {
    logger.d('Creating AliasRecommendationService');
    return AliasRecommendationService();
  });

  locator.registerLazySingleton<DataMigrationService>(() {
    logger.d('Creating DataMigrationService');
    return DataMigrationService(
      favoritesSource: locator<FavoritesLocalSource>(),
      quickAccessSource: locator<QuickAccessLocalSource>(),
      folderAnalyzer: locator<FolderAnalyzer>(),
    );
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
    final favoritesSource = locator<FavoritesLocalSource>();
    final favoriteFilesSource = locator<FavoriteFilesLocalSource>();
    final recentFilesSource = locator<RecentFilesLocalSource>();
    final newFilesScanner = await locator.getAsync<NewFilesScanner>();
    final newFilesLocalSource = locator<NewFilesLocalSource>();
    final newFilesSettings = await locator.getAsync<NewFilesSettings>();
    final themeSource = locator<ThemeLocalSource>();
    final trashDatabase = locator<AppTrashDatabase>();

    logger.d(
      'FilePresenter dependencies: repository=$repository, viewModel=$viewModel, favoritesSource=$favoritesSource, favoriteFilesSource=$favoriteFilesSource, recentFilesSource=$recentFilesSource, themeSource=$themeSource, trashDatabase=$trashDatabase',
    );

    return FilePresenter(
      repository: repository,
      viewModel: viewModel,
      favoritesSource: favoritesSource,
      favoriteFilesSource: favoriteFilesSource,
      recentFilesSource: recentFilesSource,
      newFilesScanner: newFilesScanner,
      newFilesLocalSource: newFilesLocalSource,
      newFilesSettings: newFilesSettings,
      themeSource: themeSource,
      trashDatabase: trashDatabase,
    );
  });

  locator.registerLazySingleton<QuickAccessPresenter>(() {
    logger.d('Creating QuickAccessPresenter (Singleton)');
    final localSource = locator<QuickAccessLocalSource>();
    final viewModel = locator<QuickAccessViewModel>();
    final appScanner = locator<SmartAppScanner>();
    final userDetector = locator<UserFolderDetector>();
    final aliasService = locator<AliasRecommendationService>();
    final notificationService = locator<NewFolderNotificationService>();

    logger.d(
      'QuickAccessPresenter dependencies: localSource=$localSource, viewModel=$viewModel',
    );

    return QuickAccessPresenter(
      localSource: localSource,
      viewModel: viewModel,
      appScanner: appScanner,
      userDetector: userDetector,
      aliasService: aliasService,
      notificationService: notificationService,
    );
  });

  logger.i('Dependency injection setup complete');
}
