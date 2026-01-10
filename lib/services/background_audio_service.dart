import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path/path.dart' as path;
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';

/// 全局后台音频播放服务（单例模式）
///
/// 管理音频播放器的生命周期，确保后台播放功能正常工作
/// 即使 UI 页面被销毁，播放器也会继续在后台运行
class BackgroundAudioService {
  static final BackgroundAudioService _instance = BackgroundAudioService._internal();
  factory BackgroundAudioService() => _instance;
  BackgroundAudioService._internal();

  AudioPlayer? _audioPlayer;
  bool _isBackgroundServiceInitialized = false;
  int _currentIndex = 0;
  List<FileItem>? _currentPlaylist;
  String? _currentAudioPath; // 当前正在播放的音频文件路径

  /// 获取 AudioPlayer 实例
  AudioPlayer? get player => _audioPlayer;

  /// 获取当前播放索引
  int get currentIndex => _currentIndex;

  /// 获取当前播放列表
  List<FileItem>? get currentPlaylist => _currentPlaylist;

  /// 获取当前播放的音频文件路径
  String? get currentAudioPath => _currentAudioPath;

  /// 是否正在播放
  bool get isPlaying => _audioPlayer?.playing ?? false;

  /// 播放状态流
  Stream<PlayerState>? get playerStateStream => _audioPlayer?.playerStateStream;

  /// 处理状态流
  Stream<ProcessingState>? get processingStateStream => _audioPlayer?.processingStateStream;

  /// 位置流
  Stream<Duration>? get positionStream => _audioPlayer?.positionStream;

  /// 总时长流
  Stream<Duration?>? get durationStream => _audioPlayer?.durationStream;

