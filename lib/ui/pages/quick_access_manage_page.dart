import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';
import 'package:easyfile/viewmodel/quick_access_viewmodel.dart';

/// 快速访问管理页面
///
/// 三层分类展示：系统目录、应用目录、用户自定义
/// 支持应用子目录树状展开、扫描、别名编辑等功能
class QuickAccessManagePage extends StatefulWidget {
  final QuickAccessPresenter presenter;
  final QuickAccessViewModel viewModel;

  const QuickAccessManagePage({
    super.key,
    required this.presenter,
    required this.viewModel,
  });

  @override
  State<QuickAccessManagePage> createState() => _QuickAccessManagePageState();
}

class _QuickAccessManagePageState extends State<QuickAccessManagePage> {
  // 应用目录展开状态
  final Map<String, bool> _expandedAppFolders = {};

  // 是否处于首页排序编辑模式
  bool _isEditingHomeOrder = false;

  // 选中的文件夹ID集合
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    // 延迟加载避免在build期间触发setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    await widget.presenter.loadQuickAccessFolders();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, child) {
        return Scaffold(
          appBar: _buildAppBar(),
          body: _buildBody(),
          floatingActionButton: _buildFAB(),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.home),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: '返回主页',
      ),
      title: const Row(
        children: [
          Icon(Icons.folder_special, size: 24),
          SizedBox(width: 8),
          Text('快速访问管理'),
        ],
      ),
      actions: [
        // 扫描按钮
        PopupMenuButton<String>(
          icon: const Icon(Icons.radar),
          tooltip: '扫描目录',
          onSelected: _handleScanAction,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'incremental',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.update),
                title: Text('增量扫描'),
                subtitle: Text('检测新增的应用目录'),
              ),
            ),
            const PopupMenuItem(
              value: 'user',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.search),
                title: Text('常规扫描'),
                subtitle: Text('扫描常用应用'),
              ),
            ),
            const PopupMenuItem(
              value: 'deep',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.manage_search),
                title: Text('深度扫描'),
                subtitle: Text('全面扫描所有应用'),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'detect_user',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.folder_open),
                title: Text('检测用户目录'),
                subtitle: Text('查找用户创建的文件夹'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (widget.viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.viewModel.folders.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 2),
        children: [
          // 扫描提示（如果正在扫描）
          if (widget.viewModel.isScanning) _buildScanningIndicator(),

          // 首页展示区域
          _buildHomeDisplaySection(),

          // 系统目录部分
          _buildSection(
            title: '系统目录',
            icon: Icons.security,
            folders: widget.viewModel.systemFolders,
            color: Colors.blue,
          ),

          // 应用目录部分（带树状结构）
          _buildAppSection(),

          // 用户自定义部分
          _buildSection(
            title: '用户自定义',
            icon: Icons.person,
            folders: widget.viewModel.userCustomFolders,
            color: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildScanningIndicator() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text(
            '正在扫描目录...',
            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  /// 构建首页展示区域
  Widget _buildHomeDisplaySection() {
    // 获取用户定制的首页文件夹（homeDisplayOrder 不为 null）
    final userCustomizedFolders = widget.viewModel.folders
        .where((f) => f.homeDisplayOrder != null)
        .toList()
      ..sort(
        (a, b) => (a.homeDisplayOrder ?? 999).compareTo(
          b.homeDisplayOrder ?? 999,
        ),
      );

    // 首页推荐区域最多6个文件夹（不再有"更多"按钮）
    const maxHomeItems = 6;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 16, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Row(
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text(
                '首页展示 (${userCustomizedFolders.length}/$maxHomeItems)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (userCustomizedFolders.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isEditingHomeOrder = !_isEditingHomeOrder;
                    });
                  },
                  icon: Icon(_isEditingHomeOrder ? Icons.check : Icons.sort),
                  label: Text(_isEditingHomeOrder ? '完成' : '排序'),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 卡片列表或空状态
          if (userCustomizedFolders.isEmpty)
            _buildEmptyHomeDisplay()
          else
            _isEditingHomeOrder
                ? _buildHomeDisplayReorderable(userCustomizedFolders)
                : _buildHomeDisplayCards(userCustomizedFolders),
        ],
      ),
    );
  }

  /// 空状态提示
  Widget _buildEmptyHomeDisplay() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.lightbulb_outline, size: 48, color: Colors.amber[400]),
            const SizedBox(height: 12),
            Text(
              '未定制首页推荐',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '首页当前显示随机系统目录',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              '从下方列表选择项目加入首页，定制您的专属推荐',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  /// 非编辑模式：横向均匀分布卡片
  Widget _buildHomeDisplayCards(List<QuickAccessFolder> folders) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据卡片数量和屏幕宽度动态调整padding
        final totalPositions = folders.length;
        final screenWidth = constraints.maxWidth;

        // 动态计算padding：屏幕越小或卡片越多，padding越小
        double horizontalPadding;
        if (totalPositions >= 6) {
          // 6个卡片：根据屏幕宽度调整
          horizontalPadding = screenWidth > 400 ? 8.0 : 4.0;
        } else {
          horizontalPadding = screenWidth > 400 ? 20.0 : 12.0;
        }

        final minSpacing = 2.0;

        // 计算可用空间（减去两侧padding）
        final availableWidth = constraints.maxWidth - (horizontalPadding * 2);

        // 计算间距总宽度
        final spacingCount = totalPositions - 1;
        final totalSpacing = minSpacing * spacingCount;

        // 计算卡片大小：(可用宽度 - 间距总宽度) / 卡片数量
        // 移除最大值限制，让卡片可以更灵活地缩小
        final cardSize = ((availableWidth - totalSpacing) / totalPositions)
            .clamp(40.0, 100.0);

        // 重新计算实际间距
        final actualTotalSpacing = availableWidth - (cardSize * totalPositions);
        final spacing = (actualTotalSpacing / spacingCount).clamp(
          minSpacing,
          minSpacing * 2,
        );

        return SizedBox(
          height: cardSize,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                for (int i = 0; i < folders.length; i++) ...[
                  _buildHomeCard(folders[i], i, cardSize),
                  if (i < folders.length - 1) SizedBox(width: spacing),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// 单个首页卡片
  Widget _buildHomeCard(QuickAccessFolder folder, int index, double cardSize) {
    return SizedBox(
      width: cardSize,
      height: cardSize,
      child: Card(
        elevation: 2,
        child: InkWell(
          onTap: () {
            // 可以点击预览或导航
          },
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _getFolderIcon(folder),
                      size: cardSize * 0.35,
                      color: _getFolderColor(folder.type),
                    ),
                    SizedBox(height: cardSize * 0.03),
                    SizedBox(
                      width: cardSize - 4,
                      child: Text(
                        folder.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: (cardSize * 0.16).clamp(9.0, 12.0),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 移除按钮
              Positioned(
                top: 2,
                right: 2,
                child: InkWell(
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final success = await widget.presenter.setHomeDisplayOrder(
                      folder.id,
                      null,
                    );
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text(success ? '已移出首页' : '操作失败')),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(0.5),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 编辑模式：可拖拽排序列表
  Widget _buildHomeDisplayReorderable(List<QuickAccessFolder> folders) {
    return ReorderableListView.builder(
      shrinkWrap: true, // 必须：ReorderableListView 要求
      physics: const NeverScrollableScrollPhysics(),
      itemCount: folders.length,
      onReorder: (oldIndex, newIndex) async {
        if (oldIndex < newIndex) {
          newIndex -= 1;
        }

        // 更新顺序
        final orderMap = <String, int?>{};
        for (int i = 0; i < folders.length; i++) {
          int newOrder;
          if (i == oldIndex) {
            newOrder = newIndex;
          } else if (oldIndex < newIndex) {
            if (i > oldIndex && i <= newIndex) {
              newOrder = i - 1;
            } else {
              newOrder = i;
            }
          } else {
            if (i >= newIndex && i < oldIndex) {
              newOrder = i + 1;
            } else {
              newOrder = i;
            }
          }
          orderMap[folders[i].id] = newOrder;
        }

        await widget.presenter.updateHomeDisplayOrders(orderMap);
      },
      itemBuilder: (context, index) {
        final folder = folders[index];
        return _buildHomeReorderableItem(
          folder,
          index,
          key: ValueKey(folder.id),
        );
      },
    );
  }

  /// 可拖拽的首页项
  Widget _buildHomeReorderableItem(
    QuickAccessFolder folder,
    int index, {
    required Key key,
  }) {
    return ListTile(
      key: key,
      leading: Icon(
        _getFolderIcon(folder),
        color: _getFolderColor(folder.type),
      ),
      title: Text(folder.displayName),
      subtitle: Text(folder.path, style: const TextStyle(fontSize: 11)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final success = await widget.presenter.setHomeDisplayOrder(
                folder.id,
                null,
              );
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(content: Text(success ? '已移出首页' : '操作失败')),
              );
            },
            tooltip: '移出首页',
          ),
          const Icon(Icons.drag_handle),
        ],
      ),
    );
  }

  IconData _getFolderIcon(QuickAccessFolder folder) {
    switch (folder.type) {
      case QuickAccessFolderType.system:
        return Icons.folder_special;
      case QuickAccessFolderType.appRoot:
      case QuickAccessFolderType.appSubfolder:
        return Icons.apps;
      case QuickAccessFolderType.userCustom:
        return Icons.folder;
    }
  }

  Color _getFolderColor(QuickAccessFolderType type) {
    switch (type) {
      case QuickAccessFolderType.system:
        return Colors.blue;
      case QuickAccessFolderType.appRoot:
      case QuickAccessFolderType.appSubfolder:
        return Colors.orange;
      case QuickAccessFolderType.userCustom:
        return Colors.green;
    }
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  '暂无快速访问目录',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  '点击右下角按钮开始扫描',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _handleScanAction('user'),
                  icon: const Icon(Icons.search),
                  label: const Text('开始扫描'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<QuickAccessFolder> folders,
    required Color color,
  }) {
    if (folders.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${folders.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...folders.map((folder) => _buildFolderTile(folder, color)),
        const Divider(height: 1, thickness: 0.5),
      ],
    );
  }

  Widget _buildAppSection() {
    final appRoots = widget.viewModel.appRootFolders;
    if (appRoots.isEmpty) return const SizedBox.shrink();

    final hierarchy = widget.presenter.getAppFolderHierarchy();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.apps, size: 20, color: Colors.orange),
              const SizedBox(width: 8),
              const Text(
                '应用目录',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${appRoots.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...appRoots.map((root) {
          final subfolders = hierarchy[root.path] ?? [];
          final isExpanded = _expandedAppFolders[root.path] ?? false;

          return _buildAppFolderWithSubfolders(
            root: root,
            subfolders: subfolders,
            isExpanded: isExpanded,
          );
        }),
        const Divider(height: 1, thickness: 0.5),
      ],
    );
  }

  Widget _buildAppFolderWithSubfolders({
    required QuickAccessFolder root,
    required List<QuickAccessFolder> subfolders,
    required bool isExpanded,
  }) {
    return Column(
      children: [
        _buildFolderTile(
          root,
          Colors.orange,
          trailing: subfolders.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onPressed: () {
                    setState(() {
                      _expandedAppFolders[root.path] = !isExpanded;
                    });
                  },
                )
              : null,
        ),
        if (isExpanded && subfolders.isNotEmpty)
          ...subfolders.map(
            (subfolder) => Padding(
              padding: const EdgeInsets.only(left: 32),
              child: _buildFolderTile(
                subfolder,
                Colors.orange.withValues(alpha: 0.7),
                isSubfolder: true,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFolderTile(
    QuickAccessFolder folder,
    Color color, {
    Widget? trailing,
    bool isSubfolder = false,
  }) {
    final isSelected = _selectedIds.contains(folder.id);
    final exists = Directory(folder.path).existsSync();

    return ListTile(
      selected: isSelected,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _buildFolderIcon(folder, isSubfolder, exists, color),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontWeight: isSubfolder ? FontWeight.normal : FontWeight.w500,
                  color: exists
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black)
                      : Colors.grey,
                  decoration: exists ? null : TextDecoration.lineThrough,
                  fontSize: 16,
                ),
                children: [
                  TextSpan(text: folder.originalName),
                  if (folder.userAlias != null) ...[
                    TextSpan(
                      text: ' | 别名：',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                    TextSpan(
                      text: folder.userAlias!,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (folder.homeDisplayOrder != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                Icons.push_pin,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: trailing ?? _buildFolderActions(folder),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(
          left: 36, // 图标宽度(24) + 右边距(12) = 36
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              folder.path,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (!exists)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: const Text(
                  '目录不存在',
                  style: TextStyle(fontSize: 11, color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建文件夹图标（包含状态指示）
  Widget _buildFolderIcon(
    QuickAccessFolder folder,
    bool isSubfolder,
    bool exists,
    Color color,
  ) {
    // 子文件夹使用箭头图标
    if (isSubfolder) {
      return Icon(
        Icons.subdirectory_arrow_right,
        color: exists ? color : Colors.grey,
        size: 20,
      );
    }

    // 首页展示：使用星标文件夹
    if (folder.isOnHomePage) {
      return Icon(
        Icons.folder_special,
        color: exists ? Colors.amber : Colors.grey,
        size: 24,
      );
    }

    // 已加入快速访问但不在首页：文件夹+对钩叠加
    if (folder.isAddedToQuickAccess) {
      return SizedBox(
        width: 24,
        height: 24,
        child: Stack(
          children: [
            Icon(Icons.folder, color: exists ? color : Colors.grey, size: 24),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green[600],
                  size: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 未加入：普通文件夹
    return Icon(Icons.folder, color: exists ? color : Colors.grey, size: 24);
  }

  Widget _buildFolderActions(QuickAccessFolder folder) {
    final isOnHomePage = folder.isOnHomePage;
    final isAdded = folder.isAddedToQuickAccess;

    return PopupMenuButton<String>(
      onSelected: (value) => _handleFolderAction(value, folder),
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];

        // 首页展示操作 - 所有项目都可以加入首页展示
        if (isOnHomePage) {
          items.add(
            const PopupMenuItem(
              value: 'remove_from_home',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.star_border),
                title: Text('移出首页展示'),
              ),
            ),
          );
        } else {
          items.add(
            const PopupMenuItem(
              value: 'add_to_home',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.star),
                title: Text('加入首页展示'),
              ),
            ),
          );
        }

        // 别名编辑
        items.add(
          const PopupMenuItem(
            value: 'alias',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.edit),
              title: Text('编辑别名'),
            ),
          ),
        );

        // 快速访问操作（与首页展示互斥）
        items.add(const PopupMenuDivider());
        if (isAdded) {
          // 已加入快速访问，显示移除选项
          items.add(
            const PopupMenuItem(
              value: 'remove_from_qa',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.remove_circle_outline),
                title: Text('移出快速访问'),
              ),
            ),
          );
        } else if (isOnHomePage) {
          // 已在首页展示，快速访问不可用
          items.add(
            const PopupMenuItem(
              enabled: false,
              value: 'add_to_qa_disabled',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.add_circle_outline, color: Colors.grey),
                title: Text(
                  '加入快速访问（已在首页）',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          );
        } else {
          // 未加入快速访问，且不在首页，显示加入选项
          items.add(
            const PopupMenuItem(
              value: 'add_to_qa',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.add_circle_outline, color: Colors.green),
                title: Text('加入快速访问', style: TextStyle(color: Colors.green)),
              ),
            ),
          );
          items.add(
            const PopupMenuItem(
              value: 'hide',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.visibility_off, color: Colors.orange),
                title: Text('忽略此项', style: TextStyle(color: Colors.orange)),
              ),
            ),
          );
        }

        return items;
      },
    );
  }

  Widget? _buildFAB() {
    // 扫描功能已移至顶部菜单
    return null;
  }

  Future<void> _handleScanAction(String action) async {
    if (widget.viewModel.isScanning) {
      _showSnackBar('正在扫描中，请稍候...');
      return;
    }

    ScanResult? result;
    String actionName = '';

    final messenger = ScaffoldMessenger.of(context);

    try {
      switch (action) {
        case 'incremental':
          actionName = '增量扫描';
          result = await widget.presenter.performIncrementalScan();
          break;
        case 'user':
          actionName = '常规扫描';
          result = await widget.presenter.performUserInitiatedScan();
          break;
        case 'deep':
          actionName = '深度扫描';
          result = await widget.presenter.performDeepScan();
          break;
        case 'detect_user':
          actionName = '用户目录检测';
          result = await widget.presenter.detectUserFolders();
          break;
      }

      if (result != null) {
        if (!mounted) return;
        _showScanResultDialog(actionName, result);
      }
    } catch (e) {
      logger.e('Scan action failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('$actionName失败: $e')),
      );
    }
  }

  Future<void> _handleFolderAction(
    String action,
    QuickAccessFolder folder,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case 'add_to_home':
        // 加入首页展示时，自动移除快速访问标记
        if (folder.isAddedToQuickAccess) {
          await widget.presenter.removeFromQuickAccess(folder.id);
        }
        await _handleAddToHome(folder);
        break;

      case 'remove_from_home':
        final success = await widget.presenter.setHomeDisplayOrder(
          folder.id,
          null,
        );
        if (!mounted) return;
        messenger.showSnackBar(
            SnackBar(content: Text(success ? '已移出首页展示' : '操作失败')));
        break;

      case 'add_to_qa':
        // 直接加入快速访问，无需检查首页推荐数量（现在支持6个推荐项）
        final success = await widget.presenter.addToQuickAccess(folder.id);
        if (!mounted) return;
        messenger.showSnackBar(
            SnackBar(content: Text(success ? '已加入快速访问' : '操作失败')));
        break;

      case 'remove_from_qa':
        _showRemoveFromQADialog(folder);
        break;

      case 'hide':
        _showHideDialog(folder);
        break;

      case 'alias':
        _showAliasEditDialog(folder);
        break;
    }
  }

  /// 处理加入首页（检查动态限制：无快速访问6项，有快速访问5项）
  Future<void> _handleAddToHome(QuickAccessFolder folder) async {
    final messenger = ScaffoldMessenger.of(context);
    final homeFolders = await widget.presenter.getHomeFolders();

    // 首页推荐区域最多6个文件夹
    const maxHomeItems = 6;

    if (homeFolders.length >= maxHomeItems) {
      // 已满，需要替换
      if (mounted) {
        _showReplaceHomeItemDialog(folder, homeFolders);
      }
    } else {
      // 未满，直接添加
      final order = homeFolders.length;
      final success = await widget.presenter.setHomeDisplayOrder(
        folder.id,
        order,
      );
      if (!mounted) return;
      messenger.showSnackBar(success
          ? SnackBar(content: Text('已加入首页展示'))
          : SnackBar(content: Text('操作失败')));
    }
  }

  void _showScanResultDialog(String actionName, ScanResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$actionName完成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('扫描完成！'),
            const SizedBox(height: 12),

            // 分类统计
            if (result.totalFound > 0) ...[
              Text(
                '发现目录分类：',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),
              if (result.systemCount > 0)
                _buildResultRow(
                  '  系统目录',
                  result.systemCount,
                  color: Colors.blue,
                ),
              if (result.appRootCount > 0)
                _buildResultRow(
                  '  应用根目录',
                  result.appRootCount,
                  color: Colors.orange,
                ),
              if (result.appSubCount > 0)
                _buildResultRow(
                  '  应用子目录',
                  result.appSubCount,
                  color: Colors.orange.shade300,
                ),
              if (result.userCustomCount > 0)
                _buildResultRow(
                  '  用户自建',
                  result.userCustomCount,
                  color: Colors.green,
                ),
              const Divider(height: 20),
            ],

            // 总计
            _buildResultRow('发现总计', result.totalFound, highlight: true),

            // 操作结果
            if (result.newlyAdded > 0)
              _buildResultRow('新增目录', result.newlyAdded, color: Colors.green),
            if (result.unhidden > 0)
              _buildResultRow('恢复显示', result.unhidden, color: Colors.orange),
            if (result.alreadyExists > 0)
              _buildResultRow('已存在', result.alreadyExists, color: Colors.grey),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow(
    String label,
    int count, {
    bool highlight = false,
    Color? color,
  }) {
    final displayColor =
        color ?? (highlight ? Theme.of(context).colorScheme.primary : null);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.bold : null,
              color: displayColor,
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: highlight ? 18 : 14,
              color: displayColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showAliasEditDialog(QuickAccessFolder folder) {
    // 初始值：如果有userAlias用userAlias，否则用recommendedAlias，都没有就空
    final initialValue = folder.userAlias ?? folder.recommendedAlias ?? '';
    final controller = TextEditingController(text: initialValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑别名'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('原始名称: ${folder.originalName}'),
            if (folder.recommendedAlias != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '系统推荐: ${folder.recommendedAlias}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: '别名',
                hintText: '输入自定义别名',
                helperText: '留空则恢复原始名称',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => controller.clear(),
                  tooltip: '清空',
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final alias = controller.text.trim();
              // 只有完全清空才设为null，其他情况（包括推荐别名）都保存
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final success = await widget.presenter.setUserAlias(
                folder.id,
                alias.isEmpty ? null : alias,
              );

              if (!mounted) return;
              navigator.pop();
              messenger.showSnackBar(
                SnackBar(content: Text(success ? '别名已更新' : '更新失败')),
              );
              if (success) {
                await _loadData();
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 移出快速访问确认对话框
  void _showRemoveFromQADialog(QuickAccessFolder folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出快速访问'),
        content: Text(
          '确定要将"${folder.displayName}"移出快速访问吗？\n\n不会删除实际文件，稍后可以重新加入。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final success = await widget.presenter.removeFromQuickAccess(
                folder.id,
              );
              if (!mounted) return;
              navigator.pop();
              messenger.showSnackBar(
                  SnackBar(content: Text(success ? '已移出快速访问' : '操作失败')));
            },
            child: const Text('移出'),
          ),
        ],
      ),
    );
  }

  /// 忽略项目确认对话框
  void _showHideDialog(QuickAccessFolder folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('忽略此项'),
        content: Text(
          '确定要忽略"${folder.displayName}"吗？\n\n该项将不再显示在列表中，可通过深度扫描重新发现。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final success = await widget.presenter.hideFolder(folder.id);
              if (!mounted) return;
              navigator.pop();
              messenger.showSnackBar(
                  SnackBar(content: Text(success ? '已忽略' : '操作失败')));
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('忽略'),
          ),
        ],
      ),
    );
  }

  /// 替换首页项目对话框
  void _showReplaceHomeItemDialog(
    QuickAccessFolder newFolder,
    List<QuickAccessFolder> currentHomeFolders,
  ) {
    String? selectedId;

    // 首页推荐区域最多6个文件夹
    const maxHomeItems = 6;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('首页展示已满'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
              maxWidth: 400,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('超过首页展示项目数量（最多$maxHomeItems项），请选择要替换的项目：'),
                  const SizedBox(height: 16),
                  ...currentHomeFolders.map(
                    // ignore: deprecated_member_use
                    (folder) => RadioListTile<String>(
                      dense: true,
                      value: folder.id,
                      // ignore: deprecated_member_use
                      groupValue: selectedId,
                      // ignore: deprecated_member_use
                      onChanged: (value) => setState(() => selectedId = value),
                      title: Text(folder.displayName),
                      subtitle: Text(
                        folder.path,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: selectedId == null
                  ? null
                  : () async {
                      // 移除选中的项，添加新项
                      final orderMap = <String, int?>{};
                      orderMap[selectedId!] = null; // 移除

                      // 重新分配顺序
                      int order = 0;
                      for (final folder in currentHomeFolders) {
                        if (folder.id != selectedId) {
                          orderMap[folder.id] = order++;
                        }
                      }
                      orderMap[newFolder.id] = order; // 添加新项

                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(context);
                      final success = await widget.presenter
                          .updateHomeDisplayOrders(orderMap);
                      if (!mounted) return;
                      navigator.pop();
                      messenger.showSnackBar(SnackBar(
                          content: Text(success ? '已替换并加入首页' : '操作失败')));
                    },
              child: const Text('确认替换'),
            ),
          ],
        ),
      ),
    );
  }
}
