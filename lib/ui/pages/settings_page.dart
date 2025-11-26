import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/file_display_settings_service.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/cache_manager_service.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settingsService = PageSettingsService();
  final _displaySettings = FileDisplaySettingsService();
  final _cacheManager = CacheManagerService();

  bool _gridShowFileInfo = true; // 默认值，会在initState中加载
  bool _showHiddenFiles = false;
  bool _showSystemFiles = false;
  bool _showFullPath = false;

  @override
  void initState() {
    super.initState();
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

    setState(() {
      _gridShowFileInfo = showInfo;
      _showHiddenFiles = showHidden;
      _showSystemFiles = showSystem;
      _showFullPath = showFullPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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

          const Divider(height: 32),

          // 文件管理部分
          _buildSectionHeader('文件管理', Icons.folder_open),
          _buildShowHiddenFilesToggle(context),
          _buildShowSystemFilesToggle(context),

          const Divider(height: 32),

          // 存储管理
          _buildSectionHeader('存储管理', Icons.storage),
          _buildCacheManagementTile(context),

          const Divider(height: 32),

          // 其他设置（预留）
          _buildSectionHeader('其他', Icons.more_horiz),
          ListTile(
            leading: Icon(Icons.info_outline, color: colorScheme.primary),
            title: const Text('关于应用'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: 跳转到关于页面
            },
          ),

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
        content: Column(
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
    );
  }

  /// 网格模式文件信息显示开关
  Widget _buildGridFileInfoToggle(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.grid_view),
      title: const Text('网格模式显示文件信息'),
      subtitle: Text(
        _gridShowFileInfo ? '当前显示文件名和大小' : '当前仅显示缩略图（图片/视频分类）',
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
              content: Text(value ? '已开启文件信息显示' : '已切换到简洁模式'),
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

  /// 缓存管理
  Widget _buildCacheManagementTile(BuildContext context) {
    return ListTile(
      leading:
          Icon(Icons.storage, color: Theme.of(context).colorScheme.primary),
      title: const Text('缓存管理'),
      subtitle: const Text('查看和清理应用缓存'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showCacheManagement(context),
    );
  }

  /// 显示缓存管理界面
  void _showCacheManagement(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      builder: (context) => _CacheManagementSheet(cacheManager: _cacheManager),
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
}

/// 缓存管理对话框 Widget
class _CacheManagementSheet extends StatefulWidget {
  final CacheManagerService cacheManager;

  const _CacheManagementSheet({required this.cacheManager});

  @override
  State<_CacheManagementSheet> createState() => _CacheManagementSheetState();
}

class _CacheManagementSheetState extends State<_CacheManagementSheet> {
  List<CacheItem> _cacheItems = [];
  int _totalSize = 0;
  bool _isLoading = true;
  bool _isClearing = false;
  String? _clearingItemName;

  @override
  void initState() {
    super.initState();
    _loadCacheData();
  }

  Future<void> _loadCacheData() async {
    setState(() => _isLoading = true);

    final items = await widget.cacheManager.getAllCacheItems();
    final total = await widget.cacheManager.getTotalCacheSize();

    if (mounted) {
      setState(() {
        _cacheItems = items;
        _totalSize = total;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearCache(CacheItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清理'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要清理${item.name}吗？'),
            const SizedBox(height: 8),
            Text(
              '大小：${item.formattedSize}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            if (item.type == CacheType.thumbnail) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ 清理后，视频和音频缩略图将在下次浏览时重新生成',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
            if (item.type == CacheType.categoryScan) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ 清理后，下次打开分类页面（图片、视频等）时需要重新扫描',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
            if (item.type == CacheType.searchHistory) ...[
              const SizedBox(height: 8),
              const Text(
                'ℹ️ 将删除所有搜索历史记录，清理后可重新积累',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ],
            if (item.type == CacheType.videoPlayback) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ 清理后，所有视频将从头播放，需重新读取视频时长',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清理'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isClearing = true;
      _clearingItemName = item.name;
    });

    logger.i('=== START: Clearing ${item.name} (${item.type}) ===');

    bool success = false;
    try {
      success = await widget.cacheManager.clearCache(item.type).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          logger.w('Cache clearing TIMEOUT for ${item.name}');
          return false;
        },
      );
      logger.i('Cache clearing completed, success=$success');
    } catch (e) {
      logger.e('Error clearing cache: $e');
      success = false;
    }

    if (mounted) {
      // 针对日志文件特殊优化：清理后直接设置为0，不重新加载
      // 因为重新加载会因为日志写入而显示非0值
      if (success && item.type == CacheType.log) {
        setState(() {
          _isClearing = false;
          _clearingItemName = null;
          // 直接更新日志文件的大小为0
          final logIndex = _cacheItems.indexWhere(
            (i) => i.type == CacheType.log,
          );
          if (logIndex >= 0) {
            _cacheItems[logIndex] = CacheItem(
              name: '日志文件',
              description: '应用运行日志',
              size: 0,
              type: CacheType.log,
            );
            // 更新总大小
            _totalSize = _cacheItems.fold(0, (sum, item) => sum + item.size);
          }
        });
      } else {
        setState(() {
          _isClearing = false;
          _clearingItemName = null;
        });
        // 其他缓存正常重新加载
        await _loadCacheData();
      }

      // 显示结果
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '${item.name}已清理' : '清理失败，请重试'),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    logger.i('=== END: Clearing ${item.name} ===');
  }

  Future<void> _clearAllCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清理全部缓存'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要清理全部缓存吗？'),
            SizedBox(height: 8),
            Text(
              '这将清理以下内容：',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            Text('• 视频和音频缩略图', style: TextStyle(fontSize: 13)),
            Text('• 应用日志文件', style: TextStyle(fontSize: 13)),
            Text('• 分类统计和文件列表', style: TextStyle(fontSize: 13)),
            Text('• 搜索历史记录', style: TextStyle(fontSize: 13)),
            Text('• 视频播放数据', style: TextStyle(fontSize: 13)),
            SizedBox(height: 8),
            Text(
              '⚠️ 缩略图和文件列表将重新生成，视频将从头播放',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清理'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isClearing = true;
      _clearingItemName = '全部缓存';
    });

    ClearAllResult? result;
    try {
      result = await widget.cacheManager.clearAllCache().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          logger.w('Clear all cache timeout');
          return ClearAllResult(
            successCount: 0,
            failCount: CacheType.values.length,
            errors: ['操作超时'],
          );
        },
      );
    } catch (e) {
      logger.e('Error clearing all cache: $e');
    }

    if (mounted) {
      setState(() {
        _isClearing = false;
        _clearingItemName = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result?.message ?? '清理失败，请重试'),
          backgroundColor:
              result != null && !result.hasError ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );

      // 重新加载缓存数据
      await _loadCacheData();
    }
  }

  IconData _getCacheIcon(CacheType type) {
    switch (type) {
      case CacheType.thumbnail:
        return Icons.image;
      case CacheType.log:
        return Icons.article;
      case CacheType.categoryScan:
        return Icons.analytics;
      case CacheType.searchHistory:
        return Icons.history;
      case CacheType.videoPlayback:
        return Icons.play_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.storage,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  '缓存管理',
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
          // 缓存项列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      ListView.builder(
                        controller: scrollController,
                        itemCount: _cacheItems.length,
                        itemBuilder: (context, index) {
                          final item = _cacheItems[index];
                          final isClearing =
                              _isClearing && _clearingItemName == item.name;

                          return ListTile(
                            leading: Icon(_getCacheIcon(item.type)),
                            title: Text(item.name),
                            subtitle: Text(item.description),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.formattedSize,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isClearing)
                                  const SizedBox(
                                    width: 60,
                                    height: 32,
                                    child: Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    ),
                                  )
                                else
                                  OutlinedButton(
                                    onPressed: item.size > 0 && !_isClearing
                                        ? () => _clearCache(item)
                                        : null,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      minimumSize: const Size(0, 32),
                                    ),
                                    child: const Text('清理',
                                        style: TextStyle(fontSize: 13)),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                      if (_isClearing && _clearingItemName == '全部缓存')
                        Container(
                          color: Colors.black26,
                          child: const Center(
                            child: Card(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text('正在清理全部缓存...'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          // 底部：总缓存大小和全部清理按钮
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  '总缓存大小',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.cacheManager.formatSize(_totalSize),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed:
                      _totalSize > 0 && !_isClearing ? _clearAllCache : null,
                  child: const Text('全部清理'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
