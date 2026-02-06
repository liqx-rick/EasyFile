import 'package:flutter/material.dart';

/// 权限说明页面
class PermissionGuidePage extends StatelessWidget {
  const PermissionGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('权限说明'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 说明卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '为什么需要这些权限？',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '易览文件是一款本地文件管理应用，所有权限都用于提供核心功能，不会收集或上传您的个人数据。',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 必需权限
          _buildSectionTitle(context, '必需权限', Icons.warning_amber),
          const SizedBox(height: 12),

          _buildPermissionCard(
            context: context,
            icon: Icons.folder,
            title: '存储权限',
            subtitle: '所有文件访问权限 / 读写外部存储',
            badge: '必需',
            description: '这是文件管理应用的核心权限，用于：',
            purposes: [
              '浏览、打开、预览设备上的文件和文件夹',
              '复制、移动、删除、重命名文件',
              '创建文件夹和提取压缩包',
              '扫描并分类不同类型的文件',
              '查看存储空间使用情况',
            ],
            howToGrant: '应用首次启动时会自动请求，您也可以在系统设置中手动授予：\n'
                '设置 > 应用 > 易览文件 > 权限 > 存储\n\n'
                'Android 11+：选择"允许访问所有文件"\n'
                'Android 10及以下：选择"允许"',
            impact: '如果拒绝此权限，应用将无法正常工作。',
          ),

          const SizedBox(height: 12),

          _buildPermissionCard(
            context: context,
            icon: Icons.photo_library,
            title: '照片和视频权限',
            subtitle: 'Android 13+',
            badge: '必需',
            description: '在Android 13及更高版本中，访问媒体文件需要单独授权：',
            purposes: [
              '访问图片分类中的照片',
              '访问视频分类中的视频文件',
              '生成图片和视频的缩略图',
              '预览和打开相册中的媒体文件',
            ],
            howToGrant: '应用首次启动时会请求，或在系统设置中授予：\n'
                '设置 > 应用 > 易览文件 > 权限 > 照片和视频 > 允许',
            impact: '拒绝后仍可使用应用，但无法查看图片和视频分类中的文件。',
          ),

          const SizedBox(height: 24),

          // 可选权限
          _buildSectionTitle(context, '可选权限', Icons.check_circle_outline),
          const SizedBox(height: 12),

          _buildPermissionCard(
            context: context,
            icon: Icons.fingerprint,
            title: '生物识别权限',
            subtitle: '指纹 / 面容识别',
            badge: '可选',
            description: '用于隐私空间功能，提供更便捷的安全验证：',
            purposes: [
              '使用指纹或面容解锁隐私空间',
              '替代PIN码快速进入隐私模式',
              '仅在设备上本地验证，不上传数据',
            ],
            howToGrant: '在隐私空间设置中开启生物识别时会请求权限：\n'
                '设置 > 应用 > 易览文件 > 权限 > 生物识别 > 允许',
            impact: '拒绝后仍可使用PIN码解锁隐私空间，不影响其他功能。',
          ),

          const SizedBox(height: 12),

          _buildPermissionCard(
            context: context,
            icon: Icons.apps,
            title: '查询已安装应用权限',
            subtitle: 'QUERY_ALL_PACKAGES',
            badge: '可选',
            description: '用于应用管理功能，查看设备上的应用信息：',
            purposes: [
              '列出所有已安装应用',
              '按应用查看其生成的文件',
              '显示应用图标、名称等基本信息',
              '统计应用文件占用空间',
            ],
            howToGrant: '首次进入应用管理功能时会请求，或在系统设置中授予：\n'
                '设置 > 应用 > 易览文件 > 权限 > （查找相关权限）',
            impact: '拒绝后仍可正常使用文件浏览等核心功能，但"应用管理"功能不可用。',
          ),

          const SizedBox(height: 32),

          // 如何管理权限
          _buildHowToManageSection(context),

          const SizedBox(height: 24),

          // 隐私承诺
          _buildPrivacyPromiseSection(context),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 构建分节标题
  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  /// 构建权限卡片
  Widget _buildPermissionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String badge,
    required String description,
    required List<String> purposes,
    required String howToGrant,
    required String impact,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badge,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // 用途说明
            Text(
              description,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            ...purposes.map((purpose) => Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(top: 7, right: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          purpose,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),

            const SizedBox(height: 16),

            // 如何授予
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.settings, size: 16, color: colorScheme.onPrimaryContainer),
                      const SizedBox(width: 6),
                      Text(
                        '如何授予权限',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    howToGrant,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 拒绝影响
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      impact,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 如何管理权限部分
  Widget _buildHowToManageSection(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.manage_accounts,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  '如何管理权限',
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
              '您可以随时在系统设置中查看和修改应用权限：\n\n'
              '1. 打开手机"设置"应用\n'
              '2. 找到"应用"或"应用管理"\n'
              '3. 在应用列表中找到"易览文件"\n'
              '4. 点击"权限"查看所有权限状态\n'
              '5. 点击任意权限可以开启或关闭\n\n'
              '注意：关闭必需权限可能导致应用无法正常使用。',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 隐私承诺部分
  Widget _buildPrivacyPromiseSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user, color: colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  '隐私承诺',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '✓ 所有数据仅存储在您的设备上\n'
              '✓ 不会上传您的文件或个人信息\n'
              '✓ 不包含任何广告或跟踪代码\n'
              '✓ 权限仅用于提供核心功能\n'
              '✓ 您可以随时撤销任何权限',
              style: TextStyle(
                fontSize: 13,
                height: 1.8,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
