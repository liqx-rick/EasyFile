import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/ui/widgets/file_item_tile.dart';
import 'package:easyfile/ui/widgets/unified_grid_item.dart';
import 'package:easyfile/ui/widgets/unified_view_config.dart';
import 'package:easyfile/core/logger.dart';

/// Data model for a file group with collapsible support.
///
/// Used by [FileCollectionView] to organize files into collapsible groups.
/// Each group has a unique key, a title for display, and a list of file items.
///
/// Example:
/// ```dart
/// FileGroup(
///   key: 'today',
///   title: 'Today (5 files)',
///   items: todayFiles,
///   isCollapsible: true,
///   initiallyExpanded: true,
/// )
/// ```
class FileGroup {
  final String key;
  final String title;
  final List<FileItem> items;
  final bool isCollapsible;
  final bool initiallyExpanded;

  const FileGroup({
    required this.key,
    required this.title,
    required this.items,
    this.isCollapsible = true,
    this.initiallyExpanded = true,
  });
}

/// Controller to manage selection state for FileCollectionView.
///
/// This controller provides a centralized way to manage file selection state
/// across different views. It uses [ValueNotifier] to notify listeners when
/// the selection changes, enabling reactive UI updates.
///
/// The controller maintains a set of selected file paths and provides methods
/// for adding, removing, and querying selections.
///
/// Example:
/// ```dart
/// final controller = SelectionController();
///
/// // Select files
/// controller.select('/path/to/file1.txt');
/// controller.select('/path/to/file2.txt');
///
/// // Check selection
/// if (controller.contains('/path/to/file1.txt')) {
///   print('File is selected');
/// }
///
/// // Clear all selections
/// controller.clear();
///
/// // Don't forget to dispose
/// controller.dispose();
/// ```
class SelectionController {
  final ValueNotifier<Set<String>> _selected = ValueNotifier({});
  final ValueNotifier<bool> _isSelectionMode = ValueNotifier(false);

  /// Gets the notifier that emits when selection changes.
  ///
  /// Use this to listen to selection changes:
  /// ```dart
  /// controller.selectedNotifier.addListener(() {
  ///   print('Selection changed: ${controller.selected}');
  /// });
  /// ```
  ValueNotifier<Set<String>> get selectedNotifier => _selected;

  /// Gets the notifier that emits when selection mode changes.
  ///
  /// Use this to listen to selection mode changes:
  /// ```dart
  /// controller.selectionModeNotifier.addListener(() {
  ///   print('Selection mode: ${controller.isSelectionMode}');
  /// });
  /// ```
  ValueNotifier<bool> get selectionModeNotifier => _isSelectionMode;

  /// Gets the current set of selected file paths.
  Set<String> get selected => _selected.value;

  /// Gets the count of currently selected items.
  int get count => _selected.value.length;

  /// Gets whether selection mode is active.
  bool get isSelectionMode => _isSelectionMode.value;

  /// Checks if a file path is currently selected.
  ///
  /// Returns `true` if [path] is in the selection set.
  bool contains(String path) => _selected.value.contains(path);

  /// Checks if any items are currently selected.
  ///
  /// Returns `true` if at least one item is selected.
  bool get isSelecting => _selected.value.isNotEmpty;

  /// Adds a file path to the selection.
  ///
  /// If [path] is already selected, this has no effect.
  /// Automatically enters selection mode if not already active.
  void select(String path) {
    final copy = Set<String>.from(_selected.value);
    copy.add(path);
    _selected.value = copy;
    if (!_isSelectionMode.value) {
      _isSelectionMode.value = true;
    }
  }

  /// Removes a file path from the selection.
  ///
  /// If [path] is not selected, this has no effect.
  void deselect(String path) {
    final copy = Set<String>.from(_selected.value);
    copy.remove(path);
    _selected.value = copy;
  }

  /// Toggles the selection state of a file path.
  ///
  /// If [path] is selected, it will be deselected.
  /// If [path] is not selected, it will be selected.
  void toggle(String path) {
    final copy = Set<String>.from(_selected.value);
    if (copy.contains(path)) {
      copy.remove(path);
    } else {
      copy.add(path);
    }
    _selected.value = copy;
  }

