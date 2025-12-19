import 'package:flutter/material.dart';
import 'package:disk_space_plus/disk_space_plus.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/data/models/recommendation_card.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';
import 'package:easyfile/viewmodel/quick_access_viewmodel.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/ui/widgets/files_browse_card.dart';
import 'package:easyfile/ui/widgets/storage_management_card.dart';
import 'package:easyfile/core/services/recommendation_service.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/ui/pages/recommendation_detail_page.dart';

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

  /// 推荐服务（可选注入，如果不提供则使用默认实现）
  final RecommendationService? recommendationService;

  /// 清除推荐卡片缓存（用于设置变更后强制重新加载）
  static void clearRecommendationCache() {
    _QuickAccessSectionState.clearCache();
  }

  const QuickAccessSection({
    super.key,
    required this.quickAccessViewModel,
    required this.quickAccessPresenter,
    required this.fileViewModel,
    required this.filePresenter,
    this.categoryCardSize = 0.0,
    this.recommendationService,
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

  // 推荐卡片
  late RecommendationService _recommendationService;
  List<RecommendationCard> _recommendationCards = [];
  bool _loadingRecommendations = true;

  // 静态缓存：避免每次rebuild都显示loading
  static List<RecommendationCard>? _cachedCards;
  static DateTime? _cacheTime;
  static const _cacheValidDuration = Duration(minutes: 5); // 5分钟缓存

  /// 内部清除缓存方法
  static void clearCache() {
    final hadCache = _cachedCards != null;
    final cardsCount = _cachedCards?.length ?? 0;
    _cachedCards = null;
    _cacheTime = null;
    logger.w('🔥 推荐卡片缓存已清除 (之前有缓存: $hadCache, $cardsCount个卡片)');
  }

  @override
  void initState() {
    super.initState();
    _initServices();
    _initAnimation();
    _loadStorageInfo();
    _loadRecommendations();
    // 延迟加载避免在build期间触发setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadQuickAccessFolders();
      }
    });
  }

  void _initServices() {
    // 使用注入的服务或创建默认实例（兼容旧代码）
    _recommendationService =
        widget.recommendationService ?? _createDefaultRecommendationService();
  }

  /// 创建默认推荐服务（无缓存优化）
  ///
  /// 注意：此方法仅用于向后兼容，实际使用时应注入已初始化的服务
  /// TODO: 在应用启动时初始化服务并注入
  RecommendationService _createDefaultRecommendationService() {
    logger.w('使用默认推荐服务（无缓存优化），建议注入已初始化的服务');

    // 创建未初始化的服务（会降低性能）
    final detectionService = AppDetectionService();
    final scanner = UnifiedAppScanner(detectionService);

    return RecommendationService(
      detectionService: detectionService,
      scanner: scanner,
    );
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

  Future<void> _loadRecommendations() async {
    // 检查缓存是否有效
    final now = DateTime.now();
    final hasCache = _cachedCards != null && _cacheTime != null;
    final cacheAge = hasCache ? now.difference(_cacheTime!) : null;
    final cacheValid = hasCache && cacheAge! < _cacheValidDuration;
    
    logger.d('📊 缓存检查: 有缓存=$hasCache, 缓存年龄=${cacheAge?.inSeconds}秒, 有效=$cacheValid');
    
    if (cacheValid) {
      // 使用缓存，立即显示，无loading
      if (mounted) {
        setState(() {
          _recommendationCards = _cachedCards!;
          _loadingRecommendations = false;
        });
      }
      logger.d('✅ 使用推荐卡片缓存 (${_cachedCards!.length}个)');
      return;
    }

    // 缓存失效或不存在，重新加载
    logger.d('🔄 重新加载推荐卡片...');
    try {
      final cards = await _recommendationService.getRecommendations();
      if (mounted) {
        setState(() {
          _recommendationCards = cards;
          _loadingRecommendations = false;
          // 更新静态缓存
          _cachedCards = cards;
          _cacheTime = DateTime.now();
        });
        logger.d('✅ 推荐卡片加载完成，已更新缓存 (${cards.length}个)');
      }
    } catch (e) {
      logger.e('Failed to load recommendations: $e');
      if (mounted) {
        setState(() {
          _loadingRecommendations = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 固定3x2网格布局（6个位置：4个推荐卡片 + 2个功能卡片）
    // 推荐卡片数据准备暂时保留占位符，后续填充

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 使用 constraints.maxWidth 而不是 MediaQuery.of(context).size.width
          // 这样在横屏模式下会使用左侧栏的宽度，而不是整个屏幕宽度
          final availableWidth = constraints.maxWidth;
          final isSmallScreen = availableWidth < 360;

          // 固定高度：分类图片高度 × 2 + 行间距
          final spacing = isSmallScreen ? 3.0 : 4.0;
          final totalHeight = widget.categoryCardSize * 2 + spacing;

          return SizedBox(
            height: totalHeight,
            child: PageView(
              physics: const NeverScrollableScrollPhysics(), // 禁用滑动（预留未来多页功能）
              children: [
                _buildFirstPage(
                    context, availableWidth, isSmallScreen, spacing),
                // 第2页预留（暂不实现）
                _buildSecondPagePlaceholder(),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 构建第1页：固定3x2网格（4推荐 + 2功能）
  /// 布局：1:1:1（等比例）
  /// [推荐1] [推荐2] [功能1-浏览]
  /// [推荐3] [推荐4] [功能2-存储]
  Widget _buildFirstPage(
    BuildContext context,
    double availableWidth,
    bool isSmallScreen,
    double spacing,
  ) {
    // 计算卡片尺寸 - 等比例
    // 使用 availableWidth（容器可用宽度）而不是屏幕宽度
    // 这样在横屏模式下会基于左侧栏宽度计算，确保卡片尺寸合适
    final cardWidth =
        (availableWidth - spacing * 4) / 3; // 4条间距（开头+中间2个+结尾）
    final cardHeight = widget.categoryCardSize;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: Column(
        children: [
          // 第一行：推荐1, 推荐2, 功能1
          Row(
            children: [
              SizedBox(width: spacing),
              _buildRecommendationCard(
                  context, cardWidth, cardHeight, 0, isSmallScreen),
              SizedBox(width: spacing),
              _buildRecommendationCard(
                  context, cardWidth, cardHeight, 1, isSmallScreen),
              SizedBox(width: spacing),
              _buildFunctionCard(
                context,
                cardWidth,
                cardHeight,
                isBrowseCard: true,
              ),
              SizedBox(width: spacing),
            ],
          ),
          SizedBox(height: spacing),
          // 第二行：推荐3, 推荐4, 功能2
          Row(
            children: [
              SizedBox(width: spacing),
              _buildRecommendationCard(
                  context, cardWidth, cardHeight, 2, isSmallScreen),
              SizedBox(width: spacing),
              _buildRecommendationCard(
                  context, cardWidth, cardHeight, 3, isSmallScreen),
              SizedBox(width: spacing),
              _buildFunctionCard(
                context,
                cardWidth,
                cardHeight,
                isBrowseCard: false,
              ),
              SizedBox(width: spacing),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建第2页占位符（预留多页滑动能力）
  Widget _buildSecondPagePlaceholder() {
    return Container(
      alignment: Alignment.center,
      child: Text(
        '第2页预留',
        style: TextStyle(color: Colors.grey[400], fontSize: 12),
      ),
    );
  }

  /// 构建推荐卡片（支持加载状态、空状态、真实卡片）
  Widget _buildRecommendationCard(
    BuildContext context,
    double cardWidth,
    double cardHeight,
    int index,
    bool isSmallScreen,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 加载中
    if (_loadingRecommendations) {
      return Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.06)
                  ]
                : [Colors.white, const Color(0xFFF8F9FA)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
            ),
          ),
        ),
      );
    }

    // 无卡片（超出范围）
    if (index >= _recommendationCards.length) {
      return Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0.04)
                  ]
                : [const Color(0xFFF8F9FA), const Color(0xFFF0F0F0)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            Icons.folder_outlined,
            size: (cardHeight * 0.35).clamp(18.0, 28.0),
            color: Colors.grey[300],
          ),
        ),
      );
    }

    // 真实推荐卡片
    final card = _recommendationCards[index];
    final iconSize = (cardHeight * 0.47).clamp(26.0, 36.0);
    final fontSize = (cardHeight * 0.16).clamp(10.0, 14.0);

    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.06)
                ]
              : [Colors.white, const Color(0xFFF8F9FA)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _navigateToRecommendation(card),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 左侧：应用图标 + 名称（上下排列）
                Expanded(
                  flex: 13,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 应用图标
                      if (card.appIcon != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(iconSize * 0.2),
                          child: Image.memory(
                            card.appIcon!,
                            width: iconSize,
                            height: iconSize,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                card.icon,
                                size: iconSize,
                                color: card.color,
                              );
                            },
                          ),
                        )
                      else
                        Icon(
                          card.icon,
                          size: iconSize,
                          color: card.color,
                        ),
                      // 应用名称
                      Text(
                        card.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                // 右侧：数据统计（数量和大小上下排列）
                Expanded(
                  flex: 10,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 文件数量
                      Text(
                        '${card.fileCount}个',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      // 总大小
                      Text(
                        _formatSize(card.totalSize ?? 0),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建单个功能卡片（固定尺寸，嵌入3x2网格）
  ///
  /// 参数：
  /// - [isBrowseCard]: true=文件浏览卡片，false=存储管理卡片
  Widget _buildFunctionCard(
    BuildContext context,
    double cardWidth,
    double cardHeight, {
    required bool isBrowseCard,
  }) {
    final availableHeight = cardHeight;

    if (isBrowseCard) {
      return SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: FilesBrowseCard(
          totalSpace: _totalSpace,
          freeSpace: _freeSpace,
          isLoading: _loadingStorage,
          presenter: widget.filePresenter,
          viewModel: widget.fileViewModel,
          isCompactMode: true, // 固定使用紧凑模式
          availableHeight: availableHeight,
        ),
      );
    } else {
      return SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: StorageManagementCard(
          isCompactMode: true, // 固定使用紧凑模式
          availableHeight: availableHeight,
        ),
      );
    }
  }

  // 此方法保留用于未来可能的快捷访问导航功能
  // ignore: unused_element
  void _navigateToFolder(QuickAccessFolder folder) {
    // 更新访问时间
    widget.quickAccessPresenter.updateAccessInfo(folder.path);

    // 导航到文件夹（标记为根导航，以便正确设置rootPath）
    widget.filePresenter.loadFiles(folder.path, isRootNavigation: true);

    // 切换到浏览Tab
    widget.fileViewModel.setCurrentTab(TabView.browse);
  }

  void _navigateToRecommendation(RecommendationCard card) {
    logger.d('导航到推荐详情: ${card.title}');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecommendationDetailPage(card: card),
      ),
    );
  }

  /// 格式化文件大小
  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}K';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}M';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
  }
}
