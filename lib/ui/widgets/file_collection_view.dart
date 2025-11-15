import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/ui/widgets/file_item_tile.dart';

/// Controller to manage selection state for FileCollectionView.
class SelectionController {
  final ValueNotifier<Set<String>> _selected = ValueNotifier({});

  ValueNotifier<Set<String>> get selectedNotifier => _selected;

  Set<String> get selected => _selected.value;

  bool contains(String path) => _selected.value.contains(path);

  bool get isSelecting => _selected.value.isNotEmpty;

  void select(String path) {
    final copy = Set<String>.from(_selected.value);
    copy.add(path);
    _selected.value = copy;
  }

  void deselect(String path) {
    final copy = Set<String>.from(_selected.value);
    copy.remove(path);
    _selected.value = copy;
  }

  void toggle(String path) {
    final copy = Set<String>.from(_selected.value);
    if (copy.contains(path)) {
      copy.remove(path);
    } else {
      copy.add(path);
    }
    _selected.value = copy;
  }

  void clear() => _selected.value = {};
}

/// A lightweight, configurable collection view for displaying file items.
/// Supports an optional header slot and an external selection controller.
class FileCollectionView extends StatelessWidget {
  final List<FileItem> items;
  final bool gridMode;
  final Widget Function(FileItem)? itemBuilder;
  final void Function(FileItem)? onTap;
  final void Function(FileItem)? onLongPress;
  final EdgeInsetsGeometry padding;
  final WidgetBuilder? headerBuilder;
  final SelectionController? selectionController;

  const FileCollectionView({
    super.key,
    required this.items,
    this.gridMode = false,
    this.itemBuilder,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(vertical: 8.0),
    this.headerBuilder,
    this.selectionController,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
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

    final content = gridMode ? _buildGrid(context) : _buildList(context);

    if (headerBuilder != null) {
      return Column(
        children: [
          headerBuilder!(context),
          Expanded(child: content),
        ],
      );
    }

    return content;
  }

  Widget _buildList(BuildContext context) {
    return ListView.separated(
      padding: padding as EdgeInsets?,
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (c, i) => _buildItemWrapper(context, items[i]),
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
      itemCount: items.length,
      itemBuilder: (c, i) => _buildItemWrapper(context, items[i]),
    );
  }

  Widget _buildItemWrapper(BuildContext context, FileItem item) {
    final child = itemBuilder != null
        ? itemBuilder!(item)
        : FileItemTile(
            file: item,
            onTap: onTap == null ? null : () => onTap!(item),
            onLongPress: onLongPress == null ? null : () => onLongPress!(item),
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