  /// Selects all files in the provided list of paths.
  ///
  /// Replaces the current selection with the new set of paths.
  void selectAll(List<String> paths) {
    _selected.value = Set<String>.from(paths);
    if (!_isSelectionMode.value) {
      _isSelectionMode.value = true;
    }
  }

  /// Enters selection mode without selecting any files.
  ///
  /// This is useful when you want to show checkboxes but haven't
  /// selected any files yet (e.g., when entering edit mode).
  void enterSelectionMode() {
    if (!_isSelectionMode.value) {
      _isSelectionMode.value = true;
    }
  }

  /// Clears all selections and exits selection mode.
  void clear() {
    _selected.value = {};
    _isSelectionMode.value = false;
  }

  /// Disposes the controller and releases resources.
  ///
  /// Must be called when the controller is no longer needed.
  void dispose() {
    _selected.dispose();
    _isSelectionMode.dispose();
  }
}

/// A lightweight, configurable collection view for displaying file items.
///
/// [FileCollectionView] provides a unified way to display files in either list
/// or grid mode, with support for grouping, selection, and custom rendering.
///
/// ## Features
///
/// - **Dual Mode**: Switch between list and grid layouts using [gridMode]
/// - **Grouping**: Organize files into collapsible groups using [groups]
/// - **Selection**: Integrate with [SelectionController] for selection state
/// - **Custom Headers**: Add a header widget using [headerBuilder]
/// - **Pull to Refresh**: Enable with [onRefresh] callback
/// - **Infinite Scroll**: Trigger loading more with [onScrollNearEnd]
/// - **Accessibility**: Built-in Semantics support
///
/// ## Usage
///
/// ### Basic List View
/// ```dart
/// FileCollectionView(
///   items: files,
///   gridMode: false,
///   itemBuilder: (file) => ListTile(title: Text(file.name)),
///   onTap: (file) => openFile(file),
/// )
/// ```
///
/// ### Grid View with Selection
/// ```dart
/// final controller = SelectionController();
///
/// FileCollectionView(
///   items: files,
///   gridMode: true,
///   selectionController: controller,
///   itemBuilder: (file) => FileCard(file: file),
///   onTap: (file) => controller.toggle(file.path),
/// )
/// ```
///
/// ### Grouped Files
/// ```dart
/// FileCollectionView(
///   groups: [
///     FileGroup(key: 'today', title: 'Today', items: todayFiles),
///     FileGroup(key: 'yesterday', title: 'Yesterday', items: yesterdayFiles),
///   ],
///   gridMode: false,
///   itemBuilder: (file) => FileListItem(file: file),
/// )
/// ```
///
/// See also:
/// - [SelectionController] for managing selection state
/// - [FileGroup] for organizing files into groups
class FileCollectionView extends StatelessWidget {
  final List<FileItem>? items;
  final List<FileGroup>? groups;
  final bool gridMode;
  final Widget Function(FileItem)? itemBuilder;
  final Widget Function(BuildContext, FileGroup)? groupHeaderBuilder;
  final void Function(FileItem)? onTap;
  final void Function(FileItem)? onLongPress;
  final EdgeInsetsGeometry padding;
  final WidgetBuilder? headerBuilder;
  final bool stickyHeader;
  final SelectionController? selectionController;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onScrollNearEnd;
  final double? itemExtent;
  final double? cacheExtent;
  // FileItemTile 显示选项
  final bool showFullPath;
  final bool showAccessTime;
  final bool showFavoriteButton;
  final bool Function(String)? isFavorite;
  final Future<bool> Function(FileItem)? onFavoriteToggle;
  final DateTime? Function(FileItem)? getAccessTime;
  // 统一网格组件支持
  final bool useUnifiedGridItem;
  final UnifiedViewConfig? config;
  final UnifiedViewConfig? Function(FileItem)? viewConfigBuilder;
  final bool showCheckbox;

  const FileCollectionView({
    super.key,
    this.items,
    this.groups,
    this.gridMode = false,
    this.itemBuilder,
    this.groupHeaderBuilder,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(vertical: 4.0),
    this.headerBuilder,
    this.stickyHeader = false,
    this.selectionController,
    this.onRefresh,
    this.onScrollNearEnd,
    this.itemExtent,
    this.cacheExtent,
    this.showFullPath = false,
    this.showAccessTime = false,
    this.showFavoriteButton = true,
    this.isFavorite,
    this.onFavoriteToggle,
    this.getAccessTime,
    this.useUnifiedGridItem = false,
    this.config,
    this.viewConfigBuilder,
    this.showCheckbox = false,
  }) : assert(items != null || groups != null,
            'Either items or groups must be provided');

