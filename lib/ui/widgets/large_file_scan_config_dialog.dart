import 'package:flutter/material.dart';

import 'package:easyfile/core/models/large_file_scan_config.dart';

/// 大文件扫描配置对话框
class LargeFileScanConfigDialog extends StatefulWidget {
  final LargeFileScanConfig initialConfig;

  const LargeFileScanConfigDialog({
    super.key,
    required this.initialConfig,
  });

  /// 显示配置对话框
  static Future<LargeFileScanConfig?> show(
    BuildContext context,
    LargeFileScanConfig currentConfig,
  ) {
    return showDialog<LargeFileScanConfig>(
      context: context,
      builder: (context) => LargeFileScanConfigDialog(
        initialConfig: currentConfig,
      ),
    );
  }

  @override
  State<LargeFileScanConfigDialog> createState() =>
      _LargeFileScanConfigDialogState();
}

class _LargeFileScanConfigDialogState extends State<LargeFileScanConfigDialog> {
  late int _minSizeInMB;
  late Set<FileTypeFilter> _fileTypes;

  @override
  void initState() {
    super.initState();
    _minSizeInMB = widget.initialConfig.minSizeInMB;
    _fileTypes = Set.from(widget.initialConfig.fileTypes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('自定义大文件扫描'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 最小文件大小
            Text(
              '最小文件大小',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4), // 减小：8 → 4
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: colorScheme.primary,
                      inactiveTrackColor: Colors.grey[300],
                      thumbColor: colorScheme.primary,
                      overlayColor: colorScheme.primary.withValues(alpha: 0.2),
                      valueIndicatorColor: colorScheme.primary,
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _minSizeInMB.toDouble(),
                      min: 1,
                      max: 500,
                      divisions: 499,
                      label: '$_minSizeInMB MB',
                      onChanged: (value) {
                        setState(() => _minSizeInMB = value.toInt());
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    '$_minSizeInMB MB',
                    style: theme.textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12), // 减小：16 → 12

            // 文件类型
            Text(
              '文件类型',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8), // 减小：12 → 8
            _buildFileTypeCards(colorScheme),
            const SizedBox(height: 24), // 新增：增大与按钮的间距
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final newConfig = LargeFileScanConfig(
              minSizeInMB: _minSizeInMB,
              fileTypes: _fileTypes,
              maxResults: widget.initialConfig.maxResults,
            );
            Navigator.pop(context, newConfig);
          },
          child: const Text('保存并查找'),
        ),
      ],
    );
  }

  /// 构建文件类型卡片（固定两排3列布局）
  Widget _buildFileTypeCards(ColorScheme colorScheme) {
    // 将6种文件类型分成两排，每排3个
    final allTypes = FileTypeFilter.values;
    final firstRow = allTypes.sublist(0, 3);
    final secondRow = allTypes.sublist(3, 6);

    return Column(
      children: [
        _buildFileTypeRow(firstRow, colorScheme),
        const SizedBox(height: 8),
        _buildFileTypeRow(secondRow, colorScheme),
      ],
    );
  }

  /// 构建一排文件类型卡片
  Widget _buildFileTypeRow(
    List<FileTypeFilter> types,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: types.map((type) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildFileTypeCard(type, colorScheme),
          ),
        );
      }).toList(),
    );
  }

  /// 构建单个文件类型卡片
  Widget _buildFileTypeCard(
    FileTypeFilter type,
    ColorScheme colorScheme,
  ) {
    final isSelected = _fileTypes.contains(type);
    final iconData = _getIconForType(type);
    final color = _getColorForType(type);

    return Material(
      color: isSelected ? color.withValues(alpha: 0.15) : Colors.grey[100],
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              // 至少保留一个类型
              if (_fileTypes.length > 1) {
                _fileTypes.remove(type);
              }
            } else {
              _fileTypes.add(type);
            }
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    iconData,
                    color: isSelected ? color : Colors.grey[600],
                    size: 32,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? color : Colors.grey[700],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              // 右上角选中标记
              if (isSelected)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 获取文件类型对应的图标
  IconData _getIconForType(FileTypeFilter type) {
    switch (type) {
      case FileTypeFilter.video:
        return Icons.videocam;
      case FileTypeFilter.audio:
        return Icons.audiotrack;
      case FileTypeFilter.image:
        return Icons.image;
      case FileTypeFilter.document:
        return Icons.description;
      case FileTypeFilter.archive:
        return Icons.folder_zip;
      case FileTypeFilter.other:
        return Icons.insert_drive_file;
    }
  }

  /// 获取文件类型对应的颜色
  Color _getColorForType(FileTypeFilter type) {
    switch (type) {
      case FileTypeFilter.video:
        return Colors.red;
      case FileTypeFilter.audio:
        return Colors.purple;
      case FileTypeFilter.image:
        return Colors.blue;
      case FileTypeFilter.document:
        return Colors.orange;
      case FileTypeFilter.archive:
        return Colors.green;
      case FileTypeFilter.other:
        return Colors.grey;
    }
  }
}
