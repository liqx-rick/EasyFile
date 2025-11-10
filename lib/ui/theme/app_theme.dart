import 'package:flutter/material.dart';

class AppTheme {
  // 主色调
  static const Color primarySeedColor = Colors.blue;
  
  /// 浅色主题
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: primarySeedColor,
    brightness: Brightness.light,
    
    // AppBar 主题
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    
    // Card 主题
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
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
    dividerTheme: const DividerThemeData(
      thickness: 1,
      space: 1,
    ),
  );

  /// 深色主题
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: primarySeedColor,
    brightness: Brightness.dark,
    
    // AppBar 主题
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    
    // Card 主题
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
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
    dividerTheme: const DividerThemeData(
      thickness: 1,
      space: 1,
    ),
  );
}
