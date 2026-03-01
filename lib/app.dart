import 'package:easyfile/analytics/analytics_manager.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/category_group_service.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/permission_service.dart';
import 'package:easyfile/core/services/privacy_consent_service.dart';
import 'package:easyfile/core/services/privacy_session_manager.dart';
import 'package:easyfile/core/services/theme_settings_service.dart';
import 'package:easyfile/core/services/view_mode_service.dart';
import 'package:easyfile/ui/pages/main_container_page.dart';
import 'package:easyfile/ui/pages/splash_page.dart';
import 'package:easyfile/ui/theme/app_theme.dart';
import 'package:easyfile/ui/widgets/privacy_policy_dialog.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/viewmodel/splash_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EasyFileApp extends StatefulWidget {
  const EasyFileApp({super.key});

  @override
  State<EasyFileApp> createState() => _EasyFileAppState();
}

class _EasyFileAppState extends State<EasyFileApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // 注册应用生命周期监听器
    WidgetsBinding.instance.addObserver(this);
    logger.i('📱 应用生命周期监听器已注册');
  }

  @override
  void dispose() {
    // 移除应用生命周期监听器
    WidgetsBinding.instance.removeObserver(this);
    logger.i('📱 应用生命周期监听器已移除');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final sessionManager = PrivacySessionManager();

    switch (state) {
      case AppLifecycleState.resumed:
        // 应用返回前台
        sessionManager.onAppResumed();
        AnalyticsManager.log('app_foreground');
        logger.d('📱 [Analytics] app_foreground');
        break;
      case AppLifecycleState.inactive:
        // 应用进入非活动状态（例如接听电话、系统对话框）
        // 暂不处理，等待真正进入后台
        logger.d('📱 应用进入非活动状态');
        break;
      case AppLifecycleState.paused:
        // 应用进入后台
        sessionManager.onAppPaused();
        AnalyticsManager.log('app_background');
        logger.d('📱 [Analytics] app_background');
        break;
      case AppLifecycleState.detached:
        // 应用即将被销毁
        logger.i('📱 应用即将被销毁');
        break;
      case AppLifecycleState.hidden:
        // 应用在后台但仍在运行
        logger.d('📱 应用在后台运行');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    logger.d('Building EasyFileApp');

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
        ChangeNotifierProvider<ThemeSettingsService>.value(
          value: ThemeSettingsService(),
        ),
      ],
      child: Consumer2<FileViewModel, ThemeSettingsService>(
        builder: (context, fileViewModel, themeService, _) {
          final themeMode = themeService.themeMode;

          return MaterialApp(
            title: '易览文件',
            debugShowCheckedModeBanner: false,
            themeMode: themeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            initialRoute: '/',
            routes: {'/': (context) => const AppNavigator()},
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

class AppNavigator extends StatefulWidget {
  const AppNavigator({super.key});

  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator> with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  bool _hasCompletedSplash = false;
  bool _isLoadingState = true;

  // 静态变量：标记应用是否已经显示过 Splash（整个进程生命周期内）
  static bool _hasShownSplashInThisProcess = false;
  static DateTime? _processStartTime;

  // MethodChannel 用于与原生通信
  static const platform = MethodChannel('com.guangqi.easyfile/state');

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
    // ===== 合规检查：在进入 try-finally 之前先检查隐私政策同意状态 =====
    // 必须在请求任何权限之前先获得用户同意（符合《审核指南》7.5项要求）
    // 注意：此处不在 try-finally 内，未同意时直接 return，不触发 finally 的 UI 更新，
    // 确保 _isLoadingState 保持 true（显示 loading 界面）直到用户真正同意为止。
    final hasConsented = await PrivacyConsentService.hasUserConsented();
    logger.i('_initializeApp: Privacy consent status = $hasConsented');

    if (!hasConsented) {
      // 用户未同意隐私政策：保持 loading 状态，仅弹出隐私政策对话框
      // _isLoadingState 维持 true，不执行任何初始化逻辑
      logger.i('_initializeApp: Consent not given, showing privacy dialog...');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPrivacyPolicyDialog();
      });
      // 移除 native splash，显示 loading spinner + 隐私政策弹窗
      try {
        FlutterNativeSplash.remove();
      } catch (_) {}
      return; // 不进入 try-finally，_isLoadingState 保持 true
    }

    // ===== 用户已同意隐私政策，执行完整初始化流程 =====
    try {
      logger.i('_initializeApp: Starting full initialization...');

      // 用户已同意，请求存储权限并完成 Analytics 初始化
      await _requestStoragePermissionIfNeeded();
      await _completeAnalyticsInitialization();

      // 检查是否从后台恢复
      bool isRestoringFromBackground = false;
      try {
        logger.i('_initializeApp: Checking background restore state...');
        isRestoringFromBackground = await platform.invokeMethod<bool>('isRestoringFromBackground') ?? false;
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
      final timeSinceStart = DateTime.now().difference(_processStartTime!).inSeconds;
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

  /// 完成 Analytics 初始化（用户同意隐私政策后）
  Future<void> _completeAnalyticsInitialization() async {
    try {
      // ===== 合规步骤2: 授权隐私政策 =====
      await AnalyticsManager.grant();
      logger.i('✓ Analytics privacy granted (Step 2/3)');

      // ===== 合规步骤3: 正式初始化 =====
      await AnalyticsManager.init();
      logger.i('✓ Analytics initialized (Step 3/3)');

      // 记录应用启动事件
      await AnalyticsManager.log('app_launch', params: {
        'launch_type': 'cold',
      });
      logger.d('[Analytics] app_launch logged');
    } catch (e) {
      logger.e('Analytics initialization failed: $e');
    }
  }

  /// 如果需要，请求存储权限（仅在首次启动且未授予时）
  Future<void> _requestStoragePermissionIfNeeded() async {
    try {
      logger.i('_requestStoragePermissionIfNeeded: Checking permissions...');

      // 检查 MANAGE_EXTERNAL_STORAGE 权限状态（最高权限）
      final manageStorageStatus = await Permission.manageExternalStorage.status;

      // 如果已有完整文件管理权限，无需请求其他权限
      if (manageStorageStatus.isGranted) {
        logger.i(
            '_requestStoragePermissionIfNeeded: MANAGE_EXTERNAL_STORAGE already granted, no other permissions needed');
        return;
      }

      // 如果没有完整权限，尝试请求（只在首次启动时）
      if (manageStorageStatus.isDenied && !manageStorageStatus.isPermanentlyDenied) {
        logger.i('_requestStoragePermissionIfNeeded: Requesting MANAGE_EXTERNAL_STORAGE...');
        final result = await Permission.manageExternalStorage.request();

        // 如果用户授予了完整权限，直接返回
        if (result.isGranted) {
          logger.i('_requestStoragePermissionIfNeeded: MANAGE_EXTERNAL_STORAGE granted');
          return;
        }
      }

      // 如果没有获得完整权限，检查基础存储权限
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isDenied && !storageStatus.isPermanentlyDenied) {
        logger.i('_requestStoragePermissionIfNeeded: Requesting basic storage permission...');
        await Permission.storage.request();
      }

      // 对于 Android 13+，如果没有完整权限，请求照片和视频权限
      // 注意：只有在用户拒绝或无法获得 MANAGE_EXTERNAL_STORAGE 时才需要
      final photosStatus = await Permission.photos.status;
      final videosStatus = await Permission.videos.status;

      if (photosStatus.isDenied && !photosStatus.isPermanentlyDenied) {
        logger.i('_requestStoragePermissionIfNeeded: Requesting photos permission (Android 13+)...');
        await Permission.photos.request();
      }
      if (videosStatus.isDenied && !videosStatus.isPermanentlyDenied) {
        logger.i('_requestStoragePermissionIfNeeded: Requesting videos permission (Android 13+)...');
        await Permission.videos.request();
      }

      logger.i('_requestStoragePermissionIfNeeded: Permission requests completed');
    } catch (e) {
      logger.w('_requestStoragePermissionIfNeeded: Error requesting permissions: $e');
      // 权限请求失败不阻塞启动
    }
  }

  /// 显示隐私政策弹窗
  void _showPrivacyPolicyDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PrivacyPolicyDialog(
        onAgree: () async {
          Navigator.of(context).pop();
          logger.i('User agreed to privacy policy');

          // 保存用户同意状态
          await PrivacyConsentService.setUserConsented();

          // 重新调用 _initializeApp()：此时 hasConsented=true，
          // 将执行完整初始化流程并通过 finally 块更新 UI
          // （不在此处手动 setState，避免在初始化完成前提前渲染页面）
          _initializeApp();
        },
        onDisagree: () {
          logger.i('User disagreed with privacy policy, exiting app');
          // 用户不同意，退出应用
          SystemNavigator.pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoadingState) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return _hasCompletedSplash ? const MainContainerPage() : SplashPage(onComplete: _onSplashComplete);
  }
}
