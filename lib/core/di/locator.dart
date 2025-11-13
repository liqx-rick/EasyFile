import 'package:get_it/get_it.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/repositories/file_repository.dart';
import 'package:easyfile/data/sources/favorites_local_source.dart';
import 'package:easyfile/data/sources/favorite_files_local_source.dart';
import 'package:easyfile/data/sources/local_file_source.dart';
import 'package:easyfile/data/sources/recent_files_local_source.dart';
import 'package:easyfile/data/sources/theme_local_source.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/viewmodel/splash_viewmodel.dart';

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

  // Presenter - 使用单例的 ViewModel 和数据源
  locator.registerLazySingleton<FilePresenter>(() {
    logger.d('Creating FilePresenter (Singleton)');
    final repository = locator<FileRepository>();
    final viewModel = locator<FileViewModel>();
    final favoritesSource = locator<FavoritesLocalSource>();
    final favoriteFilesSource = locator<FavoriteFilesLocalSource>();
    final recentFilesSource = locator<RecentFilesLocalSource>();
    final themeSource = locator<ThemeLocalSource>();
    
    logger.d('FilePresenter dependencies: repository=$repository, viewModel=$viewModel, favoritesSource=$favoritesSource, favoriteFilesSource=$favoriteFilesSource, recentFilesSource=$recentFilesSource, themeSource=$themeSource');
    
    return FilePresenter(
      repository: repository,
      viewModel: viewModel,
      favoritesSource: favoritesSource,
      favoriteFilesSource: favoriteFilesSource,
      recentFilesSource: recentFilesSource,
      themeSource: themeSource,
    );
  });

  logger.i('Dependency injection setup complete');
}
