import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/models/duplicate_file_scan_config.dart';
import 'package:easyfile/core/models/large_file_scan_config.dart';
import 'package:easyfile/core/services/cache_manager_service.dart';
import 'package:easyfile/core/services/duplicate_file_service.dart';
import 'package:easyfile/core/services/file_display_settings_service.dart';
import 'package:easyfile/core/services/enhanced_duplicate_file_scan_service.dart';
import 'package:easyfile/core/services/large_file_cache_manager.dart';
import 'package:easyfile/core/services/large_file_service.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/ui/pages/category_file_page.dart'
    hide FileTypeFilter;
import 'package:easyfile/ui/pages/duplicate_files_page.dart';
import 'package:easyfile/ui/pages/large_files_page.dart';
import 'package:easyfile/ui/pages/junk_files_page.dart';
import 'package:easyfile/ui/pages/app_management_page.dart';

import 'package:easyfile/ui/widgets/large_file_scan_config_dialog.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/utils/file_size_formatter.dart';

/// 存储管理页面
/// 用于管理应用缓存和临时文件
class StorageManagementPage extends StatefulWidget {
  const StorageManagementPage({super.key});

  @override
  State<StorageManagementPage> createState() => _StorageManagementPageState();
}

class _StorageManagementPageState extends State<StorageManagementPage> {
  // 存储空间数据
  double? _totalSpace; // MB
  double? _freeSpace; // MB
  bool _loadingStorage = true;

  // 分类文件大小数据（单位：字节）
  final Map<CategoryType, int> _categorySizes = {
    CategoryType.images: 0,
    CategoryType.video: 0,
    CategoryType.documents: 0,
    CategoryType.music: 0,
  };

  // 记录哪些分类正在加载
  final Map<CategoryType, bool> _loadingCategories = {
    CategoryType.images: true,
    CategoryType.video: true,
    CategoryType.documents: true,
    CategoryType.music: true,
  };

  // 缓存key
  static const String _cacheKeyCategorySizes = 'storage_category_sizes';

