import 'package:flutter/material.dart';

/// 隐私政策页面
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
              '最后更新：2026年2月',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 引言
          _buildSection(
            context: context,
            title: '引言',
            content: '欢迎使用易览文件（以下简称"本应用"）。我们深知隐私对您的重要性，本隐私政策旨在帮助您了解我们如何收集、使用、存储和保护您的信息。\n\n'
                '请您仔细阅读本隐私政策。使用本应用即表示您同意本隐私政策的内容。',
          ),

          // 信息收集
          _buildSection(
            context: context,
            title: '1. 信息收集',
            content: '本应用是一款完全本地化的文件管理工具，我们坚持最小化数据收集原则：',
            items: [
              '我们不会收集您的个人身份信息',
              '我们不会上传您的文件或文件列表',
              '我们不会追踪您的使用行为',
              '应用不包含任何数据分析或统计SDK',
              '所有数据均存储在您的设备本地',
            ],
          ),

          // 权限使用
          _buildSection(
            context: context,
            title: '2. 权限使用说明',
            content: '为了提供完整的文件管理功能，本应用需要以下权限：',
            items: [
              '存储权限：用于读取、管理设备上的文件和文件夹',
              '照片和视频权限（Android 13+）：用于访问图片和视频分类',
              '生物识别权限（可选）：用于隐私空间的指纹/面容解锁',
              '查询已安装应用权限（可选）：用于应用管理功能',
            ],
            footer: '所有权限仅在本地使用，不会与任何第三方共享。',
          ),

          // 数据存储
          _buildSection(
            context: context,
            title: '3. 数据存储与安全',
            items: [
              '所有数据（包括设置、缓存、收藏等）仅存储在您的设备本地',
              '隐私空间的PIN码采用加密存储',
              '应用不会自动备份数据到云端',
              '卸载应用后，所有应用数据将被清除',
            ],
          ),

          // 第三方服务
          _buildSection(
            context: context,
            title: '4. 第三方服务',
            content: '本应用当前不集成任何第三方服务：',
            items: [
              '不包含广告服务',
              '不集成数据分析工具',
              '不包含社交媒体插件',
              '不提供云存储服务',
              '不包含任何用户追踪代码',
            ],
          ),

          // 儿童隐私
          _buildSection(
            context: context,
            title: '5. 儿童隐私保护',
            content: '本应用不会故意收集13岁以下儿童的信息。如果您发现我们无意中收集了儿童的信息，请通过意见反馈联系我们，我们将尽快删除相关信息。',
          ),

          // 隐私政策变更
          _buildSection(
            context: context,
            title: '6. 隐私政策变更',
            content: '我们可能会不时更新本隐私政策。更新后的隐私政策将在应用内发布。继续使用本应用即表示您接受更新后的隐私政策。',
          ),

          // 联系我们
          _buildSection(
            context: context,
            title: '7. 联系我们',
            content: '如果您对本隐私政策有任何疑问或建议，请通过应用内的"意见反馈"功能联系我们。',
          ),

          const SizedBox(height: 32),

          // 承诺卡片
          Card(
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
                        '我们的承诺',
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
                    '✓ 您的文件永远只在您的设备上\n'
                    '✓ 我们无法访问您的任何数据\n'
                    '✓ 完全透明，无隐藏行为\n'
                    '✓ 持续保护您的隐私安全',
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

          const SizedBox(height: 16),
        ],
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
