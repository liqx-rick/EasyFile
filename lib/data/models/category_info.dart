import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:flutter/material.dart';

/// 文件分类类型枚举
enum CategoryType {
  /// 图片文件
  images,

  /// 文档文件
  documents,

  /// 音乐文件
  music,

  /// 视频文件
  video,

  /// 下载文件
  downloads,

  /// APK文件
  apk,

  /// 压缩包文件
  archive,
}

/// 文件分类信息
class CategoryInfo {
  /// 分类类型
  final CategoryType type;

  /// 显示名称
  final String name;

  /// 图标
  final IconData icon;

  /// 背景颜色
  final Color backgroundColor;

  /// 图标颜色
  final Color iconColor;

  const CategoryInfo({
    required this.type,
    required this.name,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
  });

  /// 动态获取文件扩展名列表（从 FileTypesConfig 获取）
  List<String> getExtensions() {
    final config = AppConfig.instance.fileTypes;
    switch (type) {
      case CategoryType.images:
        return config.imageExtensions;
      case CategoryType.video:
        return config.videoExtensions;
      case CategoryType.music:
        return config.audioExtensions;
      case CategoryType.documents:
        return config.documentExtensions;
      case CategoryType.archive:
        return config.archiveExtensions;
      case CategoryType.apk:
        return config.apkExtensions;
      case CategoryType.downloads:
        return []; // 空数组表示接受所有文件类型
    }
  }

  /// 所有分类的完整定义（供内部功能使用）
  static const List<CategoryInfo> _allCategoryDefinitions = [
    // 图片
    CategoryInfo(
      type: CategoryType.images,
      name: '图片',
      icon: Icons.image,
      backgroundColor: Color(0xFFE3F2FD), // 淡蓝色
      iconColor: Color(0xFF1976D2), // 蓝色
    ),

    // 文档
    CategoryInfo(
      type: CategoryType.documents,
      name: '文档',
      icon: Icons.description,
      backgroundColor: Color(0xFFF3E5F5), // 淡紫色
      iconColor: Color(0xFF7B1FA2), // 紫色
    ),

    // 音乐
    CategoryInfo(
      type: CategoryType.music,
      name: '音乐',
      icon: Icons.music_note,
      backgroundColor: Color(0xFFE3F2FD), // 淡蓝色
      iconColor: Color(0xFF1976D2), // 蓝色 (接近primaryColor)
    ),

    // 视频
    CategoryInfo(
      type: CategoryType.video,
      name: '视频',
      icon: Icons.video_library,
      backgroundColor: Color(0xFFFFF3E0), // 淡橙色
      iconColor: Color(0xFFF57C00), // 橙色
    ),

    // 下载
    CategoryInfo(
      type: CategoryType.downloads,
      name: '下载',
      icon: Icons.download,
      backgroundColor: Color(0xFFE1F5FE), // 淡青色
      iconColor: Color(0xFF0277BD), // 深蓝色
    ),

    // APK
    CategoryInfo(
      type: CategoryType.apk,
      name: 'APK',
      icon: Icons.android,
      backgroundColor: Color(0xFFE8F5E9), // 淡绿色
      iconColor: Color(0xFF4CAF50), // 绿色
    ),

    // 压缩包
    CategoryInfo(
      type: CategoryType.archive,
      name: '压缩包',
      icon: Icons.archive,
      backgroundColor: Color(0xFFFFF9C4), // 淡黄色
      iconColor: Color(0xFFFBC02D), // 黄色
    ),
  ];

  /// 获取首页导航显示的分类（仅前5个）
  static List<CategoryInfo> get allCategories => _allCategoryDefinitions.sublist(0, 5);

  /// 根据文件扩展名获取分类
  static CategoryType? getCategoryByExtension(String extension) {
    final lowerExtension = extension.toLowerCase();

    for (final category in _allCategoryDefinitions) {
      if (category.getExtensions().contains(lowerExtension)) {
        return category.type;
      }
    }

    return null;
  }

  /// 根据分类类型获取分类信息
  static CategoryInfo? getInfoByType(CategoryType type) {
    for (final category in _allCategoryDefinitions) {
      if (category.type == type) {
        return category;
      }
    }
    return null;
  }

  /// 检查文件是否属于某个分类
  static bool isFileInCategory(String fileName, CategoryType categoryType) {
    // 使用 FileUtils.getExtension() 支持双扩展名识别（如 app.apk.1）
    final extension = FileUtils.getExtension(fileName);
    final categoryInfo = getInfoByType(categoryType);

    if (categoryInfo == null) return false;

    return categoryInfo.getExtensions().contains(extension);
  }
}
