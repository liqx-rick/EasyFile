import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/utils/thumbnail_cache_manager.dart';

/// 视频真实缩略图组件
///
/// 从视频文件生成真实的第一帧缩略图
/// 支持缓存机制，避免重复生成
class RealVideoThumbnail extends StatefulWidget {
  final String videoPath;
  final double size;
  final String? duration; // 可选的时长显示

  const RealVideoThumbnail({
    super.key,
    required this.videoPath,
    this.size = 40,
    this.duration,
  });

  @override
  State<RealVideoThumbnail> createState() => _RealVideoThumbnailState();
}

class _RealVideoThumbnailState extends State<RealVideoThumbnail> {
  Uint8List? _thumbnailData;
  bool _isLoading = true;
  bool _hasError = false;
  final _cacheManager = ThumbnailCacheManager();

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    try {
      // 1. 检查文件是否存在
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        logger.w('Video file does not exist: ${widget.videoPath}');
        if (mounted) {
          setState(() {
            _hasError = true;
            _isLoading = false;
          });
        }
        return;
      }

      // 2. 尝试从缓存加载
      final cachedData = await _cacheManager.getCached(widget.videoPath);
      if (cachedData != null) {
        logger.d('Loaded video thumbnail from cache');
        if (mounted) {
          setState(() {
            _thumbnailData = cachedData;
            _isLoading = false;
          });
        }
        return;
      }

      // 3. 生成新缩略图
      logger.d('Generating video thumbnail: ${widget.videoPath}');
      final thumbnailData = await VideoThumbnail.thumbnailData(
        video: widget.videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: widget.size > 64 ? 256 : 128, // 根据显示大小调整
        quality: 75,
      );

      if (thumbnailData != null) {
        // 4. 保存到缓存
        await _cacheManager.saveCache(widget.videoPath, thumbnailData);

        if (mounted) {
          setState(() {
            _thumbnailData = thumbnailData;
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Failed to generate thumbnail');
      }
    } catch (e) {
      logger.e('Error loading video thumbnail: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade700, Colors.blue.shade500],
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: SizedBox(
          width: widget.size * 0.3,
          height: widget.size * 0.3,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackIcon() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade700, Colors.blue.shade500],
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.play_circle_outline,
        color: Colors.white,
        size: widget.size * 0.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildPlaceholder();
    }

    if (_hasError || _thumbnailData == null) {
      return _buildFallbackIcon();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频缩略图
            Image.memory(
              _thumbnailData!,
              fit: BoxFit.cover,
              // 限制缓存大小，避免内存泄漏
              cacheWidth:
                  (widget.size * MediaQuery.of(context).devicePixelRatio)
                      .toInt()
                      .clamp(100, 400),
              cacheHeight:
                  (widget.size * MediaQuery.of(context).devicePixelRatio)
                      .toInt()
                      .clamp(100, 400),
              // 降低质量以减少内存占用
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                return _buildFallbackIcon();
              },
            ),

            // 渐变遮罩层
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.4)
                  ],
                ),
              ),
            ),

            // 播放图标
            Center(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: widget.size * 0.3,
                ),
              ),
            ),

            // 时长标签（右下角）
            if (widget.duration != null)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    widget.duration!,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.size > 50 ? 10 : 8,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
