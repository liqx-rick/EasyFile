import 'package:easyfile/core/content/privacy_policy_content.dart';
import 'package:flutter/material.dart';

/// 隐私政策页面
/// 内容来源：[PrivacyPolicyContent]，请勿在此处直接修改文字。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私政策'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 更新日期
          Center(
            child: Text(
              '最后更新：${PrivacyPolicyContent.lastUpdated}',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 从数据模型中动态渲染所有段落
          for (final section in PrivacyPolicyContent.sections)
            if (section.isCard)
              _buildCard(context, section)
            else
              _buildSection(
                context: context,
                title: section.title,
                content: section.content,
                items: section.items,
                footer: section.footer,
              ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, PrivacySection section) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24, top: 8),
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.verified_user,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    section.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                section.items.map((e) => '✓ $e').join('\n'),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.8,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    String? content,
    List<String>? items,
    String? footer,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        if (content != null) ...[
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
            ),
          ),
          if (items != null) const SizedBox(height: 8),
        ],
        if (items != null) ...[
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 7, left: 4, right: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(fontSize: 14, height: 1.6),
                      ),
                    ),
                  ],
                ),
              )),
        ],
        if (footer != null) ...[
          const SizedBox(height: 8),
          Text(
            footer,
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
