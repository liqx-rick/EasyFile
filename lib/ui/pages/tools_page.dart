import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/duplicate_file_scan_config.dart';
import 'package:easyfile/core/models/junk_file_scan_config.dart';
import 'package:easyfile/core/models/large_file_scan_config.dart';
import 'package:easyfile/core/services/duplicate_file_service.dart';
import 'package:easyfile/core/services/enhanced_duplicate_file_scan_service.dart';
import 'package:easyfile/core/services/large_file_service.dart';
import 'package:easyfile/core/services/privacy_service.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/pages/apk_management_page.dart';
import 'package:easyfile/ui/pages/app_management_page.dart';
import 'package:easyfile/ui/pages/duplicate_files_page.dart';
import 'package:easyfile/ui/pages/junk_files_page.dart';
import 'package:easyfile/ui/pages/large_files_page.dart';
import 'package:easyfile/ui/pages/privacy_auth_page.dart';
import 'package:easyfile/ui/pages/privacy_setup_page.dart';
import 'package:easyfile/ui/pages/privacy_space_page.dart';
import 'package:easyfile/ui/pages/trash_files_page.dart';
import 'package:flutter/material.dart';

/// 专业工具页（+1屏）
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  /// 跳转到大文件页
  void _navigateToLargeFiles() {
    final presenter = locator<FilePresenter>();
    final largeFileService = LargeFileService(presenter);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LargeFilesPage(
          largeFileService: largeFileService,
          initialConfig: const LargeFileScanConfig(
            minSizeInMB: 100,
          ),
        ),
      ),
    );
  }

  /// 跳转到重复文件页
  void _navigateToDuplicateFiles() {
    final presenter = locator<FilePresenter>();
    final duplicateService = DuplicateFileService(presenter);
    final enhancedService = EnhancedDuplicateFileScanService(duplicateService);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DuplicateFilesPage(
          enhancedScanService: enhancedService,
          initialConfig: DuplicateFileScanConfig.fullScan(),
        ),
      ),
    );
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

  /// 跳转到安装包管理页
  void _navigateToApkManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ApkManagementPage(),
      ),
    );
  }

  /// 跳转到应用管理页
  void _navigateToAppManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AppManagementPage(),
      ),
    );
  }

  /// 跳转到系统回收站页
  void _navigateToTrashFiles() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TrashFilesPage(),
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('专业工具'),
      ),
      body: ListView(
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
        icon: Icons.description,
        label: '大文件',
        color: Colors.orange,
        onTap: _navigateToLargeFiles,
      ),
      _ToolItem(
        icon: Icons.content_copy,
        label: '重复文件',
        color: Colors.purple,
        onTap: _navigateToDuplicateFiles,
      ),
      _ToolItem(
        icon: Icons.cleaning_services,
        label: '垃圾清理',
        color: Colors.brown,
        onTap: _navigateToJunkFiles,
      ),
      _ToolItem(
        icon: Icons.android,
        label: '安装包管理',
        color: Colors.green,
        onTap: _navigateToApkManagement,
      ),
      _ToolItem(
        icon: Icons.apps,
        label: '应用管理',
        color: Colors.blue,
        onTap: _navigateToAppManagement,
      ),
      _ToolItem(
        icon: Icons.restore_from_trash,
        label: '系统回收站',
        color: Colors.red,
        onTap: _navigateToTrashFiles,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: tools.map((tool) => _buildToolCard(tool, theme)).toList(),
    );
  }

  /// 跳转到隐私空间页（带身份验证）
  Future<void> _navigateToPrivacySpace() async {
    final privacyService = PrivacyService();

    try {
      // 检查是否已初始化
      final isInitialized = await privacyService.isInitialized();
      logger.d('🔐 隐私空间初始化状态: $isInitialized');

      if (!isInitialized) {
        // 首次进入，显示设置页面
        if (!mounted) return;
        logger.d('📝 首次进入，打开 PrivacySetupPage');
        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) => const PrivacySetupPage(),
          ),
        );

        logger.d('📝 PrivacySetupPage 返回结果: $result');
        // 如果设置成功，直接进入隐私空间（已在 PrivacySetupPage 中激活会话）
        if (result == true && mounted) {
          logger.d('✅ 设置成功，直接进入 PrivacySpacePage');
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const PrivacySpacePage(),
            ),
          );
        }
      } else {
        // 已初始化，显示验证页面
        if (!mounted) return;
        logger.d('🔒 已初始化，打开 PrivacyAuthPage');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const PrivacyAuthPage(),
          ),
        );
      }
    } catch (e) {
      logger.e('导航到隐私空间失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开隐私空间失败：$e')),
        );
      }
    }
  }

  /// 构建安全与隐私工具
  Widget _buildSecurityTools(ThemeData theme) {
    final tools = [
      _ToolItem(
        icon: Icons.lock,
        label: '隐私空间',
        color: Colors.indigo,
        onTap: _navigateToPrivacySpace,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: tools.map((tool) => _buildToolCard(tool, theme)).toList(),
    );
  }

  /// 构建智能整理工具
  Widget _buildSmartTools(ThemeData theme) {
    final tools = [
      _ToolItem(
        icon: Icons.photo_album,
        label: '智能相册',
        color: Colors.pink,
        onTap: () => _showComingSoon('智能相册'),
      ),
      _ToolItem(
        icon: Icons.collections,
        label: '文件集合',
        color: Colors.purple,
        onTap: () => _showComingSoon('文件集合'),
      ),
      _ToolItem(
        icon: Icons.note,
        label: '文件笔记',
        color: Colors.teal,
        onTap: () => _showComingSoon('文件笔记'),
      ),
      _ToolItem(
        icon: Icons.build,
        label: '批量工具',
        color: Colors.deepOrange,
        onTap: () => _showComingSoon('批量工具'),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: tools.map((tool) => _buildToolCard(tool, theme)).toList(),
    );
  }

  /// 构建工具卡片
  Widget _buildToolCard(_ToolItem tool, ThemeData theme) {
    return InkWell(
      onTap: tool.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                tool.icon,
                size: 48,
                color: tool.color,
              ),
              const SizedBox(height: 12),
              Text(
                tool.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
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
  final Color color;
  final VoidCallback onTap;

  const _ToolItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}
