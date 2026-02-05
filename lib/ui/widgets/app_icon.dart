import 'package:flutter/material.dart';

/// 应用图标组件
/// 显示应用图标，支持自定义大小和路径
class AppIcon extends StatelessWidget {
  /// 图标大小
  final double size;

  /// 图标路径
  final String iconPath;

  const AppIcon({
    super.key,
    this.size = 100,
    this.iconPath = 'assets/images/logo.png',
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      iconPath,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        // 如果图片加载失败，显示占位图标
        return Container(
          width: size,
          height: size,
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.folder_rounded,
            size: size * 0.6,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }
}
