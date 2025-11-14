import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/favorite_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';

/// 管理收藏文件夹页面
///
/// 显示系统默认目录，用户可以点击添加或取消收藏
class FavoritesManagePage extends StatefulWidget {
  final FilePresenter presenter;
  final FileViewModel viewModel;

  const FavoritesManagePage({
    super.key,
    required this.presenter,
    required this.viewModel,
  });

  @override
  State<FavoritesManagePage> createState() => _FavoritesManagePageState();
}

class _FavoritesManagePageState extends State<FavoritesManagePage> {
  List<DefaultDirectory> _defaultDirectories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDefaultDirectories();
  }

  /// 加载平台特定的默认目录
  Future<void> _loadDefaultDirectories() async {
    setState(() {
      _isLoading = true;
    });

    try {
      List<DefaultDirectory> directories = [];

      if (Platform.isAndroid) {
        directories = await _getAndroidDefaultDirectories();
      } else if (Platform.isWindows) {
        directories = await _getWindowsDefaultDirectories();
      } else {
        directories = await _getGenericDefaultDirectories();
      }

      setState(() {
        _defaultDirectories = directories;
        _isLoading = false;
      });
    } catch (e) {
      logger.e('Error loading default directories: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 获取Android平台默认目录
  Future<List<DefaultDirectory>> _getAndroidDefaultDirectories() async {
    List<DefaultDirectory> directories = [];

    // Android标准目录
    final standardPaths = {
      'DCIM': '/storage/emulated/0/DCIM',
      'Pictures': '/storage/emulated/0/Pictures',
      'Documents': '/storage/emulated/0/Documents',
      'Music': '/storage/emulated/0/Music',
      'Movies': '/storage/emulated/0/Movies',
      'Download': '/storage/emulated/0/Download',
      'Android': '/storage/emulated/0/Android',
    };

    for (final entry in standardPaths.entries) {
      final dir = Directory(entry.value);
      if (dir.existsSync()) {
        directories.add(
          DefaultDirectory(
            name: entry.key,
            path: entry.value,
            iconName: _getIconForDirectoryName(entry.key),
            description: _getDescriptionForDirectoryName(entry.key),
          ),
        );
      }
    }

    return directories;
  }

  /// 获取Windows平台默认目录
  Future<List<DefaultDirectory>> _getWindowsDefaultDirectories() async {
    List<DefaultDirectory> directories = [];

    try {
      // Windows用户目录
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        final standardPaths = {
          'Downloads': '$userProfile\\Downloads',
          'Documents': '$userProfile\\Documents',
          'Pictures': '$userProfile\\Pictures',
          'Music': '$userProfile\\Music',
          'Videos': '$userProfile\\Videos',
          'Desktop': '$userProfile\\Desktop',
        };

        for (final entry in standardPaths.entries) {
          final dir = Directory(entry.value);
          if (dir.existsSync()) {
            directories.add(
              DefaultDirectory(
                name: entry.key,
                path: entry.value,
                iconName: _getIconForDirectoryName(entry.key),
                description: _getDescriptionForDirectoryName(entry.key),
              ),
            );
          }
        }
      }

      // 添加系统盘
      final systemDrive = Platform.environment['SystemDrive'] ?? 'C:';
      final systemDir = Directory('$systemDrive\\');
      if (systemDir.existsSync()) {
        directories.add(
          DefaultDirectory(
            name: 'System Drive',
            path: systemDir.path,
            iconName: 'storage',
            description: '系统盘',
          ),
        );
      }
    } catch (e) {
      logger.w('Error getting Windows directories: $e');
    }

    return directories;
  }

  /// 获取通用平台默认目录
  Future<List<DefaultDirectory>> _getGenericDefaultDirectories() async {
    List<DefaultDirectory> directories = [];

    try {
      // 尝试获取用户目录
      final documentsDir = await getApplicationDocumentsDirectory();
      directories.add(
        DefaultDirectory(
          name: 'Documents',
          path: documentsDir.path,
          iconName: 'documents',
          description: '文档目录',
        ),
      );

      // 当前工作目录
      final currentDir = Directory.current;
      if (currentDir.existsSync()) {
        directories.add(
          DefaultDirectory(
            name: 'Current',
            path: currentDir.path,
            iconName: 'folder',
            description: '当前目录',
          ),
        );
      }

      // 根目录 (Unix-like系统)
      if (!Platform.isWindows) {
        final rootDir = Directory('/');
        if (rootDir.existsSync()) {
          directories.add(
            DefaultDirectory(
              name: 'Root',
              path: '/',
              iconName: 'storage',
              description: '根目录',
            ),
          );
        }
      }
    } catch (e) {
      logger.w('Error getting generic directories: $e');
    }

    return directories;
  }

  /// 根据目录名获取图标
  String _getIconForDirectoryName(String name) {
    switch (name.toLowerCase()) {
      case 'dcim':
      case 'pictures':
        return 'pictures';
      case 'documents':
        return 'documents';
      case 'music':
        return 'music';
      case 'movies':
      case 'videos':
        return 'videos';
      case 'download':
      case 'downloads':
        return 'download';
      case 'desktop':
        return 'desktop';
      case 'android':
      case 'system drive':
      case 'root':
        return 'storage';
      default:
        return 'folder';
    }
  }

  /// 根据目录名获取描述
  String _getDescriptionForDirectoryName(String name) {
    switch (name.toLowerCase()) {
      case 'dcim':
        return '相机照片';
      case 'pictures':
        return '图片文件';
      case 'documents':
        return '文档文件';
      case 'music':
        return '音乐文件';
      case 'movies':
        return '视频文件';
      case 'videos':
        return '视频文件';
      case 'download':
      case 'downloads':
        return '下载文件';
      case 'desktop':
        return '桌面';
      case 'android':
        return 'Android应用数据';
      case 'system drive':
        return '系统盘';
      case 'root':
        return '根目录';
      case 'current':
        return '当前工作目录';
      default:
        return '文件夹';
    }
  }

  /// 获取目录图标
  IconData _getDirectoryIcon(String iconName) {
    switch (iconName) {
      case 'pictures':
        return Icons.image;
      case 'documents':
        return Icons.description;
      case 'music':
        return Icons.music_note;
      case 'videos':
        return Icons.video_library;
      case 'download':
        return Icons.download;
      case 'desktop':
        return Icons.desktop_windows;
      case 'storage':
        return Icons.storage;
      case 'home':
        return Icons.home;
      default:
        return Icons.folder;
    }
  }

  /// 检查目录是否已收藏
  bool _isDirectoryFavorited(String path) {
    return widget.viewModel.favorites.any((favorite) => favorite.path == path);
  }

  /// 切换目录收藏状态
  Future<void> _toggleDirectoryFavorite(DefaultDirectory directory) async {
    final isFavorited = _isDirectoryFavorited(directory.path);

    if (isFavorited) {
      // 删除收藏
      final favorite = widget.viewModel.favorites.firstWhere(
        (f) => f.path == directory.path,
      );
      final success = await widget.presenter.removeFavorite(favorite.id);

      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已取消收藏"${directory.name}"')));
      }
    } else {
      // 添加收藏
      final favorite = FavoriteItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: directory.name,
        path: directory.path,
        iconName: directory.iconName,
        createdAt: DateTime.now(),
      );

      final success = await widget.presenter.addFavorite(favorite);

      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已添加收藏"${directory.name}"')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '返回主页',
        ),
        title: const Text('管理收藏文件夹'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _defaultDirectories.isEmpty
          ? _buildEmptyState()
          : _buildDirectoriesList(),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _loadDefaultDirectories,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  '未找到默认目录',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  '请检查系统权限或手动添加收藏夹',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Text(
                  '下拉刷新',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建目录列表
  Widget _buildDirectoriesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 说明文字
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('系统默认目录', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '点击右侧图标可添加或取消收藏，收藏的目录将出现在主页面的收藏区域。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        const Divider(),

        // 目录列表
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadDefaultDirectories,
            child: ListView.builder(
              itemCount: _defaultDirectories.length,
              itemBuilder: (context, index) {
                final directory = _defaultDirectories[index];
                final isFavorited = _isDirectoryFavorited(directory.path);

                return ListTile(
                  leading: Icon(
                    _getDirectoryIcon(directory.iconName),
                    size: 32,
                    color: Theme.of(context).primaryColor,
                  ),
                  title: Text(
                    directory.name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(directory.description),
                      const SizedBox(height: 2),
                      Text(
                        directory.path,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isFavorited)
                        IconButton(
                          icon: Icon(
                            _getPinnedStateForPath(directory.path)
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            color: _getPinnedStateForPath(directory.path)
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                          ),
                          tooltip: _getPinnedStateForPath(directory.path)
                              ? '取消置顶'
                              : '置顶',
                          onPressed: () => _togglePinForPath(directory.path),
                        ),
                      IconButton(
                        icon: Icon(
                          isFavorited ? Icons.star : Icons.star_border,
                          color: isFavorited ? Colors.amber : Colors.grey,
                        ),
                        onPressed: () => _toggleDirectoryFavorite(directory),
                        tooltip: isFavorited ? '取消收藏' : '添加收藏',
                      ),
                    ],
                  ),
                  onTap: () => _toggleDirectoryFavorite(directory),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  bool _getPinnedStateForPath(String path) {
    final f = widget.viewModel.favorites.where((e) => e.path == path);
    if (f.isEmpty) return false;
    return f.first.pinned;
  }

  Future<void> _togglePinForPath(String path) async {
    try {
      final existing = widget.viewModel.favorites.firstWhere(
        (f) => f.path == path,
      );
      final updated = existing.copyWith(pinned: !existing.pinned);
      final ok = await widget.presenter.updateFavorite(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? (updated.pinned ? '已置顶' : '已取消置顶') : '操作失败'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('操作失败')));
    }
  }
}

/// 默认目录信息类
class DefaultDirectory {
  final String name;
  final String path;
  final String iconName;
  final String description;

  const DefaultDirectory({
    required this.name,
    required this.path,
    required this.iconName,
    required this.description,
  });

  @override
  String toString() {
    return 'DefaultDirectory(name: $name, path: $path, iconName: $iconName)';
  }
}
