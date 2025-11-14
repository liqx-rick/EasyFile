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
          // 使用 cacheWidth 优化内存使用
          cacheWidth: (size * MediaQuery.of(context).devicePixelRatio).toInt(),
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) {
              return child;
            }
            // 显示加载动画
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: frame == null
                  ? Container(
                      color: Colors.grey[200],
                      child: Center(
                        child: SizedBox(
                          width: size / 3,
                          height: size / 3,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                    )
                  : child,
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
