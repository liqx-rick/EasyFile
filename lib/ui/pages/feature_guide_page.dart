import 'package:flutter/material.dart';

/// 功能指南页面
class FeatureGuidePage extends StatelessWidget {
  const FeatureGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('功能指南'),
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
                    Icons.menu_book,
                    color: Theme.of(context).colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '详细了解易览文件的各项功能',
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

          // 1. 文件查找与浏览
          _buildSectionTitle(context, '文件查找与浏览', Icons.search),
          const SizedBox(height: 12),

          _buildFeatureCard(
            context: context,
            icon: Icons.category,
            title: '分类卡片',
            description: '按类型快速查找：图片、文档、音乐、视频、下载',
            details: [
              '• 顶部5个分类卡片：图片、文档、音乐、视频、下载',
              '• 自动扫描全设备对应类型的文件',
              '• 支持列表和网格两种视图模式',
              '• 可按名称、时间、大小、类型排序',
              '• 支持时间分组显示',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.recommend,
            title: '智能推荐区',
            description: '快速访问常用应用文件和功能',
            details: [
              '• 前4个推荐卡片：根据文件数量显示应用（微信/QQ/WPS/钉钉/Telegram等）',
              '• 不足4个时递补：时光记忆、生活剪影、声音记录、大文件',
              '• 右侧固定卡片：浏览文件、存储管理',
              '• 向右滑动查看第二屏：压缩包、回收站、垃圾清理、安装包、应用管理、隐私空间',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.navigation,
            title: '快捷导航栏',
            description: '快速切换不同内容视图',
            details: [
              '• 快捷访问：下拉菜单默认显示系统文件夹（下载、相册、文档等）',
              '• 收藏：查看收藏的文件列表',
              '• 最近：自动记录最近访问的文件',
              '• 新文件：查看近期新增的文件',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.folder_open,
            title: '浏览文件',
            description: '进入系统文件夹导航',
            details: [
              '• 点击智能推荐区右侧"浏览文件"卡片',
              '• 进入系统文件夹导航模式',
              '• 点击文件夹进入子文件夹浏览',
              '• 支持文件夹层级导航',
            ],
          ),

          const SizedBox(height: 32),

          // 2. 文件操作与管理
          _buildSectionTitle(context, '文件操作与管理', Icons.edit),
          const SizedBox(height: 12),

          _buildFeatureCard(
            context: context,
            icon: Icons.visibility,
            title: '文件预览',
            description: '支持多种格式的文件预览',
            details: [
              '• 单击文件打开预览界面',
              '• 支持图片、视频、音频、文档、PDF等格式',
              '• 图片和视频支持左右滑动切换',
              '• 预览页面可进行分享、删除、打印等单文件相关的操作',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.more_vert,
            title: '单文件操作',
            description: '长按文件显示操作菜单',
            details: [
              '• 长按任意文件显示操作菜单',
              '• 查看详情：文件大小、修改时间等信息',
              '• 添加收藏：收藏常用文件',
              '• 重命名、移动、复制文件',
              '• 移入隐私空间保护私密文件',
              '• 分享、打印、删除等操作',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.select_all,
            title: '批量操作',
            description: '编辑模式下多选文件进行批量处理',
            details: [
              '• 点击铅笔图标进入编辑模式',
              '• 勾选需要操作的文件',
              '• 底部操作栏提供批量操作按钮',
              '• 支持批量复制、移动、删除、收藏、分享',
              '• 点击全选按钮快速选择所有文件',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.star,
            title: '收藏功能',
            description: '收藏文件快速访问',
            details: [
              '• 方式一：在预览页面点击收藏按钮',
              '• 方式二：长按文件选择"添加收藏"',
              '• 点击快捷导航栏的"收藏"查看收藏列表',
              '• 收藏的文件会显示在内容区域',
            ],
          ),

          const SizedBox(height: 32),

          // 3. 推荐与发现
          _buildSectionTitle(context, '推荐与发现', Icons.explore),
          const SizedBox(height: 12),

          _buildFeatureCard(
            context: context,
            icon: Icons.fiber_new,
            title: '新文件监测',
            description: '自动发现近期新增的文件',
            details: [
              '• 基于MediaStore自动监听近期新增文件',
              '• 可配置保留天数（7天/15天/30天）',
              '• 自动发现照片、视频、文档、音频等',
              '• 支持时间分组显示（今天、昨天、近N天）',
              '• 在设置中配置新文件显示策略',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.apps,
            title: '应用专属文件',
            description: '集中显示常用应用生成的文件',
            details: [
              '• 首次访问后根据文件数量显示应用卡片（最多4个）',
              '• 按优先级扫描应用：微信、QQ、WPS、钉钉、Telegram等',
              '• 文件数量达到阈值的应用才会显示',
              '• 首次访问后即固定，不再动态调整',
              '• 不足4个时递补：时光记忆、生活剪影、声音记录、大文件',
              '• 点击应用卡片快速查看对应文件',
            ],
          ),

          const SizedBox(height: 32),

          // 4. 工具与清理
          _buildSectionTitle(context, '工具与清理', Icons.build),
          const SizedBox(height: 12),

          _buildFeatureCard(
            context: context,
            icon: Icons.archive,
            title: '压缩包管理',
            description: '查看和解压ZIP、RAR、7Z等压缩包',
            details: [
              '• 支持查看压缩包内文件列表',
              '• 可预览压缩包内的图片、文档等',
              '• 支持全部解压到指定目录',
              '• 支持密码保护的压缩包（输入密码后解压）',
              '• 支持查看解压记录，允许清理解压记录',
              '• 在推荐区向右滑动查看"压缩包管理"卡片',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.delete_outline,
            title: '回收站',
            description: '恢复误删文件或永久删除',
            details: [
              '• 删除的文件自动移入回收站',
              '• 支持恢复误删的文件到原位置',
              '• 可手动清空回收站释放空间',
              '• 默认保留7天后自动清空',
              '• 在设置中配置保留天数或关闭回收站功能',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.cleaning_services,
            title: '垃圾清理',
            description: '清理无用文件释放存储空间',
            details: [
              '• 清理空文件夹（删除不包含文件的文件夹）',
              '• 清理安装包（APK文件）',
              '• 清理临时文件',
              '• 清理系统回收站中长期未清理的文件',
              '• 在推荐区向右滑动查看"垃圾清理"卡片',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.android,
            title: '安装包管理',
            description: '管理APK安装包',
            details: [
              '• 扫描设备上的APK安装包',
              '• 显示安装包的状态（已安装/未安装）',
              '• 点击已安装按钮显示应用信息',
              '• 点击未安装按钮进行安装（首次使用需要赋予权限）',
              '• 点击列表项显示安装包文件的详细信息',
              '• 删除不需要的安装包',
              '• 在推荐区向右滑动查看"安装包管理"卡片',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.phone_android,
            title: '应用管理',
            description: '查看已安装应用及其存储占用',
            details: [
              '• 首次访问需要打开"允许访问使用记录"权限才能使用完整功能',
              '• 授权后可以下拉刷新应用列表',
              '• 顶部卡片正确显示应用数量、总占用空间及缓存总量',
              '• 应用列表可以按大小、名称、使用来显示列表顺序',
              '• 点击"显示系统应用"可以显示系统默认安装的应用',
              '• 查看应用详细信息',
              '• 在推荐区向右滑动查看"应用管理"卡片',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.storage,
            title: '存储管理',
            description: '查看空间占用并优化存储',
            details: [
              '• 可视化展示各类型文件占用空间',
              '• 大文件分析：扫描并列出大文件，快速释放空间',
              '• 重复文件检测：智能检测重复文件，避免浪费空间',
              '• 查看存储空间使用情况',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.folder_special,
            title: '快捷访问文件夹',
            description: '从快捷访问菜单访问系统文件夹',
            details: [
              '• 点击快捷导航栏的"快捷访问"下拉菜单',
              '• 选择系统常用文件夹（下载、相册、文档等）',
              '• 快速进入选中的文件夹',
              '• 文件会显示在下方内容区域',
            ],
          ),

          const SizedBox(height: 32),

          // 5. 设置与个性化
          _buildSectionTitle(context, '设置与个性化', Icons.settings),
          const SizedBox(height: 12),

          _buildFeatureCard(
            context: context,
            icon: Icons.lock,
            title: '隐私空间',
            description: 'PIN码或生物识别保护私密文件',
            details: [
              '• 首次使用需设置4位PIN码',
              '• 可启用指纹或面容识别（支持设备的生物识别方式）',
              '• 移入隐私空间的文件被隐藏保护',
              '• 支持会话超时自动锁定',
              '• 可查看、打开、移出或删除隐私文件',
              '• 点击左上角设置按钮可设定：生物识别开关、修改PIN码、重置隐私空间',
              '• 在推荐区向右滑动查看"隐私空间"卡片',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.edit_location,
            title: '自定义快捷访问菜单',
            description: '通过快捷访问管理，可以自定义快捷访问菜单的显示列表',
            details: [
              '• 添加常用文件夹到快捷访问菜单',
              '• 添加文件夹的子文件夹',
              '• 添加其他自定义文件夹',
              '• 设置忽略文件夹行为',
              '• 重新扫描文件夹',
              '• 管理会影响快捷访问下拉菜单显示的文件夹',
              '• 在主页三点菜单中选择"快捷访问管理"',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.palette,
            title: '显示偏好',
            description: '自定义外观主题和文件显示方式',
            details: [
              '• 主题模式：浅色、深色、跟随系统',
              '• 视图模式：列表或网格视图',
              '• 排序方式：按名称、时间、大小、类型',
              '• 显示/隐藏文件设置',
              '• 自定义各页面的视图和排序方式',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.storage_outlined,
            title: '存储与缓存',
            description: '管理应用缓存和临时文件',
            details: [
              '查看缓存使用情况',
              '清理应用缓存',
              '临时文件清理设置',
              '管理存储空间',
            ],
          ),

          _buildFeatureCard(
            context: context,
            icon: Icons.tune,
            title: '功能配置',
            description: '配置各项功能的显示策略',
            details: [
              '• 新文件显示策略：配置保留天数（7天/15天/30天）',
              '• 最近文件显示策略配置',
              '• 回收站功能：启用/禁用及保留天数设置',
              '• 其他功能的个性化配置',
            ],
          ),

          const SizedBox(height: 32),
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

  /// 构建功能卡片
  Widget _buildFeatureCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required List<String> details,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              description,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: details.map((detail) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      detail,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
