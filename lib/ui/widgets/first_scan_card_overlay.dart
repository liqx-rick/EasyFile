import 'package:flutter/material.dart';
import 'dart:math' as math;

/// 首次扫描全屏卡片覆盖层
/// 极简设计风格，展示扫描进度和品牌标语
class FirstScanCardOverlay extends StatefulWidget {
  final bool isScanning;
  final double progress; // 0.0 - 1.0
  final VoidCallback? onComplete;

  const FirstScanCardOverlay({
    super.key,
    required this.isScanning,
    required this.progress,
    this.onComplete,
  });

  @override
  State<FirstScanCardOverlay> createState() => _FirstScanCardOverlayState();
}

class _FirstScanCardOverlayState extends State<FirstScanCardOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  bool _isCompleting = false;

  @override
  void initState() {
    super.initState();
    // 底层圆环旋转动画
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FirstScanCardOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 检测完成状态
    if (widget.progress >= 1.0 && !_isCompleting) {
      _isCompleting = true;
      // 延迟 2.5 秒后关闭，让用户看到完成状态
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) {
          widget.onComplete?.call();
        }
      });
    }
  }

  /// 根据进度获取状态文案
  String _getStatusText(double progress) {
    if (progress >= 1.0) {
      return '✅ 初始化完成，开始探索吧';
    } else if (progress >= 0.91) {
      return '✨ 正在完成最后的准备';
    } else if (progress >= 0.71) {
      return '⚡ 正在优化访问体验';
    } else if (progress >= 0.51) {
      return '🎵 正在分类音乐和文档';
    } else if (progress >= 0.31) {
      return '🖼️ 正在整理图片和视频';
    } else if (progress >= 0.11) {
      return '📂 正在发现常用目录';
    } else {
      return '🔍 正在准备文件空间';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isScanning) {
      return const SizedBox.shrink();
    }

    final statusText = _getStatusText(widget.progress);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final isLandscape = screenWidth > screenHeight;

    // 横屏模式下使用更小的尺寸
    final cardWidth = isLandscape
        ? math.min(screenWidth * 0.6, 480.0)
        : (screenWidth > 600 ? 360.0 : screenWidth * 0.85);
    final circleSize = isLandscape ? 80.0 : (screenWidth > 600 ? 140.0 : 120.0);
    final verticalPadding = isLandscape ? 20.0 : 40.0;
    final horizontalPadding = isLandscape ? 24.0 : 32.0;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 30 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Container(
              width: cardWidth,
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 32,
                    spreadRadius: 0,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 进度圆环
                  _buildProgressCircle(circleSize, isDark),

                  SizedBox(height: isLandscape ? 12 : 24),

                  // 状态文案
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      statusText,
                      key: ValueKey(statusText),
                      style: TextStyle(
                        fontSize: isLandscape ? 14 : 18,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  SizedBox(height: isLandscape ? 12 : 20),

                  // 线性进度条
                  SizedBox(
                    width: isLandscape ? 180 : 240,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: widget.progress),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return LinearProgressIndicator(
                          value: value,
                          backgroundColor:
                              isDark ? Colors.grey[700] : Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation(
                            _getProgressColor(value),
                          ),
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                        );
                      },
                    ),
                  ),

                  SizedBox(height: isLandscape ? 16 : 32),

                  // 品牌标语 - 使用更大更粗的样式和品牌蓝色
                  Text(
                    'EasyFile，让文件管理更简单',
                    style: TextStyle(
                      fontSize: isLandscape ? 13 : 16,
                      color: Colors.blue[700],
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建进度圆环
  Widget _buildProgressCircle(double size, bool isDark) {
    final progress = widget.progress.clamp(0.0, 1.0);
    final isComplete = progress >= 1.0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: isComplete ? 1.05 : 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 底层旋转圆环（灰色）
                RotationTransition(
                  turns: _rotationController,
                  child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 8,
                    color: isDark ? Colors.grey[700] : Colors.grey[200],
                  ),
                ),

                // 进度圆环（彩色渐变）
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: progress),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return CustomPaint(
                      size: Size(size, size),
                      painter: _CircularProgressPainter(
                        progress: value,
                        strokeWidth: 8,
                        color: _getProgressColor(value),
                        backgroundColor: Colors.transparent,
                      ),
                    );
                  },
                ),

                // 中心内容
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: isComplete
                      ? Icon(
                          Icons.check_circle,
                          key: const ValueKey('check'),
                          size: size * 0.4,
                          color: Colors.green,
                        )
                      : Text(
                          '${(progress * 100).toInt()}%',
                          key: const ValueKey('percent'),
                          style: TextStyle(
                            fontSize: size * 0.2,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.grey[800],
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 根据进度获取渐变色
  Color _getProgressColor(double progress) {
    if (progress >= 1.0) {
      return Colors.green;
    } else if (progress >= 0.7) {
      return Colors.blue;
    } else {
      return Theme.of(context).colorScheme.primary;
    }
  }
}

/// 自定义圆形进度绘制器
class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color color;
  final Color backgroundColor;

  _CircularProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // 绘制进度弧
    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // 从顶部开始
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
