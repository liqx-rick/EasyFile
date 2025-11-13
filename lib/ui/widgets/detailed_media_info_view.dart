import 'package:flutter/material.dart';
import 'package:easyfile/utils/media_info_extractor.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/utils/time_formatter.dart';

/// 详细媒体信息展示组件
/// 
/// 显示视频/音频的完整元数据信息
class DetailedMediaInfoView extends StatelessWidget {
  final DetailedMediaInfo info;
  final bool isVideo;

  const DetailedMediaInfoView({
    super.key,
    required this.info,
    required this.isVideo,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题（音频）
          if (!isVideo && info.title != null) ...[
            Text(
              info.title!,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (info.artist != null)
              Text(
                info.artist!,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                ),
              ),
            const SizedBox(height: 24),
          ],

          // 基本信息
          _buildSection(
            context,
            '基本信息',
            Icons.info_outline,
            [
              if (!isVideo && info.title != null)
                _buildRow('标题', info.title!),
              _buildRow('文件名', info.fileName),
              _buildRow('格式', info.format),
              _buildRow('文件大小', FileUtils.formatFileSize(info.fileSize)),
              if (info.duration != null)
                _buildRow('时长', _formatDuration(info.duration!)),
            ],
          ),

          // 视频信息
          if (isVideo) ...[
            const SizedBox(height: 20),
            _buildSection(
              context,
              '视频信息',
              Icons.videocam,
              [
                if (info.width != null && info.height != null) ...[
                  _buildRow('分辨率', '${info.width} × ${info.height}'),
                  _buildRow(
                    '宽高比',
                    info.aspectRatio != null
                        ? info.aspectRatio!.toStringAsFixed(2)
                        : '-',
                  ),
                ],
              ],
            ),
          ],

          // 音频信息
          if (!isVideo) ...[
            const SizedBox(height: 20),
            _buildSection(
              context,
              '音频信息',
              Icons.music_note,
              [
                if (info.artist != null) _buildRow('艺术家', info.artist!),
                if (info.album != null) _buildRow('专辑', info.album!),
                if (info.year != null) _buildRow('年份', info.year!),
                if (info.genre != null) _buildRow('流派', info.genre!),
              ],
            ),
          ],

          // 文件信息
          const SizedBox(height: 20),
          _buildSection(
            context,
            '文件信息',
            Icons.folder_open,
            [
              _buildRow('创建时间', TimeFormatter.formatFullTime(info.createdAt)),
              _buildRow('修改时间', TimeFormatter.formatFullTime(info.modifiedAt)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> rows,
  ) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(children: rows),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
