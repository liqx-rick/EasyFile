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

  /// 文件扩展名列表
  final List<String> extensions;

  const CategoryInfo({
    required this.type,
    required this.name,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    required this.extensions,
  });

  /// 获取所有支持的分类
  static List<CategoryInfo> get allCategories => [
        // 图片
        const CategoryInfo(
          type: CategoryType.images,
          name: '图片',
          icon: Icons.image,
          backgroundColor: Color(0xFFE3F2FD), // 淡蓝色
          iconColor: Color(0xFF1976D2), // 蓝色
          extensions: [
            'jpg',
            'jpeg',
            'png',
            'gif',
            'bmp',
            'webp',
            'svg',
            'ico',
            'tiff',
            'tif',
            'heic',
            'heif',
          ],
        ),

        // 文档
        const CategoryInfo(
          type: CategoryType.documents,
          name: '文档',
          icon: Icons.description,
          backgroundColor: Color(0xFFF3E5F5), // 淡紫色
          iconColor: Color(0xFF7B1FA2), // 紫色
          extensions: [
            'pdf',
            'doc',
            'docx',
            'txt',
            'rtf',
            'xls',
            'xlsx',
            'ppt',
            'pptx',
            'odt',
            'ods',
            'odp',
            'csv',
            'md',
          ],
        ),

        // 音乐
        const CategoryInfo(
          type: CategoryType.music,
          name: '音乐',
          icon: Icons.music_note,
          backgroundColor: Color(0xFFE8F5E8), // 淡绿色
          iconColor: Color(0xFF388E3C), // 绿色
          extensions: [
            'mp3',
            'wav',
            'flac',
            'm4a',
            'aac',
            'ogg',
            'wma',
            'opus',
            'amr',
            '3gp',
          ],
        ),

        // 视频
        const CategoryInfo(
          type: CategoryType.video,
          name: '视频',
          icon: Icons.video_library,
          backgroundColor: Color(0xFFFFF3E0), // 淡橙色
          iconColor: Color(0xFFF57C00), // 橙色
          extensions: [
            'mp4',
            'avi',
            'mov',
            'wmv',
            'flv',
            'mkv',
            'webm',
            '3gp',
            'rmvb',
            'rm',
            'asf',
          ],
        ),

        // 下载
        const CategoryInfo(
          type: CategoryType.downloads,
          name: '下载',
          icon: Icons.download,
          backgroundColor: Color(0xFFE1F5FE), // 淡青色
          iconColor: Color(0xFF0277BD), // 深蓝色
          extensions: [], // 空数组表示接受所有文件类型
        ),
      ];

  /// 根据文件扩展名获取分类
  static CategoryType? getCategoryByExtension(String extension) {
    final lowerExtension = extension.toLowerCase();

    for (final category in allCategories) {
      if (category.extensions.contains(lowerExtension)) {
        return category.type;
      }
    }

    return null;
  }

  /// 根据分类类型获取分类信息
  static CategoryInfo? getInfoByType(CategoryType type) {
    for (final category in allCategories) {
      if (category.type == type) {
        return category;
      }
    }
    return null;
  }

  /// 检查文件是否属于某个分类
  static bool isFileInCategory(String fileName, CategoryType categoryType) {
    final extension = fileName.split('.').last.toLowerCase();
    final categoryInfo = getInfoByType(categoryType);

    if (categoryInfo == null) return false;

    return categoryInfo.extensions.contains(extension);
  }
}
