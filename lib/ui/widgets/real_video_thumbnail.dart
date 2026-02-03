import 'dart:io';
import 'dart:typed_data';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/services/video_thumbnail_load_queue.dart';
import 'package:flutter/material.dart';

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

class _RealVideoThumbnailState extends State<RealVideoThumbnail> with AutomaticKeepAliveClientMixin {
  Uint8List? _thumbnailData;
  bool _isLoading = true;
  bool _hasError = false;
  String? _duration;
  final _loadQueue = VideoThumbnailLoadQueue();

  // 缓存计算的 cacheWidth，避免每次 build() 都重新计算导致 Image widget 重建
  int? _cachedCacheWidth;

  /// 保持 widget 状态，避免在 GridView 滚动时被销毁后重新加载缩略图
  /// 即使 GridView 设置了 addAutomaticKeepAlives: false，
  /// 单个 widget 仍可通过此 mixin 选择保持状态
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 立即激活 KeepAlive 机制，防止滚动时被销毁
    updateKeepAlive();
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
        _cachedCacheWidth = null; // 重置缓存的宽度
      });
      _loadThumbnail();
      if (widget.showDuration) {
        _loadDuration();
      }
    }
    // 如果 size 改变，也需要重置 cacheWidth
    else if (oldWidget.size != widget.size) {
      setState(() {
        _cachedCacheWidth = null; // 重置缓存的宽度
      });
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
      final thumbnailData = await _loadQueue.loadThumbnail(widget.videoPath, widget.size);

      if (thumbnailData != null) {
        // 只在数据真正改变时才 setState
        // 避免重复加载相同的缩略图数据触发不必要的 rebuild
        if (mounted && _thumbnailData != thumbnailData) {
          setState(() {
            _thumbnailData = thumbnailData;
            _isLoading = false;
          });
        } else if (mounted && _isLoading) {
          // 如果数据相同但还在 loading 状态，只更新 loading 标志
          setState(() {
            _isLoading = false;
          });
        }
        // 性能优化：移除滚动时频繁触发的日志输出
        // logger.d('Thumbnail loaded in ${loadDuration.inMilliseconds}ms');
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
      // 只在 duration 真正改变时才 setState，避免不必要的 rebuild
      // 频繁的 setState 会导致 Image.memory 被重新创建，触发重复的图片解码请求
      if (mounted && duration != null && _duration != duration) {
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
          colors: [Colors.grey.shade300, Colors.grey.shade200],
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Align(
        alignment: Alignment.bottomLeft, // 左下角对齐
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.play_circle_outline,
            color: Colors.grey.shade400.withValues(alpha: 0.6), // 半透明灰色
            size: widget.size * 0.2, // 缩小到20%
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

    // 缓存 cacheWidth 计算结果，避免每次 build 都创建新的 Image widget
    // 这会导致 Flutter 认为这是一个新的图片请求，触发重复的解码操作
    if (_cachedCacheWidth == null) {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final rawWidth = widget.size * dpr;
      _cachedCacheWidth = rawWidth.toInt().clamp(150, 800);
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
              cacheWidth: _cachedCacheWidth,
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
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.4)],
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
