import 'package:flutter/material.dart';
import 'package:easyfile/core/services/view_mode_service.dart';

/// 文件管理工具栏
/// 统一的工具栏组件，包含返回、搜索、视图切换等功能
class FileToolbar extends StatelessWidget {
  /// 是否显示返回按钮
  final bool showBackButton;

  /// 返回按钮点击回调
  final VoidCallback? onBackPressed;

  /// 返回按钮提示文本
  final String backTooltip;

  /// 是否显示搜索按钮
  final bool showSearchButton;

  /// 搜索按钮点击回调
  final VoidCallback? onSearchPressed;

  /// 当前是否处于搜索模式
  final bool isSearchMode;

  /// 是否显示视图模式切换按钮
  final bool showViewModeToggle;

  /// 图标大小
  final double iconSize;

  /// 额外的工具按钮（显示在视图切换按钮之前）
  final List<Widget>? extraActions;

  const FileToolbar({
    super.key,
    this.showBackButton = false,
    this.onBackPressed,
    this.backTooltip = '返回上级',
    this.showSearchButton = true,
    this.onSearchPressed,
    this.isSearchMode = false,
    this.showViewModeToggle = true,
    this.iconSize = 20,
    this.extraActions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 返回上级按钮
        if (showBackButton)
          IconButton(
            icon: Icon(Icons.arrow_back, size: iconSize),
            onPressed: onBackPressed,
            tooltip: backTooltip,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 28,
            ),
          ),
        
        // 搜索按钮
        if (showSearchButton)
          IconButton(
            icon: Icon(Icons.search, size: iconSize),
            onPressed: onSearchPressed,
            tooltip: isSearchMode ? '退出搜索' : '搜索',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 28,
            ),
          ),

        // 额外的操作按钮
        if (extraActions != null) ...extraActions!,

        // 视图模式切换按钮
        if (showViewModeToggle)
          ListenableBuilder(
            listenable: ViewModeService(),
            builder: (context, _) {
              final viewModeService = ViewModeService();
              final isGridView = viewModeService.isGridView;

              return IconButton(
                icon: Icon(
                  isGridView ? Icons.view_list : Icons.grid_view,
                  size: iconSize,
                ),
                onPressed: () {
                  viewModeService.toggleViewMode();
                },
                tooltip: isGridView ? '列表视图' : '网格视图',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
              );
            },
          ),
      ],
    );
  }
}
