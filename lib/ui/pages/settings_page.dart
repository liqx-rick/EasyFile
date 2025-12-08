import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/file_display_settings_service.dart';
import 'package:easyfile/core/services/duplicate_file_service.dart';
import 'package:easyfile/core/services/enhanced_duplicate_file_scan_service.dart';
import 'package:easyfile/core/services/cache_manager_service.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/ui/pages/cache_management_page.dart';
import 'package:easyfile/ui/pages/trash_page.dart';
import 'package:easyfile/ui/pages/trash_config_page.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settingsService = PageSettingsService();
  final _displaySettings = FileDisplaySettingsService();

  bool _gridShowFileInfo = true; // 默认值，会在initState中加载
  bool _showHiddenFiles = false;
  bool _showSystemFiles = false;
  bool _showFullPath = false;
  int _minFileSize = FileDisplaySettingsService.defaultMinFileSize;

  @override
  void initState() {
    super.initState();

    // 设置到CacheManagerService中，供缓存管理页面使用
    final presenter = locator<FilePresenter>();
    final duplicateFileService = DuplicateFileService(presenter);
    final enhancedScanService =
        EnhancedDuplicateFileScanService(duplicateFileService);
    CacheManagerService().setDuplicateFileScanService(enhancedScanService);

    _loadSettings();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    // 使用categoryImages作为参考页面来获取默认行为
    final showInfo =
        _settingsService.getGridShowFileInfo(PageId.categoryImages);

    // 加载文件显示设置
    final showHidden = await _displaySettings.getShowHiddenFiles();
    final showSystem = await _displaySettings.getShowSystemFiles();
    final showFullPath = await _displaySettings.getShowFullPath();
    final minSize = await _displaySettings.getMinFileSize();

    setState(() {
      _gridShowFileInfo = showInfo;
      _showHiddenFiles = showHidden;
      _showSystemFiles = showSystem;
      _showFullPath = showFullPath;
      _minFileSize = minSize;
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
          // 视图与排序部分
          _buildSectionHeader('视图与排序', Icons.view_module),
          _buildRestoreDefaultsTile(context),
          _buildCurrentSettingsTile(context),
          _buildRecommendedSettingsTile(context),

          const Divider(height: 32),

          // 显示设置部分
          _buildSectionHeader('显示设置', Icons.visibility),
          _buildThemeModeTile(context),
          _buildGridFileInfoToggle(context),
          _buildShowFullPathToggle(context),
          _buildShowHiddenFilesToggle(context),
          _buildShowSystemFilesToggle(context),

          const Divider(height: 32),

          // 重复文件扫描设置
          _buildSectionHeader('重复文件扫描', Icons.content_copy),
          _buildMinFileSizeSetting(context),

          const Divider(height: 32),

          // 存储与缓存管理
          _buildSectionHeader('存储与缓存', Icons.storage),
          _buildCacheManagementTile(context),
          _buildTrashTile(context),

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

  /// 恢复推荐设置
  Widget _buildRestoreDefaultsTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.restore, color: colorScheme.primary),
      title: const Text('恢复推荐设置'),
      subtitle: const Text('将所有页面恢复为推荐的视图、排序和分组设置'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showRestoreDialog(context),
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

  /// 当前设置
  Widget _buildCurrentSettingsTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.settings),
      title: const Text('当前设置'),
      subtitle: const Text('查看各页面当前的设置状态'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showCurrentSettings(context),
    );
  }

  /// 显示当前设置
  void _showCurrentSettings(BuildContext context) {
    try {
      final allSettings = _settingsService.getAllPageSettings();
      logger.i('Got all settings: ${allSettings.length} pages');

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      '当前设置',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: PageId.values.map((pageId) {
                    final settings = allSettings[pageId]!;
                    final hasCustom =
                        _settingsService.hasCustomSettings(pageId);

                    return ListTile(
                      title: Text(PageDefaultSettings.getDescription(pageId)),
                      subtitle: Text(
                        _formatSettings(settings),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: hasCustom
                          ? const Icon(Icons.edit, size: 16, color: Colors.blue)
                          : null,
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      logger.e('Error showing current settings: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载设置失败: $e')),
      );
    }
  }

  /// 推荐配置说明
  Widget _buildRecommendedSettingsTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.lightbulb_outline),
      title: const Text('推荐配置说明'),
      subtitle: const Text('了解我们为不同场景优化的设置'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showRecommendedSettings(context),
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

    return ListTile(
      leading: Icon(getThemeIcon(currentTheme)),
      title: const Text('主题模式'),
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
                groupValue: viewModel.themeMode,
                onChanged: (value) {
                  if (value != null) {
                    viewModel.setThemeMode(value);
                    Navigator.pop(context);
                  }
                },
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
                groupValue: viewModel.themeMode,
                onChanged: (value) {
                  if (value != null) {
                    viewModel.setThemeMode(value);
                    Navigator.pop(context);
                  }
                },
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
                groupValue: viewModel.themeMode,
                onChanged: (value) {
                  if (value != null) {
                    viewModel.setThemeMode(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 网格模式文件信息显示开关
  Widget _buildGridFileInfoToggle(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.grid_view),
      title: const Text('网格模式显示文件信息'),
      subtitle: Text(
        _gridShowFileInfo 
            ? '显示文件名和大小' 
            : '简洁模式：图片/视频仅显示缩略图',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      value: _gridShowFileInfo,
      onChanged: (value) async {
        setState(() {
          _gridShowFileInfo = value;
        });
        await _settingsService.setGridShowFileInfo(value);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                value 
                    ? '已开启文件信息显示' 
                    : '已切换到简洁模式（图片/视频）',
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      },
    );
  }

  /// 显示隐藏文件开关
  Widget _buildShowHiddenFilesToggle(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(
        _showHiddenFiles ? Icons.visibility : Icons.visibility_off,
      ),
      title: const Text('显示隐藏文件'),
      subtitle: Text(
        _showHiddenFiles ? '当前显示以 . 开头的隐藏文件' : '当前隐藏以 . 开头的文件',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      value: _showHiddenFiles,
      onChanged: (value) async {
        setState(() {
          _showHiddenFiles = value;
        });
        await _displaySettings.setShowHiddenFiles(value);
      },
    );
  }

  /// 显示系统文件开关
  Widget _buildShowSystemFilesToggle(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(
        _showSystemFiles ? Icons.folder_special : Icons.folder_off,
      ),
      title: const Text('显示系统文件'),
      subtitle: Text(
        _showSystemFiles ? '当前显示 Android、.thumbnails 等系统文件夹' : '当前隐藏系统文件夹和文件',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      value: _showSystemFiles,
      onChanged: (value) async {
        setState(() {
          _showSystemFiles = value;
        });
        await _displaySettings.setShowSystemFiles(value);
      },
    );
  }

  /// 显示完整路径开关
  Widget _buildShowFullPathToggle(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(
        _showFullPath ? Icons.folder_open : Icons.folder,
      ),
      title: const Text('显示文件路径'),
      subtitle: Text(
        _showFullPath ? '分类列表模式下显示文件完整路径' : '分类列表模式下不显示路径',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      value: _showFullPath,
      onChanged: (value) async {
        setState(() {
          _showFullPath = value;
        });
        await _displaySettings.setShowFullPath(value);
      },
    );
  }

  /// 最小文件大小设置
  Widget _buildMinFileSizeSetting(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        ListTile(
          leading:
              Icon(Icons.photo_size_select_large, color: colorScheme.primary),
          title: const Text('最小文件大小'),
          subtitle: Text(
            '扫描重复文件时，跳过小于此大小的文件',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Text(
            FileDisplaySettingsService.formatFileSize(_minFileSize),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
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

  /// 显示推荐配置说明
  void _showRecommendedSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    '推荐配置说明',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: PageId.values.map((pageId) {
                  final settings = PageDefaultSettings.getDefaults(pageId);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            PageDefaultSettings.getDescription(pageId),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatSettings(settings),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            PageDefaultSettings.getReason(pageId),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 格式化设置文本
  String _formatSettings(PageSettings settings) {
    final viewMode = settings.viewMode == ViewMode.grid ? '网格视图' : '列表视图';
    final sortType = _getSortTypeName(settings.sortType);
    final groupEnabled = settings.groupEnabled == true ? '时间分组' : '不分组';

    return '$viewMode | $sortType | $groupEnabled';
  }

  /// 获取排序类型名称
  String _getSortTypeName(SortType? sortType) {
    switch (sortType) {
      case SortType.name:
        return '按名称';
      case SortType.modifiedTime:
        return '按时间';
      case SortType.size:
        return '按大小';
      case SortType.fileType:
        return '按类型';
      default:
        return '默认';
    }
  }

  /// 缓存管理入口
  Widget _buildCacheManagementTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.cleaning_services, color: colorScheme.primary),
      title: const Text('缓存管理'),
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
      leading: Icon(Icons.delete_outline, color: colorScheme.primary),
      title: const Text('回收站'),
      subtitle: const Text('查看和管理最近删除的文件'),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const TrashConfigPage(),
                ),
              );
            },
            child: const Icon(Icons.settings_outlined, size: 20),
          ),
          const SizedBox(height: 4),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const TrashPage(),
          ),
        );
      },
    );
  }
}
