import 'package:flutter/material.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';

/// 新目录通知服务
///
/// 管理新发现文件夹的通知状态，提供非侵入式的通知UI
class NewFolderNotificationService extends ChangeNotifier {
  // 待通知的新文件夹列表
  final List<QuickAccessFolder> _pendingFolders = [];

  // 是否显示通知徽章
  bool _showBadge = false;

  // 是否已读
  bool _isRead = false;

  // Getters
  List<QuickAccessFolder> get pendingFolders =>
      List.unmodifiable(_pendingFolders);
  bool get showBadge => _showBadge && !_isRead;
  int get unreadCount => _isRead ? 0 : _pendingFolders.length;
  bool get hasPendingFolders => _pendingFolders.isNotEmpty;

  /// 添加新发现的文件夹
  void addNewFolders(List<QuickAccessFolder> folders) {
    if (folders.isEmpty) return;

    _pendingFolders.addAll(folders);
    _showBadge = true;
    _isRead = false;
    notifyListeners();
  }

  /// 添加单个文件夹
  void addNewFolder(QuickAccessFolder folder) {
    _pendingFolders.add(folder);
    _showBadge = true;
    _isRead = false;
    notifyListeners();
  }

  /// 标记为已读（不清除列表，只隐藏徽章）
  void markAsRead() {
    _isRead = true;
    notifyListeners();
  }

  /// 清除所有待通知的文件夹
  void clearAll() {
    _pendingFolders.clear();
    _showBadge = false;
    _isRead = false;
    notifyListeners();
  }

  /// 移除指定的文件夹
  void removeFolder(String path) {
    _pendingFolders.removeWhere((f) => f.path == path);
    if (_pendingFolders.isEmpty) {
      _showBadge = false;
      _isRead = false;
    }
    notifyListeners();
  }

  /// 批量移除文件夹
  void removeFolders(List<String> paths) {
    _pendingFolders.removeWhere((f) => paths.contains(f.path));
    if (_pendingFolders.isEmpty) {
      _showBadge = false;
      _isRead = false;
    }
    notifyListeners();
  }

  /// 重置已读状态（当有新内容时）
  void resetReadState() {
    if (_pendingFolders.isNotEmpty) {
      _isRead = false;
      _showBadge = true;
      notifyListeners();
    }
  }
}

