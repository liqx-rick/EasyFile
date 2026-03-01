import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/junk_file_scan_config.dart';
import 'package:easyfile/core/services/app_trash_manager.dart';
import 'package:easyfile/core/services/junk_file_cache_manager.dart';
import 'package:easyfile/ui/pages/junk_files_page.dart';
import 'package:easyfile/ui/pages/trash_page.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:flutter/material.dart';

/// 专业工具页（+1屏）
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // 工具统计数据
  final int _archiveCount = 0;
  int _trashCount = 0;
  int _junkSize = 0;
  int _apkCount = 0;
  final int _privacyCount = 0;
  final int _appCount = 0;

  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadToolStatistics();
  }

  /// 加载工具统计数据
  Future<void> _loadToolStatistics() async {
    setState(() => _isLoadingStats = true);

    try {
      // 并行加载所有统计数据
      await Future.wait([
        _loadTrashStats(),
        _loadJunkStats(),
      ]);
    } catch (e) {
      logger.e('加载工具统计失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  /// 加载回收站统计
  Future<void> _loadTrashStats() async {
    try {
      final trashManager = locator<AppTrashManager>();
      final stats = await trashManager.getStatistics();
      
      if (mounted) {
        setState(() {
          _trashCount = stats['fileCount'] as int? ?? 0;
        });
      }
    } catch (e) {
      logger.w('加载回收站统计失败: $e');
    }
  }

  /// 加载垃圾文件统计
  Future<void> _loadJunkStats() async {
    try {
      final junkCacheManager = locator<JunkFileCacheManager>();
      final cacheInfo = await junkCacheManager.getCacheInfo();

      if (mounted) {
        setState(() {
          _apkCount = cacheInfo['apkCount'] as int? ?? 0;
          _junkSize = cacheInfo['totalSize'] as int? ?? 0;
        });
      }
    } catch (e) {
      logger.w('加载垃圾文件统计失败: $e');
    }
  }

  /// 跳转到垃圾清理页
  void _navigateToJunkFiles() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const JunkFilesPage(
          initialConfig: JunkFileScanConfig(),
        ),
      ),
    );
  }

  /// 跳转到回收站页
  void _navigateToTrash() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TrashPage(),
      ),
    );
  }

  /// 显示"敬请期待"提示
  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature 功能即将上线'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('专业工具'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadToolStatistics,
            tooltip: '刷新',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadToolStatistics,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 存储优化分组
            _buildSectionHeader('🔧 存储优化', theme),
            const SizedBox(height: 12),
            _buildOptimizationTools(theme),
            const SizedBox(height: 24),

            // 安全与隐私分组
            _buildSectionHeader('🔐 安全与隐私', theme),
            const SizedBox(height: 12),
            _buildSecurityTools(theme),
            const SizedBox(height: 24),

            // 智能整理分组
            _buildSectionHeader('✨ 智能整理', theme),
            const SizedBox(height: 12),
            _buildSmartTools(theme),
            const SizedBox(height: 24),

            // 提示：向左滑动
            _buildSwipeHint(theme),
          ],
        ),
      ),
    );
  }

  /// 构建分组标题
  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }

  /// 构建存储优化工具
  Widget _buildOptimizationTools(ThemeData theme) {
    final tools = [
      _ToolItem(
        icon: Icons.folder_zip,
        label: '压缩包管理',
        subtitle: _archiveCount > 0 ? '$_archiveCount 个压缩包' : '敬请期待',
        color: Colors.amber,
        enabled: false,
        onTap: () => _showComingSoon('压缩包管理'),
      ),
      _ToolItem(
        icon: Icons.delete,
        label: '回收站',
        subtitle: _trashCount > 0 ? '$_trashCount 个文件' : '空',
        color: Colors.red,
        enabled: true,
        onTap: _navigateToTrash,
      ),
      _ToolItem(
        icon: Icons.cleaning_services,
        label: '垃圾清理',
        subtitle: _junkSize > 0
            ? '可清理 ${FileSizeFormatter.formatBytesWithSpace(_junkSize)}'
            : '正在扫描...',
        color: Colors.brown,
        enabled: true,
        onTap: _navigateToJunkFiles,
      ),
      _ToolItem(
        icon: Icons.android,
        label: '安装包管理',
        subtitle: _apkCount > 0 ? '$_apkCount 个 APK' : '无',
        color: Colors.green,
        enabled: true,
        onTap: _navigateToJunkFiles, // APK在垃圾清理中
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.2,
      children: tools.map((tool) => _buildToolCard(tool, theme)).toList(),
    );
  }

  /// 构建安全与隐私工具
  Widget _buildSecurityTools(ThemeData theme) {
    final tools = [
      _ToolItem(
        icon: Icons.lock,
        label: '隐私空间',
        subtitle: _privacyCount > 0 ? '$_privacyCount 个文件' : '敬请期待',
        color: Colors.indigo,
        enabled: false,
        onTap: () => _showComingSoon('隐私空间'),
      ),
      _ToolItem(
        icon: Icons.apps,
        label: '应用管理',
        subtitle: _appCount > 0 ? '$_appCount 个应用' : '敬请期待',
        color: Colors.blue,
        enabled: false,
        onTap: () => _showComingSoon('应用管理'),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.2,
      children: tools.map((tool) => _buildToolCard(tool, theme)).toList(),
    );
  }

  /// 构建智能整理工具
  Widget _buildSmartTools(ThemeData theme) {
    final tools = [
      _ToolItem(
        icon: Icons.photo_album,
        label: '智能相册',
        subtitle: '敬请期待',
        color: Colors.pink,
        enabled: false,
        onTap: () => _showComingSoon('智能相册'),
      ),
      _ToolItem(
        icon: Icons.collections,
        label: '文件集合',
        subtitle: '敬请期待',
        color: Colors.purple,
        enabled: false,
        onTap: () => _showComingSoon('文件集合'),
      ),
      _ToolItem(
        icon: Icons.note,
        label: '文件笔记',
        subtitle: '敬请期待',
        color: Colors.teal,
        enabled: false,
        onTap: () => _showComingSoon('文件笔记'),
      ),
      _ToolItem(
        icon: Icons.build,
        label: '批量工具',
        subtitle: '敬请期待',
        color: Colors.deepOrange,
        enabled: false,
        onTap: () => _showComingSoon('批量工具'),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.2,
      children: tools.map((tool) => _buildToolCard(tool, theme)).toList(),
    );
  }

  /// 构建工具卡片
  Widget _buildToolCard(_ToolItem tool, ThemeData theme) {
    return Opacity(
      opacity: tool.enabled ? 1.0 : 0.5,
      child: InkWell(
        onTap: tool.enabled ? tool.onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  tool.icon,
                  size: 40,
                  color: tool.enabled ? tool.color : Colors.grey,
                ),
                const SizedBox(height: 12),
                Text(
                  tool.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  _isLoadingStats && tool.subtitle.contains('个')
                      ? '加载中...'
                      : tool.subtitle,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建滑动提示
  Widget _buildSwipeHint(ThemeData theme) {
    return Center(
      child: Text(
        '← 向左滑动返回主页',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
        ),
      ),
    );
  }
}

/// 工具项数据类
class _ToolItem {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _ToolItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.enabled,
    required this.onTap,
  });
}
