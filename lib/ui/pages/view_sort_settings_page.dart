import 'package:flutter/material.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/services/category_sort_service.dart';

/// 视图与排序管理页面
class ViewSortSettingsPage extends StatefulWidget {
  const ViewSortSettingsPage({super.key});

  @override
  State<ViewSortSettingsPage> createState() => _ViewSortSettingsPageState();
}

class _ViewSortSettingsPageState extends State<ViewSortSettingsPage> {
  final _settingsService = PageSettingsService();
  Map<PageId, PageSettings> _allSettings = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 加载所有页面设置
  void _loadSettings() {
    try {
      final settings = _settingsService.getAllPageSettings();
      logger.i('Loaded ${settings.length} page settings');
      setState(() {
        _allSettings = settings;
      });
    } catch (e) {
      logger.e('Failed to load page settings: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('视图与排序管理'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 统计概览卡片
          _buildOverviewCard(context),

          const SizedBox(height: 24),

          // 恢复默认设置
          _buildRestoreSection(context),

          const SizedBox(height: 24),

          // 当前详细配置
          _buildCurrentSettingsSection(context),

          const SizedBox(height: 24),

          // 推荐配置说明
          _buildRecommendedSection(context),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 构建统计概览卡片
  Widget _buildOverviewCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '当前使用的页面设置',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._allSettings.entries.map((entry) {
              final pageId = entry.key;
              final settings = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '• ${PageDefaultSettings.getDescription(pageId)}：',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatSettingsBrief(settings),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 构建恢复默认设置部分
  Widget _buildRestoreSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.refresh, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '恢复默认设置',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.restore, color: Colors.orange),
            title: const Text('恢复所有页面为默认设置'),
            subtitle: const Text('将重置所有页面的视图、排序和分组'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showRestoreDialog(context),
          ),
        ],
      ),
    );
  }

  /// 构建当前详细配置部分
  Widget _buildCurrentSettingsSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.list_alt, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '当前详细配置',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._allSettings.entries.map((entry) {
            final pageId = entry.key;
            final settings = entry.value;
            return ExpansionTile(
              leading:
                  Icon(Icons.folder_open, color: colorScheme.primary, size: 20),
              title: Text(PageDefaultSettings.getDescription(pageId)),
              subtitle: Text(
                _formatSettingsBrief(settings),
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSettingRow(
                          '视图模式', _formatViewMode(settings.viewMode)),
                      const SizedBox(height: 8),
                      _buildSettingRow(
                          '排序方式', _formatSortType(settings.sortType)),
                      const SizedBox(height: 8),
                      _buildSettingRow('分组设置',
                          settings.groupEnabled == true ? '时间分组' : '不分组'),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  /// 构建推荐配置说明部分
  Widget _buildRecommendedSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      child: ExpansionTile(
        leading: Icon(Icons.lightbulb_outline, color: colorScheme.primary),
        title: const Text('为什么推荐这些设置？'),
        subtitle: const Text('了解推荐配置的理由'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: PageId.values.map((pageId) {
                final settings = PageDefaultSettings.getDefaults(pageId);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            PageDefaultSettings.getDescription(pageId),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatSettings(settings),
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            PageDefaultSettings.getReason(pageId),
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.8),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建设置行
  Widget _buildSettingRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// 格式化设置（简要）
  String _formatSettingsBrief(PageSettings settings) {
    final viewMode = _formatViewMode(settings.viewMode);
    final sortType = _formatSortType(settings.sortType);
    return '$viewMode，$sortType';
  }

  /// 格式化设置（完整）
  String _formatSettings(PageSettings settings) {
    final viewMode = _formatViewMode(settings.viewMode);
    final sortType = _formatSortType(settings.sortType);
    final groupEnabled = settings.groupEnabled == true ? '时间分组' : '不分组';
    return '$viewMode | $sortType | $groupEnabled';
  }

  /// 格式化视图模式
  String _formatViewMode(ViewMode? viewMode) {
    return viewMode == ViewMode.grid ? '网格视图' : '列表视图';
  }

  /// 格式化排序类型
  String _formatSortType(SortType? sortType) {
    switch (sortType) {
      case SortType.name:
        return '按名称排序';
      case SortType.modifiedTime:
        return '按时间排序';
      case SortType.size:
        return '按大小排序';
      case SortType.fileType:
        return '按类型排序';
      default:
        return '默认排序';
    }
  }

  /// 显示恢复确认对话框
  void _showRestoreDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('确认恢复默认？'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('这将重置以下内容为推荐值：'),
            SizedBox(height: 8),
            Text('• 所有页面的视图模式（列表/网格）'),
            Text('• 所有页面的排序方式'),
            Text('• 所有页面的分组设置'),
            SizedBox(height: 12),
            Text(
              '您之前的个性化设置将被覆盖。',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
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
              _loadSettings(); // 重新加载设置
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已恢复推荐设置'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
  }
}
