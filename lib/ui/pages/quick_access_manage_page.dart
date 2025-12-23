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
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 延迟加载避免在build期间触发setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
        // 扫描按钮 - 使用文字更清晰
        TextButton.icon(
          icon: const Icon(Icons.radar, size: 20),
          label: const Text('扫描'),
          onPressed: () => _handleScanAction('scan'),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody() {
    if (widget.viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final systemFolders = widget.viewModel.systemFolders;
    final otherFolders = widget.viewModel.otherFolders;

    if (systemFolders.isEmpty && otherFolders.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        key: const PageStorageKey('quick_access_list'),
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        children: [
          // 扫描提示（如果正在扫描）
          if (widget.viewModel.isScanning) _buildScanningIndicator(),

          // ⭐ v2.0：系统推荐区
          if (systemFolders.isNotEmpty)
            _buildSystemFoldersSection(systemFolders),

          // 📂 v2.0：其他目录区
          if (otherFolders.isNotEmpty) _buildOtherFoldersSection(otherFolders),
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
                  '点击右上角"扫描"按钮开始',
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

  Widget _buildFolderActions(QuickAccessFolder folder) {
    // v2.0: 首页推荐已移除
    // 现在所有文件夹都是完整的数据库记录，包括子文件夹
    bool isAdded = folder.isAddedToQuickAccess;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 视觉指示器：图钉表示已加入快速访问
        if (isAdded)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              Icons.push_pin,
              color: Colors.amber,
              size: 16,
            ),
          ),

        // 操作菜单按钮（用 SizedBox 限制高度，避免 PopupMenuButton 默认约束）
        SizedBox(
          width: 30,
          height: 30,
          child: PopupMenuButton<String>(
            onSelected: (value) {
              // 延迟执行以确保菜单已完全关闭
              Future.microtask(() => _handleFolderAction(value, folder));
            },
            icon: const Icon(Icons.more_vert, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[];

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

              // 快速访问操作
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
              } else {
                // 未加入快速访问，显示加入选项
                items.add(
                  const PopupMenuItem(
                    value: 'add_to_qa',
                    child: ListTile(
                      dense: true,
                      leading:
                          Icon(Icons.add_circle_outline, color: Colors.green),
                      title:
                          Text('加入快速访问', style: TextStyle(color: Colors.green)),
                    ),
                  ),
                );
                items.add(
                  const PopupMenuItem(
                    value: 'hide',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.visibility_off, color: Colors.orange),
                      title:
                          Text('忽略此项', style: TextStyle(color: Colors.orange)),
                    ),
                  ),
                );
              }

              return items;
            },
          ),
        ),
      ],
    );
  }

  Widget? _buildFAB() {
    // 扫描功能已移至顶部菜单
    return null;
  }

  /// 获取友好的路径显示名称
  /// 示例：/storage/emulated/0/DCIM/ → 内部存储/DCIM
  String _getFriendlyPath(String fullPath) {
    // 路径映射，用于显示更友好的文件夹路径
    const pathMappings = {
      '/storage/emulated/0': '内部存储',
      '/storage/emulated/legacy': '内部存储',
      '/cache': '缓存',
      '/data': '数据',
      '/system': '系统',
    };

    String displayPath = fullPath.replaceAll(RegExp(r'/+$'), ''); // 移除末尾的 /

    // 寻找匹配的前缀
    for (final entry in pathMappings.entries) {
      if (displayPath.startsWith(entry.key)) {
        final remaining = displayPath
            .substring(entry.key.length)
            .replaceAll(RegExp(r'^/+'), '');
        if (remaining.isEmpty) {
          return entry.value;
        } else {
          return '${entry.value}/$remaining';
        }
      }
    }

    return fullPath;
  }

  Future<void> _handleScanAction(String action) async {
    if (widget.viewModel.isScanning) {
      _showSnackBar('正在扫描中，请稍候...');
      return;
    }

    // ⭐ 滚动到顶部以显示扫描状态
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    ScanResult? result;
    String actionName = '';

    final messenger = ScaffoldMessenger.of(context);

    try {
      switch (action) {
        case 'scan':
        case 'deep': // Keep for backward compatibility
          actionName = '扫描目录';
          result = await widget.presenter.performDeepScan();
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
      case 'add_to_qa':
        // 所有文件夹都是完整的数据库记录，直接添加
        final success = await widget.presenter.addToQuickAccess(folder.id);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text(success ? '已加入快速访问' : '操作失败')),
        );
        if (success) _loadDataKeepPosition(); // 保持滚动位置
        break;

      case 'remove_from_qa':
        _showRemoveFromQADialog(folder);
        break;

      case 'hide':
        // 统一的隐藏对话框（不再区分子文件夹）
        _showHideDialog(folder);
        break;

      case 'alias':
        // 统一的别名编辑对话框（不再区分子文件夹）
        _showAliasEditDialog(folder);
        break;
    }
  }

  /// 加载数据并保持滚动位置
  Future<void> _loadDataKeepPosition() async {
    // 保存当前滚动位置
    double? savedPosition;
    if (_scrollController.hasClients) {
      savedPosition = _scrollController.offset;
    }

    // 加载数据（会触发rebuild）
    await widget.presenter.loadQuickAccessFolders();

    // 等待两帧后恢复位置（确保ListView完全重建）
    await Future.delayed(Duration.zero);
    if (mounted && savedPosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && savedPosition != null) {
          _scrollController.jumpTo(savedPosition);
        }
      });
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
              if (result.otherCount > 0)
                _buildResultRow(
                  '  其他文件夹',
                  result.otherCount,
                  color: Colors.orange,
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
            onPressed: () async {
              Navigator.of(context).pop();
              // 关闭对话框后刷新数据，显示新增的目录
              await _loadData();
            },
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
    String initialValue = folder.userAlias ?? folder.recommendedAlias ?? '';

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
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);

              // 所有文件夹都是完整的数据库记录，直接使用ID
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
                // 异步重新加载，保持滚动位置
                _loadDataKeepPosition();
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
              // 所有文件夹都直接使用ID
              final success = await widget.presenter.removeFromQuickAccess(
                folder.id,
              );
              if (!mounted) return;
              navigator.pop();
              messenger.showSnackBar(
                  SnackBar(content: Text(success ? '已移出快速访问' : '操作失败')));
              if (success) {
                _loadDataKeepPosition();
              }
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

              // 所有文件夹都是完整的数据库记录，直接使用ID
              final success = await widget.presenter.hideFolder(folder.id);
              if (!mounted) return;
              navigator.pop();
              messenger.showSnackBar(
                  SnackBar(content: Text(success ? '已忽略' : '操作失败')));
              if (success) {
                _loadDataKeepPosition();
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('忽略'),
          ),
        ],
      ),
    );
  }

  // ========== v2.0 新增方法：两区布局 ==========

  /// 构建系统推荐区（支持二级目录展开）
  Widget _buildSystemFoldersSection(List<QuickAccessFolder> folders) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 区域标题
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              const Icon(Icons.folder, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                '常用文件夹',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${widget.viewModel.systemFoldersTotalCount} 个',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),

        // 系统目录项（支持展开子目录）
        ..._buildSystemFoldersTiles(folders),

        const Divider(height: 24, thickness: 1, indent: 0, endIndent: 0),
      ],
    );
  }

  /// 构建系统文件夹项列表
  List<Widget> _buildSystemFoldersTiles(List<QuickAccessFolder> folders) {
    final tiles = <Widget>[];

    // 按预定义顺序遍历每个系统目录根
    for (final rootPath in folders.map((f) => f.path).toSet()) {
      final rootFolder = folders.firstWhere((f) => f.path == rootPath);
      final isExpanded = widget.viewModel.isSystemFolderExpanded(rootPath);

      // 动态检测是否有可见的子文件夹
      final hasSubfolders = widget.viewModel.hasSubfolders(rootPath);
      // 检查是否有新增的子文件夹
      final hasNewChildren = widget.viewModel.hasNewSubfolders(rootPath);

      // 根目录项（根据实际子文件夹情况决定是否可展开）
      tiles.add(
        Container(
          color: hasNewChildren ? Colors.blue.shade50 : Colors.transparent,
          child: FolderItemTile(
            folder: rootFolder,
            icon: Icons.folder,
            hasSubfolders: hasSubfolders, // 动态设置
            isExpanded: isExpanded,
            isNew: widget.viewModel.isNewFolder(rootFolder.id),
            onTap: () {
              // 点击根目录的处理（如打开、编辑别名等）
            },
            onExpandToggle: hasSubfolders
                ? () {
                    // 只有有子文件夹时才提供展开回调
                    widget.viewModel.toggleSystemFolderExpanded(rootPath);
                  }
                : null,
            trailingWidget: _buildFolderActions(rootFolder),
            pathFormatter: _getFriendlyPath,
          ),
        ),
      );

      // 展开时显示子目录（直接从数据库获取，无需动态扫描）
      if (isExpanded && hasSubfolders) {
        // 添加额外检查
        // 从数据库获取所有子文件夹
        final subfolders = widget.viewModel.getSubfoldersFromDatabase(rootPath);

        // 显示所有子文件夹（复用FolderItemTile）
        for (final subfolder in subfolders) {
          tiles.add(
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: FolderItemTile(
                folder: subfolder,
                icon: Icons.folder,
                hasSubfolders: false,
                isExpanded: false,
                isNew: widget.viewModel.isNewFolder(subfolder.id),
                onTap: () {},
                trailingWidget: _buildFolderActions(subfolder),
                pathFormatter: _getFriendlyPath,
              ),
            ),
          );
        }
      }
    }

    return tiles;
  }

  /// 构建其他文件夹区（扁平结构）
  Widget _buildOtherFoldersSection(List<QuickAccessFolder> folders) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 区域标题
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              const Icon(Icons.folder, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                '其他文件夹',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${folders.length} 个',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),

        // 其他目录列表（扁平结构）
        ...folders.map((folder) => FolderItemTile(
              folder: folder,
              icon: Icons.folder,
              isNew: widget.viewModel.isNewFolder(folder.id),
              onTap: () {},
              trailingWidget: _buildFolderActions(folder),
              pathFormatter: _getFriendlyPath,
            )),
      ],
    );
  }
}

