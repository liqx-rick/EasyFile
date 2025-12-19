import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/file_display_settings_service.dart';
import 'package:easyfile/core/services/duplicate_file_service.dart';
import 'package:easyfile/core/services/enhanced_duplicate_file_scan_service.dart';
import 'package:easyfile/core/services/cache_manager_service.dart';
import 'package:easyfile/core/services/recommendation_settings.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/ui/pages/cache_management_page.dart';
import 'package:easyfile/ui/pages/trash_config_page.dart';
import 'package:easyfile/ui/pages/new_files_settings_page.dart';
import 'package:easyfile/ui/pages/file_display_settings_page.dart';
import 'package:easyfile/ui/pages/mediastore_scan_test_page.dart';
import 'package:easyfile/ui/pages/app_file_scan_test_page.dart';
import 'package:easyfile/ui/pages/native_camera_photos_test_page.dart';
import 'package:easyfile/ui/widgets/quick_access_section.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settingsService = PageSettingsService();
  final _displaySettings = FileDisplaySettingsService();

  int _minFileSize = FileDisplaySettingsService.defaultMinFileSize;
  int _recommendationThreshold = RecommendationSettings.defaultFileCountThreshold;

  @override
  void initState() {
    super.initState();

    // 初始化重复文件扫描服务：注入依赖到CacheManagerService，供缓存清理页面使用
    final presenter = locator<FilePresenter>();
    final duplicateFileService = DuplicateFileService(presenter);
    final enhancedScanService =
        EnhancedDuplicateFileScanService(duplicateFileService);
    CacheManagerService().setDuplicateFileScanService(enhancedScanService);

    _loadSettings();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    final minSize = await _displaySettings.getMinFileSize();
    final recSettings = await RecommendationSettings.load();

    setState(() {
      _minFileSize = minSize;
      _recommendationThreshold = recSettings.fileCountThreshold;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        elevation: 0,
      ),
      body: ListView(
        children: [
          // 显示偏好部分
          _buildSectionHeader('显示偏好', Icons.visibility),
          _buildThemeModeTile(context),
          const Divider(height: 1, indent: 56),
          _buildViewSortRestoreTile(context),
          const Divider(height: 1, indent: 56),
          _buildFileDisplayTile(context),

          const Divider(height: 32),

          // 存储与缓存管理
          _buildSectionHeader('存储与缓存', Icons.storage),
          _buildCacheManagementTile(context),
          const Divider(height: 1, indent: 56),
          _buildTrashTile(context),

          const Divider(height: 32),

          // 功能设置
          _buildSectionHeader('功能设置', Icons.tune),
          _buildNewFilesPrivacyTile(context),
          const Divider(height: 1, indent: 56),
          _buildDuplicateScanSettingTile(context),

          const Divider(height: 32),

          // 开发者选项
          _buildSectionHeader('开发者选项', Icons.developer_mode),
          _buildRecommendationThresholdTile(context),
          const Divider(height: 1, indent: 56),
          _buildNativeCameraTestTile(context),
          const Divider(height: 1, indent: 56),
          _buildScanTestTile(context, '图片扫描性能测试', CategoryType.images, Icons.image),
          _buildScanTestTile(context, '音频扫描性能测试', CategoryType.music, Icons.music_note),
          _buildScanTestTile(context, '视频扫描性能测试', CategoryType.video, Icons.video_library),
          _buildScanTestTile(context, '文档扫描性能测试', CategoryType.documents, Icons.description),
          _buildScanTestTile(context, 'APK扫描性能测试', CategoryType.apk, Icons.android),
          _buildScanTestTile(context, '压缩包扫描性能测试', CategoryType.archive, Icons.archive),
          _buildAppFileScanTestTile(context),

          const Divider(height: 32),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 构建分节标题
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  /// 主题模式设置
  Widget _buildThemeModeTile(BuildContext context) {
    final viewModel = context.watch<FileViewModel>();
    final currentTheme = viewModel.themeMode;

    String getThemeText(ThemeMode mode) {
      switch (mode) {
        case ThemeMode.light:
          return '浅色';
        case ThemeMode.dark:
          return '深色';
        case ThemeMode.system:
          return '跟随系统';
      }
    }

    IconData getThemeIcon(ThemeMode mode) {
      switch (mode) {
        case ThemeMode.light:
          return Icons.light_mode;
        case ThemeMode.dark:
          return Icons.dark_mode;
        case ThemeMode.system:
          return Icons.brightness_auto;
      }
    }

    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(getThemeIcon(currentTheme), color: colorScheme.primary),
      title: const Text('外观主题'),
      subtitle: Text('当前：${getThemeText(currentTheme)}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showThemeDialog(context, viewModel),
    );
  }

  /// 显示主题选择对话框
  void _showThemeDialog(BuildContext context, FileViewModel viewModel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题模式'),
        content: SingleChildScrollView(
          child: RadioGroup<ThemeMode>(
            groupValue: viewModel.themeMode,
            onChanged: (value) {
              if (value != null) {
                viewModel.setThemeMode(value);
                Navigator.pop(context);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<ThemeMode>(
                  title: const Row(
                    children: [
                      Icon(Icons.light_mode, size: 20),
                      SizedBox(width: 12),
                      Text('浅色'),
                    ],
                  ),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: const Row(
                    children: [
                      Icon(Icons.dark_mode, size: 20),
                      SizedBox(width: 12),
                      Text('深色'),
                    ],
                  ),
                  value: ThemeMode.dark,
                ),
                RadioListTile<ThemeMode>(
                  title: const Row(
                    children: [
                      Icon(Icons.brightness_auto, size: 20),
                      SizedBox(width: 12),
                      Text('跟随系统'),
                    ],
                  ),
                  subtitle: const Text(
                    '根据系统设置自动切换',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: ThemeMode.system,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 视图与排序恢复（ExpansionTile形式）
  Widget _buildViewSortRestoreTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      leading: Icon(Icons.view_module, color: colorScheme.primary),
      title: const Text('视图与排序'),
      subtitle: const Text('一键恢复所有页面为推荐设置'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '这将重置所有页面的视图模式、排序方式和分组设置',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _showRestoreDialog(context),
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('恢复推荐设置'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 文件显示配置入口
  Widget _buildFileDisplayTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.description, color: colorScheme.primary),
      title: const Text('文件显示'),
      subtitle: const Text('文件信息、路径、隐藏文件等'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const FileDisplaySettingsPage(),
          ),
        );
      },
    );
  }

  /// 显示恢复确认对话框
  void _showRestoreDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复推荐设置'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('这将重置以下内容为推荐值：'),
            SizedBox(height: 8),
            Text('• 所有页面的视图模式（列表/网格）'),
            Text('• 所有页面的排序方式'),
            Text('• 所有页面的分组设置'),
            SizedBox(height: 8),
            Text(
              '您之前的个性化设置将被覆盖。',
              style: TextStyle(color: Colors.orange, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await _settingsService.resetToDefaults();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已恢复推荐设置')),
                );
              }
            },
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
  }

  /// 重复文件扫描设置（展开式）
  Widget _buildDuplicateScanSettingTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      leading: Icon(Icons.content_copy, color: colorScheme.primary),
      title: const Text('重复文件清理'),
      subtitle: Text(
        '最小文件阈值：${FileDisplaySettingsService.formatFileSize(_minFileSize)}',
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.of(context).size.width * 0.1,
            vertical: 2,
          ),
          child: Row(
            children: [
              Text(
                FileDisplaySettingsService.formatFileSize(
                  FileDisplaySettingsService.minFileSizeMin,
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Slider(
                  value: _minFileSize.toDouble(),
                  min: FileDisplaySettingsService.minFileSizeMin.toDouble(),
                  max: FileDisplaySettingsService.minFileSizeMax.toDouble(),
                  divisions: 99, // 100 steps from 10KB to 10MB
                  label:
                      FileDisplaySettingsService.formatFileSize(_minFileSize),
                  onChanged: (value) {
                    setState(() {
                      _minFileSize = value.toInt();
                    });
                  },
                  onChangeEnd: (value) async {
                    await _displaySettings.setMinFileSize(value.toInt());
                  },
                ),
              ),
              Text(
                FileDisplaySettingsService.formatFileSize(
                  FileDisplaySettingsService.minFileSizeMax,
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 缓存管理入口
  Widget _buildCacheManagementTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.cleaning_services, color: colorScheme.primary),
      title: const Text('缓存清理'),
      subtitle: const Text('清理应用缩略图、扫描等产生的缓存'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        final cacheManager = locator<CacheManagerService>();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CacheManagementPage(
              cacheManager: cacheManager,
            ),
          ),
        );
      },
    );
  }

  /// 回收站入口
  Widget _buildTrashTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.settings, color: colorScheme.primary),
      title: const Text('回收站设置'),
      subtitle: const Text('启用回收站，自动清理周期等'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const TrashConfigPage(),
          ),
        );
      },
    );
  }

  /// 扫描性能测试入口
  Widget _buildScanTestTile(
    BuildContext context,
    String title,
    CategoryType categoryType,
    IconData icon,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(icon, color: colorScheme.primary),
      title: Text(title),
      subtitle: const Text('对比 MediaStore 和文件系统的扫描性能'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MediaStoreScanTestPage(
              categoryType: categoryType,
            ),
          ),
        );
      },
    );
  }

  /// 应用文件扫描方案对比测试入口
  Widget _buildAppFileScanTestTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.apps, color: colorScheme.primary),
      title: const Text('应用文件扫描方案对比'),
      subtitle: const Text('对比路径扫描 vs MediaStore OWNER_PACKAGE_NAME'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const AppFileScanTestPage(),
          ),
        );
      },
    );
  }

  /// 本机相机拍照统计测试入口
  Widget _buildNativeCameraTestTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.camera_alt, color: colorScheme.primary),
      title: const Text('本机相机拍照统计'),
      subtitle: const Text('通过 EXIF 信息判断是否为本机拍摄的照片'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const NativeCameraPhotosTestPage(),
          ),
        );
      },
    );
  }

  /// 新文件设置入口
  Widget _buildNewFilesPrivacyTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.fiber_new, color: colorScheme.primary),
      title: const Text('新文件'),
      subtitle: const Text('设置主页新文件发现功能模块的扫描范围、时间跨度等'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const NewFilesSettingsPage(),
          ),
        );
      },
    );
  }

  /// 首页推荐文件数量阈值设置
  Widget _buildRecommendationThresholdTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.filter_list, color: colorScheme.primary),
      title: const Text('首页推荐应用文件数量阈值'),
      subtitle: Text('当前阈值：$_recommendationThreshold 个文件'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final selected = await showDialog<int>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('选择文件数量阈值'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('应用文件数量大于此阈值时才会显示在首页推荐'),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: RecommendationSettings.availableThresholds.map((threshold) {
                          return RadioListTile<int>(
                            title: Text('$threshold 个文件'),
                            value: threshold,
                            groupValue: _recommendationThreshold,
                            onChanged: (value) {
                              Navigator.of(context).pop(value);
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          ),
        );

        if (selected != null) {
          setState(() {
            _recommendationThreshold = selected;
          });

          // 保存设置
          final settings = RecommendationSettings(fileCountThreshold: selected);
          await settings.save();

          // 清除推荐卡片缓存，确保下次刷新时使用新阈值
          logger.i('📌 开发者选项：阈值已修改为 $selected，清除缓存');
          QuickAccessSection.clearRecommendationCache();

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('文件数量阈值已设置为 $selected')),
            );
          }
        }
      },
    );
  }
}
