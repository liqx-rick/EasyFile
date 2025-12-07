import 'package:flutter/material.dart';

/// Mixin for handling back button behavior with PopScope
/// 
/// Provides a standardized way to handle back button presses across different pages
/// with support for common scenarios like search mode, edit mode, and navigation.
/// 
/// Usage:
/// ```dart
/// class MyPageState extends State<MyPage> with PopScopeHandlerMixin {
///   @override
///   bool get isSearchMode => _isSearchMode;
///   
///   @override
///   bool get isEditMode => _isEditMode;
///   
///   @override
///   void exitSearchMode() {
///     setState(() {
///       _isSearchMode = false;
///       _searchQuery = '';
///     });
///   }
///   
///   @override
///   void exitEditMode() {
///     setState(() {
///       _isEditMode = false;
///     });
///   }
///   
///   @override
///   Widget build(BuildContext context) {
///     return PopScope(
///       canPop: canPopPage(),
///       onPopInvokedWithResult: handlePopInvoked,
///       child: Scaffold(...),
///     );
///   }
/// }
/// ```
mixin PopScopeHandlerMixin<T extends StatefulWidget> on State<T> {
  /// Whether the page is in search mode
  /// Override this to return your search mode state if not provided by other mixins
  bool get isSearchMode => false;
  
  /// Whether the page is in edit mode
  /// This should be provided by EditModeMixin or overridden in the page class
  /// Note: If using EditModeMixin, this will automatically use its isEditMode
  bool get isEditMode;
  
  /// Whether the page can navigate up (e.g., in a subdirectory)
  /// Override this to implement custom navigation logic
  bool canNavigateUp() => false;
  
  /// Exit search mode
  /// Override this to implement your search exit logic
  void exitSearchMode() {
    // Default implementation does nothing
    // Subclass should override if search mode is supported
  }
  
  /// Exit edit mode
  /// This should be provided by EditModeMixin or overridden in the page class
  /// Note: If using EditModeMixin, this will automatically use its exitEditMode
  void exitEditMode();
  
  /// Navigate up (e.g., go to parent directory)
  /// Override this to implement your navigation logic
  void navigateUp() {
    // Default implementation does nothing
    // Subclass should override if navigation is supported
  }
  
  /// Determine if the page can be popped
  /// 
  /// Returns false if any of the following conditions are true:
  /// - Search mode is active
  /// - Edit mode is active
  /// - Can navigate up (in subdirectory)
  /// 
  /// Override this method for custom canPop logic
  @protected
  bool canPopPage() {
    return !isSearchMode && !isEditMode && !canNavigateUp();
  }
  
  /// Handle pop action with priority-based logic
  /// 
  /// Priority order:
  /// 1. Exit search mode (if active)
  /// 2. Exit edit mode (if active)
  /// 3. Navigate up (if in subdirectory)
  /// 4. Allow system default behavior
  /// 
  /// Override this method for custom pop handling logic
  @protected
  void handlePopInvoked(bool didPop, dynamic result) {
    if (didPop) return;
    
    // Priority 1: Exit search mode
    if (isSearchMode) {
      exitSearchMode();
      return;
    }
    
    // Priority 2: Exit edit mode
    if (isEditMode) {
      exitEditMode();
      return;
    }
    
    // Priority 3: Navigate up
    if (canNavigateUp()) {
      navigateUp();
      return;
    }
    
    // If we reach here, the pop was handled by returning false from canPopPage
    // but none of the conditions were met. This shouldn't normally happen.
  }
  
  /// Convenience method to wrap content with PopScope
  /// 
  /// Example:
  /// ```dart
  /// @override
  /// Widget build(BuildContext context) {
  ///   return wrapWithPopScope(
  ///     child: Scaffold(...),
  ///   );
  /// }
  /// ```
  @protected
  Widget wrapWithPopScope({required Widget child}) {
    return PopScope(
      canPop: canPopPage(),
      onPopInvokedWithResult: handlePopInvoked,
      child: child,
    );
  }
}
