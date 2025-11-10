import 'dart:io';

import 'package:flutter/material.dart';
import 'package:disk_space_plus/disk_space_plus.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/favorite_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/ui/pages/storage_page.dart';

/// 收藏夹区域组件
///
/// 显示用户收藏的快捷目录
/// 采用两列布局：左侧显示收藏夹卡片，右侧显示存储空间信息
class FavoritesSection extends StatefulWidget {
  final FileViewModel viewModel;
  final FilePresenter presenter;

  const FavoritesSection({
    super.key,
    required this.viewModel,
    required this.presenter,
  });

  @override
  State<FavoritesSection> createState() => _FavoritesSectionState();
}

class _FavoritesSectionState extends State<FavoritesSection> {
  double? _totalSpace;
  double? _freeSpace;
  bool _loadingStorage = true;
  String? _selectedFavoritePath; // 当前选中的收藏夹路径

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
  }

  Future<void> _loadStorageInfo() async {
    try {
      final diskSpace = DiskSpacePlus();
      final totalSpace = await diskSpace.getTotalDiskSpace;
      final freeSpace = await diskSpace.getFreeDiskSpace;

      if (mounted) {
        setState(() {
          _totalSpace = totalSpace;
          _freeSpace = freeSpace;
          _loadingStorage = false;
        });
      }
    } catch (e) {
      logger.e('Failed to load storage info: $e');
      if (mounted) {
        setState(() {
          _loadingStorage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.viewModel.favorites.isEmpty) {
      return const SizedBox.shrink();
    }

    // 如果切换到最近Tab，清除选中状态
    if (widget.viewModel.currentTab == TabView.recent &&
        _selectedFavoritePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedFavoritePath = null;
          });
        }
      });
    }

    // 检查当前路径是否匹配某个收藏夹，自动更新选中状态
    if (widget.viewModel.currentTab == TabView.browse &&
        widget.viewModel.currentPath.isNotEmpty) {
      // 查找匹配的收藏夹
      final matchedFavorite = widget.viewModel.favorites.firstWhere(
        (fav) => fav.path == widget.viewModel.currentPath,
        orElse: () => widget.viewModel.favorites.first, // 返回一个dummy值
      );

      // 如果找到匹配的收藏夹，且当前选中状态不同，则更新
      if (matchedFavorite.path == widget.viewModel.currentPath &&
          _selectedFavoritePath != widget.viewModel.currentPath) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _selectedFavoritePath = widget.viewModel.currentPath;
            });
          }
        });
      }
    }

    final sorted = [...widget.viewModel.favorites]..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: _buildFavoritesGrid(context, sorted),
          ),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).dividerColor.withOpacity(0),
                  Theme.of(context).dividerColor.withOpacity(0.5),
                  Theme.of(context).dividerColor.withOpacity(0),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildStorageInfo(context),
        ],
      ),
    );
  }

  Widget _buildStorageInfo(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => StoragePage(
              presenter: widget.presenter,
              viewModel: widget.viewModel,
            ),
          ),
        );
      },
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: _loadingStorage
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _totalSpace == null || _freeSpace == null
                ? Center(
                    child: Text(
                      '存储空间',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withOpacity(0.6),
                          ),
                    ),
                  )
                : Stack(
                    children: [
                      // 底部居中："存储空间"文字（粗体）
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 6,
                        child: Text(
                          '存储空间',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    height: 1.0,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // 右上角：已用/总容量
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Text(
                          _formatStorageText(),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 8,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    height: 1.0,
                                  ),
                          maxLines: 1,
                        ),
                      ),
                      // 中间：圆形进度条
                      Center(
                        child: _buildCircularStorageIndicator(context),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildCircularStorageIndicator(BuildContext context) {
    if (_totalSpace == null || _freeSpace == null) {
      return const SizedBox.shrink();
    }

    final usedSpace = _totalSpace! - _freeSpace!;
    final usagePercent = (usedSpace / _totalSpace! * 100).clamp(0, 100);

    Color barColor;
    if (usagePercent < 70) {
      barColor = Colors.green;
    } else if (usagePercent < 90) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.red;
    }

    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              value: usagePercent / 100,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              strokeWidth: 4,
            ),
          ),
          Text(
            '${usagePercent.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: barColor,
            ),
          ),
        ],
      ),
    );
  }

  String _formatStorageText() {
    if (_totalSpace == null || _freeSpace == null) {
      return '';
    }

    // disk_space_plus 返回的是 MB 单位
    final usedMB = _totalSpace! - _freeSpace!;
    final totalMB = _totalSpace!;

    // 转换为 GB
    final usedGB = usedMB / 1024;
    final totalGB = totalMB / 1024;

    return '${usedGB.toStringAsFixed(1)}/${totalGB.toStringAsFixed(1)}G';
  }

  Widget _buildFavoritesGrid(BuildContext context, List<FavoriteItem> items) {
    final displayCount = items.length > 5 ? 5 : items.length;
    final hasMore = items.length > 5;

    return SizedBox(
      height: 100,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: List.generate(3, (index) {
                if (index < displayCount) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4.0, vertical: 2.0),
                      child: _buildFavoriteCard(context, items[index]),
                    ),
                  );
                } else if (index == displayCount && hasMore) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4.0, vertical: 2.0),
                      child:
                          _buildMoreCard(context, items.length - displayCount),
                    ),
                  );
                } else {
                  return const Expanded(child: SizedBox());
                }
              }),
            ),
          ),
          Expanded(
            child: Row(
              children: List.generate(3, (index) {
                final itemIndex = index + 3;
                if (itemIndex < displayCount) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4.0, vertical: 2.0),
                      child: _buildFavoriteCard(context, items[itemIndex]),
                    ),
                  );
                } else if (itemIndex == displayCount && hasMore) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4.0, vertical: 2.0),
                      child:
                          _buildMoreCard(context, items.length - displayCount),
                    ),
                  );
                } else {
                  return const Expanded(child: SizedBox());
                }
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteCard(BuildContext context, FavoriteItem favorite) {
    // 判断是否是当前选中的收藏夹
    final bool isSelected = _selectedFavoritePath == favorite.path;

    return GestureDetector(
      onLongPress: () => _showFavoriteOptions(context, favorite),
      child: Material(
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        elevation: isSelected ? 4 : 1,
        shadowColor: isSelected
            ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
            : Colors.black.withOpacity(0.1),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: () => _onFavoriteTap(favorite, context),
            borderRadius: BorderRadius.circular(12),
            splashColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
            highlightColor:
                Theme.of(context).colorScheme.primary.withOpacity(0.1),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _getFavoriteEmoji(favorite.iconName),
                    style: const TextStyle(fontSize: 20, height: 1.0),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    favorite.name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 11,
                          height: 1.1,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMoreCard(BuildContext context, int count) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showAllFavorites(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.more_horiz,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 1),
              Text(
                '更多',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                      height: 1.1,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getFavoriteEmoji(String? iconName) {
    switch (iconName) {
      case 'home':
        return '🏠';
      case 'download':
        return '📥';
      case 'documents':
        return '📄';
      case 'pictures':
        return '🖼️';
      case 'music':
        return '🎵';
      case 'videos':
        return '🎬';
      case 'desktop':
        return '💻';
      case 'storage':
        return '💾';
      default:
        return '📁';
    }
  }

  void _onFavoriteTap(FavoriteItem favorite, BuildContext context) {
    logger.d('Navigating to favorite: ${favorite.name} (${favorite.path})');

    // 更新选中状态
    setState(() {
      _selectedFavoritePath = favorite.path;
    });

    // 切换到文件浏览Tab
    widget.viewModel.setCurrentTab(TabView.browse);

    _checkAndNavigateToFavorite(favorite, context);
  }

  Future<void> _checkAndNavigateToFavorite(
      FavoriteItem favorite, BuildContext context) async {
    try {
      final directory = Directory(favorite.path);
      if (!directory.existsSync()) {
        if (context.mounted) {
          final shouldRemove = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('目录不存在'),
              content:
                  Text('收藏夹"${favorite.name}"指向的目录已不存在或无法访问。\n\n是否移除此收藏夹？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('保留'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('移除'),
                ),
              ],
            ),
          );
          if (shouldRemove == true) {
            final success = await widget.presenter.removeFavorite(favorite.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        success ? '已移除失效的收藏夹"${favorite.name}"' : '移除收藏夹失败')),
              );
            }
          }
        }
      } else {
        widget.presenter.loadFiles(favorite.path, isRootNavigation: true);
        widget.presenter.updateFavoriteLastAccessed(favorite.id);
      }
    } catch (e) {
      logger.e('Error checking favorite directory: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('访问目录"${favorite.name}"时出错')),
        );
      }
    }
  }

  void _showFavoriteOptions(BuildContext context, FavoriteItem favorite) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                favorite.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: Theme.of(context).primaryColor,
              ),
              title: Text(favorite.pinned ? '取消置顶' : '置顶'),
              onTap: () async {
                Navigator.of(context).pop();
                final updated = favorite.copyWith(pinned: !favorite.pinned);
                final success = await widget.presenter.updateFavorite(updated);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(success
                            ? (updated.pinned ? '已置顶' : '已取消置顶')
                            : '操作失败')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('重命名'),
              onTap: () {
                Navigator.of(context).pop();
                _showRenameFavoriteDialog(context, favorite);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('移除收藏'),
              onTap: () {
                Navigator.of(context).pop();
                _showDeleteFavoriteDialog(context, favorite);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('取消'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _showAllFavorites(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('所有收藏夹'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.viewModel.favorites.length,
            itemBuilder: (context, index) {
              final favorite = widget.viewModel.favorites[index];
              return ListTile(
                leading: Text(
                  _getFavoriteEmoji(favorite.iconName),
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text(favorite.name),
                subtitle: Text(
                  favorite.path,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showFavoriteOptions(context, favorite);
                  },
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _onFavoriteTap(favorite, context);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showRenameFavoriteDialog(BuildContext context, FavoriteItem favorite) {
    final controller = TextEditingController(text: favorite.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名收藏夹'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '新名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != favorite.name) {
                Navigator.of(context).pop();
                final updatedFavorite = favorite.copyWith(name: newName);
                final success =
                    await widget.presenter.updateFavorite(updatedFavorite);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(success ? '已重命名为"$newName"' : '重命名失败')),
                  );
                }
              } else {
                Navigator.of(context).pop();
              }
            },
            child: const Text('重命名'),
          ),
        ],
      ),
    );
  }

  void _showDeleteFavoriteDialog(BuildContext context, FavoriteItem favorite) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除收藏'),
        content: Text('确定要移除收藏夹"${favorite.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final success =
                  await widget.presenter.removeFavorite(favorite.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text(success ? '已移除收藏夹"${favorite.name}"' : '移除失败')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }
}
