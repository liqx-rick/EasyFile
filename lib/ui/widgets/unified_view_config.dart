import 'package:flutter/material.dart';

/// 统一视图配置类
///
/// 为网格视图和列表视图提供统一的配置参数，确保三个页面
/// (file_browser_page, category_file_page, storage_page) 的视觉一致性。
///
/// 使用响应式设计，根据屏幕宽度动态调整缩略图大小。
///
/// 示例:
/// ```dart
/// final config = UnifiedViewConfig.fromContext(context);
/// print(config.gridThumbnailSize);  // 72.0 - 96.0 (动态)
/// print(config.listThumbnailSize);  // 40.0 - 56.0 (动态)
/// ```
class UnifiedViewConfig {
  // ============================================================================
  // 网格视图配置
  // ============================================================================

  /// 网格视图缩略图大小（响应式：72-96px）
  ///
  /// 根据屏幕宽度动态计算：
  /// - 小屏(<360): 72px
  /// - 中屏(360-480): 80px
  /// - 大屏(>480): 96px
  final double gridThumbnailSize;

  /// 网格视图内边距
  static const double gridPadding = 8.0;

  /// 网格项圆角半径
  static const double gridBorderRadius = 8.0;

  /// 网格项内部内边距
  static const double gridItemPadding = 8.0;

  /// 文件名区域固定高度
  static const double fileNameHeight = 40.0;

  /// 文件名文字样式
  static const TextStyle fileNameStyle = TextStyle(
    fontSize: 12,
    height: 1.2,
  );

  /// 文件大小区域固定高度
  static const double fileSizeHeight = 16.0;

  /// 文件大小文字样式
  static TextStyle fileSizeStyle(BuildContext context) => TextStyle(
        fontSize: 11,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  // ============================================================================
  // 列表视图配置
  // ============================================================================

  /// 列表视图缩略图大小（响应式：40-56px）
  ///
  /// 根据屏幕宽度动态计算：
  /// - 小屏(<360): 40px
  /// - 中屏(360-480): 48px
  /// - 大屏(>480): 56px
  final double listThumbnailSize;

  /// 列表项垂直内边距
  static const double listItemVerticalPadding = 8.0;

  /// 列表项水平内边距
  static const double listItemHorizontalPadding = 16.0;

  // ============================================================================
  // 通用配置
  // ============================================================================

  /// 图标和文本之间的间距
  static const double iconTextSpacing = 8.0;

  /// 收藏按钮大小
  static const double favoriteIconSize = 20.0;

  /// 选中状态的复选框大小
  static const double checkboxSize = 24.0;

  /// 选中状态背景透明度
  static const double selectedBackgroundOpacity = 0.3;

  // ============================================================================
  // 构造函数
  // ============================================================================

  const UnifiedViewConfig._({
    required this.gridThumbnailSize,
    required this.listThumbnailSize,
  });

  /// 从 BuildContext 创建响应式配置
  ///
  /// 根据屏幕宽度自动计算合适的缩略图大小。
  factory UnifiedViewConfig.fromContext(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // 网格缩略图：72-96px
    double gridSize;
    if (screenWidth < 360) {
      gridSize = 72.0;
    } else if (screenWidth < 480) {
      gridSize = 80.0;
    } else {
      gridSize = 96.0;
    }

    // 列表缩略图：40-56px
    double listSize;
    if (screenWidth < 360) {
      listSize = 40.0;
    } else if (screenWidth < 480) {
      listSize = 48.0;
    } else {
      listSize = 56.0;
    }

    return UnifiedViewConfig._(
      gridThumbnailSize: gridSize,
      listThumbnailSize: listSize,
    );
  }

  /// 创建固定大小的配置（用于测试）
  factory UnifiedViewConfig.fixed({
    double gridThumbnailSize = 80.0,
    double listThumbnailSize = 48.0,
  }) {
    return UnifiedViewConfig._(
      gridThumbnailSize: gridThumbnailSize,
      listThumbnailSize: listThumbnailSize,
    );
  }

  // ============================================================================
  // 辅助方法
  // ============================================================================

  /// 获取选中状态的背景颜色
  Color getSelectedBackgroundColor(BuildContext context) {
    return Theme.of(context)
        .colorScheme
        .primary
        .withValues(alpha: selectedBackgroundOpacity);
  }

  /// 获取未选中状态的背景颜色
  Color getUnselectedBackgroundColor(BuildContext context) {
    return Theme.of(context).colorScheme.surface;
  }

  /// 获取文件大小文字颜色
  Color getFileSizeColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  @override
  String toString() {
    return 'UnifiedViewConfig('
        'gridThumbnail: $gridThumbnailSize, '
        'listThumbnail: $listThumbnailSize)';
  }
}
