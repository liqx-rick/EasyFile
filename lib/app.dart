import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/permission_service.dart';
import 'package:easyfile/core/services/view_mode_service.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/category_group_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/ui/pages/file_browser_page.dart';
import 'package:easyfile/ui/pages/splash_page.dart';
import 'package:easyfile/ui/theme/app_theme.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/viewmodel/splash_viewmodel.dart';

class EasyFileApp extends StatelessWidget {
  const EasyFileApp({super.key});

  @override
  Widget build(BuildContext context) {
    logger.i('Building EasyFileApp');

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<FileViewModel>(
          create: (_) => locator<FileViewModel>(),
        ),
        ChangeNotifierProvider<SplashViewModel>(
          create: (_) => locator<SplashViewModel>(),
        ),
        ChangeNotifierProvider<ViewModeService>.value(
          value: ViewModeService(),
        ),
        ChangeNotifierProvider<CategorySortService>.value(
          value: CategorySortService(),
        ),
        ChangeNotifierProvider<CategoryGroupService>.value(
          value: CategoryGroupService(),
        ),
        ChangeNotifierProvider<PageSettingsService>.value(
          value: PageSettingsService(),
        ),
        ChangeNotifierProvider<PermissionService>.value(
          value: locator<PermissionService>(),
        ),
      ],
      child: Consumer<FileViewModel>(
        builder: (context, viewModel, _) {
          return MaterialApp(
            title: 'EasyFile',
            debugShowCheckedModeBanner: false,
            themeMode: viewModel.themeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            // 使用命名路由系统
            initialRoute: '/',
            routes: {'/': (context) => const AppNavigator()},
            // 保持导航栈在应用生命周期中
            navigatorObservers: [_AppNavigatorObserver()],
          );
        },
      ),
    );
  }
}

/// 导航观察器 - 用于调试
class _AppNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    logger.d('Navigator: didPush ${route.settings.name}');
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    logger.d('Navigator: didPop ${route.settings.name}');
  }
}

/// 应用导航器 - 管理页面切换逻辑
class AppNavigator extends StatefulWidget {
  const AppNavigator({super.key});

  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  bool _hasCompletedSplash = false;
  bool _isLoadingState = true;

  // 静态变量：标记应用是否已经显示过 Splash（整个进程生命周期内）
  static bool _hasShownSplashInThisProcess = false;
  static DateTime? _processStartTime;

  // MethodChannel 用于与原生通信
  static const platform = MethodChannel('com.example.easyfile/state');

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 记录进程启动时间
    if (_processStartTime == null) {
      _processStartTime = DateTime.now();
      logger.i('AppNavigator: NEW PROCESS started at $_processStartTime');
    }

    // 添加保险措施：5秒后强制移除 native splash
    Future.delayed(const Duration(seconds: 5), () {
      logger.w('Force removing native splash after 5 seconds timeout');
      FlutterNativeSplash.remove();
    });

    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      logger.i('_initializeApp: Starting initialization...');
      
      // 检查是否从后台恢复
      bool isRestoringFromBackground = false;
      try {
        logger.i('_initializeApp: Checking background restore state...');
        isRestoringFromBackground = await platform
            .invokeMethod<bool>('isRestoringFromBackground') ?? false;
        logger.i('_initializeApp: isRestoringFromBackground = $isRestoringFromBackground');
      } catch (e) {
        logger.w('_initializeApp: Platform method failed (using default): $e');
        isRestoringFromBackground = false;
      }

      logger.i(
        'App initialization - Restoring from background: $isRestoringFromBackground',
      );

      if (isRestoringFromBackground) {
        // 从后台恢复：不显示 Splash Page，恢复之前的状态
        _hasCompletedSplash = true;
        logger.i('Restoring from background - will restore previous state');
      } else {
        // 新打开应用：根据进程状态决定是否显示 Splash Page
        _hasCompletedSplash = _hasShownSplashInThisProcess;
        if (!_hasCompletedSplash) {
          logger.i('New app launch - will show splash and reset to Recent tab');

          // 清除保存的状态并重置 FileViewModel
          try {
            logger.i('_initializeApp: Clearing saved state...');
            final prefs = await SharedPreferences.getInstance();
            await Future.wait([
              prefs.remove('last_viewed_file_path'),
              prefs.remove('current_tab'),
              prefs.remove('last_browse_path'),
            ]);
            logger.i('_initializeApp: State cleared');
          } catch (e) {
            logger.w('_initializeApp: Could not clear preferences: $e');
          }

          // 重置 FileViewModel 到默认状态（Recent tab）
          try {
            logger.i('_initializeApp: Resetting FileViewModel...');
            locator<FileViewModel>().resetToDefault();
            logger.i('FileViewModel reset to Recent tab');
          } catch (e) {
            logger.w('Could not reset FileViewModel: $e');
          }
        }
      }
      
      logger.i('_initializeApp: Initialization complete');
    } catch (e, stackTrace) {
      logger.e('Error in _initializeApp: $e\n$stackTrace');
      _hasCompletedSplash = _hasShownSplashInThisProcess;
    } finally {
      logger.i('_initializeApp: Updating UI and removing native splash');
      if (mounted) {
        setState(() {
          _isLoadingState = false;
        });
      }
      // 确保移除 native splash
      try {
        FlutterNativeSplash.remove();
        logger.i('_initializeApp: Native splash removed');
      } catch (e) {
        logger.e('_initializeApp: Error removing native splash: $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (_processStartTime != null) {
      final timeSinceStart =
          DateTime.now().difference(_processStartTime!).inSeconds;
      logger.i('App lifecycle: $state (${timeSinceStart}s since start)');
    }

    if (state == AppLifecycleState.paused) {
      logger.w('App going to background');
    } else if (state == AppLifecycleState.resumed) {
      logger.i('App resumed');
    }
  }

  void _onSplashComplete() {
    logger.i('Splash complete');
    _hasShownSplashInThisProcess = true;

    if (mounted) {
      setState(() {
        _hasCompletedSplash = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoadingState) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return _hasCompletedSplash
        ? const FileBrowserPage()
        : SplashPage(onComplete: _onSplashComplete);
  }
}
