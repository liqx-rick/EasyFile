import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:easyfile/core/logger.dart';

/// 视频适配模式枚举
enum VideoFitMode {
  contain, // 适应：完整显示，可能有黑边
  cover, // 填充：填满屏幕，可能裁剪
}

/// 播放状态类
class PlaybackState {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool isBuffering;

  const PlaybackState({
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.isBuffering,
  });

  /// 播放进度百分比 (0.0 - 1.0)
  double get progress {
    if (duration.inMilliseconds == 0) return 0.0;
    return position.inMilliseconds / duration.inMilliseconds;
  }

  @override
  String toString() {
    return 'PlaybackState(isPlaying: $isPlaying, position: ${position.inSeconds}s, '
        'duration: ${duration.inSeconds}s, isBuffering: $isBuffering, progress: ${(progress * 100).toStringAsFixed(1)}%)';
  }
}

/// 视频播放器组件
///
/// 功能特性：
/// - 播放进度记忆（使用 SharedPreferences）
/// - 播放状态监听和回调
/// - 横竖屏自适应
/// - 参数化配置（自动播放、循环播放等）
/// - 完善的错误处理
/// - 优化的 Chewie 配置（倍速播放等）
class VideoPlayerWidget extends StatefulWidget {
  /// 视频文件路径
  final String videoPath;

  /// 视频ID（用于保存/恢复播放位置）
  final String? videoId;

  /// 是否自动播放
  final bool autoPlay;

  /// 是否循环播放
  final bool looping;

  /// 播放状态变化回调
  final Function(PlaybackState)? onPlaybackStateChanged;

  /// 视频观看完成回调（播放进度达到80%以上时触发）
  final Function(String)? onVideoWatched;

  /// 错误回调
  final Function(String)? onError;

  /// 切换UI显示/隐藏回调（用于同步切换顶部AppBar）
  final VoidCallback? onToggleUI;

  /// 设置UI显示状态的回调（用于全屏时强制隐藏AppBar）
  final Function(bool show)? onSetUIVisible;

