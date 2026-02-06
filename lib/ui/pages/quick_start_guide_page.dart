import 'package:flutter/material.dart';

/// 快速入门页面
class QuickStartGuidePage extends StatelessWidget {
  const QuickStartGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('快速入门'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 引导文字
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.tips_and_updates,
                    color: Theme.of(context).colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '掌握这5个操作，快速上手易览文件',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 1. 认识主界面
          _buildGuideSection(
            context: context,
            number: '1',
            title: '认识主界面',
            icon: Icons.home,
            color: Theme.of(context).colorScheme.primary,
            steps: [
              '顶部5个分类卡片：图片、文档、音乐、视频、下载',
              '中部智能推荐区显示常用应用文件（微信、QQ等），右侧有浏览文件和存储管理',
              '向右滑动推荐区查看更多功能：压缩包、回收站、垃圾清理等',
              '快捷导航栏：快捷访问、收藏、最近、新文件',
            ],
            tips: '从上到下依次是：分类卡片、智能推荐区、快捷导航栏、内容区域',
          ),

          const SizedBox(height: 20),

          // 2. 快速查找文件
          _buildGuideSection(
            context: context,
            number: '2',
            title: '快速查找文件',
            icon: Icons.search,
            color: Theme.of(context).colorScheme.primary,
            steps: [
              '按类型查找：点击顶部分类卡片查看全设备对应文件',
              '按应用查找：点击智能推荐卡片（微信、QQ等）',
              '按文件夹查找：点击"快捷访问"选择系统文件夹',
              '按时间查找：点击"最近"或"新文件"查看相关文件',
            ],
            tips: '分类卡片会自动扫描全设备，无需手动刷新',
          ),

          const SizedBox(height: 20),

          // 3. 浏览和搜索
          _buildGuideSection(
            context: context,
            number: '3',
            title: '浏览和搜索',
            icon: Icons.folder_open,
            color: Theme.of(context).colorScheme.primary,
            steps: [
              '点击文件夹可进入子文件夹浏览',
              '点击右上角搜索图标，输入文件名查找',
              '点击排序按钮选择排序方式（名称、时间、大小、类型）',
              '切换列表/网格视图查看文件',
            ],
            tips: '搜索支持部分匹配，输入文件名的一部分即可',
          ),

          const SizedBox(height: 20),

          // 4. 文件操作
          _buildGuideSection(
            context: context,
            number: '4',
            title: '文件操作',
            icon: Icons.edit,
            color: Theme.of(context).colorScheme.primary,
            steps: [
              '单击文件：打开预览界面',
              '长按文件：显示操作菜单（收藏、重命名、移动、复制、分享、删除等）',
              '编辑模式：点击铅笔图标进入，勾选多个文件进行批量操作',
              '收藏文件：在预览页面点击收藏按钮，或长按选择"添加收藏"',
            ],
            tips: '长按操作菜单提供最全的单文件功能，编辑模式适合批量处理',
          ),

          const SizedBox(height: 20),

          // 5. 使用实用功能
          _buildGuideSection(
            context: context,
            number: '5',
            title: '使用实用功能',
            icon: Icons.widgets,
            color: Theme.of(context).colorScheme.primary,
            steps: [
              '浏览文件：点击右侧"浏览文件"卡片进入系统文件夹导航',
              '存储管理：查看空间占用情况',
              '更多功能：在推荐区向右滑动查看压缩包管理、回收站、垃圾清理、隐私空间等',
            ],
            tips: '在推荐区向右滑动可看到更多高级文件管理工具',
          ),

          const SizedBox(height: 32),

          // 下一步提示
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
                        Icons.lightbulb_outline,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '继续探索',
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
                    '• 查看"功能指南"了解压缩包、回收站、隐私空间等高级功能\n'
                    '• 遇到问题？访问"常见问题"快速找到答案\n'
                    '• 有建议或反馈？前往"意见反馈"告诉我们',
                    style: TextStyle(
                      fontSize: 13,
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

  /// 构建指南章节
  Widget _buildGuideSection({
    required BuildContext context,
    required String number,
    required String title,
    required IconData icon,
    required Color color,
    required List<String> steps,
    String? tips,
  }) {
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
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    number,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 步骤列表
            ...steps.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 7, left: 4, right: 12),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                    ),
                  ],
                ),
              );
            }),

            // 提示
            if (tips != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tips,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