  // 大文件扫描配置缓存（用于显示最新配置）
  LargeFileScanConfig? _cachedLargeFileScanConfig;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
    _loadCategorySizes();
    _loadLargeFileScanConfig();
  }

  /// 加载大文件扫描配置
  Future<void> _loadLargeFileScanConfig() async {
    try {
      final cacheManager = LargeFileCacheManager();
      final cache = await cacheManager.loadCache();

      if (mounted) {
        setState(() {
          _cachedLargeFileScanConfig = cache?.config;
        });
      }
    } catch (e) {
      logger.e('Failed to load large file scan config: $e');
    }
  }

  /// 加载存储空间信息（获取总容量和剩余空间）
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

  /// 加载分类文件大小
  /// 采用两阶段策略：
  /// 1. 先从缓存快速显示
  /// 2. 后台并行扫描更新真实数据
  Future<void> _loadCategorySizes() async {
    if (!mounted) return;

    await _loadCachedSizes();

    // 并行扫描所有分类更新数据
    try {
      final presenter = locator<FilePresenter>();

      // 并行加载所有分类
      final futures = CategoryType.values.map((categoryType) async {
        try {
          final files = await presenter.scanFilesByCategory(categoryType);
          final totalSize = files.fold<int>(
            0,
            (sum, file) => sum + file.size,
          );

          if (mounted) {
            setState(() {
              _categorySizes[categoryType] = totalSize;
              _loadingCategories[categoryType] = false;
            });
          }

          return MapEntry(categoryType, totalSize);
        } catch (e) {
          logger.e('Failed to load size for $categoryType: $e');
          if (mounted) {
            setState(() {
              _loadingCategories[categoryType] = false;
            });
          }
          return MapEntry(categoryType, 0);
        }
      });

      final results = await Future.wait(futures);

      // 3. 保存到缓存
      await _saveCachedSizes(Map.fromEntries(results));
    } catch (e) {
      logger.e('Failed to load category sizes: $e');
    }
  }

  /// 从SharedPreferences加载缓存的分类大小
  Future<void> _loadCachedSizes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKeyCategorySizes);

      if (cached != null) {
        final Map<String, dynamic> data = jsonDecode(cached);

        if (mounted) {
          setState(() {
            for (final entry in data.entries) {
              final categoryType = CategoryType.values.firstWhere(
                (t) => t.name == entry.key,
                orElse: () => CategoryType.images,
              );
              _categorySizes[categoryType] = entry.value as int;
              _loadingCategories[categoryType] = false;
            }
          });
        }

        logger.d('Loaded cached category sizes');
      }
    } catch (e) {
      logger.e('Failed to load cached sizes: $e');
    }
  }

  /// 保存分类大小到SharedPreferences
  Future<void> _saveCachedSizes(Map<CategoryType, int> sizes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, int>{};

      sizes.forEach((type, size) {
        data[type.name] = size;
      });

      await prefs.setString(_cacheKeyCategorySizes, jsonEncode(data));
      logger.d('Saved category sizes to cache');
    } catch (e) {
      logger.e('Failed to save cached sizes: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('存储管理'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. 存储空间概览
          _buildSectionTitle('存储空间概览', Icons.pie_chart_rounded, colorScheme),
          const SizedBox(height: 12),
          _buildStorageOverviewSection(theme, colorScheme),
          const SizedBox(height: 24),

          // 2. 文件清理
          if ((AppConfig.instance.feature.isJunkCleanupEnabled ||
              AppConfig.instance.feature.isLargeFilesEnabled ||
              AppConfig.instance.feature.isDuplicateFilesEnabled)) ...[
            _buildSectionTitle('文件清理', Icons.folder_outlined, colorScheme),
            const SizedBox(height: 12),
            // 垃圾文件清理
            if (AppConfig.instance.feature.isJunkCleanupEnabled) ...[
              _buildUnifiedCard(
                theme: theme,
                colorScheme: colorScheme,
                icon: Icons.delete_sweep,
                title: '垃圾文件清理',
                description: '清理APK安装包、临时文件、空文件夹',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const JunkFilesPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
            // 大文件·快速扫描
            if (AppConfig.instance.feature.isLargeFilesEnabled) ...[
              _buildUnifiedCard(
                theme: theme,
                colorScheme: colorScheme,
                icon: Icons.search,
                title: '大文件·快速扫描',
                description: '全面扫描所有大于 ${AppConfig.instance.fileScan.largeFileThreshold}MB 的文件',
                isRecommended: true,
                onTap: () {
                  final presenter = locator<FilePresenter>();
                  final largeFileService = LargeFileService(presenter);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => LargeFilesPage(
                        largeFileService: largeFileService,
                        initialConfig: LargeFileScanConfig.fromFileScanConfig(
                            AppConfig.instance.fileScan),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
            // 大文件·自定义扫描
            if (AppConfig.instance.feature.isLargeFilesEnabled) ...[
              _buildUnifiedCard(
                theme: theme,
                colorScheme: colorScheme,
                icon: Icons.tune,
                title: '大文件·自定义扫描',
                description: _cachedLargeFileScanConfig != null
                    ? _formatScanConfig(_cachedLargeFileScanConfig!)
                    : '自定义类型 · >${AppConfig.instance.fileScan.largeFileThreshold}MB',
                onTap: () async {
                  final navigator = Navigator.of(context);
                  final cacheManager = LargeFileCacheManager();
                  final cache = await cacheManager.loadCache();
                  if (!mounted) return;
                  
                  final currentConfig = cache?.config ??
                      LargeFileScanConfig.fromFileScanConfig(
                          AppConfig.instance.fileScan);
                  
                  // ignore: use_build_context_synchronously
                  final newConfig = await LargeFileScanConfigDialog.show(
                    context,
                    currentConfig,
                  );
                  if (newConfig != null && mounted) {
                    setState(() {
                      _cachedLargeFileScanConfig = newConfig;
                    });
                    final presenter = locator<FilePresenter>();
                    final largeFileService = LargeFileService(presenter);
                    navigator.push(
                      MaterialPageRoute(
                        builder: (context) => LargeFilesPage(
                          largeFileService: largeFileService,
                          initialConfig: newConfig,
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
            // 重复文件·完整检测
            if (AppConfig.instance.feature.isDuplicateFilesEnabled) ...[
              _buildUnifiedCard(
                theme: theme,
                colorScheme: colorScheme,
                icon: Icons.content_copy,
                title: '重复文件·完整检测',
                description: '全面扫描重复文件并智能推荐清理',
                isRecommended: true,
                onTap: () async {
                  final navigator = Navigator.of(context);
                  final displaySettings = FileDisplaySettingsService();
                  final minSizeBytes = await displaySettings.getMinFileSize();
                  final minSizeKB = (minSizeBytes / 1024).round();
                  if (!mounted) return;
                  final config = DuplicateFileScanConfig(
                    scanMode: DuplicateScanMode.full,
                    minSizeInKB: minSizeKB > 0 ? minSizeKB : null,
                  );
                  final presenter = locator<FilePresenter>();
                  final duplicateFileService = DuplicateFileService(presenter);
                  final enhancedScanService =
                      EnhancedDuplicateFileScanService(duplicateFileService);
                  CacheManagerService()
                      .setDuplicateFileScanService(enhancedScanService);
                  if (mounted) {
                    navigator.push(
                      MaterialPageRoute(
                        builder: (context) => DuplicateFilesPage(
                          enhancedScanService: enhancedScanService,
                          initialConfig: config,
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
            // 重复文件·分类检测
            if (AppConfig.instance.feature.isDuplicateFilesEnabled)
              _buildUnifiedCard(
                theme: theme,
                colorScheme: colorScheme,
                icon: Icons.category,
                title: '重复文件·分类检测',
                description: '按图片/视频/文档/音频/其他分类',
                onTap: () async {
                  final buildContext = context;
                  await _showCategorySelectionDialog(buildContext, theme, colorScheme);
                },
              ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  /// 构建分区标题
  Widget _buildSectionTitle(
    String title,
    IconData icon,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  /// 构建存储空间概览区（圆环图 + 分类网格）
  Widget _buildStorageOverviewSection(
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 圆环进度图
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _buildCircularProgressSection(theme, colorScheme),
            ),

            const SizedBox(height: 16),

            Divider(
              height: 1,
              color: colorScheme.outlineVariant,
            ),

            const SizedBox(height: 16),

            _buildCategoryGridCards(theme, colorScheme),
          ],
        ),
      ),
    );
  }

  /// 圆环进度图区域
  Widget _buildCircularProgressSection(
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // 使用真实的存储数据
    if (_loadingStorage || _totalSpace == null || _freeSpace == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final totalSpaceGB = _totalSpace! / 1024;
    final freeSpaceGB = _freeSpace! / 1024;
    final usedSpaceGB = totalSpaceGB - freeSpaceGB;
    final percentage = (usedSpaceGB / totalSpaceGB * 100);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = MediaQuery.of(context).size.width >
            MediaQuery.of(context).size.height;

        return Row(
          mainAxisAlignment: isLandscape
              ? MainAxisAlignment.center
              : MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 圆环图
            SizedBox(
              width: 110,
              height: 110,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 110,
                    height: 110,
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 1500),
                      curve: Curves.easeOutCubic,
                      tween: Tween<double>(begin: 0, end: percentage / 100),
                      builder: (context, value, child) {
                        return CircularProgressIndicator(
                          value: value,
                          strokeWidth: 10,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getStorageColor(percentage),
                          ),
                        );
                      },
                    ),
                  ),
                  // 中央文字
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 1500),
                        curve: Curves.easeOutCubic,
                        tween: Tween<double>(begin: 0, end: percentage),
                        builder: (context, value, child) {
                          return Text(
                            '${value.toInt()}%',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _getStorageColor(percentage),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '已使用',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(width: isLandscape ? 40 : 20),

            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStorageStatItem(
                    '已用空间',
                    '${usedSpaceGB.toStringAsFixed(1)} GB',
                    _getStorageColor(percentage),
                    theme,
                  ),
                  const SizedBox(height: 12),
                  _buildStorageStatItem(
                    '可用空间',
                    '${freeSpaceGB.toStringAsFixed(1)} GB',
                    const Color(0xFF4CAF50),
                    theme,
                  ),
                  const SizedBox(height: 12),
                  _buildStorageStatItem(
                    '总容量',
                    '${totalSpaceGB.toStringAsFixed(1)} GB',
                    colorScheme.onSurfaceVariant,
                    theme,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 存储统计项
  Widget _buildStorageStatItem(
    String label,
    String value,
    Color color,
    ThemeData theme,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  /// 构建分类网格卡片（3列布局）
  Widget _buildCategoryGridCards(
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // 计算其他文件大小 = 总已用空间 - 已分类的空间（图片/视频/文档/音乐）
    int otherSize = 0;
    if (_totalSpace != null && _freeSpace != null) {
      final usedBytes = ((_totalSpace! - _freeSpace!) * 1024 * 1024).toInt();
      final categorizedSize =
          _categorySizes.values.fold<int>(0, (sum, size) => sum + size);
      otherSize = (usedBytes - categorizedSize).clamp(0, usedBytes);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 16) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildCategoryCard(
              icon: '📷',
              label: '图片',
              size: FileSizeFormatter.formatBytes(
                  _categorySizes[CategoryType.images] ?? 0),
              color: const Color(0xFF2196F3),
              categoryType: CategoryType.images,
              width: itemWidth,
              theme: theme,
              colorScheme: colorScheme,
              isLoading: _loadingCategories[CategoryType.images] ?? false,
            ),
            _buildCategoryCard(
              icon: '📹',
              label: '视频',
              size: FileSizeFormatter.formatBytes(
                  _categorySizes[CategoryType.video] ?? 0),
              color: const Color(0xFF9C27B0),
              categoryType: CategoryType.video,
              width: itemWidth,
              theme: theme,
              colorScheme: colorScheme,
              isLoading: _loadingCategories[CategoryType.video] ?? false,
            ),
            _buildCategoryCard(
              icon: '📄',
              label: '文档',
              size: FileSizeFormatter.formatBytes(
                  _categorySizes[CategoryType.documents] ?? 0),
              color: const Color(0xFF4CAF50),
              categoryType: CategoryType.documents,
              width: itemWidth,
              theme: theme,
              colorScheme: colorScheme,
              isLoading: _loadingCategories[CategoryType.documents] ?? false,
            ),
            _buildCategoryCard(
              icon: '🎵',
              label: '音乐',
              size: FileSizeFormatter.formatBytes(
                  _categorySizes[CategoryType.music] ?? 0),
              color: const Color(0xFFFF9800),
              categoryType: CategoryType.music,
              width: itemWidth,
              theme: theme,
              colorScheme: colorScheme,
              isLoading: _loadingCategories[CategoryType.music] ?? false,
            ),
            _buildCategoryCard(
              icon: '📦',
              label: '其他',
              size: FileSizeFormatter.formatBytes(otherSize),
              color: const Color(0xFF607D8B),
              categoryType: null,
              width: itemWidth,
              theme: theme,
              colorScheme: colorScheme,
              isLoading: false,
            ),
          ],
        );
      },
    );
  }

  /// 构建单个分类卡片
  Widget _buildCategoryCard({
    required String icon,
    required String label,
    required String size,
    required Color color,
    required CategoryType? categoryType,
    required double width,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required bool isLoading,
  }) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onCategoryCardTap(categoryType, label),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      icon,
                      style: const TextStyle(fontSize: 20),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 10,
                      color: color,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                isLoading
                    ? SizedBox(
                        height: 20,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  color.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '计算中',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Text(
                        size,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 处理分类卡片点击
  /// "其他"分类显示说明对话框，正常分类跳转到文件列表页面
  void _onCategoryCardTap(CategoryType? categoryType, String label) {
    if (categoryType == null) {
      _showOtherCategoryDialog();
    } else {
      _navigateToCategoryPage(categoryType);
    }
  }

  /// 跳转到分类页面（固定使用列表模式按大小排序）
  void _navigateToCategoryPage(CategoryType categoryType) {
    try {
      final presenter = locator<FilePresenter>();
      final viewModel = locator<FileViewModel>();

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CategoryFilePage(
            categoryType: categoryType,
            presenter: presenter,
            viewModel: viewModel,
            isFromStorageManagement: true,
          ),
        ),
      );
    } catch (e) {
      logger.e('Failed to navigate to category page: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开分类页面: $e')),
        );
      }
    }
  }

  /// 显示“其他”分类说明对话框
  void _showOtherCategoryDialog() {
    final presenter = locator<FilePresenter>();
    final buildContext = context;

    showDialog(
      context: buildContext,
      builder: (dialogContext) => Dialog(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 32),
                    child: Row(
                      children: [
                        const Text('📦', style: TextStyle(fontSize: 24)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '其他文件说明',
                            style: Theme.of(dialogContext).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '其他文件包含：',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildOtherFileTypeItem('应用数据和缓存'),
                        _buildOtherFileTypeItem('压缩文件 (ZIP, RAR...)'),
                        _buildOtherFileTypeItem('APK 安装包'),
                        _buildOtherFileTypeItem('系统临时文件'),
                        _buildOtherFileTypeItem('其他未分类的文件'),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(dialogContext)
                                .colorScheme
                                .primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                size: 20,
                                color: Theme.of(dialogContext)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '可以在"大文件查找"功能中按大小查看这些文件',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(dialogContext)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          final navigator = Navigator.of(buildContext);
                          Navigator.pop(dialogContext);
                          navigator.push(
                            MaterialPageRoute(
                              builder: (context) => const AppManagementPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.apps, size: 16),
                        label: const Text('应用', style: TextStyle(fontSize: 13)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          final presenterRef = presenter;
                          final navigator = Navigator.of(buildContext);
                          Navigator.pop(dialogContext);
                          await Future.delayed(Duration.zero);
                          if (!mounted) return;

                          // 预设"其他"类型 + 1MB
                          final initialConfig = LargeFileScanConfig(
                            minSizeInMB: 1,
                            fileTypes: {FileTypeFilter.other},
                            maxResults: 1000,
                          );

                          if (!mounted) return;
                          final config = await LargeFileScanConfigDialog.show(
                            context,
                            initialConfig,
                          );

                          if (config != null && mounted) {
                            final largeFileService =
                                LargeFileService(presenterRef);
                            navigator.push(
                              MaterialPageRoute(
                                builder: (context) => LargeFilesPage(
                                  largeFileService: largeFileService,
                                  initialConfig: config,
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.search, size: 16),
                        label: const Text('查找', style: TextStyle(fontSize: 13)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(dialogContext),
                tooltip: '关闭',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建"其他"文件类型列表项
  Widget _buildOtherFileTypeItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  /// 构建应用管理卡片
  /// 格式化扫描配置为简短描述
  String _formatScanConfig(LargeFileScanConfig config) {
    final types = config.fileTypes.map((t) => t.label).take(3).join('|');
    final size = config.minSizeInMB;
    return '$types · >${size}MB';
  }

  /// 根据使用率获取颜色
  Color _getStorageColor(double percentage) {
    if (percentage < 60) {
      return const Color(0xFF4CAF50); // 绿色
    } else if (percentage < 80) {
      return const Color(0xFFFF9800); // 橙色
    } else {
      return const Color(0xFFF44336); // 红色
    }
  }

  /// 统一的卡片模板（支持可选的推荐标签）
  Widget _buildUnifiedCard({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
    bool isRecommended = false,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: colorScheme.onPrimaryContainer,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          if (isRecommended)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department,
                      size: 12,
                      color: Colors.orange[700],
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '推荐',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 显示重复文件分类选择对话框
  Future<void> _showCategorySelectionDialog(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) async {
    final categories = [
      (
        icon: '📷',
        label: '图片',
        description: '常见于相册、截图等（支持 JPG / PNG / GIF 等格式）',
        type: FileTypeFilter.image,
      ),
      (
        icon: '📹',
        label: '视频',
        description: '常见于录像、下载等（支持 MP4 / AVI / MKV 等格式）',
        type: FileTypeFilter.video,
      ),
      (
        icon: '📄',
        label: '文档',
        description: '常见于办公文件、电子书等（支持 PDF / DOC / TXT 等格式）',
        type: FileTypeFilter.document,
      ),
      (
        icon: '🎵',
        label: '音频',
        description: '常见于音乐、录音等（支持 MP3 / FLAC / WAV 等格式）',
        type: FileTypeFilter.audio,
      ),
      (
        icon: '📦',
        label: '其他',
        description: '常见于安装包、备份等（支持 ZIP / RAR / 7Z 等格式）',
        type: FileTypeFilter.other,
      ),
    ];

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('选择文件类型'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final category = categories[index];
              return Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest,
                child: InkWell(
                  onTap: () async {
                    final buildContext = context;
                    final navigator = Navigator.of(buildContext);
                    Navigator.pop(dialogContext);
                    if (!mounted) return;

                    final displaySettings = FileDisplaySettingsService();
                    final minSizeBytes = await displaySettings.getMinFileSize();
                    final minSizeKB = (minSizeBytes / 1024).round();

                    if (!mounted) return;

                    final config = DuplicateFileScanConfig(
                      scanMode: DuplicateScanMode.category,
                      selectedType: category.type,
                      minSizeInKB: minSizeKB > 0 ? minSizeKB : null,
                    );

                    final presenter = locator<FilePresenter>();
                    final duplicateFileService = DuplicateFileService(presenter);
                    final enhancedScanService =
                        EnhancedDuplicateFileScanService(duplicateFileService);

                    CacheManagerService()
                        .setDuplicateFileScanService(enhancedScanService);

                    navigator.push(
                      MaterialPageRoute(
                        builder: (context) => DuplicateFilesPage(
                          enhancedScanService: enhancedScanService,
                          initialConfig: config,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text(
                          category.icon,
                          style: const TextStyle(fontSize: 32),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                category.label,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                category.description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}