  /// 初始化后台播放服务
  Future<void> initialize() async {
    if (_isBackgroundServiceInitialized) {
      logger.d('BackgroundAudioService already initialized');
      return;
    }

    try {
      // 注意：AudioSession 已在 main() 中全局初始化，这里只需设置事件监听
      final audioSession = await AudioSession.instance;
      
      // 监听音频中断事件
      audioSession.interruptionEventStream.listen((event) {
        logger.w('Audio interruption: ${event.type}');
        if (event.begin) {
          logger.w('Audio interrupted, pausing playback');
          pause();
        } else {
          logger.i('Audio interruption ended, can resume');
        }
      });
      
      // 监听音频焦点变化（耳机拔出等）
      audioSession.becomingNoisyEventStream.listen((_) {
        logger.w('Audio becoming noisy (earphone unplugged), pausing');
        pause();
      });

      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.easyfile.audio',
        androidNotificationChannelName: 'EasyFile Audio Player',
        androidNotificationOngoing: false, // 可滑动关闭通知，显示关闭按钮
        androidNotificationClickStartsActivity: true,
        androidStopForegroundOnPause: true, // 暂停时停止前台服务
      );
      _isBackgroundServiceInitialized = true;
      logger.d('JustAudioBackground initialized successfully');
    } catch (e) {
      logger.e('Failed to initialize JustAudioBackground: $e');
      rethrow;
    }
  }

  /// 加载并播放音频文件或播放列表
  Future<void> loadAndPlay({
    required String audioPath,
    required String fileName,
    List<FileItem>? fileList,
    bool autoPlay = true,
  }) async {
    try {
      // 确保后台服务已初始化
      if (!_isBackgroundServiceInitialized) {
        await initialize();
      }

      // 确保只创建一次 AudioPlayer
      if (_audioPlayer == null) {
        _audioPlayer = AudioPlayer();
        
        // 设置默认音量为 1.0（满音量）
        await _audioPlayer!.setVolume(1.0);
        
        logger.d('AudioPlayer created');
      }

      // 停止当前播放但不释放播放器
      if (_audioPlayer!.playing) {
        await _audioPlayer!.stop();
        logger.d('Stopped current playback');
      }

      _currentPlaylist = fileList;
      _currentAudioPath = audioPath; // 保存当前播放的音频路径

      // 加载播放源
      if (fileList != null && fileList.isNotEmpty) {
        await _loadPlaylist(audioPath, fileList);
      } else {
        await _loadSingleFile(audioPath, fileName);
      }

      // 自动播放（不等待完成，避免阻塞）
      if (autoPlay) {
        _audioPlayer!.play().then((_) {
          logger.d('Auto play started');
        }).catchError((e) {
          logger.e('Failed to start playback: $e');
        });
      }
    } catch (e, stackTrace) {
      logger.e('Failed to load and play audio: $e\n$stackTrace');
      rethrow;
    }
  }

  /// 加载播放列表
  Future<void> _loadPlaylist(String currentPath, List<FileItem> fileList) async {
    final List<AudioSource> audioSources = [];

    // 找到当前文件在列表中的索引
    _currentIndex = fileList.indexWhere((item) => item.path == currentPath);
    if (_currentIndex == -1) {
      _currentIndex = 0;
    }

    // 创建音频源列表
    for (final fileItem in fileList) {
      final fileName = path.basename(fileItem.path);
      audioSources.add(
        AudioSource.file(
          fileItem.path,
          tag: MediaItem(
            id: fileItem.path,
            title: fileName,
            artist: 'EasyFile',
            artUri: Uri.parse('asset:///assets/icon/app_icon.png'),
          ),
        ),
      );
    }

    // 创建播放列表
    final playlist = ConcatenatingAudioSource(children: audioSources);

    await _audioPlayer!.setAudioSource(
      playlist,
      initialIndex: _currentIndex,
      initialPosition: Duration.zero,
    );

    logger.d('Playlist loaded with ${audioSources.length} items, starting at index $_currentIndex');
  }

  /// 加载单个文件
  Future<void> _loadSingleFile(String audioPath, String fileName) async {
    await _audioPlayer!.setAudioSource(
      AudioSource.file(
        audioPath,
        tag: MediaItem(
          id: audioPath,
          title: fileName,
          artist: 'EasyFile',
          artUri: Uri.parse('asset:///assets/icon/app_icon.png'),
        ),
      ),
    );
    _currentIndex = 0;
    logger.d('Single file loaded: $fileName');
  }

  /// 播放/暂停
  Future<void> togglePlayPause() async {
    if (_audioPlayer == null) return;

    try {
      if (_audioPlayer!.playing) {
        await _audioPlayer!.pause();
        logger.d('Playback paused');
      } else {
        await _audioPlayer!.play();
        logger.d('Playback resumed');
      }
    } catch (e) {
      logger.e('Failed to toggle play/pause: $e');
    }
  }

  /// 播放
  Future<void> play() async {
    if (_audioPlayer == null) return;
    await _audioPlayer!.play();
  }

  /// 暂停
  Future<void> pause() async {
    if (_audioPlayer == null) return;
    await _audioPlayer!.pause();
  }

  /// 停止
  Future<void> stop() async {
    if (_audioPlayer == null) return;
    await _audioPlayer!.stop();
  }

  /// 下一首
  Future<void> seekToNext() async {
    if (_audioPlayer == null) return;
    
    // 如果有播放列表且长度大于1，允许切换（即使在单曲循环模式下）
    final hasPlaylist = _currentPlaylist != null && _currentPlaylist!.length > 1;
    if (!hasPlaylist && !_audioPlayer!.hasNext) return;

    try {
      if (hasPlaylist) {
        // 有播放列表时，手动计算下一首索引
        final nextIndex = (_currentIndex + 1) % _currentPlaylist!.length;
        await _audioPlayer!.seek(Duration.zero, index: nextIndex);
        _currentIndex = nextIndex;
        logger.d('Playing next track (playlist mode), index: $_currentIndex');
      } else {
        // 没有播放列表，使用默认行为
        await _audioPlayer!.seekToNext();
        _currentIndex = _audioPlayer!.currentIndex ?? _currentIndex;
        logger.d('Playing next track, index: $_currentIndex');
      }
    } catch (e) {
      logger.e('Failed to play next: $e');
    }
  }

  /// 上一首
  Future<void> seekToPrevious() async {
    if (_audioPlayer == null) return;
    
    // 如果有播放列表且长度大于1，允许切换（即使在单曲循环模式下）
    final hasPlaylist = _currentPlaylist != null && _currentPlaylist!.length > 1;
    if (!hasPlaylist && !_audioPlayer!.hasPrevious) return;

    try {
      if (hasPlaylist) {
        // 有播放列表时，手动计算上一首索引
        final prevIndex = (_currentIndex - 1 + _currentPlaylist!.length) % _currentPlaylist!.length;
        await _audioPlayer!.seek(Duration.zero, index: prevIndex);
        _currentIndex = prevIndex;
        logger.d('Playing previous track (playlist mode), index: $_currentIndex');
      } else {
        // 没有播放列表，使用默认行为
        await _audioPlayer!.seekToPrevious();
        _currentIndex = _audioPlayer!.currentIndex ?? _currentIndex;
        logger.d('Playing previous track, index: $_currentIndex');
      }
    } catch (e) {
      logger.e('Failed to play previous: $e');
    }
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    if (_audioPlayer == null) return;

    try {
      await _audioPlayer!.seek(position);
    } catch (e) {
      logger.e('Failed to seek: $e');
    }
  }

  /// 设置循环模式
  Future<void> setLoopMode(LoopMode mode) async {
    if (_audioPlayer == null) return;
    await _audioPlayer!.setLoopMode(mode);
    logger.d('Loop mode set to: $mode');
  }

  /// 设置播放速度
  Future<void> setSpeed(double speed) async {
    if (_audioPlayer == null) return;

    try {
      await _audioPlayer!.setSpeed(speed);
      logger.d('Playback speed set to: ${speed}x');
    } catch (e) {
      logger.e('Failed to set speed: $e');
    }
  }

  /// 释放资源（仅在应用完全退出时调用）
  Future<void> dispose() async {
    logger.d('Disposing BackgroundAudioService');
    await _audioPlayer?.dispose();
    _audioPlayer = null;
    _currentPlaylist = null;
    _currentIndex = 0;
  }
}
