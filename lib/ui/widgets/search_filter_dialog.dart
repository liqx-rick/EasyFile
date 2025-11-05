import 'package:flutter/material.dart';

class SearchFilterDialog extends StatefulWidget {
  final Function(SearchFilter) onFilterChanged;
  final SearchFilter currentFilter;

  const SearchFilterDialog({
    super.key,
    required this.onFilterChanged,
    required this.currentFilter,
  });

  @override
  State<SearchFilterDialog> createState() => _SearchFilterDialogState();
}

class _SearchFilterDialogState extends State<SearchFilterDialog> {
  late SearchFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.currentFilter.copy();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('搜索过滤器'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('文件类型:', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('所有'),
                  selected: _filter.fileTypes.isEmpty,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _filter.fileTypes.clear();
                      }
                    });
                  },
                ),
                FilterChip(
                  label: const Text('图片'),
                  selected: _filter.fileTypes.contains(FileType.image),
                  onSelected: (selected) {
                    setState(() {
                      _toggleFileType(FileType.image, selected);
                    });
                  },
                ),
                FilterChip(
                  label: const Text('文档'),
                  selected: _filter.fileTypes.contains(FileType.document),
                  onSelected: (selected) {
                    setState(() {
                      _toggleFileType(FileType.document, selected);
                    });
                  },
                ),
                FilterChip(
                  label: const Text('视频'),
                  selected: _filter.fileTypes.contains(FileType.video),
                  onSelected: (selected) {
                    setState(() {
                      _toggleFileType(FileType.video, selected);
                    });
                  },
                ),
                FilterChip(
                  label: const Text('音频'),
                  selected: _filter.fileTypes.contains(FileType.audio),
                  onSelected: (selected) {
                    setState(() {
                      _toggleFileType(FileType.audio, selected);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('仅搜索文件'),
              subtitle: const Text('排除文件夹'),
              value: _filter.filesOnly,
              onChanged: (value) {
                setState(() {
                  _filter.filesOnly = value ?? false;
                });
              },
            ),
            CheckboxListTile(
              title: const Text('区分大小写'),
              value: _filter.caseSensitive,
              onChanged: (value) {
                setState(() {
                  _filter.caseSensitive = value ?? false;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text('搜索深度:', style: TextStyle(fontWeight: FontWeight.bold)),
            Slider(
              value: _filter.maxDepth.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '${_filter.maxDepth} 层',
              onChanged: (value) {
                setState(() {
                  _filter.maxDepth = value.round();
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            widget.onFilterChanged(_filter);
            Navigator.of(context).pop();
          },
          child: const Text('应用'),
        ),
      ],
    );
  }

  void _toggleFileType(FileType type, bool selected) {
    if (selected) {
      _filter.fileTypes.add(type);
    } else {
      _filter.fileTypes.remove(type);
    }
  }
}

class SearchFilter {
  Set<FileType> fileTypes;
  bool filesOnly;
  bool caseSensitive;
  int maxDepth;

  SearchFilter({
    Set<FileType>? fileTypes,
    this.filesOnly = false,
    this.caseSensitive = false,
    this.maxDepth = 3,
  }) : fileTypes = fileTypes ?? {};

  SearchFilter copy() {
    return SearchFilter(
      fileTypes: Set.from(fileTypes),
      filesOnly: filesOnly,
      caseSensitive: caseSensitive,
      maxDepth: maxDepth,
    );
  }

  bool isEmpty() {
    return fileTypes.isEmpty && !filesOnly && !caseSensitive && maxDepth == 3;
  }
}

enum FileType {
  image,
  document,
  video,
  audio,
}