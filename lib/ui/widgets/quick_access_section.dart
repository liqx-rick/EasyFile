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
  final double categoryCardSize;

  const QuickAccessSection({
    super.key,
    required this.quickAccessViewModel,
    required this.quickAccessPresenter,
    required this.fileViewModel,
    required this.filePresenter,
    this.categoryCardSize = 0.0,
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

  // "更多"卡片的GlobalKey，用于定位菜单弹出位置
  final GlobalKey _moreCardKey = GlobalKey();

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

    // 筛选用户定制的首页展示文件夹
    final userCustomizedHomeFolders = folders
        .where((f) => f.homeDisplayOrder != null)
        .toList()
      ..sort(
        (a, b) =>
            (a.homeDisplayOrder ?? 999).compareTo(b.homeDisplayOrder ?? 999),
      );

    List<QuickAccessFolder> displayFoldersForHome;

    if (userCustomizedHomeFolders.isNotEmpty) {
      // 用户已定制过首页，使用用户定制的
      displayFoldersForHome = userCustomizedHomeFolders;
    } else {
      // 用户未定制，从系统目录中按优先级选择最重要的4个
      final systemFolders =
          folders.where((f) => f.type == QuickAccessFolderType.system).toList();

      if (systemFolders.length <= 4) {
        displayFoldersForHome = systemFolders;
      } else {
        // 按优先级排序：下载 > DCIM/相机 > 图片 > 文档 > 音乐 > 视频 > 其他
        systemFolders.sort((a, b) {
          int getPriority(QuickAccessFolder folder) {
            final path = folder.path.toLowerCase();
            if (path.contains('download')) return 1;
            if (path.contains('dcim') || path.contains('camera')) return 2;
            if (path.contains('picture') || path.contains('photo')) return 3;
            if (path.contains('document')) return 4;
            if (path.contains('music')) return 5;
            if (path.contains('movie') || path.contains('video')) return 6;
            return 99; // 其他
          }

          return getPriority(a).compareTo(getPriority(b));
        });

        // 选择优先级最高的前4个
        displayFoldersForHome = systemFolders.take(4).toList();
      }
    }

    if (displayFoldersForHome.isEmpty) {
      return const SizedBox.shrink();
    }

    // 根据推荐数量决定布局模式
    final isCompactMode = displayFoldersForHome.length <= 4;

    // 调试信息
    logger.d(
      'QuickAccessSection: displayFolders count = ${displayFoldersForHome.length}, isCompactMode = $isCompactMode',
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 快速访问区域 - 根据模式调整比例
          Expanded(
            flex: isCompactMode ? 80 : 65,
            child: _buildQuickAccessCards(
              context,
              displayFoldersForHome,
              isCompactMode,
            ),
          ),

          // 分隔线区域 - 根据模式调整比例
          Expanded(
            flex: isCompactMode ? 4 : 5,
            child: Center(
              child: Container(
                width: 1,
                height: isCompactMode ? 60 : 100,
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
          ),

          // 存储空间信息 - 根据模式调整比例和显示方式
          Expanded(
            flex: isCompactMode ? 16 : 30,
            child: isCompactMode
                ? _buildStorageInfoCompact(context)
                : _buildStorageInfo(context),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessCards(
    BuildContext context,
    List<QuickAccessFolder> homeFolders,
    bool isCompactMode,
  ) {
    logger.d(
      '_buildQuickAccessCards: isCompactMode = $isCompactMode, folders = ${homeFolders.length}',
    );

    if (isCompactMode) {
      // 紧凑模式：单行显示，最多4个文件夹 + 1个更多卡片
      final displayFolders = homeFolders.take(4).toList();

      return LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;

          // 单行5个卡片（4个文件夹 + 1个更多）
          final totalCards = 5;
          final minSpacing = 3.0;
          final maxSpacing = 12.0;

          // 计算卡片尺寸
          final estimatedCardSize =
              (availableWidth - (totalCards + 1) * minSpacing) / totalCards;
          final cardSize = estimatedCardSize.clamp(40.0, double.infinity);

          // 计算实际间距
          final totalCardWidth = cardSize * totalCards;
          final availableSpace = availableWidth - totalCardWidth;
          final spacing = availableSpace > 0
              ? (availableSpace / (totalCards + 1)).clamp(
                  minSpacing,
                  maxSpacing,
                )
              : minSpacing;

          return Row(
            children: [
              SizedBox(width: spacing),
              for (int i = 0; i < displayFolders.length; i++) ...[
                _buildFolderCard(context, displayFolders[i], cardSize),
                SizedBox(width: spacing),
              ],
              // 总是显示更多卡片
              _buildMoreCard(context, cardSize),
              SizedBox(width: spacing),
            ],
          );
        },
      );
    } else {
      // 正常模式：2行显示，最多7个文件夹 + 1个更多卡片
      final displayFolders = homeFolders.take(7).toList();

      return LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;

          // 每行4张卡片
          final cardsPerRow = 4;
          final minSpacing = 3.0;
          final maxSpacing = 12.0;

          // 计算卡片尺寸
          final estimatedCardSize =
              (availableWidth - (cardsPerRow + 1) * minSpacing) / cardsPerRow;
          final cardSize = estimatedCardSize.clamp(40.0, double.infinity);

          // 计算实际间距
          final totalCardWidth = cardSize * cardsPerRow;
          final availableSpace = availableWidth - totalCardWidth;
          final spacing = availableSpace > 0
              ? (availableSpace / (cardsPerRow + 1)).clamp(
                  minSpacing,
                  maxSpacing,
                )
              : minSpacing;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行
              Row(
                children: [
                  SizedBox(width: spacing),
                  for (int i = 0; i < 4 && i < displayFolders.length; i++) ...[
                    _buildFolderCard(context, displayFolders[i], cardSize),
                    SizedBox(width: spacing),
                  ],
                  // 如果第一行不满4个，在第一行末尾显示"更多"
                  if (displayFolders.length < 4) ...[
                    _buildMoreCard(context, cardSize),
                    SizedBox(width: spacing),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              // 第二行
              Row(
                children: [
                  SizedBox(width: spacing),
                  for (int i = 4; i < 8 && i < displayFolders.length; i++) ...[
                    _buildFolderCard(context, displayFolders[i], cardSize),
                    SizedBox(width: spacing),
                  ],
                  // 如果第一行满了但第二行有空间，在第二行末尾显示"更多"
                  if (displayFolders.length >= 4) ...[
                    _buildMoreCard(context, cardSize),
                    SizedBox(width: spacing),
                  ],
                ],
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _showFolderMenu(BuildContext context) async {
    // 获取"更多"卡片的位置
    final RenderBox? moreCardBox =
        _moreCardKey.currentContext?.findRenderObject() as RenderBox?;
    if (moreCardBox == null) return;

    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset moreCardPosition = moreCardBox.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );
    final Size moreCardSize = moreCardBox.size;

    // 计算菜单位置：从"更多"卡片的右侧展开
    final RelativeRect position = RelativeRect.fromLTRB(
      moreCardPosition.dx + moreCardSize.width, // 左边界：卡片右侧
      moreCardPosition.dy, // 顶部对齐卡片顶部
      overlay.size.width -
          (moreCardPosition.dx + moreCardSize.width + 200), // 右边界：留出菜单宽度
      overlay.size.height - moreCardPosition.dy, // 底部
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

  List<PopupMenuEntry<QuickAccessFolder>> _buildPopupMenuItems(
    BuildContext context,
  ) {
    final allFolders = widget.quickAccessViewModel.folders;

    // 按类型分组
    final systemFolders = allFolders
        .where(
          (f) =>
              f.type == QuickAccessFolderType.system && f.isAddedToQuickAccess,
        )
        .toList();
    final appFolders = allFolders
        .where(
          (f) =>
              (f.type == QuickAccessFolderType.appRoot ||
                  f.type == QuickAccessFolderType.appSubfolder) &&
              f.isAddedToQuickAccess,
        )
        .toList();
    final userFolders = allFolders
        .where(
          (f) =>
              f.type == QuickAccessFolderType.userCustom &&
              f.isAddedToQuickAccess,
        )
        .toList();

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
                  fontSize: 13,
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
                  fontSize: 13,
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
                  fontSize: 13,
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

  PopupMenuItem<QuickAccessFolder> _buildFolderMenuItem(
    QuickAccessFolder folder,
    Color color,
  ) {
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

  Widget _buildFolderCard(
    BuildContext context,
    QuickAccessFolder folder,
    double cardSize,
  ) {
    final exists = Directory(folder.path).existsSync();
    final color = _getFolderColorByType(folder.type);

    return SizedBox(
      width: cardSize,
      height: cardSize,
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(12),
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
                  size: 24,
                  color: exists ? color : Colors.grey,
                ),
                const SizedBox(height: 1),
                Text(
                  folder.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: exists ? null : Colors.grey,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建"更多"卡片
  Widget _buildMoreCard(BuildContext context, double cardSize) {
    return SizedBox(
      key: _moreCardKey, // 添加key用于定位
      width: cardSize,
      height: cardSize,
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surface,
        child: InkWell(
          onTap: () => _showFolderMenu(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.more_horiz,
                  size: 24,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 1),
                Text(
                  '更多',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.1,
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
        if (path.contains('dcim') || path.contains('camera')) {
          return Icons.camera_alt;
        }
        if (path.contains('download')) return Icons.download;
        if (path.contains('picture') || path.contains('photo')) {
          return Icons.photo;
        }
        if (path.contains('document')) return Icons.description;
        if (path.contains('music')) return Icons.music_note;
        if (path.contains('movie') || path.contains('video')) {
          return Icons.video_library;
        }
        return Icons.folder_special;

      case QuickAccessFolderType.appRoot:
      case QuickAccessFolderType.appSubfolder:
        return Icons.apps;

      case QuickAccessFolderType.userCustom:
        return Icons.folder;
    }
  }

  /// 紧凑模式的存储信息显示（文字+进度条）
  Widget _buildStorageInfoCompact(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StoragePage(
              presenter: widget.filePresenter,
              viewModel: widget.fileViewModel,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storage,
                  size: 11,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 3),
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
            const SizedBox(height: 5),
            if (_loadingStorage)
              const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_totalSpace != null && _freeSpace != null) ...[
              // 进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: (_totalSpace! - _freeSpace!) / _totalSpace!,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getStorageColor(_freeSpace! / _totalSpace!),
                  ),
                  minHeight: 3,
                ),
              ),
              const SizedBox(height: 3),
              // 文字信息 - 使用FittedBox防止换行
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_formatStorageSize(_freeSpace!)} 可用',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '共 ${_formatStorageSize(_totalSpace!)}',
                  style: TextStyle(
                    fontSize: 8,
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else
              Text(
                '加载失败',
                style: TextStyle(fontSize: 9, color: Colors.grey[600]),
              ),
          ],
        ),
      ),
    );
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
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '可用',
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color
                                    ?.withValues(alpha: 0.6),
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
                      fontSize: 10,
                      color: Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              )
            else
              Text(
                '加载失败',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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

    // 导航到文件夹（标记为根导航，以便正确设置rootPath）
    widget.filePresenter.loadFiles(folder.path, isRootNavigation: true);

    // 切换到浏览Tab
    widget.fileViewModel.setCurrentTab(TabView.browse);
  }
}
