import 'package:flutter/material.dart';
import 'package:easyfile/ui/pages/file_browser_page.dart';
import 'package:easyfile/ui/theme/app_theme.dart';

class EasyFileApp extends StatelessWidget {
  const EasyFileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyFile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const FileBrowserPage(),
    );
  }
}
