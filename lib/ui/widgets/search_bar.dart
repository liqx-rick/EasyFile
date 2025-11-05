import 'package:flutter/material.dart';
import 'package:easyfile/core/logger.dart';

class SearchBar extends StatefulWidget {
  final Function(String) onSearch;
  final VoidCallback onClear;
  final String? initialQuery;

  const SearchBar({
    super.key,
    required this.onSearch,
    required this.onClear,
    this.initialQuery,
  });

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  late TextEditingController _controller;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _isExpanded = widget.initialQuery?.isNotEmpty ?? false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _isExpanded ? 250 : 48, // 使用固定宽度而不是double.infinity
      height: 48,
      child: _isExpanded ? _buildExpandedSearch() : _buildCollapsedSearch(),
    );
  }

  Widget _buildCollapsedSearch() {
    return IconButton(
      icon: const Icon(Icons.search),
      onPressed: () {
        setState(() {
          _isExpanded = true;
        });
        logger.d('Search bar expanded');
      },
      tooltip: '搜索文件',
    );
  }

  Widget _buildExpandedSearch() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.search, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索文件和文件夹...',
                border: InputBorder.none,
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (query) {
                if (query.isNotEmpty) {
                  logger.d('Search submitted: $query');
                  widget.onSearch(query);
                }
              },
              onChanged: (query) {
                // 实时搜索（可选）
                if (query.isEmpty) {
                  widget.onClear();
                }
              },
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () {
                _controller.clear();
                widget.onClear();
                logger.d('Search cleared');
              },
              tooltip: '清除搜索',
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              setState(() {
                _isExpanded = false;
              });
              if (_controller.text.isNotEmpty) {
                _controller.clear();
                widget.onClear();
              }
              logger.d('Search bar collapsed');
            },
            tooltip: '关闭搜索',
          ),
        ],
      ),
    );
  }
}