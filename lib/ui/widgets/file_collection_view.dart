import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/ui/widgets/file_item_tile.dart';

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

  /// Gets the notifier that emits when selection changes.
  ///
  /// Use this to listen to selection changes:
  /// ```dart
  /// controller.selectedNotifier.addListener(() {
  ///   print('Selection changed: ${controller.selected}');
  /// });
  /// ```
  ValueNotifier<Set<String>> get selectedNotifier => _selected;

  /// Gets the current set of selected file paths.
  Set<String> get selected => _selected.value;

  /// Gets the count of currently selected items.
  int get count => _selected.value.length;

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
  void select(String path) {
    final copy = Set<String>.from(_selected.value);
    copy.add(path);
    _selected.value = copy;
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
  }

  /// Clears all selections.
  void clear() => _selected.value = {};

  /// Disposes the controller and releases resources.
  ///
  /// Must be called when the controller is no longer needed.
  void dispose() {
    _selected.dispose();
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

  const FileCollectionView({
    super.key,
    this.items,
    this.groups,
    this.gridMode = false,
    this.itemBuilder,
    this.groupHeaderBuilder,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(vertical: 8.0),
    this.headerBuilder,
    this.stickyHeader = false,
    this.selectionController,
    this.onRefresh,
    this.onScrollNearEnd,
    this.itemExtent,
    this.cacheExtent,
  }) : assert(items != null || groups != null, 'Either items or groups must be provided');

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
        if (controller.position.pixels >= controller.position.maxScrollExtent - 200) {
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

  Widget _buildGrid(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width < 600 ? 2 : (width < 900 ? 3 : 4);
    return GridView.builder(
      padding: padding as EdgeInsets?,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 3,
      ),
      itemCount: items!.length,
      itemBuilder: (c, i) => _buildItemWrapper(context, items![i]),
    );
  }

  Widget _buildGroupedView(BuildContext context) {
    return ListView.builder(
      padding: padding as EdgeInsets?,
      itemCount: groups!.length,
      itemBuilder: (context, groupIndex) {
        final group = groups![groupIndex];
        return _GroupSection(
          group: group,
          gridMode: gridMode,
          headerBuilder: groupHeaderBuilder,
          itemBuilder: itemBuilder,
          itemWrapper: _buildItemWrapper,
          onTap: onTap,
          onLongPress: onLongPress,
        );
      },
    );
  }

  Widget _buildItemWrapper(BuildContext context, FileItem item) {
    Widget child = itemBuilder != null
        ? itemBuilder!(item)
        : FileItemTile(
            file: item,
            onTap: onTap == null ? null : () => onTap!(item),
            onLongPress: onLongPress == null ? null : () => onLongPress!(item),
          );

    // Add semantics for accessibility
    child = Semantics(
      label: item.isDirectory ? '文件夹: ${item.name}' : '文件: ${item.name}',
      button: true,
      enabled: true,
      child: child,
    );

    // If selectionController provided, handle tap/longPress to toggle selection
    if (selectionController != null) {
      return ValueListenableBuilder<Set<String>>(
        valueListenable: selectionController!.selectedNotifier,
        builder: (context, selected, _) {
          final isSelected = selected.contains(item.path);

          return InkWell(
            onTap: () {
              if (selectionController!.isSelecting) {
                selectionController!.toggle(item.path);
              } else {
                if (onTap != null) onTap!(item);
              }
            },
            onLongPress: () {
              selectionController!.toggle(item.path);
              if (onLongPress != null) onLongPress!(item);
            },
            child: Stack(
              children: [
                child,
                if (isSelected)
                  Positioned.fill(
                    child: Container(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withOpacity(0.12),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    }

    return child;
  }
}

/// Internal widget to render a collapsible group section.
class _GroupSection extends StatefulWidget {
  final FileGroup group;
  final bool gridMode;
  final Widget Function(BuildContext, FileGroup)? headerBuilder;
  final Widget Function(FileItem)? itemBuilder;
  final Widget Function(BuildContext, FileItem) itemWrapper;
  final void Function(FileItem)? onTap;
  final void Function(FileItem)? onLongPress;

  const _GroupSection({
    required this.group,
    required this.gridMode,
    required this.headerBuilder,
    required this.itemBuilder,
    required this.itemWrapper,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<_GroupSection> createState() => _GroupSectionState();
}

class _GroupSectionState extends State<_GroupSection> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.group.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final header = widget.headerBuilder != null
        ? widget.headerBuilder!(context, widget.group)
        : _buildDefaultHeader(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: widget.group.isCollapsible
              ? () => setState(() => _isExpanded = !_isExpanded)
              : null,
          child: header,
        ),
        if (_isExpanded) ..._buildGroupItems(),
      ],
    );
  }

  Widget _buildDefaultHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          if (widget.group.isCollapsible)
            Icon(
              _isExpanded ? Icons.expand_more : Icons.chevron_right,
              size: 20,
            ),
          if (widget.group.isCollapsible) const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.group.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Text(
            '${widget.group.items.length}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupItems() {
    return widget.group.items
        .map((item) => widget.itemWrapper(context, item))
        .toList();
  }
}
