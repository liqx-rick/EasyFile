import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 关于页面
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '加载中...';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _version = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
      });
    } catch (e) {
      setState(() {
        _version = '1.1.0';
        _buildNumber = '1';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('关于'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 应用图标和名称
          Center(
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    size: 60,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'EasyFile',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '简洁高效的文件管理器',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'v$_version${_buildNumber.isNotEmpty ? " ($_buildNumber)" : ""}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // 核心特性
          _buildSectionTitle('核心特性', Icons.star_rounded),
          const SizedBox(height: 12),
          _buildFeatureCard(
            icon: Icons.folder_special,
            title: '智能分类',
            description: '自动识别图片、视频、音频、文档等文件类型',
            color: Colors.blue,
          ),
          _buildFeatureCard(
            icon: Icons.history,
            title: '最近访问',
            description: '快速访问最近打开的文件和文件夹',
            color: Colors.green,
          ),
          _buildFeatureCard(
            icon: Icons.favorite,
            title: '收藏管理',
            description: '收藏常用文件夹，一键直达',
            color: Colors.red,
          ),
          _buildFeatureCard(
            icon: Icons.search,
            title: '快速搜索',
            description: '支持文件名搜索，带搜索历史记录',
            color: Colors.orange,
          ),
          _buildFeatureCard(
            icon: Icons.storage,
            title: '存储管理',
            description: '查看存储空间使用情况，清理缓存',
            color: Colors.purple,
          ),
          _buildFeatureCard(
            icon: Icons.palette,
            title: '主题切换',
            description: '支持浅色、深色和跟随系统主题',
            color: Colors.teal,
          ),

          const SizedBox(height: 24),

          // 版本信息
          _buildSectionTitle('版本信息', Icons.info_outline),
          const SizedBox(height: 12),
          _buildInfoCard(
            children: [
              _buildInfoRow('版本号', 'v$_version'),
              const Divider(height: 24),
              _buildInfoRow('构建号', _buildNumber.isNotEmpty ? _buildNumber : 'N/A'),
              const Divider(height: 24),
              _buildInfoRow('发布日期', '2025-11'),
              const Divider(height: 24),
              _buildInfoRow('适用平台', 'Android'),
            ],
          ),

          const SizedBox(height: 24),

          // 开发信息
          _buildSectionTitle('开发信息', Icons.code),
          const SizedBox(height: 12),
          _buildInfoCard(
            children: [
              _buildInfoRow('开发框架', 'Flutter 3.x'),
              const Divider(height: 24),
              _buildInfoRow('开发语言', 'Dart'),
              const Divider(height: 24),
              _buildInfoRow('设计规范', 'Material Design 3'),
              const Divider(height: 24),
              _buildInfoRow('架构模式', 'MVVM + Provider'),
            ],
          ),

          const SizedBox(height: 24),

          // 法律信息
          _buildSectionTitle('法律信息', Icons.gavel),
          const SizedBox(height: 12),
          _buildInfoCard(
            children: [
              Text(
                '© 2025 EasyFile Team',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '本软件按"原样"提供，不提供任何明示或暗示的保证。在任何情况下，作者或版权持有人均不对任何索赔、损害或其他责任负责。',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 致谢
          _buildSectionTitle('开源致谢', Icons.favorite_border),
          const SizedBox(height: 12),
          _buildInfoCard(
            children: [
              Text(
                '本应用使用了以下开源项目：',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              _buildOpenSourceItem('provider', '状态管理'),
              _buildOpenSourceItem('get_it', '依赖注入'),
              _buildOpenSourceItem('permission_handler', '权限管理'),
              _buildOpenSourceItem('video_player', '视频播放'),
              _buildOpenSourceItem('audioplayers', '音频播放'),
              _buildOpenSourceItem('disk_space_plus', '存储空间'),
              const SizedBox(height: 8),
              Text(
                '感谢所有开源贡献者！',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // 反馈按钮
          Center(
            child: OutlinedButton.icon(
              onPressed: () {
                // TODO: 打开反馈页面或邮件
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('反馈功能开发中')),
                );
              },
              icon: const Icon(Icons.feedback_outlined),
              label: const Text('意见反馈'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          description,
          style: const TextStyle(fontSize: 13),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
      ),
    );
  }

  Widget _buildInfoCard({required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildOpenSourceItem(String name, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                children: [
                  TextSpan(
                    text: name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  TextSpan(
                    text: ' - $description',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
}
