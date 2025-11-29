import 'package:flutter/material.dart';
import 'package:easyfile/core/models/large_file_scan_config.dart';

/// 重复文件类型选择对话框
class DuplicateFileScanTypeDialog extends StatefulWidget {
  final FileTypeFilter? initialType;
  final int? initialMinSizeKB;
  
  const DuplicateFileScanTypeDialog({
    super.key,
    this.initialType,
    this.initialMinSizeKB,
  });

  @override
  State<DuplicateFileScanTypeDialog> createState() =>
      _DuplicateFileScanTypeDialogState();
}

class _DuplicateFileScanTypeDialogState
    extends State<DuplicateFileScanTypeDialog> {
  late FileTypeFilter _selectedType;
  late double _minFileSizeKB;

  @override
  void initState() {
    super.initState();
    // 使用传入的初始值，否则使用默认值
    _selectedType = widget.initialType ?? FileTypeFilter.video;
    _minFileSizeKB = (widget.initialMinSizeKB ?? 100).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Center(
        child: Text(
          '分类清理',
          style: theme.textTheme.titleLarge,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '请选择要检测的文件类型：',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              _buildTypeOption(
                FileTypeFilter.image,
                '图片',
                '常见于相册、截图等（支持 JPG / PNG / GIF 等格式）',
                colorScheme,
              ),
              _buildTypeOption(
                FileTypeFilter.video,
                '视频',
                '常见于录像、下载等（支持 MP4 / AVI / MKV 等格式）',
                colorScheme,
              ),
              _buildTypeOption(
                FileTypeFilter.audio,
                '音频',
                '常见于音乐、录音等（支持 MP3 / FLAC / WAV 等格式）',
                colorScheme,
              ),
              _buildTypeOption(
                FileTypeFilter.document,
                '文档',
                '常见于办公文件、电子书等（支持 PDF / DOC / TXT 等格式）',
                colorScheme,
              ),
              _buildTypeOption(
                FileTypeFilter.archive,
                '压缩包',
                '常见于安装包、备份等（支持 ZIP / RAR / 7Z 等格式）',
                colorScheme,
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              // 文件大小滑块
              Text(
                '最小文件大小：${_minFileSizeKB.toInt()} KB',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '10 KB',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _minFileSizeKB,
                      min: 10,
                      max: 1024,
                      divisions: 101,
                      label: '${_minFileSizeKB.toInt()} KB',
                      onChanged: (value) {
                        setState(() {
                          _minFileSizeKB = (value / 10).round() * 10.0;
                        });
                      },
                    ),
                  ),
                  Text(
                    '1 MB',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      actions: [
        // 温馨提示
        SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '检测可能需要几分钟，文件越多耗时越长',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                // 返回选中的类型和文件大小
                Navigator.pop(context, {
                  'type': _selectedType,
                  'minSizeKB': _minFileSizeKB.toInt(),
                });
              },
              child: const Text('开始检测'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTypeOption(
    FileTypeFilter type,
    String label,
    String description,
    ColorScheme colorScheme,
  ) {
    final isSelected = _selectedType == type;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedType = type;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Radio button
            Padding(
              padding: const EdgeInsets.only(top: 1), // 向下移1px以对齐
              child: Radio<FileTypeFilter>(
                value: type,
                groupValue: _selectedType,
                onChanged: (value) {
                  setState(() {
                    _selectedType = value!;
                  });
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