  @override
  Widget build(BuildContext context) {
    final hasContent = (items != null && items!.isNotEmpty) ||
        (groups != null && groups!.isNotEmpty);

    if (!hasContent) {
      return Center(
        child: Padding(
          padding: padding,
          child: Text(
            '没有文件',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    Widget content = groups != null
        ? _buildGroupedView(context)
        : (gridMode ? _buildGrid(context) : _buildList(context));

    // Wrap with RefreshIndicator if onRefresh is provided
    if (onRefresh != null) {
      content = RefreshIndicator(
        onRefresh: onRefresh!,
        child: content,
      );
    }

    // Handle header positioning
    if (headerBuilder != null) {
      if (stickyHeader) {
        // Sticky header: header stays fixed at top while content scrolls
        return Column(
          children: [
            headerBuilder!(context),
            Expanded(child: content),
          ],
        );
      } else {
        // Scrolling header: header scrolls with content
        // We need to wrap the list with CustomScrollView
        return _buildWithScrollingHeader(context, content);
      }
    }

    return content;
  }

  Widget _buildWithScrollingHeader(BuildContext context, Widget listContent) {
    // For scrolling header, we need to convert the list to slivers
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: headerBuilder!(context),
        ),
        SliverFillRemaining(
          child: listContent,
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    final controller = onScrollNearEnd != null ? ScrollController() : null;

    if (controller != null) {
      controller.addListener(() {
        if (controller.position.pixels >=
            controller.position.maxScrollExtent - 200) {
          onScrollNearEnd!();
        }
      });
    }

    return ListView.separated(
      controller: controller,
      padding: padding as EdgeInsets?,
      itemCount: items!.length,
      cacheExtent: cacheExtent,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (c, i) => _buildItemWrapper(context, items![i]),
    );
  }

  /// 计算网格视图的列数
  ///
  /// 根据屏幕宽度和最小卡片宽度动态计算列数，确保：
  /// - 最小卡片宽度为 110px，保证可读性
  /// - 列数限制在 3-6 列之间
  /// - 考虑水平内边距和间距
  int _calculateCrossAxisCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    const minCardWidth = 100.0; // 最小卡片宽度（从110减少到100，允许更大的缩略图）
    const spacing = 8.0;
    final horizontalPadding = (padding as EdgeInsets?)?.horizontal ?? 16.0;
    final availableWidth = width - horizontalPadding;

    // 计算能容纳的列数，限制在3-6列之间
    int crossAxisCount =
        ((availableWidth + spacing) / (minCardWidth + spacing)).floor();
    return crossAxisCount.clamp(3, 6);
  }

  Widget _buildGrid(BuildContext context) {
    final crossAxisCount = _calculateCrossAxisCount(context);

    return GridView.builder(
      padding: padding as EdgeInsets? ?? const EdgeInsets.all(8),
      // 增加预构建范围，改善滚动体验（使用传入值或默认 800px）
      cacheExtent: cacheExtent ?? 800.0,
      // 禁用自动保持 widget，减少内存占用
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      addSemanticIndexes: false,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.70, // 调整宽高比以0.75到0.70，适应增加的文件名高度
      ),
      itemCount: items!.length,
      itemBuilder: (c, i) => _buildItemWrapper(context, items![i]),
    );
  }

  Widget _buildGroupedView(BuildContext context) {
    // 使用 CustomScrollView + Slivers 实现真正的懒加载
    // 关键：添加 key 确保 gridMode 切换时重建 widget，触发 dispose
    return _GroupedSliverView(
      key: ValueKey('grouped_${gridMode ? 'grid' : 'list'}'),
      groups: groups!,
      gridMode: gridMode,
      groupHeaderBuilder: groupHeaderBuilder,
      itemWrapper: _buildItemWrapper,
      crossAxisCount: _calculateCrossAxisCount(context),
    );
  }

  Widget _buildItemWrapper(BuildContext context, FileItem item) {
    // 如果提供了自定义 itemBuilder，直接使用
    if (itemBuilder != null) {
      Widget child = itemBuilder!(item);

      // Add semantics for accessibility
      child = Semantics(
        label: item.isDirectory ? '文件夹: ${item.name}' : '文件: ${item.name}',
        button: true,
        enabled: true,
        child: child,
      );

      return child;
    }

    final isSelectionMode = selectionController?.isSelectionMode ?? false;
    final isSelected = selectionController?.contains(item.path) ?? false;

    // 网格模式且启用统一组件
    if (gridMode && useUnifiedGridItem) {
      // 获取该文件的视图配置（支持每个文件不同的配置）
      final itemConfig = viewConfigBuilder?.call(item) ?? config;
      
      // 添加唯一 key 以保持 widget 状态
      // 这确保滚动时 widget 不会被完全重建，子组件的状态得以保留
      // 特别重要：视频缩略图不会重新显示 loading 状态
      return UnifiedGridItem(
        key: ValueKey('grid_item_${item.path}'),
        file: item,
        isSelected: isSelected,
        showCheckbox: showCheckbox,
        isFavorite: isFavorite?.call(item.path) ?? false,
        showFavoriteButton: showFavoriteButton,
        config: itemConfig,
        onTap: () {
          if (isSelectionMode) {
            selectionController!.toggle(item.path);
          } else {
            if (onTap != null) onTap!(item);
          }
        },
        onLongPress: () {
          if (selectionController != null) {
            // 框架内部完全处理选择逻辑
            selectionController!.select(item.path);
            // 可选：调用页面回调用于自定义行为（如显示提示）
            if (onLongPress != null) onLongPress!(item);
          } else {
            if (onLongPress != null) onLongPress!(item);
          }
        },
        onFavoriteToggle:
            showFavoriteButton && !item.isDirectory && onFavoriteToggle != null
                ? () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final isFav = await onFavoriteToggle!(item);
                    if (context.mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(isFav ? '已添加到收藏' : '已取消收藏'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  }
                : null,
      );
    }

    // 使用默认的 FileItemTile（列表模式或未启用统一组件）
    Widget child = FileItemTile(
      file: item,
      showFullPath: showFullPath,
      showAccessTime: showAccessTime,
      accessTime: getAccessTime?.call(item),
      isFavorite: isFavorite?.call(item.path) ?? false,
      isSelected: isSelected,
      showCheckbox: isSelectionMode,
      onFavoriteToggle:
          showFavoriteButton && !item.isDirectory && onFavoriteToggle != null
              ? () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final isFav = await onFavoriteToggle!(item);
                  if (context.mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(isFav ? '已添加到收藏' : '已取消收藏'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                }
              : null,
      onTap: () {
        if (isSelectionMode) {
          selectionController!.toggle(item.path);
        } else {
          if (onTap != null) onTap!(item);
        }
      },
      onLongPress: () {
        if (selectionController != null) {
          // 框架内部完全处理选择逻辑
          selectionController!.select(item.path);
          // 可选：调用页面回调用于自定义行为（如显示提示）
          if (onLongPress != null) onLongPress!(item);
        } else {
          if (onLongPress != null) onLongPress!(item);
        }
      },
    );

    // Add semantics for accessibility
    child = Semantics(
      label: item.isDirectory ? '文件夹: ${item.name}' : '文件: ${item.name}',
      button: true,
      enabled: true,
      child: child,
    );

    return child;
  }
}

// ============================================================================
// Sliver 组件：实现真正的懒加载
// ============================================================================

/// 分组 Sliver 视图的容器 - 管理所有分组的展开/收起状态
class _GroupedSliverView extends StatefulWidget {
  final List<FileGroup> groups;
  final bool gridMode;
  final Widget Function(BuildContext, FileGroup)? groupHeaderBuilder;
  final Widget Function(BuildContext, FileItem) itemWrapper;
  final int crossAxisCount;

  const _GroupedSliverView({
    super.key,
    required this.groups,
    required this.gridMode,
    required this.groupHeaderBuilder,
    required this.itemWrapper,
    required this.crossAxisCount,
  });

  @override
  State<_GroupedSliverView> createState() => _GroupedSliverViewState();
}

class _GroupedSliverViewState extends State<_GroupedSliverView> {
  // 存储每个分组的展开状态
  late Map<String, bool> _expandedStates;

  @override
  void initState() {
    super.initState();
    _expandedStates = {
      for (var group in widget.groups) group.title: group.initiallyExpanded,
    };
  }

  @override
  void didUpdateWidget(_GroupedSliverView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检测 gridMode 是否改变
    if (oldWidget.gridMode != widget.gridMode) {
      // 切换模式时清理图片缓存
      _clearImageCache();
    }
  }

  void _toggleGroup(String groupTitle) {
    setState(() {
      _expandedStates[groupTitle] = !(_expandedStates[groupTitle] ?? true);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _clearImageCache() {
    try {
      final imageCache = PaintingBinding.instance.imageCache;
      final clearedCount = imageCache.currentSize;
      imageCache.clear();
      imageCache.clearLiveImages();
      logger.d('Cleared image cache: $clearedCount images');
    } catch (e) {
      logger.e('Error clearing image cache: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      // 添加缓存范围，提前渲染屏幕外的内容
      cacheExtent: 500,
      slivers: [
        for (final group in widget.groups) ...[
          // 分组头部
          _SliverGroupHeader(
            group: group,
            headerBuilder: widget.groupHeaderBuilder,
            isExpanded: _expandedStates[group.title] ?? true,
            onToggle: () => _toggleGroup(group.title),
          ),
          // 分组内容
          if (_expandedStates[group.title] ?? true)
            widget.gridMode
                ? _SliverGroupGrid(
                    group: group,
                    crossAxisCount: widget.crossAxisCount,
                    itemWrapper: widget.itemWrapper,
                  )
                : _SliverGroupList(
                    group: group,
                    itemWrapper: widget.itemWrapper,
                  ),
        ],
      ],
    );
  }
}

/// 分组头部的 Sliver 包装器
class _SliverGroupHeader extends StatelessWidget {
  final FileGroup group;
  final Widget Function(BuildContext, FileGroup)? headerBuilder;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _SliverGroupHeader({
    required this.group,
    required this.isExpanded,
    required this.onToggle,
    this.headerBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final header = headerBuilder != null
        ? headerBuilder!(context, group)
        : _buildDefaultHeader(context);

    return SliverToBoxAdapter(
      child: InkWell(
        onTap: group.isCollapsible ? onToggle : null,
        child: header,
      ),
    );
  }

  Widget _buildDefaultHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          if (group.isCollapsible)
            Icon(
              isExpanded ? Icons.expand_more : Icons.chevron_right,
              size: 20,
            ),
          if (group.isCollapsible) const SizedBox(width: 8),
          Expanded(
            child: Text(
              group.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分组网格的 Sliver 实现 - 真正的懒加载
class _SliverGroupGrid extends StatelessWidget {
  final FileGroup group;
  final int crossAxisCount;
  final Widget Function(BuildContext, FileItem) itemWrapper;

  const _SliverGroupGrid({
    required this.group,
    required this.crossAxisCount,
    required this.itemWrapper,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.70, // 调整宽高比以0.75到0.70，适应增加的文件名高度
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return itemWrapper(context, group.items[index]);
          },
          childCount: group.items.length,
          // 懒加载关键配置：不自动保持状态
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          addSemanticIndexes: false,
        ),
      ),
    );
  }
}

/// 分组列表的 Sliver 实现 - 真正的懒加载
class _SliverGroupList extends StatelessWidget {
  final FileGroup group;
  final Widget Function(BuildContext, FileItem) itemWrapper;

  const _SliverGroupList({
    required this.group,
    required this.itemWrapper,
  });

  @override
  Widget build(BuildContext context) {
    // 使用 SliverFixedExtentList 而不是 SliverList
    // 这样 Flutter 可以更高效地计算布局，不需要测量每个 item
    // 同时用 DecoratedBox 添加底部边框代替 Divider，避免 childCount 翻倍
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
            ),
            child: itemWrapper(context, group.items[index]),
          );
        },
        childCount: group.items.length, // 关键修复：不再乘以2
        // 懒加载关键配置：不自动保持状态
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        addSemanticIndexes: false,
      ),
    );
  }
}
