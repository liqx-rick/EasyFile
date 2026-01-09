import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/services/background_audio_service.dart';

/// 后台音频播放器组件
///
/// 使用全局 BackgroundAudioService 实现真正的后台播放功能
/// 即使页面被销毁，音频仍会继续在后台播放
/// 支持播放列表、自动播放下一首、系统通知控制等功能
class BackgroundAudioPlayerWidget extends StatefulWidget {
  final String audioPath;
  final String fileName;
  final List<FileItem>? fileList; // 播放列表
  final bool autoPlay; // 是否自动播放

  const BackgroundAudioPlayerWidget({
    super.key,
    required this.audioPath,
    required this.fileName,
    this.fileList,
    this.autoPlay = true,
  });

  @override
  State<BackgroundAudioPlayerWidget> createState() =>
      _BackgroundAudioPlayerWidgetState();
}

class _BackgroundAudioPlayerWidgetState
    extends State<BackgroundAudioPlayerWidget> {
  final BackgroundAudioService _audioService = BackgroundAudioService();
  bool _isLoading = true;
  bool _isLooping = false; // 单曲循环状态
  double _playbackRate = 1.0; // 播放速度（0.5x ~ 2.0x）
  String? _error;
  StreamSubscription? _processingStateSubscription;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      logger.d('Initializing background audio player for: ${widget.audioPath}');

      // 检查播放器是否已经初始化并且正在播放相同的音频
      final player = _audioService.player;
      final currentPath = _audioService.currentAudioPath;
      final isSameAudio = currentPath == widget.audioPath;

      if (player != null && isSameAudio) {
        logger.d('Player already initialized with same audio, syncing state only');
        // 同步循环模式和播放速度
        if (player.loopMode == LoopMode.one) {
          _isLooping = true;
        }
        _playbackRate = player.speed;
      } else {
        // 加载新的音频文件
        logger.d('Loading new audio file: ${widget.audioPath}');
        await _audioService.loadAndPlay(
          audioPath: widget.audioPath,
          fileName: widget.fileName,
          fileList: widget.fileList,
          autoPlay: widget.autoPlay,
        );
        logger.d('loadAndPlay completed');
      }

      // 订阅处理状态（用于自动播放下一首）
      // 注意：UI更新通过StreamBuilder处理，无需额外订阅playerStateStream
      _processingStateSubscription = _audioService.processingStateStream?.listen((state) {
        if (mounted && state == ProcessingState.completed && !_isLooping) {
          // 播放完成，自动播放下一首
          _audioService.seekToNext();
        }
      });

      logger.d('Processing state subscription created');

      if (mounted) {
        logger.d('Setting _isLoading = false');
        setState(() {
          _isLoading = false;
        });
      } else {
        logger.w('Widget not mounted, cannot set _isLoading = false');
      }

      logger.d('Background audio player initialized successfully');
    } catch (e, stackTrace) {
      logger.e('Failed to initialize audio player: $e\n$stackTrace');
      if (mounted) {
        setState(() {
          _error = 'Failed to load audio: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // 只取消订阅，不销毁播放器
    // 播放器由全局服务管理，可以在后台继续播放
    _processingStateSubscription?.cancel();
    super.dispose();
  }

  // 播放/暂停切换
  Future<void> _togglePlayPause() async {
    await _audioService.togglePlayPause();
  }

  // 播放下一首
  Future<void> _playNext() async {
    await _audioService.seekToNext();
  }

  // 播放上一首
  Future<void> _playPrevious() async {
    await _audioService.seekToPrevious();
  }

  // 设置播放速度
  Future<void> _setPlaybackSpeed(double speed) async {
    await _audioService.setSpeed(speed);
    if (mounted) {
      setState(() {
        _playbackRate = speed;
      });
    }
  }

  // 切换循环模式
  void _toggleLoopMode() {
    setState(() {
      _isLooping = !_isLooping;
    });
    _audioService.setLoopMode(_isLooping ? LoopMode.one : LoopMode.off);
  }

  // 快进/后退
  Future<void> _skip(Duration delta) async {
    final player = _audioService.player;
    if (player == null) return;
    
    final position = player.position;
    final duration = player.duration ?? Duration.zero;
    final newPosition = position + delta;
    
    if (newPosition < Duration.zero) {
      await player.seek(Duration.zero);
    } else if (newPosition > duration) {
      await player.seek(duration);
    } else {
      await player.seek(newPosition);
    }
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
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              '播放失败',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final player = _audioService.player;
    
    // 如果播放器为空，显示加载状态
    if (player == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // 响应式设计
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth > 600;
    final isLandscape = screenWidth > screenHeight;
    
    // 使用ListView避免溢出
    return Container(
      color: const Color.fromRGBO(6, 107, 207, 1).withOpacity(0.05),
      child: ListView(
        padding: EdgeInsets.only(
          left: isTablet ? 32.0 : 10.0,
          right: isTablet ? 32.0 : 10.0,
          top: isLandscape ? screenHeight * 0.05 : screenHeight * 0.20,
          bottom: isTablet ? 32.0 : 20.0,
        ),
        children: [
        // 音频图标
        _buildAudioIcon(context, isTablet, player, isLandscape),
        SizedBox(height: isLandscape ? 16 : (isTablet ? 32 : 24)),

        // 文件名
        StreamBuilder<SequenceState?>(
          stream: player.sequenceStateStream,
          builder: (context, snapshot) {
            final currentTag = snapshot.data?.currentSource?.tag as MediaItem?;
            return Text(
              currentTag?.title ?? widget.fileName,
              style: (isTablet
                      ? Theme.of(context).textTheme.headlineSmall
                      : Theme.of(context).textTheme.titleLarge)
                  ?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        SizedBox(height: isLandscape ? 12 : (isTablet ? 24 : 16)),

        // 进度条（两侧带快进/后退按钮）
        StreamBuilder<Duration?>(
          stream: player.positionStream,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            final duration = player.duration ?? Duration.zero;
            
            // 确保position不超过duration，防止Slider报错
            final safePosition = position > duration ? duration : position;
            final maxValue = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
            final currentValue = safePosition.inMilliseconds.toDouble().clamp(0.0, maxValue);

            return Column(
              children: [
                // 进度条和跳转按钮在同一行（添加padding使其比控制栏更窄）
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 32.0 : 20.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 后退10秒按钮
                      IconButton(
                        icon: const Icon(Icons.replay_10),
                        iconSize: isTablet ? 28 : 24,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: () => _skip(const Duration(seconds: -10)),
                        tooltip: '后退10秒',
                      ),
                      
                      // 进度条（占据剩余空间）
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          ),
                          child: Slider(
                            value: currentValue,
                            max: maxValue,
                            onChanged: (value) {
                              player.seek(Duration(milliseconds: value.toInt()));
                            },
                          ),
                        ),
                      ),
                      
                      // 快进10秒按钮
                      IconButton(
                        icon: const Icon(Icons.forward_10),
                        iconSize: isTablet ? 28 : 24,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: () => _skip(const Duration(seconds: 10)),
                        tooltip: '快进10秒',
                      ),
                    ],
                  ),
                ),
                // 时间显示在进度条下方
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 52.0 : 40.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(safePosition)),
                      Text(_formatDuration(duration)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        SizedBox(height: isLandscape ? 12 : (isTablet ? 32 : 24)),

        // 控制按钮
        _buildControlButtons(context, isTablet, player),
      ],
      ),
    );
  }

  /// 构建音频图标
  Widget _buildAudioIcon(BuildContext context, bool isTablet, AudioPlayer player, bool isLandscape) {
    final screenWidth = MediaQuery.of(context).size.width;
    // 横屏和竖屏使用相同的小尺寸
    final iconContainerSize = isLandscape 
        ? 120.0 
        : (screenWidth * (isTablet ? 0.35 : 0.45)).clamp(140.0, isTablet ? 300.0 : 240.0);
    final iconSize = iconContainerSize * 0.5;

    return Center(
      child: StreamBuilder<PlayerState>(
        stream: _audioService.playerStateStream,
        builder: (context, snapshot) {
          final playing = snapshot.data?.playing ?? false;
          
          return Container(
            width: iconContainerSize,
            height: iconContainerSize,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              playing ? Icons.music_note : Icons.audiotrack,
              size: iconSize,
              color: Theme.of(context).primaryColor,
            ),
          );
        },
      ),
    );
  }

  /// 构建控制按钮
  Widget _buildControlButtons(BuildContext context, bool isTablet, AudioPlayer player) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 360;
    final iconSize = isCompact ? 26.0 : (isTablet ? 36.0 : 30.0);
    final playIconSize = isCompact ? 40.0 : (isTablet ? 56.0 : 48.0);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 16.0 : 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
        // 循环按钮
        IconButton(
          icon: Icon(
            _isLooping ? Icons.repeat_one : Icons.repeat,
          ),
          iconSize: iconSize,
          color: Theme.of(context).primaryColor,
          onPressed: _toggleLoopMode,
          tooltip: _isLooping ? '取消循环' : '单曲循环',
        ),

        // 上一首（始终显示，无法使用时置灰）
        Opacity(
          opacity: player.hasPrevious ? 1.0 : 0.3,
          child: IconButton(
            icon: const Icon(Icons.skip_previous),
            iconSize: iconSize,
            onPressed: player.hasPrevious ? _playPrevious : null,
            tooltip: '上一首',
          ),
        ),

        // 播放/暂停按钮
        StreamBuilder<PlayerState>(
          stream: _audioService.playerStateStream,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final processingState = playerState?.processingState;
            final playing = playerState?.playing ?? false;

            if (processingState == ProcessingState.loading ||
                processingState == ProcessingState.buffering) {
              return Container(
                width: playIconSize + 16,
                height: playIconSize + 16,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                ),
              );
            } else {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    size: playIconSize,
                  ),
                  color: Colors.white,
                  onPressed: _togglePlayPause,
                  tooltip: playing ? '暂停' : '播放',
                ),
              );
            }
          },
        ),

        // 下一首（始终显示，无法使用时置灰）
        Opacity(
          opacity: player.hasNext ? 1.0 : 0.3,
          child: IconButton(
            icon: const Icon(Icons.skip_next),
            iconSize: iconSize,
            onPressed: player.hasNext ? _playNext : null,
            tooltip: '下一首',
          ),
        ),

        // 播放速度按钮
        GestureDetector(
          onTap: () => _showSpeedSelector(context, iconSize),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              '${_playbackRate}x',
              style: TextStyle(
                fontSize: iconSize * 0.5,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
        ),
      ],
    ),
    );
  }

  /// 显示播放速度选择器（底部弹出）
  void _showSpeedSelector(BuildContext context, double iconSize) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '播放速度',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 速度选项（可滚动）
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map((speed) => ListTile(
                      title: Text(
                        '${speed}x',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: speed == _playbackRate ? FontWeight.bold : FontWeight.normal,
                          color: speed == _playbackRate 
                            ? Theme.of(context).primaryColor 
                            : null,
                        ),
                      ),
                      trailing: speed == _playbackRate 
                        ? Icon(Icons.check, color: Theme.of(context).primaryColor) 
                        : null,
                      onTap: () {
                        _setPlaybackSpeed(speed);
                        Navigator.pop(context);
                      },
                    )),
                    SizedBox(height: MediaQuery.of(context).padding.bottom),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '$minutes:${twoDigits(seconds)}';
    }
  }
}
