import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:easyfile/core/logger.dart';

/// 音频播放器组件
///
/// 使用 audioplayers 实现音频播放功能
/// 支持播放控制、进度条、循环播放等功能
class AudioPlayerWidget extends StatefulWidget {
  final String audioPath;
  final String fileName;
  final bool autoPlay; // 是否自动播放

  const AudioPlayerWidget({
    super.key,
    required this.audioPath,
    required this.fileName,
    this.autoPlay = true, // 默认自动播放
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _isLooping = false; // 单曲循环状态
  bool _isCompleted = false; // 播放是否已完成
  bool _isStopped = false; // 是否被停止（停止后需要用play而不是resume）
  double _playbackRate = 1.0; // 播放速度（0.5x ~ 2.0x）
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _error;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _playerCompleteSubscription; // 播放完成监听

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      logger.d('Initializing audio player for: ${widget.audioPath}');

      _audioPlayer = AudioPlayer();

      // 监听播放状态
      _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((
        state,
      ) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
          });
        }
      });

      // 监听播放进度
      _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      });

      // 监听总时长
      _durationSubscription = _audioPlayer.onDurationChanged.listen((duration) {
        if (mounted) {
          setState(() {
            _duration = duration;
          });
        }
      });

      // 监听播放完成事件
      _playerCompleteSubscription =
          _audioPlayer.onPlayerComplete.listen((_) async {
        logger.d('Audio playback completed, isLooping: $_isLooping');
        if (mounted) {
          if (_isLooping) {
            // 循环模式：重新播放（使用play而不是seek+resume避免超时）
            try {
              setState(() {
                _isCompleted = false;
                _position = Duration.zero;
              });
              await _audioPlayer.play(DeviceFileSource(widget.audioPath));
              setState(() {
                _isPlaying = true;
              });
              logger.d('Loop playback restarted');
            } catch (e) {
              logger.e('Error in loop playback: $e');
              setState(() {
                _isPlaying = false;
              });
            }
          } else {
            // 非循环模式：停止并重置
            setState(() {
              _position = Duration.zero;
              _isPlaying = false;
              _isCompleted = true; // 标记播放已完成
            });
          }
        }
      });

      // 设置音频源
      await _audioPlayer.setSourceDeviceFile(widget.audioPath);

      logger.d('Audio player initialized successfully');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // 如果启用自动播放，则开始播放
        if (widget.autoPlay) {
          await _audioPlayer.play(DeviceFileSource(widget.audioPath));
          logger.d('Auto-play started');
        }
      }
    } catch (e) {
      logger.e('Error initializing audio player: $e');
      if (mounted) {
        setState(() {
          _error = '无法加载音频: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _playPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        logger.d('Audio paused');
      } else {
        // 如果播放已完成，重新开始播放
        if (_isCompleted) {
          setState(() {
            _isCompleted = false;
            _position = Duration.zero;
          });
          await _audioPlayer.play(DeviceFileSource(widget.audioPath));
          setState(() {
            _isPlaying = true;
          });
          logger.d('Audio restarted from beginning after completion');
        } else if (_isStopped) {
          // 如果被停止，从开头开始播放（已经seek到开头）
          setState(() {
            _isStopped = false;
          });
          await _audioPlayer.resume();
          logger.d('Audio resumed from stop');
        } else {
          await _audioPlayer.resume();
          logger.d('Audio resumed from position: $_position');
        }
      }
    } catch (e) {
      logger.e('Error toggling play/pause: $e');
      _showError('播放控制失败');
    }
  }

  Future<void> _stop() async {
    try {
      await _audioPlayer.pause();
      await _audioPlayer.seek(Duration.zero);
      setState(() {
        _position = Duration.zero;
        _isCompleted = false;
        _isStopped = true; // 标记为已停止
        _isPlaying = false;
      });
      logger.d('Audio stopped');
    } catch (e) {
      logger.e('Error stopping audio: $e');
    }
  }

  Future<void> _seek(Duration position) async {
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      logger.e('Error seeking audio: $e');
    }
  }

  /// 跳过指定时长（支持前后跳）
  Future<void> _skip(Duration delta) async {
    final newPosition = _position + delta;
    if (newPosition < Duration.zero) {
      _seek(Duration.zero);
    } else if (newPosition > _duration) {
      _seek(_duration);
    } else {
      _seek(newPosition);
    }
  }

  /// 切换循环模式
  void _toggleLoop() {
    setState(() {
      _isLooping = !_isLooping;
    });
    logger.d('Loop mode: $_isLooping');
  }

  /// 设置播放速度
  Future<void> _setPlaybackRate(double rate) async {
    try {
      await _audioPlayer.setPlaybackRate(rate);
      setState(() {
        _playbackRate = rate;
      });
      logger.d('Playback rate set to: $rate');
    } catch (e) {
      logger.e('Error setting playback rate: $e');
      _showError('设置播放速度失败');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

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
  void dispose() {
    logger.d('Disposing audio player');
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _playerCompleteSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载音频...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _error = null;
                  _isLoading = true;
                });
                _initializePlayer();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 检测主题和屏幕信息
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  // 深色模式：紫色渐变
                  Colors.purple.shade900,
                  Colors.purple.shade700,
                  Colors.purple.shade500,
                ]
              : [
                  // 浅色模式：浅紫+白色渐变
                  Colors.purple.shade50,
                  Colors.purple.shade100,
                  Colors.white,
                ],
        ),
      ),
      child: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            final screenSize = MediaQuery.of(context).size;
            final isTablet = screenSize.width > 600;
            final isLandscape = orientation == Orientation.landscape;

            // 根据屏幕方向选择对应布局
            // 横屏：左右分栏布局（左侧图标，右侧控制面板）
            // 竖屏：上下垂直布局（居中显示）
            return isLandscape
                ? _buildLandscapeLayout(context, isDark, isTablet)
                : _buildPortraitLayout(context, isDark, isTablet);
          },
        ),
      ),
    );
  }

  /// 构建竖屏布局
  ///
  /// 使用 ListView 实现可滚动布局，避免内容溢出
  /// 顶部添加 18% 屏幕高度的间距，使内容整体下移以优化视觉效果
  Widget _buildPortraitLayout(
    BuildContext context,
    bool isDark,
    bool isTablet,
  ) {
    final screenHeight = MediaQuery.of(context).size.height;

    return ListView(
      padding: EdgeInsets.only(
        left: isTablet ? 32.0 : 16.0,
        right: isTablet ? 32.0 : 16.0,
        top: screenHeight * 0.18, // 顶部下移优化视觉位置
        bottom: isTablet ? 32.0 : 20.0,
      ),
      children: [
        // 音频图标（响应式尺寸）
        _buildAudioIcon(context, isDark, isTablet),
        SizedBox(height: isTablet ? 48 : 32),

        // 文件名（使用Theme字体）
        Text(
          widget.fileName,
          style: (isTablet
                  ? Theme.of(context).textTheme.headlineSmall
                  : Theme.of(context).textTheme.titleLarge)
              ?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.purple.shade900,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: isTablet ? 24 : 16),

        // 播放速度选择
        Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<double>(
              segments: const [
                ButtonSegment(
                  value: 0.5,
                  label: Text('0.5x'),
                  icon: SizedBox.shrink(), // 隐藏图标
                ),
                ButtonSegment(
                  value: 1.0,
                  label: Text('1.0x'),
                  icon: SizedBox.shrink(), // 隐藏图标
                ),
                ButtonSegment(
                  value: 1.5,
                  label: Text('1.5x'),
                  icon: SizedBox.shrink(), // 隐藏图标
                ),
                ButtonSegment(
                  value: 2.0,
                  label: Text('2.0x'),
                  icon: SizedBox.shrink(), // 隐藏图标
                ),
              ],
              selected: {_playbackRate},
              onSelectionChanged: (Set<double> newSelection) {
                _setPlaybackRate(newSelection.first);
              },
              showSelectedIcon: false, // 不显示选中图标
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return isDark
                        ? Colors.white.withValues(alpha: 0.9)
                        : Colors.purple.shade700;
                  }
                  return isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.purple.shade100;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return isDark ? Colors.purple.shade900 : Colors.white;
                  }
                  return isDark ? Colors.white70 : Colors.purple.shade700;
                }),
              ),
            ),
          ),
        ),
        SizedBox(height: isTablet ? 48 : 32),

        // 进度条
        Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor:
                    isDark ? Colors.white : Colors.purple.shade700,
                inactiveTrackColor: isDark
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.purple.shade200,
                thumbColor: isDark ? Colors.white : Colors.purple.shade700,
                overlayColor: isDark
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.purple.shade700.withValues(alpha: 0.2),
                trackHeight: 4,
              ),
              child: Slider(
                value: _position.inSeconds.toDouble(),
                max: _duration.inSeconds.toDouble() > 0
                    ? _duration.inSeconds.toDouble()
                    : 1.0,
                onChanged: (value) {
                  _seek(Duration(seconds: value.toInt()));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_position),
                    style: TextStyle(
                        color:
                            isDark ? Colors.white70 : Colors.purple.shade700),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: TextStyle(
                        color:
                            isDark ? Colors.white70 : Colors.purple.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: isTablet ? 48 : 32),

        // 控制按钮（响应式尺寸）
        _buildControlButtons(context, isDark, isTablet),
      ],
    );
  }

  /// 构建横屏布局
  ///
  /// 采用左右分栏设计（flex 2:3），充分利用横向空间
  /// - 左侧：音频图标（40%屏幕高度）+ 文件名
  /// - 右侧：播放速度选择器 + 进度条 + 控制按钮
  /// 整体下移 23% 屏幕高度，优化视觉中心
  Widget _buildLandscapeLayout(
    BuildContext context,
    bool isDark,
    bool isTablet,
  ) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Padding(
      padding: EdgeInsets.only(top: screenHeight * 0.23), // 顶部下移优化视觉位置
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：音频图标和文件名（占 2/5 宽度）
          Expanded(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAudioIcon(context, isDark, false,
                    maxSize: screenHeight * 0.40),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    widget.fileName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.purple.shade900,
                        ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // 右侧：控制区域（占 3/5 宽度）
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPlaybackRateSelector(isDark),
                  const SizedBox(height: 8),
                  _buildProgressBar(context, isDark),
                  const SizedBox(height: 8),
                  _buildControlButtons(context, isDark, false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建播放速度选择器
  Widget _buildPlaybackRateSelector(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<double>(
          segments: const [
            ButtonSegment(
                value: 0.5, label: Text('0.5x'), icon: SizedBox.shrink()),
            ButtonSegment(
                value: 1.0, label: Text('1.0x'), icon: SizedBox.shrink()),
            ButtonSegment(
                value: 1.5, label: Text('1.5x'), icon: SizedBox.shrink()),
            ButtonSegment(
                value: 2.0, label: Text('2.0x'), icon: SizedBox.shrink()),
          ],
          selected: {_playbackRate},
          onSelectionChanged: (Set<double> newSelection) {
            _setPlaybackRate(newSelection.first);
          },
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return isDark
                    ? Colors.white.withValues(alpha: 0.9)
                    : Colors.purple.shade700;
              }
              return isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.purple.shade100;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return isDark ? Colors.purple.shade900 : Colors.white;
              }
              return isDark ? Colors.white70 : Colors.purple.shade700;
            }),
          ),
        ),
      ),
    );
  }

  /// 构建进度条
  Widget _buildProgressBar(BuildContext context, bool isDark) {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: isDark ? Colors.white : Colors.purple.shade700,
            inactiveTrackColor: isDark
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.purple.shade200,
            thumbColor: isDark ? Colors.white : Colors.purple.shade700,
            overlayColor: isDark
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.purple.shade700.withValues(alpha: 0.2),
            trackHeight: 4,
          ),
          child: Slider(
            value: _position.inSeconds.toDouble(),
            max: _duration.inSeconds.toDouble() > 0
                ? _duration.inSeconds.toDouble()
                : 1.0,
            onChanged: (value) {
              _seek(Duration(seconds: value.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.purple.shade700,
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.purple.shade700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建音频图标（响应式尺寸）
  Widget _buildAudioIcon(
    BuildContext context,
    bool isDark,
    bool isTablet, {
    double? maxSize,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final defaultSize = (screenWidth * (isTablet ? 0.3 : 0.4))
        .clamp(120.0, isTablet ? 280.0 : 220.0);
    final iconContainerSize =
        maxSize != null ? defaultSize.clamp(80.0, maxSize) : defaultSize;
    final iconSize = iconContainerSize * 0.5;

    return Container(
      width: iconContainerSize,
      height: iconContainerSize,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.2)
            : Colors.purple.shade200.withValues(alpha: 0.3),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _isPlaying ? Icons.music_note : Icons.audiotrack,
        size: iconSize,
        color: isDark ? Colors.white : Colors.purple.shade700,
      ),
    );
  }

  /// 构建控制按钮（响应式尺寸）
  Widget _buildControlButtons(
    BuildContext context,
    bool isDark,
    bool isTablet,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 360;
    final iconSize = isCompact ? 28.0 : (isTablet ? 40.0 : 36.0);
    final playIconSize = isCompact ? 40.0 : (isTablet ? 56.0 : 48.0);
    final spacing = isCompact ? 4.0 : 8.0;
    final largeSpacing = isCompact ? 8.0 : 12.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 后退10秒按钮
        IconButton(
          icon: const Icon(Icons.replay_10),
          iconSize: iconSize,
          color: isDark ? Colors.white : Colors.purple.shade700,
          onPressed: () => _skip(const Duration(seconds: -10)),
          tooltip: '后退10秒',
        ),
        SizedBox(width: spacing),

        // 停止按钮
        IconButton(
          icon: const Icon(Icons.stop),
          iconSize: iconSize,
          color: isDark ? Colors.white : Colors.purple.shade700,
          onPressed: _stop,
          tooltip: '停止',
        ),
        SizedBox(width: largeSpacing),

        // 播放/暂停按钮
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white : Colors.purple.shade700,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            iconSize: playIconSize,
            color: isDark ? Colors.purple.shade700 : Colors.white,
            onPressed: _playPause,
            tooltip: _isPlaying ? '暂停' : '播放',
          ),
        ),
        SizedBox(width: largeSpacing),

        // 快进10秒按钮
        IconButton(
          icon: const Icon(Icons.forward_10),
          iconSize: iconSize,
          color: isDark ? Colors.white : Colors.purple.shade700,
          onPressed: () => _skip(const Duration(seconds: 10)),
          tooltip: '快进10秒',
        ),
        SizedBox(width: spacing),

        // 循环按钮
        IconButton(
          icon: Icon(_isLooping ? Icons.repeat_one : Icons.repeat),
          iconSize: iconSize,
          color: _isLooping
              ? (isDark ? Colors.white : Colors.purple.shade700)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.5)
                  : Colors.purple.shade300),
          onPressed: _toggleLoop,
          tooltip: _isLooping ? '取消循环' : '单曲循环',
        ),
      ],
    );
  }

  /// 停止播放（供外部调用，如页面切换时）
  void stopPlayback() {
    _audioPlayer.stop();
  }
}
