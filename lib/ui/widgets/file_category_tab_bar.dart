import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/data/services/file_type_analyzer.dart';
import 'package:flutter/material.dart';

/// 文件类型筛选Tab栏
class FileCategoryTabBar extends StatelessWidget {
  final FileTypeStats stats;
  final FileCategory selectedCategory;
  final ValueChanged<FileCategory> onCategoryChanged;

  /// 是否显示图标（默认false，仅隐私空间为true）
  final bool showIcon;

  /// 是否显示数字统计（默认true）
  final bool showCount;

  const FileCategoryTabBar({
    super.key,
    required this.stats,
    required this.selectedCategory,
    required this.onCategoryChanged,
    this.showIcon = false,
    this.showCount = true,
  });

  @override
  Widget build(BuildContext context) {
    // 如果只有一种类型或没有文件，不显示Tab栏
    if (!stats.hasMultipleTypes && stats.totalFileCount <= 0) {
      return const SizedBox.shrink();
    }

    final visibleCategories = [
      FileCategory.all,
      ...stats.getVisibleCategories(),
    ];

    // 调试信息
    logger.d(
      'FileCategoryTabBar: totalCount=${stats.totalCount}, totalFileCount=${stats.totalFileCount}, totalDirectoryCount=${stats.totalDirectoryCount}',
    );
    for (final category in visibleCategories) {
      final count = stats.getCount(category);
      logger.d('Category ${category.displayName}: count=$count');
    }

    return Container(
      height: showIcon ? 56 : 35,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        itemCount: visibleCategories.length,
        itemBuilder: (context, index) {
          final category = visibleCategories[index];
          final count = stats.getCount(category);
          final isSelected = category == selectedCategory;

          return _buildCategoryTab(context, category, count, isSelected);
        },
      ),
    );
  }

  Widget _buildCategoryTab(
    BuildContext context,
    FileCategory category,
    int count,
    bool isSelected,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = isSelected ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.6);
    final textColor = isSelected ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.6);

    return GestureDetector(
      onTap: () => onCategoryChanged(category),
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: showIcon ? 4 : 3,
          vertical: 2,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: showIcon ? 10 : 8,
          vertical: 0,
        ),
        decoration: BoxDecoration(
          border: isSelected ? Border(bottom: BorderSide(color: colorScheme.primary, width: 2)) : null,
        ),
        child: showIcon
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    category.icon,
                    size: 20,
                    color: iconColor,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    category.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: textColor,
                    ),
                  ),
                ],
              )
            : Text(
                showCount ? '${category.displayName} ($count)' : category.displayName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: textColor,
                ),
              ),
      ),
    );
  }
}
