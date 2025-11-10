import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
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
          create: (_) => locator<FileViewModel>(), // 延迟创建，优化启动时间
        ),
        ChangeNotifierProvider<SplashViewModel>(
          create: (_) => locator<SplashViewModel>(), // 延迟创建，优化启动时间
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
            // 恢复正常流程：先显示splash page
            initialRoute: '/',
            routes: {
              '/': (context) => const SplashPage(),
              '/fileBrowser': (context) => const FileBrowserPage(),
            },
          );
        },
      ),
    );
  }
}
