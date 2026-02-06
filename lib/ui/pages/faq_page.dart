import 'package:flutter/material.dart';

/// 常见问题页面
class FAQPage extends StatelessWidget {
  const FAQPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('常见问题'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 说明文字
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '快速找到常见问题的解决方案',
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

          // 文件浏览与查找
          _buildCategoryTitle(context, '文件浏览与查找', Icons.folder_open),
          const SizedBox(height: 12),

          _buildFAQItem(
            context: context,
            question: '为什么首次访问分类页面会有一个扫描的过程，而后续访问没有这个过程？',
            answer: '分类页面采用智能缓存策略：\n\n'
                '首次访问：\n'
                '• 需要遍历设备上的所有文件并分类\n'
                '• 统计各个分类的文件数量和大小\n'
                '• 扫描结果会写入缓存数据库\n\n'
                '后续访问：\n'
                '• 直接从缓存读取数据，速度非常快\n'
                '• 应用从后台恢复时会自动后台刷新\n'
                '• 通过增量更新机制只更新变化的文件\n'
                '• 发现新增或删除文件时自动提示用户\n\n'
                '手动刷新：\n'
                '• 下拉刷新可立即扫描最新文件\n'
                '• 缓存有效期为7天，过期后自动重新扫描',
          ),

          _buildFAQItem(
            context: context,
            question: '为什么在首次访问视频网格页面时会有白屏？',
            answer: '首次加载视频缩略图需要时间：\n\n'
                '原因：\n'
                '• 系统需要从视频文件中提取缩略图\n'
                '• 视频文件越大，提取时间越长\n'
                '• 首次提取后会缓存，后续访问很快\n\n'
                '优化建议：\n'
                '• 耐心等待缩略图加载完成\n'
                '• 缩略图会被缓存，下次打开很快\n'
                '• 可以先切换到列表视图浏览',
          ),

          _buildFAQItem(
            context: context,
            question: '智能推荐卡片的显示逻辑是什么？',
            answer: '应用卡片根据文件数量智能推荐：\n\n'
                '显示规则：\n'
                '• 首次访问时自动扫描所有支持的应用\n'
                '• 按优先级顺序扫描（微信、QQ、WPS、钉钉、Telegram等）\n'
                '• 文件数量达到阈值的应用才会显示（最多4个）\n'
                '• 首次访问后即固定，不再动态调整\n\n'
                '备选卡片：\n'
                '• 不足4个时递补：时光记忆、生活剪影、声音记录、大文件\n'
                '• 如需重新扫描，可在设置的开发者选项中重置推荐',
          ),

          _buildFAQItem(
            context: context,
            question: '快捷导航栏的收藏页面是做什么用的？',
            answer: '收藏页面用于快速访问常用文件：\n\n'
                '功能：\n'
                '• 显示所有收藏的文件列表\n'
                '• 方便快速访问常用文档、照片等\n\n'
                '如何收藏：\n'
                '• 方式一：在预览页面点击收藏按钮\n'
                '• 方式二：长按文件选择"添加收藏"\n\n'
                '管理收藏：\n'
                '• 在收藏页面点击文件名后的收藏图标可取消收藏\n'
                '• 在收藏页面长按文件可取消收藏\n'
                '• 支持批量取消收藏',
          ),

          _buildFAQItem(
              context: context,
              question: '最近页面显示的文件是多久的？',
              answer: '最近页面显示最近访问的20个文件：\n\n'
                  '显示规则：\n'
                  '• 按访问时间倒序排列\n'
                  '• 最多保存20个文件记录\n'
                  '• 只记录打开预览过的文件\n'
                  '• 文件夹不会被记录\n\n'),
          _buildFAQItem(
            context: context,
            question: '新文件页面如何界定新文件？',
            answer: '新文件由系统自动监听：\n\n'
                '界定规则：\n'
                '• 基于文件的创建时间或修改时间\n'
                '• 默认显示保留天数内的文件\n'
                '• 可配置保留天数：7天、15天或30天\n'
                '• 可配置显示数量：20/50/100/200\n\n'
                '配置方法：\n'
                '1. 打开"设置" > "功能设置"\n'
                '2. 点击"新文件"\n'
                '3. 选择保留天数（7天/15天/30天）\n'
                '4. 选择显示数量（20/50/100/200）\n\n'
                '注意：\n'
                '• 只监听支持的文件类型（图片、视频、音频、文档等）\n'
                '• 支持时间分组显示（今天、昨天、近N天）',
          ),

          _buildFAQItem(
            context: context,
            question: '如何更改快捷访问菜单的文件夹列表？',
            answer: '通过快捷访问管理自定义菜单内容：\n\n'
                '操作步骤：\n'
                '1. 在主页点击右上角三点菜单\n'
                '2. 选择"快捷访问管理"\n'
                '3. 在管理页面可以：\n'
                '   • 添加常用文件夹到快捷访问菜单\n'
                '   • 添加文件夹的子文件夹\n'
                '   • 添加其他自定义文件夹\n'
                '   • 设置忽略文件夹行为\n'
                '   • 重新扫描文件夹\n\n'
                '提示：\n'
                '• 快捷访问菜单默认显示系统文件夹\n'
                '• 默认显示系统文件夹可以通过快捷访问管理页面进行移除或者增加二级目录\n'
                '• 自定义的文件夹会追加显示在菜单中',
          ),

          const SizedBox(height: 24),

          // 文件操作与管理
          _buildCategoryTitle(context, '文件操作与管理', Icons.edit),
          const SizedBox(height: 12),

          _buildFAQItem(
            context: context,
            question: '为什么打不开Office文件？',
            answer: '需要安装对应的Office应用：\n\n'
                '原因：\n'
                '• 设备上没有能够打开Office文件的应用\n'
                '• Android系统需要第三方应用处理Office文档\n\n'
                '解决方法：\n'
                '1. 安装Office应用（推荐）：\n'
                '   • WPS Office（免费，推荐）\n'
                '   • Microsoft Office\n'
                '   • Google Docs\n'
                '2. 安装后重新点击文件打开\n'
                '3. 选择刚安装的应用打开\n\n'
                '提示：首次打开会弹出"打开方式"选择器',
          ),

          _buildFAQItem(
            context: context,
            question: '如何批量删除文件？',
            answer: '使用编辑模式可以批量操作文件：\n\n'
                '操作步骤：\n'
                '1. 在文件列表页面，点击右上角的铅笔图标\n'
                '2. 进入编辑模式，出现多选框\n'
                '3. 勾选需要删除的文件\n'
                '4. 点击底部工具栏的"删除"按钮\n'
                '5. 确认删除即可\n\n'
                '快捷操作：\n'
                '• 点击"全选"按钮快速选择所有文件\n'
                '• 支持批量复制、移动、分享、收藏等操作\n\n'
                '提示：删除的文件会进入回收站，默认保留7天。',
          ),

          _buildFAQItem(
            context: context,
            question: '为什么加密的压缩包提供密码后仍然不能预览和解压？',
            answer: '可能是密码错误或不支持的加密算法：\n\n'
                '常见原因：\n'
                '• 密码输入错误（注意大小写）\n'
                '• 压缩包使用了不支持的加密算法\n'
                '• 压缩包文件已损坏\n'
                '• 部分加密的7z文件可能不支持\n\n'
                '解决方法：\n'
                '1. 确认密码正确（注意大小写和空格）\n'
                '2. 重新尝试输入密码\n'
                '3. 如果仍然失败，可能是加密算法不支持\n'
                '4. 尝试在电脑上解压后传输文件\n\n'
                '当前支持：\n'
                '• ZIP标准加密\n'
                '• RAR加密（部分算法）\n'
                '• 7Z基础加密',
          ),

          const SizedBox(height: 24),

          // 回收站与清理
          _buildCategoryTitle(context, '回收站与清理', Icons.delete_outline),
          const SizedBox(height: 12),

          _buildFAQItem(
            context: context,
            question: '回收站文件会自动清空吗？',
            answer: '是的，回收站有自动清理机制：\n\n'
                '默认规则：\n'
                '• 文件在回收站中默认保留7天\n'
                '• 超过7天的文件会自动永久删除\n'
                '• 您也可以手动清空回收站\n\n'
                '查看回收站：\n'
                '• 在推荐区向右滑动找到"回收站"卡片\n'
                '• 点击进入查看回收站中的文件\n'
                '• 支持恢复文件到原位置或永久删除',
          ),

          _buildFAQItem(
            context: context,
            question: '如何更改回收站自动清理的周期？',
            answer: '在设置中可以配置保留天数：\n\n'
                '操作步骤：\n'
                '1. 打开"设置" > "功能配置"\n'
                '2. 点击"回收站配置"\n'
                '3. 调整"自动清理周期"（可设置3-30天）\n'
                '4. 保存设置即可\n\n'
                '可选项：\n'
                '• 3天\n'
                '• 7天（默认）\n'
                '• 15天\n'
                '• 30天\n'
                '• 或完全关闭回收站功能',
          ),

          _buildFAQItem(
            context: context,
            question: '关闭回收站有什么弊端和好处？',
            answer: '关闭回收站需要权衡利弊：\n\n'
                '好处：\n'
                '• 删除文件立即释放存储空间\n'
                '• 删除操作更快\n'
                '• 不占用回收站存储空间\n\n'
                '弊端：\n'
                '• 删除后无法恢复文件\n'
                '• 误删文件将永久丢失\n'
                '• 失去"后悔"的机会\n\n'
                '建议：\n'
                '• 如果设备存储空间充足，建议保持回收站开启\n'
                '• 如果经常误删文件，强烈建议保持开启\n'
                '• 如果确定不会误删，可以关闭以节省空间',
          ),

          const SizedBox(height: 24),

          // 应用管理与权限
          _buildCategoryTitle(context, '应用管理与权限', Icons.apps),
          const SizedBox(height: 12),

          _buildFAQItem(
            context: context,
            question: '为什么应用管理页面上的统计卡片的数据显示不完整？',
            answer: '需要授予"允许访问使用记录"权限：\n\n'
                '原因：\n'
                '• 应用管理需要访问应用使用情况统计\n'
                '• Android系统要求单独授予此权限\n'
                '• 未授权时部分数据无法获取\n\n'
                '授权步骤：\n'
                '1. 首次访问应用管理页面会自动提示\n'
                '2. 点击"前往授权"按钮\n'
                '3. 在系统设置中找到"易览文件"\n'
                '4. 开启"允许访问使用记录"权限\n'
                '5. 返回应用，下拉刷新即可看到完整数据\n\n'
                '授权后可以：\n'
                '• 查看应用数量、总占用空间、缓存总量\n'
                '• 按大小、名称、使用排序应用列表\n'
                '• 显示系统应用',
          ),

          const SizedBox(height: 24),

          // 隐私与安全
          _buildCategoryTitle(context, '隐私与安全', Icons.security),
          const SizedBox(height: 12),

          _buildFAQItem(
            context: context,
            question: '为什么我从隐私空间删除或者重置隐私空间后文件找不到了？',
            answer: '隐私空间的删除和重置操作是永久性的：\n\n'
                '删除操作：\n'
                '• 从隐私空间删除文件是永久删除\n'
                '• 不会进入回收站\n'
                '• 无法恢复\n\n'
                '重置隐私空间：\n'
                '• 会清空所有隐私空间中的文件\n'
                '• 重置PIN码\n'
                '• 所有隐私文件永久删除，无法恢复\n\n'
                '安全提示：\n'
                '• 隐私空间的设计就是为了保护隐私\n'
                '• 删除和重置是不可逆操作\n'
                '• 操作前请确认文件不再需要\n'
                '• 重要文件建议先移出隐私空间再删除',
          ),

          _buildFAQItem(
            context: context,
            question: '忘记隐私空间PIN码怎么办？',
            answer: '抱歉，出于安全考虑，忘记PIN码只能重置：\n\n'
                '原因：\n'
                '• PIN码采用不可逆加密存储\n'
                '• 没有"找回密码"功能，以保护您的隐私\n'
                '• 即使是开发者也无法获取您的PIN码\n\n'
                '解决方法：\n'
                '1. 在隐私空间登录页面，多次输入错误PIN码\n'
                '2. 系统会提示"重置隐私空间"选项\n'
                '3. 重置后所有隐私文件将被永久删除\n'
                '4. 重新设置新的PIN码\n\n'
                '预防措施：\n'
                '• 使用容易记住但不易被猜到的PIN码\n'
                '• 启用生物识别（指纹/面容）作为辅助\n'
                '• 将PIN码记录在安全的地方（如密码管理器）\n'
                '• 重要文件建议备份到云端',
          ),

          const SizedBox(height: 32),

          // 底部提示
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
                        Icons.contact_support,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '没有找到您的问题？',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '您可以：\n'
                    '• 查看"快速入门"了解基本操作\n'
                    '• 查看"功能指南"了解详细使用方法\n'
                    '• 前往"意见反馈"向我们提问\n'
                    '• 查看"关于"页面了解应用信息',
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

  /// 构建分类标题
  Widget _buildCategoryTitle(BuildContext context, String title, IconData icon) {
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

  /// 构建FAQ项
  Widget _buildFAQItem({
    required BuildContext context,
    required String question,
    required String answer,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(
            question,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                answer,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