/// 新文件夹通知徽章组件
///
/// 显示在管理按钮旁边的红点徽章
class NewFolderBadge extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const NewFolderBadge({super.key, required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(10),
        ),
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// 新文件夹通知对话框
///
/// 显示检测到的新文件夹列表，允许用户选择添加或忽略
class NewFolderNotificationDialog extends StatefulWidget {
  final List<QuickAccessFolder> folders;
  final Function(List<QuickAccessFolder> selectedFolders) onAddSelected;
  final VoidCallback onDismiss;

  const NewFolderNotificationDialog({
    super.key,
    required this.folders,
    required this.onAddSelected,
    required this.onDismiss,
  });

  @override
  State<NewFolderNotificationDialog> createState() =>
      _NewFolderNotificationDialogState();
}

class _NewFolderNotificationDialogState
    extends State<NewFolderNotificationDialog> {
  late Set<String> _selectedPaths;
  bool _selectAll = true;

  @override
  void initState() {
    super.initState();
    // 默认全选
    _selectedPaths = widget.folders.map((f) => f.path).toSet();
  }

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedPaths = widget.folders.map((f) => f.path).toSet();
      } else {
        _selectedPaths.clear();
      }
    });
  }

  void _toggleFolder(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        _selectAll = false;
      } else {
        _selectedPaths.add(path);
        if (_selectedPaths.length == widget.folders.length) {
          _selectAll = true;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedFolders = widget.folders
        .where((f) => _selectedPaths.contains(f.path))
        .toList();

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.folder_special,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发现新文件夹',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '选择要添加到快速访问的文件夹',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 全选/取消全选
            CheckboxListTile(
              dense: true,
              title: Text(
                '全选 (${widget.folders.length}个)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              value: _selectAll,
              onChanged: (_) => _toggleSelectAll(),
            ),
            const Divider(),

            // 文件夹列表
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.folders.length,
                itemBuilder: (context, index) {
                  final folder = widget.folders[index];
                  final isSelected = _selectedPaths.contains(folder.path);

                  return CheckboxListTile(
                    dense: true,
                    value: isSelected,
                    onChanged: (_) => _toggleFolder(folder.path),
                    title: Row(
                      children: [
                        Icon(
                          _getFolderIcon(folder),
                          size: 20,
                          color: _getFolderColor(folder),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                folder.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                folder.path,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color
                                      ?.withValues(alpha: 0.6),
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    subtitle: folder.stats != null
                        ? Text(
                            '${folder.stats!.totalFiles} 个文件',
                            style: const TextStyle(fontSize: 10),
                          )
                        : null,
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // 分类统计
            _buildCategoryStats(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onDismiss();
            Navigator.of(context).pop();
          },
          child: const Text('稍后提醒'),
        ),
        TextButton(
          onPressed: _selectedPaths.isEmpty
              ? null
              : () {
                  widget.onAddSelected(selectedFolders);
                  Navigator.of(context).pop();
                },
          child: Text(
            _selectedPaths.isEmpty ? '添加' : '添加 (${_selectedPaths.length})',
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryStats() {
    final stats = <QuickAccessFolderType, int>{};
    for (final folder in widget.folders) {
      stats[folder.type] = (stats[folder.type] ?? 0) + 1;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: stats.entries.map((entry) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getTypeIcon(entry.key),
                size: 14,
                color: _getTypeColor(entry.key),
              ),
              const SizedBox(width: 4),
              Text(
                '${_getTypeName(entry.key)} ${entry.value}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  IconData _getFolderIcon(QuickAccessFolder folder) {
    switch (folder.type) {
      case QuickAccessFolderType.system:
        return Icons.folder_special;
      case QuickAccessFolderType.appRoot:
      case QuickAccessFolderType.appSubfolder:
        return Icons.apps;
      case QuickAccessFolderType.userCustom:
        return Icons.folder;
    }
  }

  Color _getFolderColor(QuickAccessFolder folder) {
    switch (folder.type) {
      case QuickAccessFolderType.system:
        return Colors.blue;
      case QuickAccessFolderType.appRoot:
      case QuickAccessFolderType.appSubfolder:
        return Colors.orange;
      case QuickAccessFolderType.userCustom:
        return Colors.green;
    }
  }

  IconData _getTypeIcon(QuickAccessFolderType type) {
    switch (type) {
      case QuickAccessFolderType.system:
        return Icons.security;
      case QuickAccessFolderType.appRoot:
      case QuickAccessFolderType.appSubfolder:
        return Icons.apps;
      case QuickAccessFolderType.userCustom:
        return Icons.person;
    }
  }

  Color _getTypeColor(QuickAccessFolderType type) {
    switch (type) {
      case QuickAccessFolderType.system:
        return Colors.blue;
      case QuickAccessFolderType.appRoot:
      case QuickAccessFolderType.appSubfolder:
        return Colors.orange;
      case QuickAccessFolderType.userCustom:
        return Colors.green;
    }
  }

  String _getTypeName(QuickAccessFolderType type) {
    switch (type) {
      case QuickAccessFolderType.system:
        return '系统';
      case QuickAccessFolderType.appRoot:
        return '应用';
      case QuickAccessFolderType.appSubfolder:
        return '应用子目录';
      case QuickAccessFolderType.userCustom:
        return '用户';
    }
  }
}

/// 轻量级的新文件夹提示条
///
/// 显示在页面顶部的可关闭的提示条
class NewFolderNotificationBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const NewFolderNotificationBanner({
    super.key,
    required this.count,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.folder_special,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '发现 $count 个新文件夹',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '点击查看并添加到快速访问',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  onPressed: onDismiss,
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
