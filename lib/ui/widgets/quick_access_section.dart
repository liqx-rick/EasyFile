import 'dart:io';
import 'package:flutter/material.dart';
import 'package:disk_space_plus/disk_space_plus.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';
import 'package:easyfile/viewmodel/quick_access_viewmodel.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/ui/widgets/files_browse_card.dart';
import 'package:easyfile/ui/widgets/storage_management_card.dart';

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
        // 按优先级排序：文档 > 图片 > 音乐 > 视频 > DCIM/相机 > 其他（排除Download，因为分类中已有）
        systemFolders.sort((a, b) {
          int getPriority(QuickAccessFolder folder) {
            final path = folder.path.toLowerCase();
            // Download优先级最低，避免与分类重复
            if (path.contains('download')) return 99;
            if (path.contains('document')) return 1;
            if (path.contains('picture') || path.contains('photo')) return 2;
            if (path.contains('music')) return 3;
            if (path.contains('movie') || path.contains('video')) return 4;
            if (path.contains('dcim') || path.contains('camera')) return 5;
            return 98; // 其他
          }

          return getPriority(a).compareTo(getPriority(b));
        });

        // 选择优先级最高的前4个（排除Download）
        displayFoldersForHome = systemFolders
            .where((f) => !f.path.toLowerCase().contains('download'))
            .take(4)
            .toList();
      }
    }

    if (displayFoldersForHome.isEmpty) {
      return const SizedBox.shrink();
    }

    // 检查是否有快速访问列表（不在首页推荐中的）
    final hasQuickAccessList = folders.any(
      (f) => f.isAddedToQuickAccess && f.homeDisplayOrder == null,
    );

    // 计算实际显示数量（包含"更多"按钮）
    final totalDisplayCount =
        displayFoldersForHome.length + (hasQuickAccessList ? 1 : 0);

    // 根据推荐数量决定布局模式：
    // 1个：特殊单按钮模式（与存储空间1:1）
    // 2-3个：单行模式
    // 4-6个：双行模式
    final isSingleButtonMode = totalDisplayCount == 1;
    final isCompactMode = totalDisplayCount >= 2 && totalDisplayCount <= 3;
    final isDoubleRowMode = totalDisplayCount >= 4;

    // 调试信息
    logger.d(
      'QuickAccessSection: folders=${displayFoldersForHome.length}, hasMore=$hasQuickAccessList, total=$totalDisplayCount, single=$isSingleButtonMode, compact=$isCompactMode, double=$isDoubleRowMode',
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 计算快速访问区域高度（基于分类图片高度）
          final screenWidth = MediaQuery.of(context).size.width;
          final isSmallScreen = screenWidth < 360;

          // 根据模式计算快速访问区域实际高度
          double quickAccessHeight;
          if (isSingleButtonMode || isCompactMode) {
            // 单行模式：高度=分类图片高度
            quickAccessHeight = widget.categoryCardSize;
          } else {
            // 双行模式：高度=分类图片高度×2 + 行间距 + 底部间距
            final spacing = isSmallScreen ? 2.0 : 3.0;
            quickAccessHeight = widget.categoryCardSize * 2 + spacing + 3.0;
          }

          // 动态计算flex比例，使所有卡片宽度一致
          // flex比例决定了快速访问区域和功能卡片区域的宽度分配
          int quickAccessFlex;
          int functionCardsFlex;
          
          if (isSingleButtonMode) {
            // 单按钮模式：1个快速访问按钮 + 2个功能卡片并排 = 1:2
            quickAccessFlex = 1;
            functionCardsFlex = 2;
          } else if (isCompactMode) {
            // 单行模式：2-3个快速访问按钮 + 2个功能卡片并排
            // flex比例 = 快速访问数量:2（例如2:2=1:1，3:2）
            quickAccessFlex = totalDisplayCount;
            functionCardsFlex = 2;
          } else {
            // 双行模式：4-6个快速访问按钮 + 2个功能卡片上下排列
            // 固定比例2:1（功能卡片较窄，因为上下排列占用更多纵向空间）
            quickAccessFlex = 2;
            functionCardsFlex = 1;
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 快速访问区域 - 根据模式调整比例
              Expanded(
                flex: quickAccessFlex,
                child: _buildQuickAccessCards(
                  context,
                  displayFoldersForHome,
                  isSingleButtonMode,
                  isCompactMode,
                  isDoubleRowMode,
                ),
              ),

              // 分隔线区域 - 高度自适应
              SizedBox(
                width: 8,
                child: Center(
                  child: Container(
                    width: 1,
                    height: quickAccessHeight,
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

              // 功能卡片区域 - 根据模式调整比例和显示
              Expanded(
                flex: functionCardsFlex,
                child: SizedBox(
                  height: quickAccessHeight, // 固定高度以匹配快速访问区域
                  child: _buildFunctionCards(
                      context, isCompactMode || isSingleButtonMode),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickAccessCards(
    BuildContext context,
    List<QuickAccessFolder> homeFolders,
    bool isSingleButtonMode,
    bool isCompactMode,
    bool isDoubleRowMode,
  ) {
    // 检查是否有快速访问列表
    final hasQuickAccessList = widget.quickAccessViewModel.folders.any(
      (f) => f.isAddedToQuickAccess && f.homeDisplayOrder == null,
    );

    logger.d(
      '_buildQuickAccessCards: single=$isSingleButtonMode, compact=$isCompactMode, double=$isDoubleRowMode, folders=${homeFolders.length}, hasMore=$hasQuickAccessList',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        // 根据屏幕宽度确定设备类型和尺寸参数
        final screenWidth = MediaQuery.of(context).size.width;
        final isSmallScreen = screenWidth < 360; // 小屏手机

        if (isSingleButtonMode) {
          // 单按钮模式：1个按钮填充整个左半部区域（与存储按钮1:1）
          // 高度固定为分类图片高度，宽度填充可用空间
          final minSpacing = isSmallScreen ? 2.0 : 3.0;

          // 宽度=可用空间，左右各留少量间距
          final cardWidth = availableWidth - minSpacing * 2;

          return Row(
            children: [
              SizedBox(width: minSpacing),
              _buildFolderCard(context, homeFolders[0], cardWidth,
                  widget.categoryCardSize, isSmallScreen),
              SizedBox(width: minSpacing),
            ],
          );
        } else if (isCompactMode) {
          // 单行模式：2-3个按钮
          // 高度固定为分类图片高度，宽度根据数量平均分配
          final totalCards = homeFolders.length + (hasQuickAccessList ? 1 : 0);

          final minSpacing = isSmallScreen ? 2.0 : 3.0;

          // 2个或3个卡片：平均分配宽度
          // 计算方式：(总宽度 - 所有间距) / 卡片数量
          final cardWidth =
              (availableWidth - (totalCards + 1) * minSpacing) / totalCards;

          final totalCardWidth = cardWidth * totalCards;
          final availableSpace = availableWidth - totalCardWidth;
          final spacing = (availableSpace / (totalCards + 1))
              .clamp(minSpacing, minSpacing * 2);

          return Row(
            children: [
              SizedBox(width: spacing),
              for (int i = 0; i < homeFolders.length; i++) ...[
                _buildFolderCard(context, homeFolders[i], cardWidth,
                    widget.categoryCardSize, isSmallScreen),
                SizedBox(width: spacing),
              ],
              if (hasQuickAccessList) ...[
                _buildMoreCard(
                    context, cardWidth, widget.categoryCardSize, isSmallScreen),
                SizedBox(width: spacing),
              ],
            ],
          );
        } else {
          // 双行模式：4-6个按钮
          // 高度固定为分类图片高度，宽度根据数量和行数动态分配
          final maxFolders = hasQuickAccessList ? 5 : 6;
          final displayFolders = homeFolders.take(maxFolders).toList();
          final totalCards =
              displayFolders.length + (hasQuickAccessList ? 1 : 0);

          final minSpacing = isSmallScreen ? 2.0 : 3.0;

          // 根据总卡片数决定每行布局
          int firstRowCount;
          int secondRowCount;
          double firstRowCardWidth;
          double secondRowCardWidth;

          if (totalCards == 4) {
            // 4个卡片：2行2列，各占1/2
            firstRowCount = 2;
            secondRowCount = 2;
            firstRowCardWidth = (availableWidth - 3 * minSpacing) / 2;
            secondRowCardWidth = firstRowCardWidth;
          } else if (totalCards == 5) {
            // 5个卡片：第一行2个（各占1/2），第二行3个（各占1/3）
            firstRowCount = 2;
            secondRowCount = 3;
            firstRowCardWidth = (availableWidth - 3 * minSpacing) / 2;
            secondRowCardWidth = (availableWidth - 4 * minSpacing) / 3;
          } else {
            // 6个卡片：2行3列，各占1/3
            firstRowCount = 3;
            secondRowCount = 3;
            firstRowCardWidth = (availableWidth - 4 * minSpacing) / 3;
            secondRowCardWidth = firstRowCardWidth;
          }

          final spacing = minSpacing;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行
              Row(
                children: [
                  SizedBox(width: spacing),
                  for (int i = 0;
                      i < firstRowCount && i < displayFolders.length;
                      i++) ...[
                    _buildFolderCard(
                        context,
                        displayFolders[i],
                        firstRowCardWidth,
                        widget.categoryCardSize,
                        isSmallScreen),
                    SizedBox(width: spacing),
                  ],
                  if (firstRowCount >= displayFolders.length &&
                      hasQuickAccessList) ...[
                    _buildMoreCard(context, firstRowCardWidth,
                        widget.categoryCardSize, isSmallScreen),
                    SizedBox(width: spacing),
                  ],
                ],
              ),
              if (secondRowCount > 0) ...[
                SizedBox(height: spacing),
                // 第二行
                Row(
                  children: [
                    SizedBox(width: spacing),
                    for (int i = firstRowCount;
                        i < displayFolders.length;
                        i++) ...[
                      _buildFolderCard(
                          context,
                          displayFolders[i],
                          secondRowCardWidth,
                          widget.categoryCardSize,
                          isSmallScreen),
                      SizedBox(width: spacing),
                    ],
                    if (displayFolders.length >= firstRowCount &&
                        hasQuickAccessList) ...[
                      _buildMoreCard(context, secondRowCardWidth,
                          widget.categoryCardSize, isSmallScreen),
                      SizedBox(width: spacing),
                    ],
                  ],
                ),
                const SizedBox(height: 3), // 增加底部间距
              ],
            ],
          );
        }
      },
    );
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

  /// 构建文件夹卡片（宽度动态调整，高度固定为分类图片高度）
  Widget _buildFolderCard(
    BuildContext context,
    QuickAccessFolder folder,
    double cardWidth,
    double cardHeight,
    bool isSmallScreen,
  ) {
    final exists = Directory(folder.path).existsSync();
    final color = _getFolderColorByType(folder.type);

    // 检查是否被选中（当前路径是否在此文件夹内）
    final currentPath = widget.fileViewModel.currentPath;
    final isSelected = currentPath == folder.path ||
        (currentPath.isNotEmpty &&
            currentPath.startsWith(folder.path + Platform.pathSeparator));

    // 根据卡片高度动态调整图标和文字大小
    final iconSize = (cardHeight * 0.35).clamp(18.0, 28.0);
    final fontSize = isSmallScreen ? 10.0 : (cardHeight > 60 ? 12.0 : 11.0);

    // 统一的首页推荐背景色 - 适配深色/浅色主题
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isSelected
        ? Theme.of(context).colorScheme.primaryContainer // 选中时高亮背景
        : (isDark
            ? Colors.white.withValues(alpha: 0.08) // 深色模式：8%白色透明度
            : const Color(0xFFF5F5F5)); // 浅色模式：浅灰色背景

    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: Material(
        elevation: isSelected ? 4 : 2,
        borderRadius: BorderRadius.circular(12),
        color: backgroundColor,
        child: InkWell(
          onTap: exists ? () => _navigateToFolder(folder) : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getFolderIcon(folder),
                  size: iconSize,
                  color: exists
                      ? (isSelected
                          ? Theme.of(context).colorScheme.primary
                          : color)
                      : Colors.grey,
                ),
                SizedBox(height: cardHeight * 0.02),
                Text(
                  folder.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: exists
                        ? (isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null)
                        : Colors.grey,
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
  /// 构建"更多"卡片（宽度动态调整，高度固定为分类图片高度）
  Widget _buildMoreCard(
    BuildContext context,
    double cardWidth,
    double cardHeight,
    bool isSmallScreen,
  ) {
    // 检查当前路径是否在快速访问列表中（但不在首页推荐中）
    final currentPath = widget.fileViewModel.currentPath;
    final folders = widget.quickAccessViewModel.folders;

    final isMoreSelected = folders.any((f) =>
        f.isAddedToQuickAccess &&
        f.homeDisplayOrder == null &&
        (currentPath == f.path ||
            (currentPath.isNotEmpty &&
                currentPath.startsWith(f.path + Platform.pathSeparator))));

    // 根据卡片高度动态调整图标和文字大小
    final iconSize = (cardHeight * 0.35).clamp(18.0, 28.0);
    final fontSize = isSmallScreen ? 10.0 : (cardHeight > 60 ? 12.0 : 11.0);

    // "更多"按钮使用不同的背景色 - 适配深色/浅色主题
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isMoreSelected
        ? Theme.of(context).colorScheme.secondaryContainer // 选中时高亮
        : (isDark
            ? Colors.deepPurple.withValues(alpha: 0.12) // 深色模式：12%深紫色透明度
            : const Color(0xFFE8EAF6)); // 浅色模式：浅紫色背景

    return SizedBox(
      key: _moreCardKey, // 添加key用于定位
      width: cardWidth,
      height: cardHeight,
      child: Material(
        elevation: isMoreSelected ? 4 : 2,
        borderRadius: BorderRadius.circular(12),
        color: backgroundColor,
        child: InkWell(
          onTap: () => _showFolderMenu(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.more_horiz,
                  size: iconSize,
                  color: isMoreSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                SizedBox(height: cardHeight * 0.02),
                Text(
                  '更多',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight:
                        isMoreSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isMoreSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
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

  /// 构建功能卡片区域（文件浏览卡片 + 存储管理卡片）
  /// 
  /// 根据快速访问按钮数量自动调整布局：
  /// - 单按钮模式：两个功能卡片并排显示（单行模式）
  /// - 多按钮模式：两个功能卡片上下排列（双行模式）
  /// 
  /// 参数：
  /// - [isCompactMode]: true为单行模式（并排显示），false为双行模式（上下排列）
  Widget _buildFunctionCards(BuildContext context, bool isCompactMode) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    
    // 计算单个卡片的可用高度，用于内部元素的动态尺寸计算
    double availableHeight;
    if (isCompactMode) {
      // 单行模式：卡片高度等于分类图片卡片高度
      availableHeight = widget.categoryCardSize;
    } else {
      // 双行模式：两个卡片平分总高度
      // 总高度 = 分类图片高度×2 + 间距
      // 单个卡片高度 = (总高度 - 卡片间间距) / 2 - 内边距
      final spacing = isSmallScreen ? 2.0 : 3.0;
      final totalHeight = widget.categoryCardSize * 2 + spacing + 3.0;
      final cardSpacing = 3.0;
      availableHeight = (totalHeight - cardSpacing) / 2 - 12;
    }

    if (isCompactMode) {
      // 单行模式：两个卡片并排显示
      return Row(
        children: [
          Expanded(
            child: FilesBrowseCard(
              totalSpace: _totalSpace,
              freeSpace: _freeSpace,
              isLoading: _loadingStorage,
              presenter: widget.filePresenter,
              viewModel: widget.fileViewModel,
              isCompactMode: isCompactMode,
              availableHeight: availableHeight,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: StorageManagementCard(
              isCompactMode: isCompactMode,
              availableHeight: availableHeight,
            ),
          ),
        ],
      );
    } else {
      // 双行模式：两个卡片上下排列
      return Column(
        children: [
          Expanded(
            child: FilesBrowseCard(
              totalSpace: _totalSpace,
              freeSpace: _freeSpace,
              isLoading: _loadingStorage,
              presenter: widget.filePresenter,
              viewModel: widget.fileViewModel,
              isCompactMode: isCompactMode,
              availableHeight: availableHeight,
            ),
          ),
          const SizedBox(height: 3),
          Expanded(
            child: StorageManagementCard(
              isCompactMode: isCompactMode,
              availableHeight: availableHeight,
            ),
          ),
        ],
      );
    }
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
