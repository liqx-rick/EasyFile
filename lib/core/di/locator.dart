import 'package:get_it/get_it.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/permission_service.dart';
import 'package:easyfile/data/repositories/file_repository.dart';
import 'package:easyfile/data/sources/favorites_local_source.dart';
import 'package:easyfile/data/sources/favorite_files_local_source.dart';
import 'package:easyfile/data/sources/local_file_source.dart';
import 'package:easyfile/data/sources/recent_files_local_source.dart';
import 'package:easyfile/data/sources/theme_local_source.dart';
import 'package:easyfile/data/sources/quick_access_local_source.dart';
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

  // Services
  locator.registerLazySingleton<PermissionService>(() {
    logger.d('Creating PermissionService');
    return PermissionService();
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
  locator.registerLazySingleton<FilePresenter>(() {
    logger.d('Creating FilePresenter (Singleton)');
    final repository = locator<FileRepository>();
    final viewModel = locator<FileViewModel>();
    final favoritesSource = locator<FavoritesLocalSource>();
    final favoriteFilesSource = locator<FavoriteFilesLocalSource>();
    final recentFilesSource = locator<RecentFilesLocalSource>();
    final themeSource = locator<ThemeLocalSource>();

    logger.d(
      'FilePresenter dependencies: repository=$repository, viewModel=$viewModel, favoritesSource=$favoritesSource, favoriteFilesSource=$favoriteFilesSource, recentFilesSource=$recentFilesSource, themeSource=$themeSource',
    );

    return FilePresenter(
      repository: repository,
      viewModel: viewModel,
      favoritesSource: favoritesSource,
      favoriteFilesSource: favoriteFilesSource,
      recentFilesSource: recentFilesSource,
      themeSource: themeSource,
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
