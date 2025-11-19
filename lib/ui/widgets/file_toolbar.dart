import 'package:flutter/material.dart';
import 'package:easyfile/core/services/view_mode_service.dart';
import 'package:easyfile/core/services/category_group_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';

/// 文件管理工具栏
/// 统一的工具栏组件，包含返回、搜索、排序、分组、视图切换等功能
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

  /// 是否显示排序按钮
  final bool showSortButton;

  /// 排序按钮点击回调
  final VoidCallback? onSortPressed;

  /// 是否显示分组按钮
  final bool showGroupButton;

  /// 分组按钮点击回调（当分组状态改变时）
  final VoidCallback? onGroupToggle;

  /// 是否显示视图模式切换按钮
  final bool showViewModeToggle;

  /// 图标大小
  final double iconSize;

  /// 额外的工具按钮（显示在所有按钮之前）
  final List<Widget>? extraActions;

  /// 页面ID（用于页面级设置，如果为null则使用全局设置）
  final PageId? pageId;

  const FileToolbar({
    super.key,
    this.showBackButton = false,
    this.onBackPressed,
    this.backTooltip = '返回上级',
    this.showSearchButton = true,
    this.onSearchPressed,
    this.isSearchMode = false,
    this.showSortButton = false,
    this.onSortPressed,
    this.showGroupButton = false,
    this.onGroupToggle,
    this.showViewModeToggle = true,
    this.iconSize = 20,
    this.extraActions,
    this.pageId,
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
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
            ),
          ),

        // 搜索按钮
        if (showSearchButton)
          IconButton(
            icon: Icon(Icons.search, size: iconSize),
            onPressed: onSearchPressed,
            tooltip: isSearchMode ? '退出搜索' : '搜索',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
            ),
          ),

        // 额外的操作按钮
        if (extraActions != null) ...extraActions!,

        // 排序按钮
        if (showSortButton)
          IconButton(
            icon: Icon(Icons.sort, size: iconSize),
            onPressed: onSortPressed,
            tooltip: '排序',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
            ),
          ),

        // 分组按钮
        if (showGroupButton)
          ListenableBuilder(
            listenable:
                pageId != null ? PageSettingsService() : CategoryGroupService(),
            builder: (context, _) {
              final bool isGroupEnabled;
              if (pageId != null) {
                isGroupEnabled = PageSettingsService().getGroupEnabled(pageId!);
              } else {
                isGroupEnabled = CategoryGroupService().isGroupEnabled;
              }

              return IconButton(
                icon: Icon(
                  isGroupEnabled ? Icons.calendar_view_day : Icons.view_agenda,
                  size: iconSize,
                ),
                onPressed: () {
                  if (pageId != null) {
                    PageSettingsService().toggleGroupEnabled(pageId!);
                  } else {
                    CategoryGroupService().toggleGroup();
                  }
                  onGroupToggle?.call();
                },
                tooltip: isGroupEnabled ? '取消分组' : '按日期分组',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                ),
              );
            },
          ),

        // 视图模式切换按钮
        if (showViewModeToggle)
          ListenableBuilder(
            listenable:
                pageId != null ? PageSettingsService() : ViewModeService(),
            builder: (context, _) {
              final bool isGridView;
              if (pageId != null) {
                isGridView =
                    PageSettingsService().getViewMode(pageId!) == ViewMode.grid;
              } else {
                isGridView = ViewModeService().isGridView;
              }

              return IconButton(
                icon: Icon(
                  isGridView ? Icons.view_list : Icons.grid_view,
                  size: iconSize,
                ),
                onPressed: () {
                  if (pageId != null) {
                    PageSettingsService().toggleViewMode(pageId!);
                  } else {
                    ViewModeService().toggleViewMode();
                  }
                },
                tooltip: isGridView ? '列表视图' : '网格视图',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                ),
              );
            },
          ),
      ],
    );
  }
}
