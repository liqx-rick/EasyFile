import 'dart:convert';
import 'dart:io';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/config/app_config.dart';
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
import 'package:easyfile/ui/pages/recommend_aggregate_page.dart';
import 'package:easyfile/ui/pages/archive_management_page.dart';
import 'package:easyfile/ui/pages/app_management_page.dart';
import 'package:easyfile/ui/pages/trash_page.dart';
import 'package:easyfile/ui/pages/file_browser_root_page.dart';
import 'package:easyfile/core/factories/recommend_page_config_factory.dart';
import 'package:easyfile/core/data_sources/data_source_factory.dart';

// 简单数据载体，供第二屏功能卡使用
class _QuickAction {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;
  final Color color;

  const _QuickAction({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.color,
    this.onTap,
  });
}

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
  final RecommendationService recommendationService;

  /// 全局Key用于从外部触发刷新（私有）
  static final GlobalKey<_QuickAccessSectionState> _globalKey =
      GlobalKey<_QuickAccessSectionState>();

  /// 公共的 globalKey getter（返回非泛型类型以避免暴露私有状态类）
  static GlobalKey<State<StatefulWidget>> get globalKey => _globalKey;

  /// 清除推荐卡片缓存（用于设置变更后强制重新加载）
  static void clearRecommendationCache() {
    _QuickAccessSectionState.clearCache();
  }

  /// 刷新推荐卡片（清除缓存并重新加载）
  static Future<void> refreshRecommendations() async {
    _QuickAccessSectionState.clearCache();
    await _globalKey.currentState?.refreshRecommendations();
  }

  const QuickAccessSection({
    super.key,
    required this.quickAccessViewModel,
    required this.quickAccessPresenter,
    required this.fileViewModel,
    required this.filePresenter,
    this.categoryCardSize = 0.0,
    required this.recommendationService,
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
  late bool _loadingRecommendations;

  // 分页控制
  late final PageController _pageController;
  int _currentPage = 0;

  // 静态缓存：在App同一会话中共享
  static List<RecommendationCard>? _cachedCards;
  static DateTime? _cacheTime;
  static const _cacheValidDuration = Duration(minutes: 5); // 5分钟缓存，平衡性能与数据新鲜度

  // 持久化缓存key
  static const String _cacheKey = 'recommendation_cards_cache';
  static const String _cacheTimeKey = 'recommendation_cards_cache_time';

  // 构造时检查缓存（静态 + 持久化）
  _QuickAccessSectionState() {
    // 1. 先检查静态缓存（最快）
    final hasValidStaticCache = _cachedCards != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheValidDuration;

    if (hasValidStaticCache) {
      _recommendationCards = _cachedCards!;
      _loadingRecommendations = false;
      logger.d('🎯 构造时命中静态缓存 (${_cachedCards!.length}个卡片)');
      return;
    }

    // 2. 静态缓存无效，尝试同步读取持久化缓存
    _loadingRecommendations = _tryLoadPersistentCacheSync();

    if (!_loadingRecommendations) {
      logger.d('💾 构造时命中持久化缓存 (${_recommendationCards.length}个卡片)');
    } else {
      logger.d('⏳ 无有效缓存，将显示loading');
    }
  }

  /// 尝试同步读取持久化缓存（非阻塞）
  /// 返回: true=需要loading, false=已加载缓存
  bool _tryLoadPersistentCacheSync() {
    try {
      // 尝试从全局单例读取（如果SharedPreferences已初始化）
      // 注意：这里只是尝试，如果未初始化则跳过
      _loadPersistentCacheAsync(); // 异步加载
      return true; // 先显示loading，异步加载完成后更新
    } catch (e) {
      return true;
    }
  }

  /// 异步加载持久化缓存
  Future<void> _loadPersistentCacheAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_cacheKey);
      final cacheTimeMs = prefs.getInt(_cacheTimeKey);

      if (cacheJson != null && cacheTimeMs != null) {
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(cacheTimeMs);
        final cacheAge = DateTime.now().difference(cacheTime);

        if (cacheAge < _cacheValidDuration) {
          final List<dynamic> jsonList = jsonDecode(cacheJson);
          final cards = jsonList
              .map((json) => RecommendationCard.fromJson(json))
              .toList();

          if (mounted) {
            setState(() {
              _recommendationCards = cards;
              _loadingRecommendations = false;
              // 同步更新静态缓存
              _cachedCards = cards;
              _cacheTime = cacheTime;
            });
          }
          logger.i('✅ 加载持久化缓存成功 (${cards.length}个卡片, ${cacheAge.inSeconds}秒前)');
        } else {
          logger.d('🗑️ 持久化缓存已过期 (${cacheAge.inMinutes}分钟)');
        }
      }
    } catch (e) {
      logger.e('加载持久化缓存失败: $e');
    }
  }

  /// 保存到持久化缓存
  Future<void> _savePersistentCache(List<RecommendationCard> cards) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = cards.map((card) => card.toJson()).toList();
      final jsonString = jsonEncode(jsonList);

      await prefs.setString(_cacheKey, jsonString);
      await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);

      logger.d('💾 保存持久化缓存成功 (${cards.length}个卡片)');
    } catch (e) {
      logger.e('保存持久化缓存失败: $e');
    }
  }

  /// 内部清除缓存方法
  static void clearCache() {
    final hadCache = _cachedCards != null;
    final cardsCount = _cachedCards?.length ?? 0;
    _cachedCards = null;
    _cacheTime = null;
    logger.w('🔥 推荐卡片缓存已清除 (之前有缓存: $hadCache, $cardsCount个卡片)');

    // 同时清除持久化缓存
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(_cacheKey);
      prefs.remove(_cacheTimeKey);
      logger.d('🔥 持久化缓存已清除');
    }).catchError((e) {
      logger.e('清除持久化缓存失败: $e');
    });
  }

  @override
  void initState() {
    super.initState();
    _initServices();
    _initAnimation();
    _pageController = PageController();
    _loadStorageInfo();
    _loadRecommendations(); // 后台异步加载/刷新
    // 延迟加载避免在build期间触发setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadQuickAccessFolders();
      }
    });
  }

  void _initServices() {
    // 直接使用注入的服务（已在 FileBrowserPage 中初始化）
    _recommendationService = widget.recommendationService;
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

  /// 公开的刷新方法（供外部调用）
  Future<void> refreshRecommendations() async {
    logger.i('🔄 手动刷新推荐卡片...');
    if (mounted) {
      setState(() {
        _loadingRecommendations = true;
      });
    }

    try {
      // 调用 refreshRecommendations 强制重新扫描
      final cards = await _recommendationService.refreshRecommendations();
      if (mounted) {
        setState(() {
          _recommendationCards = cards;
          _loadingRecommendations = false;
          // 更新静态缓存
          _cachedCards = cards;
          _cacheTime = DateTime.now();
        });
        logger.d('✅ 推荐卡片刷新完成 (${cards.length}个)');
        // 保存到持久化缓存
        _savePersistentCache(cards);
      }
    } catch (e) {
      logger.e('刷新推荐卡片失败: $e');
      if (mounted) {
        setState(() {
          _loadingRecommendations = false;
        });
      }
    }
  }

  Future<void> _loadRecommendations() async {
    // 检查缓存是否有效
    final now = DateTime.now();
    final hasCache = _cachedCards != null && _cacheTime != null;
    final cacheAge = hasCache ? now.difference(_cacheTime!) : null;
    final cacheValid = hasCache && cacheAge! < _cacheValidDuration;

    logger.d(
        '📊 后台检查缓存: 有缓存=$hasCache, 缓存年龄=${cacheAge?.inSeconds}秒, 有效=$cacheValid');

    if (cacheValid) {
      // 缓存有效，如果UI已使用缓存则无需操作
      if (_recommendationCards.isNotEmpty) {
        logger.d('✅ 缓存有效且UI已渲染，跳过加载');
        return;
      }

      // UI未更新（理论上不会发生，因为initState已同步设置）
      if (mounted) {
        setState(() {
          _recommendationCards = _cachedCards!;
          _loadingRecommendations = false;
        });
      }
      logger.d('✅ 使用推荐卡片缓存 (${_cachedCards!.length}个)');
      return;
    }

    // 缓存失效或不存在，后台静默刷新
    // 🎯 关键：如果已有旧缓存数据在显示，不显示loading
    final hasOldCache = _cachedCards != null && _recommendationCards.isNotEmpty;
    logger.d('🔄 后台加载推荐卡片... (静默刷新: $hasOldCache)');

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
        // 保存到持久化缓存
        _savePersistentCache(cards);
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
    _pageController.dispose();
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
          const indicatorHeight = 14.0;
          final totalHeight = widget.categoryCardSize * 2 + spacing + indicatorHeight;

          return SizedBox(
            height: totalHeight,
            child: Stack(
              children: [
                PageView(
                  controller: _pageController,
                  physics: const PageScrollPhysics(),
                  onPageChanged: (index) {
                    if (mounted) {
                      setState(() {
                        _currentPage = index;
                      });
                    }
                  },
                  children: [
                    _buildFirstPage(
                        context, availableWidth, isSmallScreen, spacing),
                    _buildSecondPage(
                        context, availableWidth, isSmallScreen, spacing),
                  ],
                ),
                Positioned(
                  right: 8,
                  bottom: 0,
                  child: Row(
                    children: List.generate(2, (index) {
                      final isActive = _currentPage == index;
                      return Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.35),
                        ),
                      );
                    }),
                  ),
                ),
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
    final cardWidth = (availableWidth - spacing * 4) / 3; // 4条间距（开头+中间2个+结尾）
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

  /// 构建第2页：固定3x2网格（功能入口）
  Widget _buildSecondPage(
    BuildContext context,
    double availableWidth,
    bool isSmallScreen,
    double spacing,
  ) {
    final cardWidth = (availableWidth - spacing * 4) / 3;
    final cardHeight = widget.categoryCardSize;

    final actions = _buildSecondPageActions();

    Widget buildSlot(int index) {
      if (index >= actions.length) {
        return _buildDisabledPlaceholderCard(cardWidth, cardHeight);
      }
      final action = actions[index];
      return _buildActionCard(
        context,
        cardWidth,
        cardHeight,
        action,
        isSmallScreen,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(width: spacing),
              buildSlot(0),
              SizedBox(width: spacing),
              buildSlot(1),
              SizedBox(width: spacing),
              buildSlot(2),
              SizedBox(width: spacing),
            ],
          ),
          SizedBox(height: spacing),
          Row(
            children: [
              SizedBox(width: spacing),
              buildSlot(3),
              SizedBox(width: spacing),
              buildSlot(4),
              SizedBox(width: spacing),
              buildSlot(5),
              SizedBox(width: spacing),
            ],
          ),
        ],
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
    final iconSize = (cardHeight * 0.70).clamp(30.0, 60.0);
    final fontSize = (cardHeight * 0.20).clamp(12.0, 20.0);

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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                // 左侧：应用图标
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
                const SizedBox(width: 8),
                // 右侧：应用名称
                Expanded(
                  child: Text(
                    card.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
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

  /// 构建功能入口卡片（第二屏）
  Widget _buildActionCard(
    BuildContext context,
    double cardWidth,
    double cardHeight,
    _QuickAction action,
    bool isSmallScreen,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconSize = (cardHeight * 0.60).clamp(30.0, 60.0);
    final fontSize = (cardHeight * 0.20).clamp(12.0, 20.0);

    final colors = isDark
        ? [
            Colors.white.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.06)
          ]
        : [Colors.white, const Color(0xFFF8F9FA)];

    return Opacity(
      opacity: action.enabled ? 1.0 : 0.55,
      child: SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: action.enabled ? action.onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // 左侧：图标
                  Icon(
                    action.icon,
                    size: iconSize,
                    color: action.color,
                  ),
                  const SizedBox(width: 8),
                  // 右侧：文字标签
                  Expanded(
                    child: Text(
                      action.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isSmallScreen ? fontSize - 1 : fontSize,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDisabledPlaceholderCard(double cardWidth, double cardHeight) {
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
    );
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

    // 根据推荐卡片生成页面配置
    final config = RecommendPageConfigFactory.fromRecommendationCard(card);

    // 创建必要的服务依赖
    final detectionService = AppDetectionService();
    final scanner = UnifiedAppScanner(detectionService);

    // 创建数据源工厂（注入依赖）
    final dataSourceFactory = DataSourceFactory(
      scanner: scanner,
      detectionService: detectionService,
      presenter: widget.filePresenter,
    );

    // 跳转到统一的推荐聚合页面（方案A：无需等待返回值）
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecommendAggregatePage(
          config: config,
          dataSourceFactory: dataSourceFactory,
          viewModel: widget.fileViewModel,
          presenter: widget.filePresenter,
        ),
      ),
    );

    // 方案A优化：卡片无统计数据，详情页返回无需刷新
    logger.d('详情页返回（卡片无需刷新）');
  }

  List<_QuickAction> _buildSecondPageActions() {
    const restoredPath = '/storage/emulated/0/EasyFile/Restored';
    final feature = AppConfig.instance.feature;

    bool restoredExists = false;
    try {
      final dir = Directory(restoredPath);
      restoredExists = dir.existsSync() && dir.listSync().isNotEmpty;
    } catch (_) {
      restoredExists = false;
    }

    return [
      _QuickAction(
        label: '压缩包管理',
        icon: Icons.archive_outlined,
        enabled: true,
        color: Colors.orange,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const ArchiveManagementPage(),
            ),
          );
        },
      ),
      _QuickAction(
        label: '回收站',
        icon: Icons.delete_outline,
        enabled: feature.isTrashEnabled,
        color: Colors.red,
        onTap: feature.isTrashEnabled
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => TrashPage(),
                  ),
                );
              }
            : null,
      ),
      _QuickAction(
        label: '文件恢复区',
        icon: Icons.restore_page,
        enabled: restoredExists,
        color: Colors.green,
        onTap: restoredExists
            ? () async {
                // 打开文件浏览器页面并指定初始路径
                final shouldReturnToSecondPage = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (context) => FileBrowserRootPage(
                      presenter: widget.filePresenter,
                      viewModel: widget.fileViewModel,
                      initialPath: restoredPath,
                      returnToSecondPage: true,
                    ),
                  ),
                );
                
                // 如果返回时标记要跳转到第二页，则切换到第二页
                if (shouldReturnToSecondPage == true && mounted) {
                  _pageController.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              }
            : null,
      ),
      _QuickAction(
        label: '应用管理',
        icon: Icons.apps,
        enabled: feature.isAppManagementEnabled,
        color: Colors.blue,
        onTap: feature.isAppManagementEnabled
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AppManagementPage(),
                  ),
                );
              }
            : null,
      ),
      _QuickAction(
        label: '安装包管理',
        icon: Icons.file_download_done,
        enabled: false,
        color: Colors.deepPurple,
        onTap: null,
      ),
      _QuickAction(
        label: '敬请期待',
        icon: Icons.more_horiz,
        enabled: false,
        color: Colors.grey,
        onTap: null,
      ),
    ];
  }
}
