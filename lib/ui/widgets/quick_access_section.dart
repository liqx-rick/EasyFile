import 'dart:io';
import 'package:flutter/material.dart';
import 'package:disk_space_plus/disk_space_plus.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';
import 'package:easyfile/viewmodel/quick_access_viewmodel.dart';
import 'package:easyfile/ui/pages/storage_page.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';

/// 快速访问区域组件（可展开/折叠）
///
/// 显示系统、应用、用户自定义三层分类的快速访问文件夹
/// 支持横向展开/折叠动画，横向滑动查看更多
class QuickAccessSection extends StatefulWidget {
  final QuickAccessViewModel quickAccessViewModel;
  final QuickAccessPresenter quickAccessPresenter;
  final FileViewModel fileViewModel;
  final FilePresenter filePresenter;

  const QuickAccessSection({
    super.key,
    required this.quickAccessViewModel,
    required this.quickAccessPresenter,
    required this.fileViewModel,
    required this.filePresenter,
  });

  @override
  State<QuickAccessSection> createState() => _QuickAccessSectionState();
}

class _QuickAccessSectionState extends State<QuickAccessSection>
    with SingleTickerProviderStateMixin {
  // 动画控制器
  late AnimationController _animationController;
  
  // 存储空间信息
  double? _totalSpace;
  double? _freeSpace;
  bool _loadingStorage = true;

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _loadStorageInfo();
    // 延迟加载避免在build期间触发setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadQuickAccessFolders();
      }
    });
  }

  void _initAnimation() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
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

  Future<void> _loadQuickAccessFolders() async {
    await widget.quickAccessPresenter.loadQuickAccessFolders();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final folders = widget.quickAccessViewModel.folders;
    // 筛选首页展示的文件夹并排序
    final homeFolders = folders.where((f) => f.isOnHomePage).toList()
      ..sort((a, b) => (a.homeDisplayOrder ?? 999).compareTo(b.homeDisplayOrder ?? 999));
    
    if (homeFolders.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 2),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 快速访问区域（2行3列卡片）
            Expanded(
              flex: 3,
              child: _buildQuickAccessCards(context, homeFolders),
            ),
            
            // 分隔线
            const SizedBox(width: 12),
            Column(
              children: [
                const SizedBox(height: 20), // 标题高度
                Expanded(
                  child: Container(
                    width: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(context).dividerColor.withValues(alpha: 0),
                          Theme.of(context).dividerColor.withValues(alpha: 0.5),
                          Theme.of(context).dividerColor.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            
            // 存储空间信息
            Column(
              children: [
                const SizedBox(height: 20), // 标题高度
                Expanded(
                  child: _buildStorageInfo(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAccessCards(BuildContext context, List<QuickAccessFolder> homeFolders) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题和弹出菜单按钮
        Row(
          children: [
            InkWell(
              onTap: () => _showFolderMenu(context),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.expand_more,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            Text(
              '快速访问',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        
        //const SizedBox(height: 1),
        
        // 2行3列卡片布局
        Column(
          children: [
            // 第一行（3个卡片）
            Row(
              children: [
                for (int i = 0; i < 3 && i < homeFolders.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 3 : 0),
                      child: _buildFolderCard(context, homeFolders[i]),
                    ),
                  ),
                // 填充空白卡片
                for (int i = homeFolders.length; i < 3; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 3 : 0),
                      child: const SizedBox(),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            // 第二行（3个卡片）
            Row(
              children: [
                for (int i = 3; i < 6 && i < homeFolders.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: (i - 3) < 2 ? 3 : 0),
                      child: _buildFolderCard(context, homeFolders[i]),
                    ),
                  ),
                // 填充空白卡片
                for (int i = homeFolders.length; i < 6; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: (i - 3) < 2 ? 3 : 0),
                      child: const SizedBox(),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showFolderMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final QuickAccessFolder? selected = await showMenu<QuickAccessFolder>(
      context: context,
      position: position,
      items: _buildPopupMenuItems(context),
    );

    if (selected != null && mounted) {
      _navigateToFolder(selected);
    }
  }

  List<PopupMenuEntry<QuickAccessFolder>> _buildPopupMenuItems(BuildContext context) {
    final allFolders = widget.quickAccessViewModel.folders;
    
    // 按类型分组
    final systemFolders = allFolders.where((f) => f.type == QuickAccessFolderType.system && f.isAddedToQuickAccess).toList();
    final appFolders = allFolders.where((f) => (f.type == QuickAccessFolderType.appRoot || f.type == QuickAccessFolderType.appSubfolder) && f.isAddedToQuickAccess).toList();
    final userFolders = allFolders.where((f) => f.type == QuickAccessFolderType.userCustom && f.isAddedToQuickAccess).toList();
    
    List<PopupMenuEntry<QuickAccessFolder>> items = [];
    
    // 系统文件夹
    if (systemFolders.isNotEmpty) {
      items.add(
        PopupMenuItem<QuickAccessFolder>(
          enabled: false,
          child: Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '系统 (${systemFolders.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ),
      );
      for (var folder in systemFolders) {
        items.add(_buildFolderMenuItem(folder, Colors.blue));
      }
      if (appFolders.isNotEmpty || userFolders.isNotEmpty) {
        items.add(const PopupMenuDivider());
      }
    }
    
    // 应用文件夹
    if (appFolders.isNotEmpty) {
      items.add(
        PopupMenuItem<QuickAccessFolder>(
          enabled: false,
          child: Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '应用 (${appFolders.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ),
      );
      for (var folder in appFolders) {
        items.add(_buildFolderMenuItem(folder, Colors.orange));
      }
      if (userFolders.isNotEmpty) {
        items.add(const PopupMenuDivider());
      }
    }
    
    // 自定义文件夹
    if (userFolders.isNotEmpty) {
      items.add(
        PopupMenuItem<QuickAccessFolder>(
          enabled: false,
          child: Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '我的 (${userFolders.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),
      );
      for (var folder in userFolders) {
        items.add(_buildFolderMenuItem(folder, Colors.green));
      }
    }
    
    return items;
  }

  PopupMenuItem<QuickAccessFolder> _buildFolderMenuItem(QuickAccessFolder folder, Color color) {
    final exists = Directory(folder.path).existsSync();
    
    return PopupMenuItem<QuickAccessFolder>(
      value: folder,
      enabled: exists,
      child: Row(
        children: [
          Icon(
            _getFolderIcon(folder),
            size: 18,
            color: exists ? color : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              folder.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: exists ? null : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderCard(BuildContext context, QuickAccessFolder folder) {
    final exists = Directory(folder.path).existsSync();
    final color = _getFolderColorByType(folder.type);
    
    return AspectRatio(
      aspectRatio: 1.0, // 保持正方形
      child: Card(
        elevation: 2,
        child: InkWell(
          onTap: exists ? () => _navigateToFolder(folder) : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getFolderIcon(folder),
                  size: 22,
                  color: exists ? color : Colors.grey,
                ),
                const SizedBox(height: 1),
                Flexible(
                  child: Text(
                    folder.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: exists ? null : Colors.grey,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getFolderColorByType(QuickAccessFolderType type) {
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

  IconData _getFolderIcon(QuickAccessFolder folder) {
    switch (folder.type) {
      case QuickAccessFolderType.system:
        // 根据路径判断系统文件夹类型
        final path = folder.path.toLowerCase();
        if (path.contains('dcim') || path.contains('camera')) return Icons.camera_alt;
        if (path.contains('download')) return Icons.download;
        if (path.contains('picture') || path.contains('photo')) return Icons.photo;
        if (path.contains('document')) return Icons.description;
        if (path.contains('music')) return Icons.music_note;
        if (path.contains('movie') || path.contains('video')) return Icons.video_library;
        return Icons.folder_special;
        
      case QuickAccessFolderType.appRoot:
      case QuickAccessFolderType.appSubfolder:
        return Icons.apps;
        
      case QuickAccessFolderType.userCustom:
        return Icons.folder;
    }
  }

  Widget _buildStorageInfo(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => StoragePage(
              presenter: widget.filePresenter,
              viewModel: widget.fileViewModel,
            ),
          ),
        );
      },
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(
                  Icons.storage,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '存储',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_loadingStorage)
              const Center(
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_totalSpace != null && _freeSpace != null)
              Column(
                children: [
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 60,
                          height: 60,
                          child: CircularProgressIndicator(
                            value: (_totalSpace! - _freeSpace!) / _totalSpace!,
                            strokeWidth: 6,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getStorageColor(_freeSpace! / _totalSpace!),
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatStorageSize(_freeSpace!),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '可用',
                              style: TextStyle(
                                fontSize: 8,
                                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '共 ${_formatStorageSize(_totalSpace!)}',
                    style: TextStyle(
                      fontSize: 8,
                      color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              )
            else
              Text(
                '加载失败',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getStorageColor(double freePercentage) {
    // 可用空间百分比分级显示
    if (freePercentage < 0.1) {
      // 少于10% - 危险（红色）
      return Colors.red;
    } else if (freePercentage < 0.2) {
      // 10%-20% - 警告（橙色）
      return Colors.orange;
    } else if (freePercentage < 0.3) {
      // 20%-30% - 注意（黄色）
      return Colors.amber;
    } else {
      // 大于30% - 充足（绿色）
      return Colors.green;
    }
  }

  String _formatStorageSize(double? value) {
    if (value == null || value == 0) {
      return '加载中';
    }
    
    // DiskSpacePlus返回MB
    final sizeInMB = value;
    final sizeInGB = sizeInMB / 1024;
    
    if (sizeInGB < 1) {
      return '${sizeInMB.toStringAsFixed(0)} MB';
    }
    return '${sizeInGB.toStringAsFixed(1)} GB';
  }

  void _navigateToFolder(QuickAccessFolder folder) {
    // 更新访问时间
    widget.quickAccessPresenter.updateAccessInfo(folder.path);
    
    // 导航到文件夹
    widget.filePresenter.navigateToFolder(folder.path);
    
    // 切换到浏览Tab
    widget.fileViewModel.setCurrentTab(TabView.browse);
  }
}
