import 'package:flutter/material.dart';

/// Edit mode action button for AppBar
/// 
/// Shows "编辑" button in normal mode and "关闭" button in edit mode.
/// Used in AppBar actions across file management pages.
/// 
/// Example:
/// ```dart
/// AppBar(
///   actions: [
///     EditModeActionButton(
///       isEditMode: _isEditMode,
///       onPressed: _isEditMode ? _exitEditMode : _enterEditMode,
///     ),
///   ],
/// )
/// ```
class EditModeActionButton extends StatelessWidget {
  /// Whether the page is in edit mode
  final bool isEditMode;
  
  /// Callback when button is pressed
  final VoidCallback onPressed;
  
  /// Icon size (default: 22)
  final double iconSize;
  
  const EditModeActionButton({
    super.key,
    required this.isEditMode,
    required this.onPressed,
    this.iconSize = 22,
  });
  
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        isEditMode ? Icons.close : Icons.edit_outlined,
        size: iconSize,
      ),
      onPressed: onPressed,
      tooltip: isEditMode ? '退出编辑' : '编辑',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(
        minWidth: 24,
        minHeight: 24,
      ),
    );
  }
}

/// Edit mode leading indicator for AppBar
/// 
/// Shows a blue circular indicator with edit icon when in edit mode.
/// Used as AppBar leading widget.
/// 
/// Example:
/// ```dart
/// AppBar(
///   leading: _isEditMode
///       ? const EditModeLeadingIndicator()
///       : IconButton(...),
/// )
/// ```
class EditModeLeadingIndicator extends StatelessWidget {
  /// Icon size (default: 18)
  final double iconSize;
  
  /// Container size (default: 32)
  final double size;
  
  const EditModeLeadingIndicator({
    super.key,
    this.iconSize = 18,
    this.size = 32,
  });
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.edit,
        size: iconSize,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}

/// Select all button for AppBar
/// 
/// Three-state checkbox button (none/partial/all selected).
/// Shows appropriate icon based on selection state.
/// 
/// Example:
/// ```dart
/// AppBar(
///   actions: [
///     SelectAllButton(
///       selectedCount: _selectedItems.length,
///       totalCount: _allFiles.length,
///       onPressed: _handleSelectAll,
///     ),
///   ],
/// )
/// ```
class SelectAllButton extends StatelessWidget {
  /// Number of selected items
  final int selectedCount;
  
  /// Total number of selectable items
  final int totalCount;
  
  /// Callback when button is pressed
  final VoidCallback onPressed;
  
  /// Icon size (default: 24)
  final double iconSize;
  
  const SelectAllButton({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    required this.onPressed,
    this.iconSize = 24,
  });
  
  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final String tooltip;
    
    if (selectedCount == 0) {
      icon = Icons.check_box_outline_blank;
      tooltip = '全选';
    } else if (selectedCount == totalCount) {
      icon = Icons.check_box;
      tooltip = '取消全选';
    } else {
      icon = Icons.indeterminate_check_box;
      tooltip = '全选';
    }
    
    return IconButton(
      icon: Icon(icon, size: iconSize),
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(
        minWidth: 32,
        minHeight: 32,
      ),
    );
  }
}

/// Edit mode toolbar button/indicator combo
/// 
/// Shows edit button in normal mode and blue indicator in edit mode.
/// Used in file management page toolbars (Browse/Recent/Favorite tabs).
/// 
/// Example:
/// ```dart
/// FileToolbar(
///   actions: [
///     EditModeToolbarButton(
///       isEditMode: _isEditMode,
///       onEnterEditMode: _enterEditMode,
///     ),
///   ],
/// )
/// ```
class EditModeToolbarButton extends StatelessWidget {
  /// Whether the page is in edit mode
  final bool isEditMode;
  
  /// Callback when entering edit mode (only called in normal mode)
  final VoidCallback onEnterEditMode;
  
  /// Icon size for edit button (default: 18)
  final double iconSize;
  
  /// Indicator size (default: 24)
  final double indicatorSize;
  
  /// Indicator icon size (default: 14)
  final double indicatorIconSize;
  
  const EditModeToolbarButton({
    super.key,
    required this.isEditMode,
    required this.onEnterEditMode,
    this.iconSize = 18,
    this.indicatorSize = 24,
    this.indicatorIconSize = 14,
  });
  
  @override
  Widget build(BuildContext context) {
    if (isEditMode) {
      // 编辑模式下：显示蓝色圆圈指示器（不可点击，仅显示状态）
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: EditModeLeadingIndicator(
          size: indicatorSize,
          iconSize: indicatorIconSize,
        ),
      );
    } else {
      // 非编辑模式：显示可点击的编辑按钮
      return IconButton(
        icon: Icon(Icons.edit_outlined, size: iconSize),
        onPressed: onEnterEditMode,
        tooltip: '编辑',
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(
          minWidth: 24,
          minHeight: 24,
        ),
      );
    }
  }
}
