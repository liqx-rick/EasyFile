import 'package:flutter/material.dart';

/// 服务条款/用户协议页面
class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('用户协议'),
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
            content: '欢迎使用易览文件！\n\n'
                '本用户协议（以下简称"本协议"）是您与易览文件（以下简称"本应用"）之间的法律协议。使用本应用即表示您已阅读、理解并同意接受本协议的全部条款。\n\n'
                '如果您不同意本协议的任何条款，请勿安装或使用本应用。',
          ),

          // 服务说明
          _buildSection(
            context: context,
            title: '1. 服务说明',
            content: '易览文件是一款本地文件管理工具，主要功能包括：',
            items: [
              '文件浏览与分类管理',
              '文件搜索、排序与筛选',
              '文件预览（图片、视频、音频、文档等）',
              '文件操作（复制、移动、删除、重命名等）',
              '压缩包管理',
              '隐私空间',
              '应用管理',
              '存储空间分析',
            ],
          ),

          // 使用规范
          _buildSection(
            context: context,
            title: '2. 使用规范',
            content: '使用本应用时，您同意：',
            items: [
              '仅将本应用用于合法目的',
              '不利用本应用进行任何违法活动',
              '不试图破解、修改或逆向工程本应用',
              '不删除或修改本应用的版权信息',
              '自行承担使用本应用的风险',
            ],
          ),

          // 权限说明
          _buildSection(
            context: context,
            title: '3. 权限说明',
            content: '本应用需要获取以下权限以提供完整功能：',
            items: [
              '存储权限：必需，用于访问和管理设备文件',
              '照片和视频权限：必需（Android 13+），用于访问媒体文件',
              '生物识别权限：可选，用于隐私空间解锁',
              '应用信息查询权限：可选，用于应用管理功能',
            ],
            footer: '您可以随时在系统设置中撤销已授予的权限，但这可能影响部分功能的正常使用。',
          ),

          // 知识产权
          _buildSection(
            context: context,
            title: '4. 知识产权',
            items: [
              '本应用的所有知识产权归开发者所有',
              '未经许可，不得复制、修改、传播本应用',
              '本应用中使用的开源组件遵循各自的开源许可协议',
              '应用图标、界面设计等视觉元素受版权保护',
            ],
          ),

          // 免责声明
          _buildSection(
            context: context,
            title: '5. 免责声明',
            content: '在法律允许的范围内：',
            items: [
              '本应用按"原样"提供，不提供任何明示或暗示的保证',
              '我们不对因使用本应用导致的数据丢失负责',
              '我们不对因误操作导致的文件删除负责',
              '我们不保证应用完全无错误或不间断运行',
              '用户应自行备份重要文件',
            ],
          ),

          // 数据安全
          _buildSection(
            context: context,
            title: '6. 数据安全',
            content: '关于您的数据安全：',
            items: [
              '所有数据仅存储在您的设备本地',
              '我们无法访问您设备上的任何文件',
              '隐私空间的PIN码采用加密存储',
              '文件操作（删除、移动等）不可撤销，请谨慎操作',
              '建议重要文件定期备份',
            ],
          ),

          // 服务变更与终止
          _buildSection(
            context: context,
            title: '7. 服务变更与终止',
            items: [
              '我们保留随时修改或终止服务的权利',
              '我们可能会更新应用版本以改进功能或修复问题',
              '您可以随时卸载应用以终止使用',
              '卸载后，应用数据将被清除',
            ],
          ),

          // 协议变更
          _buildSection(
            context: context,
            title: '8. 协议变更',
            content: '我们可能会不时更新本协议。更新后的协议将在应用内发布，并在您下次使用应用时生效。继续使用本应用即表示您接受更新后的协议。',
          ),

          // 适用法律
          _buildSection(
            context: context,
            title: '9. 适用法律',
            content: '本协议的解释、执行和争议解决均适用中华人民共和国法律。如发生争议，双方应友好协商解决；协商不成的，任何一方可向有管辖权的人民法院提起诉讼。',
          ),

          // 联系方式
          _buildSection(
            context: context,
            title: '10. 联系方式',
            content: '如果您对本协议有任何疑问或建议，请通过应用内的"意见反馈"功能联系我们。',
          ),

          const SizedBox(height: 32),

          // 最后声明
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
                        Icons.gavel,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '重要提醒',
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
                    '使用本应用前，请确保您已完全理解并同意本协议的所有条款。\n\n'
                    '特别提醒：文件删除操作不可恢复，请谨慎操作并定期备份重要数据。',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
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
