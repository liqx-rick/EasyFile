import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/data/services/file_type_analyzer.dart';

/// 文件类型筛选Tab栏
class FileCategoryTabBar extends StatelessWidget {
  final FileTypeStats stats;
  final FileCategory selectedCategory;
  final ValueChanged<FileCategory> onCategoryChanged;

  const FileCategoryTabBar({
    super.key,
    required this.stats,
    required this.selectedCategory,
    required this.onCategoryChanged,
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

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: visibleCategories.length,
        itemBuilder: (context, index) {
          final category = visibleCategories[index];
          final count = stats.getCount(category);
          final isSelected = category == selectedCategory;

          return _buildCategoryTab(
            context,
            category,
            count,
            isSelected,
          );
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
    final textColor = isSelected
        ? colorScheme.primary
        : colorScheme.onSurface.withOpacity(0.6);
    final backgroundColor = isSelected
        ? colorScheme.primaryContainer.withOpacity(0.5)
        : Colors.transparent;

    return GestureDetector(
      onTap: () => onCategoryChanged(category),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(color: colorScheme.primary, width: 1.5)
              : null,
        ),
        child: Text(
          category.displayName,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
