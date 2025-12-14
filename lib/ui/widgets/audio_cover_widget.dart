import 'package:flutter/material.dart';

/// 音频封面部件（简化版）
class AudioCoverWidget extends StatelessWidget {
  final String audioPath;
  final double size;
  final String? duration;

  const AudioCoverWidget({
    super.key,
    required this.audioPath,
    this.size = 40,
    this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.purple.shade700, Colors.purple.shade500],
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Icon(Icons.music_note, color: Colors.white, size: size * 0.5),
          if (duration != null)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  duration!,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size > 50 ? 10 : 8,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
