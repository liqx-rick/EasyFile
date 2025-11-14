import 'package:flutter/material.dart';
import 'package:easyfile/data/models/search_history_item.dart';
import 'package:easyfile/data/sources/search_history_local_source.dart';

/// 搜索历史面板
///
/// 显示最近搜索和热门搜索，支持快速重复搜索和删除历史
class SearchHistoryPanel extends StatefulWidget {
  final SearchHistoryLocalSource historySource;
  final ValueChanged<String> onSearchSelected;
  final VoidCallback? onClearHistory;

  const SearchHistoryPanel({
    super.key,
    required this.historySource,
    required this.onSearchSelected,
    this.onClearHistory,
  });

  @override
  State<SearchHistoryPanel> createState() => _SearchHistoryPanelState();
}

class _SearchHistoryPanelState extends State<SearchHistoryPanel> {
  List<SearchHistoryItem> _recentSearches = [];
  List<SearchHistoryItem> _popularSearches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    final recent = await widget.historySource.getAllHistory();
    final popular = await widget.historySource.getPopularSearches(limit: 5);

    setState(() {
      _recentSearches = recent.take(10).toList();
      _popularSearches = popular;
      _isLoading = false;
    });
  }

  Future<void> _deleteHistoryItem(String keyword) async {
    final success = await widget.historySource.deleteSearchRecord(keyword);
    if (success) {
      await _loadHistory();
    }
  }

  Future<void> _clearAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空搜索历史'),
        content: const Text('确定要清空所有搜索历史吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await widget.historySource.clearAllHistory();
      if (success) {
        await _loadHistory();
        widget.onClearHistory?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_recentSearches.isEmpty && _popularSearches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '暂无搜索历史',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 最近搜索
          if (_recentSearches.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '最近搜索',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: _clearAllHistory,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清空'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _recentSearches.map((item) {
                return _buildHistoryChip(context, item, showCount: false);
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // 热门搜索
          if (_popularSearches.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.trending_up,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '热门搜索',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _popularSearches.map((item) {
                return _buildHistoryChip(
                  context,
                  item,
                  showCount: true,
                  isPopular: true,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryChip(
    BuildContext context,
    SearchHistoryItem item, {
    bool showCount = false,
    bool isPopular = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => widget.onSearchSelected(item.keyword),
      child: Chip(
        avatar: Icon(
          isPopular ? Icons.local_fire_department : Icons.history,
          size: 16,
          color: isPopular ? Colors.orange : colorScheme.onSurfaceVariant,
        ),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.keyword,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (showCount && item.searchCount > 1) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${item.searchCount}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ],
        ),
        deleteIcon: const Icon(Icons.close, size: 16),
        onDeleted: () => _deleteHistoryItem(item.keyword),
        backgroundColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }
}
