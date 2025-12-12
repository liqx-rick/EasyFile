import 'dart:io';
import 'package:flutter/material.dart';

/// 图片缩略图组件
///
/// 异步加载图片文件并显示为缩略图，支持加载指示器和错误处理
class ImageThumbnail extends StatelessWidget {
  final String imagePath;
  final double size;
  final BoxFit fit;

  const ImageThumbnail({
    super.key,
    required this.imagePath,
    this.size = 40,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    // 限制缓存尺寸，避免加载过大的图片到内存
    final cacheSize = (size * pixelRatio).toInt().clamp(100, 400);

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.file(
          File(imagePath),
          width: size,
          height: size,
          fit: fit,
          // 只限制宽度，让Flutter自动保持原始宽高比，避免图片变形
          cacheWidth: cacheSize,
          // cacheHeight 不设置，保持图片原始比例
          // 降低质量以减少内存占用
          filterQuality: FilterQuality.low,
          // 避免重复加载
          gaplessPlayback: true,
          // 错误时不显示加载动画，直接显示占位符
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return child;
            }
            // 简化加载动画，减少重绘
            return Container(
              color: Colors.grey[200],
            );
          },
          errorBuilder: (context, error, stackTrace) {
            // 加载失败时显示默认图标
            return Container(
              color: Colors.grey[200],
              child: Icon(Icons.image, color: Colors.grey[400], size: size / 2),
            );
          },
        ),
      ),
    );
  }
}
