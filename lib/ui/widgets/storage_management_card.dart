import 'package:flutter/material.dart';
import '../../ui/pages/storage_management_page.dart';

/// 存储管理功能卡片
/// 
/// 用于主页快速访问区域，提供存储管理功能的快捷入口。
/// 点击后跳转到存储管理页面，查看存储概览、缓存管理、分类统计等功能。
/// 
/// 特性：
/// - 支持单行/双行两种布局模式
/// - 所有尺寸（图标、文字、间距、padding）均根据可用高度动态计算
/// - 活泼的视觉设计：橙色渐变背景 + 白色圆形图标 + 橙色文字
class StorageManagementCard extends StatelessWidget {
  /// 是否为紧凑模式（单行并排显示）
  final bool isCompactMode;
  
  /// 卡片可用高度，用于动态计算内部元素尺寸
  final double availableHeight;

  const StorageManagementCard({
    super.key,
    required this.isCompactMode,
    required this.availableHeight,
  });

  @override
  Widget build(BuildContext context) {
    // 根据可用高度动态计算padding（避免固定padding导致溢出）
    final cardPadding = (availableHeight * 0.04).clamp(3.0, 6.0);
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const StorageManagementPage(),
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.6),
              Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.3),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    // 根据可用高度动态计算尺寸（按比例分配，避免固定尺寸导致溢出）
    double iconSize;
    double fontSize;
    double spacing;
    bool useHorizontalLayout = false;

    if (isCompactMode) {
      // 单行模式：图标+文字竖排（图标上方，文字下方）
      // 比例分配：图标30% + 文字15% + 间距3% + padding 8% = 56%，留44%余量
      iconSize = (availableHeight * 0.30).clamp(14.0, 28.0);
      fontSize = (availableHeight * 0.15).clamp(10.0, 14.0);
      spacing = (availableHeight * 0.03).clamp(1.0, 4.0);
    } else {
      // 双行模式：图标+文字横排（图标左侧，文字右侧）
      // 比例分配：图标45% + 文字25% + 间距10% + padding 8% = 88%，留12%余量
      useHorizontalLayout = true;
      iconSize = (availableHeight * 0.45).clamp(16.0, 30.0);
      fontSize = (availableHeight * 0.25).clamp(11.0, 15.0);
      spacing = (availableHeight * 0.10).clamp(3.0, 10.0);
    }

    if (useHorizontalLayout) {
      // 横向布局：图标 + 文字横排
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(iconSize * 0.25),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.35),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.storage,
              size: iconSize,
              color: Colors.white,
            ),
          ),
          SizedBox(width: spacing),
          Text(
            '存储管理',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: fontSize,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
          ),
        ],
      );
    } else {
      // 竖向布局：图标 + 文字竖排
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(iconSize * 0.25),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.35),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.cleaning_services,
              size: iconSize,
              color: Colors.white,
            ),
          ),
          SizedBox(height: spacing),
          Text(
            '存储管理',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: fontSize,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
          ),
        ],
      );
    }
  }
}
