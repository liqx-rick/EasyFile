import 'package:flutter/material.dart';

/// Sliver吸顶效果代理
///
/// 用于实现Tab切换时标题栏的固定显示效果
/// 在 FileBrowserPage 中广泛使用（16处）
///
/// 使用场景：
/// - 浏览Tab切换时的分类标题吸顶
/// - 收藏Tab的标题栏固定
/// - 新文件Tab的标题栏固定
///
/// 示例：
/// ```dart
/// SliverPersistentHeader(
///   pinned: true,
///   delegate: PinnedHeaderDelegate(
///     child: Text('标题'),
///     height: 48.0,
///   ),
/// )
/// ```
class PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  PinnedHeaderDelegate({
    required this.child,
    required this.height,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: child,
    );
  }

  @override
  bool shouldRebuild(PinnedHeaderDelegate oldDelegate) {
    return height != oldDelegate.height || child != oldDelegate.child;
  }
}
