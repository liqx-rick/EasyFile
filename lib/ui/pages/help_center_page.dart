import 'package:flutter/material.dart';

import 'faq_page.dart' show FAQPage;
import 'feature_guide_page.dart' show FeatureGuidePage;
import 'feedback_page.dart' show FeedbackPage;
import 'permission_guide_page.dart' show PermissionGuidePage;
import 'quick_start_guide_page.dart' show QuickStartGuidePage;

/// 帮助中心主页面
class HelpCenterPage extends StatelessWidget {
  const HelpCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('帮助与支持'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 欢迎卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Text(
                    '欢迎使用易览文件',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '这里为您提供详细的使用指南和帮助信息',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 快速入门
          _buildHelpCard(
            context: context,
            icon: Icons.rocket_launch,
            iconColor: Colors.blue,
            title: '快速入门',
            subtitle: '5分钟掌握核心功能',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const QuickStartGuidePage(),
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          // 功能指南
          _buildHelpCard(
            context: context,
            icon: Icons.menu_book,
            iconColor: Colors.purple,
            title: '功能指南',
            subtitle: '详细了解各项功能的使用方法',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const FeatureGuidePage(),
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          // 常见问题
          _buildHelpCard(
            context: context,
            icon: Icons.question_answer,
            iconColor: Colors.orange,
            title: '常见问题',
            subtitle: '快速找到常见问题的解决方案',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const FAQPage(),
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          // 权限说明
          _buildHelpCard(
            context: context,
            icon: Icons.security,
            iconColor: Colors.green,
            title: '权限说明',
            subtitle: '了解应用需要的权限及其用途',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const PermissionGuidePage(),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          const Divider(),

          const SizedBox(height: 12),

          // 意见反馈
          _buildHelpCard(
            context: context,
            icon: Icons.feedback_outlined,
            iconColor: Colors.teal,
            title: '意见反馈',
            subtitle: '遇到问题或有建议？告诉我们',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const FeedbackPage(),
                ),
              );
            },
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 构建帮助卡片
  Widget _buildHelpCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
