import 'package:flutter/material.dart';

class AppTheme {
  // 主色调
  static const Color primarySeedColor = Colors.blue;

  /// 统一的字体大小定义
  static const double fontSizeH1 = 20.0; // 页面主标题
  static const double fontSizeH2 = 16.0; // 区域标题
  static const double fontSizeH3 = 14.0; // 子区域标题
  static const double fontSizeBodyLarge = 14.0; // 重要正文
  static const double fontSizeBodyMedium = 13.0; // 普通正文
  static const double fontSizeBodySmall = 12.0; // 次要信息
  static const double fontSizeCaption = 11.0; // 提示信息
  static const double fontSizeOverline = 10.0; // 标签/徽章

  /// 浅色主题
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: primarySeedColor,
    brightness: Brightness.light,

    // 文本主题
    textTheme: const TextTheme(
      // 标题
      headlineLarge: TextStyle(
        fontSize: fontSizeH1,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        fontSize: fontSizeH2,
        fontWeight: FontWeight.bold,
      ),
      headlineSmall: TextStyle(
        fontSize: fontSizeH3,
        fontWeight: FontWeight.bold,
      ),
      // 正文
      bodyLarge: TextStyle(fontSize: fontSizeBodyLarge),
      bodyMedium: TextStyle(fontSize: fontSizeBodyMedium),
      bodySmall: TextStyle(fontSize: fontSizeBodySmall),
      // 辅助文本
      labelLarge: TextStyle(
        fontSize: fontSizeBodyMedium,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: TextStyle(
        fontSize: fontSizeBodySmall,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(
        fontSize: fontSizeCaption,
        fontWeight: FontWeight.w500,
      ),
      // 标题样式
      titleLarge: TextStyle(fontSize: fontSizeH2, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(
        fontSize: fontSizeBodyLarge,
        fontWeight: FontWeight.w500,
      ),
      titleSmall: TextStyle(
        fontSize: fontSizeBodyMedium,
        fontWeight: FontWeight.w500,
      ),
    ),

    // AppBar 主题
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),

    // Card 主题
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    // FloatingActionButton 主题
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 4,
    ),

    // ListTile 主题
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),

    // Divider 主题
    dividerTheme: const DividerThemeData(thickness: 1, space: 1),
  );

  /// 深色主题
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: primarySeedColor,
    brightness: Brightness.dark,

    // 文本主题
    textTheme: const TextTheme(
      // 标题
      headlineLarge: TextStyle(
        fontSize: fontSizeH1,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        fontSize: fontSizeH2,
        fontWeight: FontWeight.bold,
      ),
      headlineSmall: TextStyle(
        fontSize: fontSizeH3,
        fontWeight: FontWeight.bold,
      ),
      // 正文
      bodyLarge: TextStyle(fontSize: fontSizeBodyLarge),
      bodyMedium: TextStyle(fontSize: fontSizeBodyMedium),
      bodySmall: TextStyle(fontSize: fontSizeBodySmall),
      // 辅助文本
      labelLarge: TextStyle(
        fontSize: fontSizeBodyMedium,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: TextStyle(
        fontSize: fontSizeBodySmall,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(
        fontSize: fontSizeCaption,
        fontWeight: FontWeight.w500,
      ),
      // 标题样式
      titleLarge: TextStyle(fontSize: fontSizeH2, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(
        fontSize: fontSizeBodyLarge,
        fontWeight: FontWeight.w500,
      ),
      titleSmall: TextStyle(
        fontSize: fontSizeBodyMedium,
        fontWeight: FontWeight.w500,
      ),
    ),

    // AppBar 主题
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),

    // Card 主题
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    // FloatingActionButton 主题
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 4,
    ),

    // ListTile 主题
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),

    // Divider 主题
    dividerTheme: const DividerThemeData(thickness: 1, space: 1),
  );
}
