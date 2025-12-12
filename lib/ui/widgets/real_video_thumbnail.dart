import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/services/video_thumbnail_load_queue.dart';

/// 视频真实缩略图组件
///
/// 功能特性：
/// - 从视频文件生成真实的第一帧缩略图
/// - 支持磁盘缓存机制，避免重复生成
/// - 自动获取并显示视频时长
/// - 使用队列控制并发，防止 MediaCodec 资源耗尽
/// - 实现 KeepAlive，避免滚动时重新加载
///
/// 性能优化：
/// - AutomaticKeepAliveClientMixin：保持 widget 状态，避免重建时重新加载
/// - 需配合 ValueKey 使用，确保 Flutter 正确识别同一个 widget
/// - 限制缓存图片大小，防止内存泄漏
class RealVideoThumbnail extends StatefulWidget {
  final String videoPath;
  final double size;
  final bool showDuration; // 是否显示时长标签

  const RealVideoThumbnail({
    super.key,
    required this.videoPath,
    this.size = 48.0,
    this.showDuration = true, // 默认显示，保持向后兼容
  });

  @override
  State<RealVideoThumbnail> createState() => _RealVideoThumbnailState();
}

class _RealVideoThumbnailState extends State<RealVideoThumbnail>
    with AutomaticKeepAliveClientMixin {
  Uint8List? _thumbnailData;
  bool _isLoading = true;
  bool _hasError = false;
  String? _duration;
  final _loadQueue = VideoThumbnailLoadQueue();

  /// 保持 widget 状态，避免在 GridView 滚动时被销毁后重新加载缩略图
  /// 即使 GridView 设置了 addAutomaticKeepAlives: false，
  /// 单个 widget 仍可通过此 mixin 选择保持状态
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
    // 只有在需要显示时长时才加载
    if (widget.showDuration) {
      _loadDuration();
    }
  }

  @override
  void didUpdateWidget(RealVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果视频路径改变，重新加载缩略图
    if (oldWidget.videoPath != widget.videoPath) {
      logger.i('🔄 [VideoThumbnail] didUpdateWidget: path changed, reloading');
      setState(() {
        _thumbnailData = null;
        _isLoading = true;
        _hasError = false;
        _duration = null;
      });
      _loadThumbnail();
      if (widget.showDuration) {
        _loadDuration();
      }
    }
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

      // 2. 使用队列加载缩略图（自动处理缓存和并发控制）
      // 如果缓存命中，通常在100ms内返回
      final startTime = DateTime.now();
      final thumbnailData =
          await _loadQueue.loadThumbnail(widget.videoPath, widget.size);
      final loadDuration = DateTime.now().difference(startTime);

      if (thumbnailData != null) {
        if (mounted) {
          setState(() {
            _thumbnailData = thumbnailData;
            _isLoading = false;
          });
        }
        logger.d('Thumbnail loaded in ${loadDuration.inMilliseconds}ms');
      } else {
        throw Exception('Failed to load thumbnail');
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

  /// 加载视频时长
  Future<void> _loadDuration() async {
    try {
      final duration = await _loadQueue.loadDuration(widget.videoPath);
      if (mounted && duration != null) {
        setState(() {
          _duration = duration;
        });
      }
    } catch (e) {
      logger.w('Failed to load video duration: $e');
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
    super.build(context); // 必须调用以支持 AutomaticKeepAliveClientMixin

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
              // 只限制宽度，让Flutter自动保持原始宽高比，避免视频变形
              cacheWidth:
                  (widget.size * MediaQuery.of(context).devicePixelRatio)
                      .toInt()
                      .clamp(150, 800),
              // cacheHeight 不设置，保持视频原始比例
              // 提升过滤质量以提高清晰度
              filterQuality: FilterQuality.medium,
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

            // 时长标签（左下角）- 仅在showDuration=true时显示
            if (widget.showDuration && _duration != null)
              Positioned(
                left: 4,
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
                    _duration!,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.size > 96 ? 11 : 10,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
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
