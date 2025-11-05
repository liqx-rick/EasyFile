import 'package:get_it/get_it.dart';
import 'package:easyfile/data/repositories/file_repository.dart';
import 'package:easyfile/data/sources/local_file_source.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/logger.dart';

final locator = GetIt.instance;

void setupLocator() {
  logger.i('Setting up dependency injection...');
  
  // Repository
  locator.registerLazySingleton<FileRepository>(() {
  logger.d('Creating FileRepository (LocalFileRepository)');
    return LocalFileRepository();
  });
  
  // ViewModel - 注册为单例，确保整个应用使用同一个实例
  locator.registerLazySingleton<FileViewModel>(() {
  logger.d('Creating FileViewModel (Singleton)');
    return FileViewModel();
  });
  
  // Presenter - 使用单例的 ViewModel
  locator.registerLazySingleton<FilePresenter>(() {
  logger.d('Creating FilePresenter (Singleton)');
    final repository = locator<FileRepository>();
    final viewModel = locator<FileViewModel>();
    return FilePresenter(repository, viewModel);
  });
  
  logger.i('Dependency injection setup complete');
}
