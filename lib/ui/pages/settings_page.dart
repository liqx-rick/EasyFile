import 'package:flutter/material.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/services/category_sort_service.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settingsService = PageSettingsService();

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
          // 显示设置部分
          _buildSectionHeader('显示设置', Icons.display_settings),
          _buildRestoreDefaultsTile(context),
          _buildCurrentSettingsTile(context),
          _buildRecommendedSettingsTile(context),

          const Divider(height: 32),

          // 文件管理（预留）
          _buildSectionHeader('文件管理', Icons.folder_open),
          _buildComingSoonTile(
            context,
            '隐藏系统文件',
            '过滤系统和隐藏文件',
            Icons.visibility_off,
          ),
          _buildComingSoonTile(
            context,
            '显示隐藏文件',
            '显示以点开头的隐藏文件',
            Icons.visibility,
          ),

          const Divider(height: 32),

          // 存储管理（预留）
          _buildSectionHeader('存储管理', Icons.storage),
          _buildComingSoonTile(
            context,
            '清理缓存',
            '清除文件分类扫描缓存',
            Icons.cleaning_services,
          ),
          _buildComingSoonTile(
            context,
            '清理搜索记录',
            '清除历史搜索记录',
            Icons.history,
          ),

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

  /// 即将推出的功能
  Widget _buildComingSoonTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
  ) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[400]),
      title: Text(title, style: TextStyle(color: Colors.grey[600])),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[500])),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '即将推出',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ),
      enabled: false,
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