  const VideoPlayerWidget({
    super.key,
    required this.videoPath,
    this.videoId,
    this.autoPlay = true,
    this.looping = false,
    this.onPlaybackStateChanged,
    this.onVideoWatched,
    this.onError,
    this.onToggleUI,
    this.onSetUIVisible,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isInitializing = true;
  String? _error;
  Timer? _stateTimer;
  bool _hasTriggeredWatched = false;

  // 控制栏显示/隐藏状态
  bool _showControls = true;
  Timer? _hideControlsTimer;

  // 全屏状态
  bool _isFullScreen = false;

  // 播放速度
  double _playbackSpeed = 1.0;

  // 音量控制
  double _volume = 1.0;
  bool _isMuted = false;
  double _volumeBeforeMute = 1.0; // 静音前的音量，用于恢复

  // 亮度控制
  double _brightness = 0.5;

  // 视频适配模式
  VideoFitMode _videoFitMode = VideoFitMode.contain;

  // 主题色（在 initState 中获取，避免跨 async 使用 BuildContext）
  Color? _primaryColor;

  // 截图相关
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  bool _isTakingScreenshot = false;

  @override
  void initState() {
    super.initState();
    // 提前获取主题色，避免在 async 方法中使用 BuildContext
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _primaryColor = Theme.of(context).primaryColor;
        _initializePlayer();
        _initializeBrightness();
      }
    });
  }

  /// 初始化亮度
  Future<void> _initializeBrightness() async {
    try {
      final currentBrightness = await ScreenBrightness().application;
      logger.i('Current screen brightness: $currentBrightness');
      if (mounted) {
        setState(() {
          _brightness = currentBrightness;
        });
      }
    } catch (e) {
      logger.e('Failed to get current brightness: $e');
      // 如果获取失败，使用默认值
      if (mounted) {
        setState(() {
          _brightness = 0.5;
        });
      }
    }
  }

  /// 初始化播放器
  Future<void> _initializePlayer() async {
    try {
      logger.i('Initializing video player for: ${widget.videoPath}');

      // 检查文件是否存在
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        throw FileSystemException('视频文件不存在', widget.videoPath);
      }

      // 创建视频控制器
      _videoPlayerController = VideoPlayerController.file(file);

      // 初始化视频
      await _videoPlayerController!.initialize();

      // 检查视频是否初始化成功
      if (!_videoPlayerController!.value.isInitialized) {
        throw Exception('视频初始化失败');
      }

      // 恢复播放位置
      if (widget.videoId != null) {
        await _restorePlaybackPosition();
      }

      // 创建 Chewie 控制器（隐藏默认控制）
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: widget.autoPlay,
        looping: widget.looping,
        showControls: false, // 隐藏默认控制，使用自定义底部控制
        allowFullScreen: true,
        allowPlaybackSpeedChanging: true,
        playbackSpeeds: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
        materialProgressColors: ChewieProgressColors(
          playedColor: _primaryColor ?? Colors.blue,
          handleColor: (_primaryColor ?? Colors.blue).withValues(alpha: 0.8),
          backgroundColor: Colors.grey.withValues(alpha: 0.3),
          bufferedColor: (_primaryColor ?? Colors.blue).withValues(alpha: 0.5),
        ),
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
        errorBuilder: (context, errorMessage) {
          return _buildErrorWidget('视频播放失败\n$errorMessage');
        },
      );

      // 设置播放器监听器
      _videoPlayerController!.addListener(_onVideoPlayerUpdate);

      // 启动状态监听定时器
      _startStateTimer();

      logger.i('Video player initialized successfully');

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } on PlatformException catch (e) {
      final errorMsg = '平台错误: ${e.message}';
      logger.e('PlatformException initializing video player: $errorMsg');
      _handleError(errorMsg);
    } on FileSystemException catch (e) {
      final errorMsg = '文件系统错误: ${e.message}';
      logger.e('FileSystemException: $errorMsg');
      _handleError(errorMsg);
    } catch (e) {
      final errorMsg = '无法加载视频: $e';
      logger.e('Error initializing video player: $e');
      _handleError(errorMsg);
    }
  }

  /// 处理错误
  void _handleError(String errorMessage) {
    if (mounted) {
      setState(() {
        _error = errorMessage;
        _isInitializing = false;
      });
      widget.onError?.call(errorMessage);
    }
  }

  /// 恢复播放位置
  Future<void> _restorePlaybackPosition() async {
    if (widget.videoId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'video_position_${widget.videoId}';
      final positionMs = prefs.getInt(key);

      if (positionMs != null && positionMs > 0) {
        final position = Duration(milliseconds: positionMs);
        await _videoPlayerController!.seekTo(position);
        logger.i(
            'Restored playback position: ${position.inSeconds}s for videoId: ${widget.videoId}');
      }
    } catch (e) {
      logger.e('Error restoring playback position: $e');
    }
  }

  /// 保存播放位置（fire-and-forget方式，不使用await）
  void _savePlaybackPosition() {
    if (widget.videoId == null || _videoPlayerController == null) return;

    final position = _videoPlayerController!.value.position;
    final key = 'video_position_${widget.videoId}';

    // fire-and-forget方式保存，不阻塞dispose
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(key, position.inMilliseconds);
      logger.i(
          'Saved playback position: ${position.inSeconds}s for videoId: ${widget.videoId}');
    }).catchError((e) {
      logger.e('Error saving playback position: $e');
    });
  }

  /// 视频播放器更新监听
  void _onVideoPlayerUpdate() {
    if (_videoPlayerController == null || !mounted) return;

    final value = _videoPlayerController!.value;

    // 检查错误
    if (value.hasError) {
      final errorMsg = '播放错误: ${value.errorDescription}';
      logger.e(errorMsg);
      _handleError(errorMsg);
    }
  }

  /// 启动状态监听定时器
  void _startStateTimer() {
    _stateTimer?.cancel();
    _stateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_videoPlayerController == null || !mounted) return;

      final value = _videoPlayerController!.value;
      final state = PlaybackState(
        isPlaying: value.isPlaying,
        position: value.position,
        duration: value.duration,
        isBuffering: value.isBuffering,
      );

      // 触发状态变化回调（确保 widget 已 mounted）
      if (mounted) {
        widget.onPlaybackStateChanged?.call(state);
      }

      // 检查是否达到观看完成条件（80%以上）
      if (!_hasTriggeredWatched &&
          state.progress >= 0.8 &&
          widget.videoId != null &&
          mounted) {
        _hasTriggeredWatched = true;
        widget.onVideoWatched?.call(widget.videoId!);
        logger.i(
            'Video watched triggered at ${(state.progress * 100).toStringAsFixed(1)}% for videoId: ${widget.videoId}');
      }
    });
  }

  /// 切换控制栏显示/隐藏
  void _toggleControls() {
    if (!mounted) return; // 安全检查
    
    logger.i(
        'Toggle controls: $_showControls -> ${!_showControls}, isFullScreen: $_isFullScreen');

    setState(() {
      _showControls = !_showControls;
    });

    // 只在非全屏模式下触发父组件的UI切换（AppBar等）
    // 全屏模式下，AppBar应该始终保持隐藏
    if (!_isFullScreen) {
      if (mounted) widget.onToggleUI?.call();
    } else {
      logger
          .i('Fullscreen mode - not toggling parent UI (AppBar stays hidden)');
    }

    // 如果显示控制栏，启动自动隐藏定时器
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  /// 启动自动隐藏控制栏定时器（3秒后自动隐藏）
  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _showControls) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  /// 取消自动隐藏定时器
  void _cancelHideControlsTimer() {
    _hideControlsTimer?.cancel();
  }

  /// 截取视频当前帧并保存到相册
  Future<void> _takeScreenshot() async {
    if (_isTakingScreenshot) {
      logger.w('Screenshot already in progress');
      return;
    }

    setState(() {
      _isTakingScreenshot = true;
    });

    try {
      // 请求相册权限
      if (Platform.isAndroid) {
        // Android 13+ 需要 photos 权限
        PermissionStatus status;
        if (await Permission.photos.isGranted) {
          status = PermissionStatus.granted;
        } else {
          status = await Permission.photos.request();
          // 如果 photos 权限不可用（Android 12 及以下），尝试 storage 权限
          if (status.isDenied || status.isPermanentlyDenied) {
            status = await Permission.storage.request();
          }
        }
        
        if (!status.isGranted) {
          logger.w('Photo/Storage permission denied');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('需要相册权限才能保存截图')),
            );
          }
          return;
        }
      }

      // 捕获当前视频帧
      final boundary = _repaintBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null) {
        logger.w('Failed to get render boundary');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('截图失败：无法捕获画面')),
          );
        }
        return;
      }

      // 转换为图像
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();

      if (pngBytes == null) {
        logger.w('Failed to convert image to bytes');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('截图失败：图像转换失败')),
          );
        }
        return;
      }

      // 保存到相册
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempDir = await Directory.systemTemp.createTemp();
      final filePath = '${tempDir.path}/video_screenshot_$timestamp.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      // 使用 gal 保存到相册
      await Gal.putImage(filePath);
      
      // 清理临时文件
      await file.delete();
      await tempDir.delete();

      logger.i('Screenshot saved to gallery');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('截图已保存到相册'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logger.e('Screenshot failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('截图失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTakingScreenshot = false;
        });
      }
    }
  }

  /// 切换全屏模式
  void _toggleFullScreen() {
    if (!mounted) return; // 安全检查
    
    logger.i('Toggle fullscreen: $_isFullScreen -> ${!_isFullScreen}');

    final willBeFullScreen = !_isFullScreen;

    setState(() {
      _isFullScreen = willBeFullScreen;
      _showControls = true; // 切换全屏时显示控制栏
    });

    // 使用onSetUIVisible强制设置父组件UI状态
    if (willBeFullScreen) {
      // 进入全屏：强制隐藏AppBar
      if (mounted) widget.onSetUIVisible?.call(false);
      logger.i('Entering fullscreen - force hiding AppBar');
    } else {
      // 退出全屏：强制显示AppBar
      if (mounted) widget.onSetUIVisible?.call(true);
      logger.i('Exiting fullscreen - force showing AppBar');
    }

    logger.i(
        'After toggle - isFullScreen: $_isFullScreen, showControls: $_showControls');

    // 设置系统界面模式
    if (_isFullScreen) {
      // 全屏：隐藏系统界面
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      // 根据视频宽高比决定屏幕方向
      if (_videoPlayerController != null &&
          _videoPlayerController!.value.isInitialized) {
        final aspectRatio = _videoPlayerController!.value.aspectRatio;
        logger.i('Video aspect ratio: $aspectRatio');

        if (aspectRatio > 1.0) {
          // 横屏视频（宽 > 高）：强制横屏
          logger.i('Landscape video - forcing landscape orientation');
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        } else {
          // 竖屏视频（高 >= 宽）：保持竖屏或允许所有方向
          logger.i('Portrait video - keeping portrait orientation');
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
        }
      } else {
        // 如果视频未初始化，允许所有方向
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
          DeviceOrientation.portraitDown,
        ]);
      }
    } else {
      // 退出全屏：恢复系统界面，允许所有方向
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    // 启动自动隐藏
    _startHideControlsTimer();
  }

  @override
  void dispose() {
    logger.i('Disposing video player');

    // 恢复系统设置
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitDown,
    ]);

    // 恢复屏幕亮度
    try {
      ScreenBrightness().resetApplicationScreenBrightness();
    } catch (e) {
      logger.w('Failed to reset brightness: $e');
    }

    // 停止定时器
    _stateTimer?.cancel();
    _hideControlsTimer?.cancel();

    // 保存播放位置（fire-and-forget）
    _savePlaybackPosition();

    // 移除监听器
    _videoPlayerController?.removeListener(_onVideoPlayerUpdate);

    // 释放资源
    _chewieController?.dispose();
    _videoPlayerController?.dispose();

    super.dispose();
  }

  /// 根据适配模式构建视频widget
  Widget _buildVideoWithFitMode() {
    final videoAspectRatio = _videoPlayerController!.value.aspectRatio;

    switch (_videoFitMode) {
      case VideoFitMode.contain:
        // 适应：保持原始比例，完整显示
        return Center(
          child: AspectRatio(
            aspectRatio: videoAspectRatio,
            child: Chewie(controller: _chewieController!),
          ),
        );

      case VideoFitMode.cover:
        // 填充：填满屏幕，裁剪超出部分
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoPlayerController!.value.size.width,
              height: _videoPlayerController!.value.size.height,
              child: Chewie(controller: _chewieController!),
            ),
          ),
        );
    }
  }

  /// 获取当前适配模式对应的图标
  IconData _getVideoFitModeIcon() {
    switch (_videoFitMode) {
      case VideoFitMode.contain:
        return Icons.fit_screen;
      case VideoFitMode.cover:
        return Icons.zoom_out_map;
    }
  }

  /// 构建错误提示组件
  Widget _buildErrorWidget(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _error = null;
                  _isInitializing = true;
                  _hasTriggeredWatched = false;
                });
                _initializePlayer();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建底部控制栏
  Widget _buildBottomControls() {
    if (_videoPlayerController == null) return const SizedBox.shrink();

    final value = _videoPlayerController!.value;
    final position = value.position;
    final duration = value.duration;
    final isPlaying = value.isPlaying;

    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：时间、快退、进度条、快进、时间
          Row(
            children: [
              // 当前时间
              Text(
                _formatDuration(position),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
              // 快退10秒按钮
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                icon: const Icon(
                  Icons.fast_rewind,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: () async {
                  final currentPosition =
                      _videoPlayerController!.value.position;
                  final newPosition =
                      currentPosition - const Duration(seconds: 10);
                  final targetPosition =
                      newPosition < Duration.zero ? Duration.zero : newPosition;

                  await _videoPlayerController!.seekTo(targetPosition);
                  if (mounted) {
                    setState(() {});
                  }
                  _startHideControlsTimer();
                },
              ),
              // 进度条
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: _primaryColor ?? Colors.blue,
                    inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                    thumbColor: _primaryColor ?? Colors.blue,
                    overlayColor:
                        (_primaryColor ?? Colors.blue).withValues(alpha: 0.3),
                  ),
                  child: Slider(
                    value: duration.inMilliseconds > 0
                        ? position.inMilliseconds.toDouble()
                        : 0.0,
                    min: 0.0,
                    max: duration.inMilliseconds.toDouble(),
                    onChanged: (value) {
                      _videoPlayerController!
                          .seekTo(Duration(milliseconds: value.toInt()));
                    },
                  ),
                ),
              ),
              // 快进10秒按钮
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                icon: const Icon(
                  Icons.fast_forward,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: () async {
                  final currentPosition =
                      _videoPlayerController!.value.position;
                  final duration = _videoPlayerController!.value.duration;
                  final newPosition =
                      currentPosition + const Duration(seconds: 10);
                  final targetPosition =
                      newPosition > duration ? duration : newPosition;

                  await _videoPlayerController!.seekTo(targetPosition);
                  if (mounted) {
                    setState(() {});
                  }
                  _startHideControlsTimer();
                },
              ),
              // 总时长
              Text(
                _formatDuration(duration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          // 两行之间的间距
          const SizedBox(height: 8),
          // 第二行：播放按钮及其他控制按钮
          Row(
            children: [
              // 播放/暂停按钮
              IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () {
                  setState(() {
                    if (isPlaying) {
                      _videoPlayerController!.pause();
                      _cancelHideControlsTimer();
                    } else {
                      _videoPlayerController!.play();
                      _startHideControlsTimer();
                    }
                  });
                },
              ),
              // 截图按钮
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                icon: _isTakingScreenshot
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 20,
                      ),
                onPressed: _isTakingScreenshot ? null : _takeScreenshot,
                tooltip: '截图',
              ),
              // 音量控制按钮
              PopupMenuButton<double>(
                padding: EdgeInsets.zero,
                offset: const Offset(-10, -200),
                constraints: const BoxConstraints(
                  minWidth: 80,
                  maxWidth: 80,
                ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: Icon(
                      _isMuted || _volume == 0
                          ? Icons.volume_off
                          : _volume < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
                color: Colors.grey[900],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onSelected: (value) {
                  // 不使用 onSelected，使用自定义滑块
                },
                itemBuilder: (context) => [
                  PopupMenuItem<double>(
                    enabled: false,
                    child: StatefulBuilder(
                      builder: (context, setPopupState) {
                        return SizedBox(
                          width: 60, // 减小弹窗宽度
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 静音按钮
                              IconButton(
                                icon: Icon(
                                  _isMuted ? Icons.volume_off : Icons.volume_up,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (_isMuted) {
                                      // 取消静音，恢复之前的音量
                                      _isMuted = false;
                                      _volume = _volumeBeforeMute;
                                      _videoPlayerController!
                                          .setVolume(_volume);
                                    } else {
                                      // 静音
                                      _isMuted = true;
                                      _volumeBeforeMute = _volume;
                                      _volume = 0.0;
                                      _videoPlayerController!.setVolume(0.0);
                                    }
                                  });
                                  _startHideControlsTimer();
                                  // 关闭弹窗
                                  Navigator.of(context).pop();
                                },
                              ),
                              const SizedBox(height: 8),
                              // 垂直音量滑块
                              SizedBox(
                                height: 120,
                                width: 40, // 减小滑块宽度
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                              overlayRadius: 12),
                                      activeTrackColor:
                                          _primaryColor ?? Colors.blue,
                                      inactiveTrackColor:
                                          Colors.grey.withValues(alpha: 0.3),
                                      thumbColor: _primaryColor ?? Colors.blue,
                                      overlayColor:
                                          (_primaryColor ?? Colors.blue)
                                              .withValues(alpha: 0.3),
                                    ),
                                    child: Slider(
                                      value: _volume,
                                      min: 0.0,
                                      max: 1.0,
                                      onChanged: (value) {
                                        // 更新外部状态
                                        setState(() {
                                          _volume = value;
                                          _isMuted = false;
                                          _videoPlayerController!
                                              .setVolume(value);
                                        });
                                        // 更新弹窗内部状态，实现视觉反馈
                                        setPopupState(() {});
                                        _startHideControlsTimer();
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // 亮度控制按钮（仅全屏模式显示）
              if (_isFullScreen)
                PopupMenuButton<double>(
                  padding: EdgeInsets.zero,
                  offset: const Offset(-10, -180),
                  constraints: const BoxConstraints(
                    minWidth: 80,
                    maxWidth: 80,
                  ),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: Icon(
                        _brightness < 0.3
                            ? Icons.brightness_low
                            : _brightness < 0.7
                                ? Icons.brightness_medium
                                : Icons.brightness_high,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  color: Colors.grey[900],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onSelected: (value) {
                    // 不使用 onSelected，使用自定义滑块
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<double>(
                      enabled: false,
                      child: StatefulBuilder(
                        builder: (context, setPopupState) {
                          return SizedBox(
                            width: 60,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 亮度图标
                                Icon(
                                  _brightness < 0.3
                                      ? Icons.brightness_low
                                      : _brightness < 0.7
                                          ? Icons.brightness_medium
                                          : Icons.brightness_high,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                const SizedBox(height: 8),
                                // 垂直亮度滑块
                                SizedBox(
                                  height: 120,
                                  width: 40,
                                  child: RotatedBox(
                                    quarterTurns: 3,
                                    child: SliderTheme(
                                      data: SliderThemeData(
                                        trackHeight: 3,
                                        thumbShape: const RoundSliderThumbShape(
                                            enabledThumbRadius: 6),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                                overlayRadius: 12),
                                        activeTrackColor:
                                            Colors.amber,
                                        inactiveTrackColor:
                                            Colors.grey.withValues(alpha: 0.3),
                                        thumbColor:
                                            Colors.amber,
                                        overlayColor:
                                            Colors.amber
                                                .withValues(alpha: 0.3),
                                      ),
                                      child: Slider(
                                        value: _brightness,
                                        min: 0.0,
                                        max: 1.0,
                                        onChanged: (value) async {
                                          // 更新外部状态
                                          setState(() {
                                            _brightness = value;
                                          });
                                          // 设置屏幕亮度
                                          try {
                                            await ScreenBrightness()
                                                .setApplicationScreenBrightness(
                                                    value);
                                            logger.i(
                                                'Screen brightness set to: $value');
                                          } catch (e) {
                                            logger.e(
                                                'Failed to set brightness: $e');
                                          }
                                          // 更新弹窗内部状态，实现视觉反馈
                                          setPopupState(() {});
                                          _startHideControlsTimer();
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              // 视频比例按钮 - 仅非全屏模式显示
              if (!_isFullScreen)
                IconButton(
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  icon: Icon(
                    _getVideoFitModeIcon(),
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: () {
                    setState(() {
                      // 在两种模式间切换
                      _videoFitMode = _videoFitMode == VideoFitMode.contain
                          ? VideoFitMode.cover
                          : VideoFitMode.contain;
                    });
                    _startHideControlsTimer();
                  },
                  tooltip: _videoFitMode == VideoFitMode.contain ? '适应' : '填充',
                ),
              // 播放速度按钮
              PopupMenuButton<double>(
                padding: EdgeInsets.zero,
                offset: const Offset(-10, -260),
                constraints: const BoxConstraints(
                  minWidth: 80,
                  maxWidth: 80,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_playbackSpeed}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                color: Colors.grey[900],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onSelected: (speed) {
                  setState(() {
                    _playbackSpeed = speed;
                  });
                  _videoPlayerController!.setPlaybackSpeed(speed);
                  // 重新启动自动隐藏定时器
                  _startHideControlsTimer();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 0.5,
                    height: 40,
                    child: Center(
                      child: Text('0.5x', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 0.75,
                    height: 40,
                    child: Center(
                      child: Text('0.75x', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 1.0,
                    height: 40,
                    child: Center(
                      child: Text('1.0x', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 1.25,
                    height: 40,
                    child: Center(
                      child: Text('1.25x', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 1.5,
                    height: 40,
                    child: Center(
                      child: Text('1.5x', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 2.0,
                    height: 40,
                    child: Center(
                      child: Text('2.0x', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ),
                ],
              ),
              // 全屏/退出全屏按钮
              IconButton(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                icon: Icon(
                  _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: _toggleFullScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 格式化时长显示
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    // 加载中状态
    if (_isInitializing) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                '正在加载视频...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    // 错误状态
    if (_error != null) {
      return Container(
        color: Colors.black,
        child: _buildErrorWidget(_error!),
      );
    }

    // 播放器未初始化
    if (_chewieController == null || _videoPlayerController == null) {
      return Container(
        color: Colors.black,
        child: _buildErrorWidget('视频加载失败'),
      );
    }

    // 横竖屏自适应布局，带底部控制栏
    return OrientationBuilder(
      builder: (context, orientation) {
        Widget videoWidget;

        // 全屏模式：始终全屏显示
        if (_isFullScreen) {
          videoWidget = SizedBox.expand(
            child: Chewie(controller: _chewieController!),
          );
        }
        // 非全屏模式：根据适配模式渲染（横屏和竖屏都支持比例设置）
        else {
          videoWidget = _buildVideoWithFitMode();
        }

        // 将视频和底部控制栏组合，添加点击屏幕切换控制栏
        return Container(
          color: Colors.black,
          child: GestureDetector(
            onTap: _toggleControls,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                // 用 RepaintBoundary 包裹视频，用于截图
                RepaintBoundary(
                  key: _repaintBoundaryKey,
                  child: videoWidget,
                ),
                // 底部控制栏（带渐显/渐隐动画）
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: _showControls
                          ? _buildBottomControls()
                          : const SizedBox.shrink(),
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
}
