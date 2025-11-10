import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/sources/path_provider.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/pages/favorites_manage_page.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/category_nav_bar.dart';
import 'package:easyfile/ui/widgets/favorites_section.dart';
import 'package:easyfile/ui/widgets/file_item_tile.dart';
import 'package:easyfile/ui/widgets/file_operation_sheet.dart';
import 'package:easyfile/ui/widgets/folder_picker_dialog.dart';
import 'package:easyfile/ui/widgets/progress_dialog.dart';
import 'package:easyfile/ui/widgets/rename_dialog.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';

class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({super.key});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  late FilePresenter presenter;
  late FileViewModel viewModel;

  @override
  void initState() {
    super.initState();
    logger.i('FileBrowserPage initState called');

    try {
      viewModel = locator<FileViewModel>();
      logger.d('ViewModel obtained: $viewModel');

      presenter = locator<FilePresenter>();
      logger.d('Presenter obtained: $presenter');

      // 延迟初始化应用程序数据，先显示UI - 这个优化保留
      Future.microtask(() => _initializeApp());
    } catch (e) {
      logger.e('Error in initState: $e');
    }
  }

  /// 初始化应用程序数据
  Future<void> _initializeApp() async {
    logger.i('Initializing app data...');
    
    try {
      // 并行初始化收藏夹和主题
      await Future.wait([
        presenter.initializeFavorites(),
        presenter.initializeTheme(),
      ]);
      
      // 最后加载初始目录
      await _loadInitialDirectory();
      
      logger.i('App initialization completed');
    } catch (e) {
      logger.e('Error during app initialization: $e');
      // 即使初始化失败，也要尝试加载目录
      await _loadInitialDirectory();
    }
  }

  Future<void> _loadInitialDirectory() async {
    try {
      // 默认显示最近访问的文件
      logger.i('Loading recent files as default view');
      await presenter.loadRecentFiles();
      
    } catch (e) {
      logger.e('Error loading recent files, fallback to directory: $e');
      // 如果加载最近文件失败，使用目录浏览作为后备
      await _fallbackToDirectoryView();
    }
  }

  /// 后备方案：加载目录浏览
  Future<void> _fallbackToDirectoryView() async {
    try {
      // 直接使用一些简单的测试路径
      List<String> testPaths = [];

      if (Platform.isAndroid) {
        testPaths = [
          '/storage/emulated/0',
          '/sdcard',
          '/storage/emulated/0/Download',
          '/data/data/com.example.easyfile/files',
        ];
      } else {
        testPaths = [
          Directory.current.path,
          Platform.environment['HOME'] ??
              Platform.environment['USERPROFILE'] ??
              '/',
        ];
      }

      String? workingPath;
      for (final testPath in testPaths) {
        try {
          final dir = Directory(testPath);
          if (dir.existsSync()) {
            final files = dir.listSync();
            logger.d('Test path $testPath works, found ${files.length} items');
            workingPath = testPath;
            break;
          }
        } catch (e) {
          logger.w('Test path $testPath failed: $e');
        }
      }

      if (workingPath != null) {
        logger.i('Using working path: $workingPath');
        presenter.loadFiles(workingPath);
      } else {
        logger.w('No working path found, using fallback');
        final fallbackPath = Directory.current.path;
        presenter.loadFiles(fallbackPath);
      }
    } catch (e) {
      logger.e('Error in _fallbackToDirectoryView: $e');
      presenter.loadFiles('/');
    }
  }

  /// 返回最近文件模式
  Future<void> _returnToRecentFiles() async {
    try {
      await presenter.loadRecentFiles();
    } catch (e) {
      logger.e('Error returning to recent files: $e');
    }
  }

  Future<void> _showPathSelector() async {
    try {
      final availablePaths = await PathProviderService.getAvailablePaths();
      if (!mounted) return;

      if (availablePaths.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有找到可用的目录')),
        );
        return;
      }

      final selectedPath = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('选择目录'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: availablePaths.length,
              itemBuilder: (context, index) {
                final path = availablePaths[index];
                final displayName = _getDisplayName(path);
                return ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(displayName),
                  subtitle: Text(path, style: const TextStyle(fontSize: 12)),
                  onTap: () => Navigator.of(context).pop(path),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      );

      if (selectedPath != null && mounted) {
        presenter.loadFiles(selectedPath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取目录列表失败: $e')),
        );
      }
    }
  }

  String _getDisplayName(String path) {
    if (path.contains('/storage/emulated/0')) {
      if (path == '/storage/emulated/0') return '内部存储';
      if (path.contains('/Download')) return '下载';
      if (path.contains('/Documents')) return '文档';
      if (path.contains('/Pictures')) return '图片';
      if (path.contains('/Android/data')) return '应用数据';
    }

    if (path.contains('Documents')) return '文档';
    if (path.contains('Desktop')) return '桌面';
    if (path.contains('Downloads')) return '下载';
    if (path.contains('Pictures')) return '图片';

    final segments = path.split(Platform.pathSeparator);
    return segments.last.isEmpty
        ? segments[segments.length - 2]
        : segments.last;
  }

  void _previewFile(FileItem file) {
    logger.d('Previewing file: ${file.path}');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FilePreviewPage(file: file),
      ),
    );
  }

  bool _canNavigateUp(String currentPath) {
    if (currentPath.isEmpty) return false;

    // 对于 Windows，检查是否在根目录（如 C:\）
    if (Platform.isWindows) {
      // 如果路径是类似 "C:\" 的格式，则不能再上级
      if (currentPath.length == 3 && currentPath.endsWith(':\\')) {
        return false;
      }
      // 如果路径是类似 "C:" 的格式，则不能再上级
      if (currentPath.length == 2 && currentPath.endsWith(':')) {
        return false;
      }
    } else {
      // 对于 Unix/Linux/macOS，检查是否在根目录
      if (currentPath == '/') {
        return false;
      }
    }

    return true;
  }

  /// 处理菜单操作
  void _handleMenuAction(String action) {
    switch (action) {
      case 'path_selector':
        _showPathSelector();
        break;
      case 'manage_favorites':
        _showFavoritesManagePage();
        break;
      case 'refresh':
        presenter.refreshCurrent();
        break;
      case 'settings':
        _showSettingsDialog();
        break;
    }
  }

  /// 显示设置对话框
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => Consumer<FileViewModel>(
        builder: (context, vm, _) => AlertDialog(
          title: const Text('应用设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.palette),
                title: const Text('主题模式'),
                subtitle: Text(_getThemeModeText(vm.themeMode)),
                onTap: () => _showThemePicker(context),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('关于'),
                subtitle: const Text('EasyFile v1.1.0'),
                onTap: () => _showAboutDialog(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示主题选择器
  void _showThemePicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Consumer<FileViewModel>(
        builder: (context, vm, _) => AlertDialog(
          title: const Text('选择主题'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                title: const Text('跟随系统'),
                value: ThemeMode.system,
                groupValue: vm.themeMode,
                onChanged: (mode) {
                  if (mode != null) {
                    presenter.setThemeMode(mode);
                    Navigator.of(context).pop();
                  }
                },
              ),
              RadioListTile<ThemeMode>(
                title: const Text('浅色主题'),
                value: ThemeMode.light,
                groupValue: vm.themeMode,
                onChanged: (mode) {
                  if (mode != null) {
                    presenter.setThemeMode(mode);
                    Navigator.of(context).pop();
                  }
                },
              ),
              RadioListTile<ThemeMode>(
                title: const Text('深色主题'),
                value: ThemeMode.dark,
                groupValue: vm.themeMode,
                onChanged: (mode) {
                  if (mode != null) {
                    presenter.setThemeMode(mode);
                    Navigator.of(context).pop();
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示关于对话框
  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'EasyFile',
      applicationVersion: '1.1.0',
      applicationLegalese: '© 2025 EasyFile Team',
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('一个简单易用的跨平台文件管理器'),
        ),
      ],
    );
  }

  /// 显示收藏夹管理页面
  void _showFavoritesManagePage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FavoritesManagePage(
          presenter: presenter,
          viewModel: viewModel,
        ),
      ),
    );
  }

  /// 获取主题模式文本描述
  String _getThemeModeText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色主题';
      case ThemeMode.dark:
        return '深色主题';
    }
  }

  /// 构建文件列表视图
  Widget _buildFileList(FileViewModel vm) {
    if (vm.files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                vm.isSearchMode ? Icons.search_off : Icons.folder_open,
                size: 48, // 减小图标大小
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(
                vm.isSearchMode ? '未找到匹配的文件' : '此文件夹为空',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  vm.isSearchMode
                      ? '尝试使用不同的搜索关键词'
                      : '当前路径: ${vm.currentPath.isEmpty ? '最近文件' : vm.currentPath}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: vm.files.length,
      itemBuilder: (context, index) {
        final file = vm.files[index];
        return FileItemTile(
          file: file,
          showFullPath: vm.isSearchMode,
          onTap: () => _onFileTap(file, vm),
          onLongPress: () => _showFileOperations(file),
        );
      },
    );
  }

  /// 处理文件点击
  void _onFileTap(FileItem file, FileViewModel vm) {
    // 添加到最近访问记录
    presenter.addToRecentFiles(file);
    
    if (file.isDirectory) {
      if (vm.isSearchMode) {
        // 在搜索模式下，清除搜索并导航到该文件夹
        presenter.clearSearch();
        presenter.navigateToFolder(file.path);
      } else {
        presenter.navigateToFolder(file.path);
      }
    } else {
      // 预览文件
      _previewFile(file);
    }
  }

  /// 显示 SnackBar 消息
  ///
  /// [message] 要显示的消息文本
  /// [isSuccess] 是否为成功消息，成功消息使用绿色背景
  void _showSnackBar(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isSuccess ? Colors.green : null,
        ),
      );
    } catch (e) {
      logger.w('Failed to show SnackBar: $e. Message was: $message');
    }
  }

  void _showFileOperations(FileItem file) {
    logger.d('Showing file operations for: ${file.name}');
    showModalBottomSheet(
      context: context,
      builder: (context) => FileOperationSheet(
        file: file,
        onOperation: (operation) => _handleFileOperation(file, operation),
      ),
    );
  }

  Future<void> _handleFileOperation(
      FileItem file, FileOperation operation) async {
    logger.d('Handling file operation: $operation for ${file.name}');

    switch (operation) {
      case FileOperation.delete:
        await _deleteFile(file);
        break;
      case FileOperation.rename:
        await _renameFile(file);
        break;
      case FileOperation.copy:
        await _copyFile(file);
        break;
      case FileOperation.move:
        await _moveFile(file);
        break;
    }
  }

  /// 删除指定的文件或文件夹
  ///
  /// 显示确认对话框，如果用户确认，则执行删除操作并显示结果消息
  Future<void> _deleteFile(FileItem file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${file.name}" 吗？\n\n此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      logger.d('Starting delete operation for: ${file.name}');
      final success = await presenter.deleteFile(file);
      logger.d('Delete operation result: $success');

      // 等待文件列表刷新完成后显示结果消息
      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        final message = success ? '已删除 "${file.name}"' : '删除失败';
        logger.d('Showing delete SnackBar: $message');
        _showSnackBar(message, isSuccess: success);
      }
    }
  }

  /// 重命名指定的文件或文件夹
  ///
  /// 显示重命名对话框，如果用户提供新名称，则执行重命名操作并显示结果消息
  Future<void> _renameFile(FileItem file) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => RenameDialog(file: file),
    );

    if (newName != null && newName.isNotEmpty) {
      logger.d('Starting rename operation: ${file.name} -> $newName');
      final success = await presenter.renameFile(file, newName);
      logger.d('Rename operation result: $success');

      // 等待文件列表刷新完成后显示结果消息
      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        final message = success ? '已重命名为 "$newName"' : '重命名失败';
        logger.d('Showing rename SnackBar: $message');
        _showSnackBar(message, isSuccess: success);
      }
    }
  }

  /// 复制指定的文件或文件夹
  ///
  /// 显示文件夹选择对话框，选择目标文件夹后执行复制操作并显示结果消息
  Future<void> _copyFile(FileItem file) async {
    final destinationFolder = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(
        currentPath: viewModel.currentPath,
        title: '选择复制目标',
      ),
    );

    if (destinationFolder != null) {
      if (!mounted) return;
      ProgressDialog.show(
        context,
        title: '复制文件',
        message: '正在复制 "${file.name}"...',
      );

      logger.d('Starting copy operation: ${file.name} to $destinationFolder');
      final destinationPath =
          '$destinationFolder${Platform.pathSeparator}${file.name}';
      final success = await presenter.copyFile(file, destinationPath);
      logger.d('Copy operation result: $success');

      // 等待文件列表刷新完成后显示结果消息
      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        ProgressDialog.hide(context);
        final message = success ? '已复制 "${file.name}"' : '复制失败';
        logger.d('Showing copy SnackBar: $message');
        _showSnackBar(message, isSuccess: success);
      }
    }
  }

  /// 移动指定的文件或文件夹
  ///
  /// 显示文件夹选择对话框，选择目标文件夹后执行移动操作并显示结果消息
  Future<void> _moveFile(FileItem file) async {
    final destinationFolder = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(
        currentPath: viewModel.currentPath,
        title: '选择移动目标',
      ),
    );

    if (destinationFolder != null) {
      if (!mounted) return;
      ProgressDialog.show(
        context,
        title: '移动文件',
        message: '正在移动 "${file.name}"...',
      );

      logger.d('Starting move operation: ${file.name} to $destinationFolder');
      final destinationPath =
          '$destinationFolder${Platform.pathSeparator}${file.name}';
      final success = await presenter.moveFile(file, destinationPath);
      logger.d('Move operation result: $success');

      // 等待文件列表刷新完成后显示结果消息
      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        ProgressDialog.hide(context);
        final message = success ? '已移动 "${file.name}"' : '移动失败';
        logger.d('Showing move SnackBar: $message');
        _showSnackBar(message, isSuccess: success);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FileViewModel>.value(
      value: viewModel,
      child: Consumer<FileViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          
          return Scaffold(
            appBar: AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 24,
                    height: 24,
                  ),
                  const SizedBox(width: 8),
                  const Text('EasyFile'),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => presenter.toggleSearch(),
                  tooltip: vm.isSearchMode ? '退出搜索' : '搜索文件',
                ),
                IconButton(
                  icon: Icon(vm.isDarkTheme ? Icons.light_mode : Icons.dark_mode),
                  onPressed: () => presenter.toggleTheme(),
                  tooltip: '切换主题',
                ),
                PopupMenuButton<String>(
                  onSelected: _handleMenuAction,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'path_selector',
                      child: Row(
                        children: [
                          Icon(Icons.folder_special),
                          SizedBox(width: 8),
                          Text('选择目录'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'manage_favorites',
                      child: Row(
                        children: [
                          Icon(Icons.star),
                          SizedBox(width: 8),
                          Text('管理收藏文件夹'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'refresh',
                      child: Row(
                        children: [
                          Icon(Icons.refresh),
                          SizedBox(width: 8),
                          Text('刷新'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'settings',
                      child: Row(
                        children: [
                          Icon(Icons.settings),
                          SizedBox(width: 8),
                          Text('设置'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    // 上部固定区域 - 限制最大高度
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * 0.5, // 调整为50%高度
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 分类导航区（快速入口）
                            CategoryNavBar(
                              presenter: presenter,
                              viewModel: vm,
                            ),
                            const Divider(height: 1),
                            
                            // 收藏夹区域
                            FavoritesSection(
                              viewModel: vm,
                              presenter: presenter,
                            ),
                            const Divider(height: 1),
                            
                            // 搜索栏（在搜索模式时显示）
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              height: vm.isSearchMode ? 60 : 0,
                              child: vm.isSearchMode
                                  ? Container(
                                      padding: const EdgeInsets.all(8),
                                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                                      child: Center(
                                        child: TextField(
                                          autofocus: true,
                                          decoration: InputDecoration(
                                            hintText: '搜索文件和文件夹...',
                                            prefixIcon: Icon(
                                              Icons.search,
                                              color: Theme.of(context).primaryColor,
                                            ),
                                            suffixIcon: IconButton(
                                              icon: const Icon(Icons.close),
                                              onPressed: () => presenter.clearSearch(),
                                            ),
                                            border: const OutlineInputBorder(),
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                          textInputAction: TextInputAction.search,
                                          onSubmitted: (query) {
                                            if (query.isNotEmpty) {
                                              presenter.searchFiles(query);
                                            }
                                          },
                                          onChanged: (query) {
                                            if (query.isEmpty) {
                                              presenter.clearSearch();
                                            }
                                          },
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),

                            // 导航和状态信息栏
                            if (!vm.isSearchMode && _canNavigateUp(vm.currentPath))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.arrow_back),
                                      onPressed: () => presenter.navigateUp(),
                                      tooltip: '返回上级目录',
                                    ),
                                    Expanded(
                                      child: Text(
                                        vm.currentPath,
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // 状态信息栏
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              color: Colors.grey[100],
                              child: vm.isSearchMode
                                  ? Row(
                                      children: [
                                        Icon(
                                          Icons.search,
                                          size: 16,
                                          color: Theme.of(context).primaryColor,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '搜索结果: ${vm.files.length} 项',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context).primaryColor,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => presenter.clearSearch(),
                                          child: const Text('清除搜索', style: TextStyle(fontSize: 12)),
                                        ),
                                      ],
                                    )
                                  : vm.isRecentFilesMode
                                      ? Row(
                                          children: [
                                            Icon(
                                              Icons.access_time,
                                              size: 16,
                                              color: Theme.of(context).primaryColor,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '最近访问: ${vm.files.length} 项',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context).primaryColor,
                                                ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () => _fallbackToDirectoryView(),
                                              child: const Text('浏览文件夹', style: TextStyle(fontSize: 12)),
                                            ),
                                          ],
                                        )
                                      : Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${vm.files.length} 项 (${vm.files.where((f) => f.isDirectory).length} 文件夹, ${vm.files.where((f) => !f.isDirectory).length} 文件)',
                                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () => _returnToRecentFiles(),
                                              child: const Text('最近文件', style: TextStyle(fontSize: 12)),
                                            ),
                                          ],
                                        ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 文件列表区域（可扩展）
                    Expanded(
                      child: _buildFileList(vm),
                    ),
                  ],
                );
              },
            ),
            
            floatingActionButton: FloatingActionButton(
              onPressed: () => presenter.refreshCurrent(),
              tooltip: '刷新',
              child: const Icon(Icons.refresh),
            ),
          );
        },
      ),
    );
  }
}
