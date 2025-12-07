import 'package:flutter/material.dart';
import '../widgets/file_collection_view.dart';

/// Mixin for edit mode functionality across different file management pages.
/// 
/// Provides common edit mode state management and behavior:
/// - Enter/Exit edit mode with hint bar animation
/// - Integration with SelectionController
/// - Consistent hint bar auto-hide logic (3 seconds)
/// 
/// Usage:
/// ```dart
/// class MyPage extends StatefulWidget { ... }
/// 
/// class _MyPageState extends State<MyPage> with EditModeMixin {
///   @override
///   SelectionController get selectionController => _selectionController;
///   
///   final SelectionController _selectionController = SelectionController();
///   
///   @override
///   Widget build(BuildContext context) {
///     return Column(
///       children: [
///         if (isEditMode && showEditModeHint)
///           const EditModeHintBar(),
///         // ... other widgets
///       ],
///     );
///   }
/// }
/// ```
mixin EditModeMixin<T extends StatefulWidget> on State<T> {
  /// Whether the page is in edit mode
  bool _isEditMode = false;
  bool get isEditMode => _isEditMode;
  
  /// Whether to show the edit mode hint bar
  bool _showEditModeHint = false;
  bool get showEditModeHint => _showEditModeHint;
  
  /// The SelectionController used by the page
  /// Must be implemented by the page
  SelectionController get selectionController;
  
  /// Optional callback when entering edit mode
  /// Override this to add custom behavior
  @protected
  void onEnterEditMode() {}
  
  /// Optional callback when exiting edit mode
  /// Override this to add custom behavior
  @protected
  void onExitEditMode() {}
  
  /// Enter edit mode
  /// 
  /// - Sets [isEditMode] to true
  /// - Shows the hint bar
  /// - Enters selection mode
  /// - Auto-hides hint bar after 3 seconds
  /// - Calls [onEnterEditMode] callback
  @protected
  void enterEditMode() {
    setState(() {
      _isEditMode = true;
      _showEditModeHint = true;
      selectionController.enterSelectionMode();
    });
    
    onEnterEditMode();
    
    // Auto-hide hint bar after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _showEditModeHint) {
        setState(() {
          _showEditModeHint = false;
        });
      }
    });
  }
  
  /// Exit edit mode
  /// 
  /// - Sets [isEditMode] to false
  /// - Hides the hint bar
  /// - Clears all selections
  /// - Calls [onExitEditMode] callback
  @protected
  void exitEditMode() {
    if (!mounted) return;
    
    setState(() {
      _isEditMode = false;
      _showEditModeHint = false;
      selectionController.clear();
    });
    
    onExitEditMode();
  }
  
  /// Toggle edit mode
  @protected
  void toggleEditMode() {
    if (_isEditMode) {
      exitEditMode();
    } else {
      enterEditMode();
    }
  }
  
  /// Get the select-all checkbox value (tri-state)
  /// 
  /// Returns:
  /// - `true`: All items are selected
  /// - `false`: No items are selected
  /// - `null`: Some (but not all) items are selected
  @protected
  bool? getSelectAllCheckboxValue(List<String> allItemPaths) {
    final selectedCount = selectionController.selected.length;
    final totalCount = allItemPaths.length;
    
    if (selectedCount == 0) {
      return false; // Nothing selected
    } else if (selectedCount == totalCount) {
      return true; // All selected
    } else {
      return null; // Partially selected
    }
  }
  
  /// Handle select all / deselect all
  /// 
  /// If all items are selected, deselects all.
  /// Otherwise, selects all items.
  @protected
  void handleSelectAll(List<String> allItemPaths) {
    final checkboxValue = getSelectAllCheckboxValue(allItemPaths);
    
    if (checkboxValue == true) {
      // All selected -> Deselect all
      selectionController.clear();
      // Re-enter selection mode to keep the selection mode active
      if (!selectionController.isSelectionMode) {
        selectionController.enterSelectionMode();
      }
    } else {
      // Nothing or partially selected -> Select all
      selectionController.selectAll(allItemPaths);
    }
  }
}
