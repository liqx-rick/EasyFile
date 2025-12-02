import 'package:flutter/material.dart';

/// 通用的分类筛选Sliver持久化头部代理
/// 
/// 用于在滚动列表中置顶显示分类筛选栏
/// 可在多个页面复用（回收站清理、垃圾文件清理等）
class SliverCategoryFilterDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  SliverCategoryFilterDelegate({
    required this.child,
    this.height = 60.0,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant SliverCategoryFilterDelegate oldDelegate) {
    return true; // 允许重建以更新动态内容（如Tab数字）
  }
}