/// 文件夹项 Tile（可复用）
class FolderItemTile extends StatelessWidget {
  final QuickAccessFolder folder;
  final IconData icon;
  final bool hasSubfolders;
  final bool isExpanded;
  final bool isNew;
  final VoidCallback onTap;
  final VoidCallback? onExpandToggle;
  final Widget? trailingWidget;
  final String Function(String)? pathFormatter;

  const FolderItemTile({
    super.key,
    required this.folder,
    required this.icon,
    this.hasSubfolders = false,
    this.isExpanded = false,
    this.isNew = false,
    required this.onTap,
    this.onExpandToggle,
    this.trailingWidget,
    this.pathFormatter,
  });

  /// 获取显示名称：
  /// - 有用户别名：显示"原名 | 别名"
  /// - 无别名：显示原名
  String _getDisplayName(QuickAccessFolder folder) {
    // 如果有用户别名，显示"原名 | 别名"格式
    if (folder.userAlias != null && folder.userAlias!.isNotEmpty) {
      return '${folder.originalName} | ${folder.userAlias!}';
    }

    return folder.originalName;
  }

  @override
  Widget build(BuildContext context) {
    final displayPath = pathFormatter?.call(folder.path) ?? folder.path;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：icon + name + menu/actions
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. 文件夹图标
                Icon(icon, color: Colors.grey[700], size: 24),
                const SizedBox(width: 12),

                // 2. 文件夹名称（展开）
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _getDisplayName(folder),
                          style: const TextStyle(fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // NEW 标记显示在文件夹名称右侧
                      if (isNew) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.fiber_new,
                          color: Colors.red,
                          size: 20,
                        ),
                      ],
                    ],
                  ),
                ),

                // 3. 菜单和图钉（来自 trailingWidget）
                if (trailingWidget != null) trailingWidget!,
              ],
            ),

            // 第二行：路径 + 展开/折叠按钮
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: GestureDetector(
                onTap: hasSubfolders ? onExpandToggle : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 路径信息（展开）
                    Expanded(
                      child: Text(
                        displayPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ),

                    // 展开/折叠按钮（仅当有子文件夹时显示）
                    if (hasSubfolders)
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: GestureDetector(
                          onTap: onExpandToggle,
                          child: Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            color: Colors.grey,
                            size: 20,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
