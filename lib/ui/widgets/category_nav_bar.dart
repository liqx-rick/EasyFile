import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/pages/category_file_page.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';

/// 分类导航栏组件
///
/// 显示五类文件快捷入口：图片、文档、音乐、视频、下载
class CategoryNavBar extends StatelessWidget {
  final FilePresenter presenter;
  final FileViewModel viewModel;
  final Function(double)? onCardSizeCalculated;

  const CategoryNavBar({
    super.key,
    required this.presenter,
    required this.viewModel,
    this.onCardSizeCalculated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: _buildCategoryGrid(context),
    );
  }

  /// 构建分类网格 - 适应屏幕宽度
  Widget _buildCategoryGrid(BuildContext context) {
    final categories = CategoryInfo.allCategories;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据屏幕宽度动态调整
        final screenWidth = constraints.maxWidth;
        final crossAxisCount = 5; // 固定5列

        // 计算可用宽度和间距
        final totalHorizontalPadding = 16; // 左右padding
        final availableWidth = screenWidth - totalHorizontalPadding;

        // 动态计算间距，确保适配屏幕
        final minSpacing = 10.0; // 最小间距增加到10
        final maxSpacing = 50.0; // 最大间距
        final totalSpacingWidth = (crossAxisCount - 1) * minSpacing;
        final cardWidth = (availableWidth - totalSpacingWidth) / crossAxisCount;

        // 根据卡片大小调整间距
        final actualSpacing =
            cardWidth < 60 ? minSpacing : (cardWidth < 70 ? 11.0 : maxSpacing);

        final actualCardWidth =
            (availableWidth - (crossAxisCount - 1) * actualSpacing) /
                crossAxisCount;
        final cardHeight = actualCardWidth;

        // Notify parent of the calculated card size
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onCardSizeCalculated?.call(cardHeight);
        });

        return SizedBox(
          height: cardHeight + 4, // 卡片高度 + 额外padding
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: actualSpacing,
              crossAxisSpacing: actualSpacing,
              childAspectRatio: actualCardWidth / cardHeight,
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return _buildCategoryCard(context, category, actualCardWidth);
            },
          ),
        );
      },
    );
  }

  /// 构建单个分类卡片
  Widget _buildCategoryCard(
    BuildContext context,
    CategoryInfo category,
    double cardWidth,
  ) {
    // 根据卡片宽度动态调整图标和文字大小，确保最小可读性
    final iconSize = (cardWidth * 0.3).clamp(18.0, 26.0);
    final fontSize = 12.0; // 固定为12px，确保可读性
    final iconPadding = (cardWidth * 0.08).clamp(3.0, 6.0);

    // 根据主题调整颜色
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adjustedIconColor = isDark
        ? _adjustColorForDarkTheme(category.iconColor)
        : category.iconColor;
    final adjustedBgColor = isDark
        ? _adjustBackgroundForDarkTheme(category.iconColor)
        : category.backgroundColor;

    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          // 触觉反馈
          HapticFeedback.lightImpact();
          // 立即跳转，不显示SnackBar
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => CategoryFilePage(
                categoryType: category.type,
                presenter: presenter,
                viewModel: viewModel,
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: adjustedBgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: adjustedIconColor.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标
              Flexible(
                flex: 2,
                child: Container(
                  padding: EdgeInsets.all(iconPadding),
                  decoration: BoxDecoration(
                    color: adjustedIconColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    category.icon,
                    size: iconSize,
                    color: adjustedIconColor,
                  ),
                ),
              ),

              SizedBox(height: cardWidth * 0.05), // 动态间距
              // 文本
              Flexible(
                flex: 1,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: cardWidth * 0.05),
                  child: Text(
                    category.name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: adjustedIconColor,
                          fontSize: fontSize,
                        ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 为深色主题调整图标颜色（提高亮度）
  Color _adjustColorForDarkTheme(Color color) {
    final hsl = HSLColor.fromColor(color);
    // 提高亮度到 65-75% 范围，保持饱和度
    return hsl.withLightness(0.7).withSaturation(0.7).toColor();
  }

  /// 为深色主题调整背景颜色
  Color _adjustBackgroundForDarkTheme(Color iconColor) {
    final hsl = HSLColor.fromColor(iconColor);
    // 使用低亮度和低饱和度的背景色
    return hsl.withLightness(0.15).withSaturation(0.3).toColor();
  }
}

/// 备选方案：水平滚动布局（如果网格太挤）
class CategoryNavBarHorizontal extends StatelessWidget {
  final FilePresenter presenter;

  const CategoryNavBarHorizontal({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '快速入口',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
            ),
          ),
          const SizedBox(height: 8),

          // 水平滚动列表
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: CategoryInfo.allCategories.length,
              itemBuilder: (context, index) {
                final category = CategoryInfo.allCategories[index];
                return _buildHorizontalCard(context, category);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalCard(BuildContext context, CategoryInfo category) {
    return Container(
      width: 80,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _onCategoryTap(context, category),
          child: Container(
            decoration: BoxDecoration(
              color: category.backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(category.icon, size: 28, color: category.iconColor),
                const SizedBox(height: 4),
                Text(
                  category.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: category.iconColor,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onCategoryTap(BuildContext context, CategoryInfo category) {
    // 与上面相同的逻辑
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('功能开发中：${category.name}分类')));
  }
}
