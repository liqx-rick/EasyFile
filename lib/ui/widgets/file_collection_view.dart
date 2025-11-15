import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/ui/widgets/file_item_tile.dart';

/// A lightweight, configurable collection view for displaying file items.
///
/// This is a minimal, backwards-compatible skeleton used as the shared
/// rendering surface for list/grid modes. It accepts an optional
/// `itemBuilder` so callers can supply custom item widgets (e.g. using
/// `FileItemTile` with custom sizes).
class FileCollectionView extends StatelessWidget {
  final List<FileItem> items;
  final bool gridMode;
  final Widget Function(FileItem)? itemBuilder;
  final void Function(FileItem)? onTap;
  final void Function(FileItem)? onLongPress;
  final EdgeInsetsGeometry padding;

  const FileCollectionView({
    super.key,
    required this.items,
    this.gridMode = false,
    this.itemBuilder,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(vertical: 8.0),
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

    if (gridMode) {
      // Simple responsive grid: 2 on small, 3 on medium, 4 on wide.
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
        itemBuilder: (c, i) => _buildItem(context, items[i]),
      );
    }

    return ListView.separated(
      padding: padding as EdgeInsets?,
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (c, i) => _buildItem(context, items[i]),
    );
  }

  Widget _buildItem(BuildContext context, FileItem item) {
    final builder = itemBuilder ??
        (file) => FileItemTile(
              file: file,
              onTap: onTap == null ? null : () => onTap!(file),
              onLongPress: onLongPress == null ? null : () => onLongPress!(file),
            );

    return builder(item);
  }
}
