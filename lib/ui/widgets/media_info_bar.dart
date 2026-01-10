import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/services/background_audio_service.dart';

/// 媒体文件信息栏组件
///
/// 在预览页面显示视频/音频的详细信息
/// - 视频：时长、分辨率、文件大小
/// - 音频：时长、格式、文件大小
class MediaInfoBar extends StatefulWidget {
  final String filePath;
  final String fileName;
  final int fileSize;
  final bool isVideo;

  const MediaInfoBar({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.isVideo,
  });

  @override
  State<MediaInfoBar> createState() => _MediaInfoBarState();
}

class _MediaInfoBarState extends State<MediaInfoBar> {
  Duration? _duration;
  String? _resolution;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMediaInfo();
  }

  Future<void> _loadMediaInfo() async {
    try {
      if (widget.isVideo) {
        await _loadVideoInfo();
      } else {
        await _loadAudioInfo();
      }
    } catch (e) {
      logger.w('Failed to load media info: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadVideoInfo() async {
    final controller = VideoPlayerController.file(File(widget.filePath));
    try {
      await controller.initialize();
      if (mounted) {
        setState(() {
          _duration = controller.value.duration;
          final width = controller.value.size.width.toInt();
          final height = controller.value.size.height.toInt();
          _resolution = '${width}x$height';
        });
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _loadAudioInfo() async {
    // 等待一小段时间，确保 BackgroundAudioService 的播放器已初始化
    await Future.delayed(const Duration(milliseconds: 100));
    
    try {
      final audioService = BackgroundAudioService();
      
      // 从共享播放器获取时长
      if (audioService.currentAudioPath == widget.filePath) {
        final player = audioService.player;
        
        // 等待播放器加载完成
        int attempts = 0;
        while (attempts < 20 && (player == null || player.duration == null)) {
          await Future.delayed(const Duration(milliseconds: 100));
          attempts++;
          
          if (audioService.player != null && audioService.player!.duration != null) {
            if (mounted) {
              setState(() {
                _duration = audioService.player!.duration;
              });
            }
            return;
          }
        }
        
        // 如果已经有时长，直接使用
        if (player != null && player.duration != null) {
          if (mounted) {
            setState(() {
              _duration = player.duration;
            });
          }
          return;
        }
      }
      
      // 如果播放器路径不匹配，说明不是当前文件，跳过显示时长
      logger.d('Audio duration not available for non-current file');
    } catch (e) {
      logger.w('Failed to load audio duration: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _getFileFormat() {
    final ext = FileUtils.getExtension(widget.fileName).toUpperCase();
    return ext;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 文件名
          Row(
            children: [
              Icon(
                widget.isVideo ? Icons.video_library : Icons.audio_file,
                color: Colors.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.fileName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 信息标签
          if (_isLoading)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('正在加载信息...'),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 时长
                if (_duration != null)
                  _InfoChip(
                    icon: Icons.access_time,
                    label: _formatDuration(_duration!),
                    color: Colors.blue,
                  ),

                // 分辨率（仅视频）
                if (widget.isVideo && _resolution != null)
                  _InfoChip(
                    icon: Icons.high_quality,
                    label: _resolution!,
                    color: Colors.blue,
                  ),

                // 格式
                _InfoChip(
                  icon: Icons.description,
                  label: _getFileFormat(),
                  color: Colors.blue,
                ),

                // 文件大小
                _InfoChip(
                  icon: Icons.storage,
                  label: FileUtils.formatFileSize(widget.fileSize),
                  color: Colors.blue,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 信息标签组件
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
