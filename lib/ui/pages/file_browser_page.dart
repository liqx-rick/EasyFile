import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/favorite_item.dart';
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

  /// 返回主页（最近访问文件列表）
  Future<void> _returnToHome() async {
    try {
      // 切换到最近 Tab
      viewModel.setCurrentTab(TabView.recent);
      // 加载最近文件
      await presenter.loadRecentFiles();
    } catch (e) {
      logger.e('Error returning to home: $e');
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
        presenter.loadFiles(selectedPath, isRootNavigation: true);
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

    // 检查是否已经回到了导航起始路径（收藏夹根路径）
    if (currentPath == viewModel.rootPath) {
      return false;
    }

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

  /// 获取主题图标
  IconData _getThemeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode; // 浅色模式：太阳
      case ThemeMode.dark:
        return Icons.dark_mode; // 深色模式：月亮
      case ThemeMode.system:
        return Icons.brightness_auto; // 跟随系统：自动亮度图标
    }
  }

  /// 获取主题切换提示文字
  String _getThemeTooltip(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '当前：浅色主题';
      case ThemeMode.dark:
        return '当前：深色主题';
      case ThemeMode.system:
        return '当前：跟随系统';
    }
  }

  /// 构建 Tab 按钮
  Widget _buildTabButton(
    BuildContext context,
    String label,
    TabView tab,
    bool isSelected, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 获取文件浏览Tab的标签文本
  String _getBrowseTabLabel(FileViewModel vm) {
    if (vm.currentTab == TabView.browse && vm.currentPath.isNotEmpty) {
      // 查找匹配的收藏夹
      final matchedFavorite = vm.favorites.firstWhere(
        (fav) => fav.path == vm.currentPath,
        orElse: () => FavoriteItem(
          id: '',
          name: '',
          path: '',
          iconName: 'folder',
          pinned: false,
          createdAt: DateTime.now(),
        ),
      );

      if (matchedFavorite.name.isNotEmpty) {
        return '文件浏览 - ${matchedFavorite.name}';
      }
    }
    return '文件浏览';
  }

  /// 构建文件列表视图
  Widget _buildFileList(FileViewModel vm) {
    if (vm.files.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          await presenter.refreshCurrent();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
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
                    const SizedBox(height: 16),
                    Text(
                      '下拉刷新',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await presenter.refreshCurrent();
      },
      child: vm.viewMode == ViewMode.list
          ? _buildListView(vm)
          : _buildGridView(vm),
    );
  }

  /// 构建列表视图
  Widget _buildListView(FileViewModel vm) {
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

  /// 构建网格视图
  Widget _buildGridView(FileViewModel vm) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.85,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: vm.files.length,
      itemBuilder: (context, index) {
        final file = vm.files[index];
        return _buildGridItem(file, vm);
      },
    );
  }

  /// 构建网格项
  Widget _buildGridItem(FileItem file, FileViewModel vm) {
    return InkWell(
      onTap: () => _onFileTap(file, vm),
      onLongPress: () => _showFileOperations(file),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 文件图标
            Icon(
              file.isDirectory ? Icons.folder : _getFileIcon(file),
              size: 48,
              color: file.isDirectory ? Colors.amber : Colors.blue,
            ),
            const SizedBox(height: 8),
            // 文件名
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                file.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            // 文件大小或日期
            if (!file.isDirectory)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _formatFileSize(file.size),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 获取文件图标
  IconData _getFileIcon(FileItem file) {
    final ext = file.name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mkv':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.audio_file;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
                  icon: Icon(_getThemeIcon(vm.themeMode)),
                  onPressed: () => presenter.toggleTheme(),
                  tooltip: _getThemeTooltip(vm.themeMode),
                ),
                IconButton(
                  icon: const Icon(Icons.home),
                  onPressed: _returnToHome,
                  tooltip: '返回主页',
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

                            // Tab 切换栏和工具按钮
                            Container(
                              color: Theme.of(context).colorScheme.surface,
                              child: Row(
                                children: [
                                  // Tab 切换 - 居左对齐
                                  _buildTabButton(
                                    context,
                                    '最近',
                                    TabView.recent,
                                    vm.currentTab == TabView.recent,
                                    onTap: () {
                                      viewModel.setCurrentTab(TabView.recent);
                                      presenter.loadRecentFiles();
                                    },
                                  ),
                                  // 分割线
                                  Container(
                                    width: 1,
                                    height: 20,
                                    color: Theme.of(context).dividerColor,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 2),
                                  ),
                                  _buildTabButton(
                                    context,
                                    _getBrowseTabLabel(vm),
                                    TabView.browse,
                                    vm.currentTab == TabView.browse,
                                    onTap: null, // 文件浏览 Tab 不可点击，只能通过收藏夹激活
                                  ),
                                  // 占位空间
                                  const Spacer(),
                                  // 工具按钮组（紧凑显示）
                                  if (vm.currentTab == TabView.browse)
                                    Transform.translate(
                                      offset: const Offset(
                                          24, 0), // 向右移动24px，减少与视图切换图标的间距
                                      child: IconButton(
                                        icon:
                                            const Icon(Icons.search, size: 20),
                                        onPressed: () =>
                                            presenter.toggleSearch(),
                                        tooltip:
                                            vm.isSearchMode ? '退出搜索' : '搜索文件',
                                        padding: const EdgeInsets.all(8),
                                        constraints: const BoxConstraints(),
                                      ),
                                    ),
                                  IconButton(
                                    icon: Icon(
                                      vm.viewMode == ViewMode.list
                                          ? Icons.grid_view
                                          : Icons.view_list,
                                      size: 20,
                                    ),
                                    onPressed: () => viewModel.toggleViewMode(),
                                    tooltip: vm.viewMode == ViewMode.list
                                        ? '网格视图'
                                        : '列表视图',
                                    padding: const EdgeInsets.all(8),
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ),

                            // 搜索栏（在搜索模式时显示）
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              height: vm.isSearchMode ? 56 : 0,
                              child: vm.isSearchMode
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      child: TextField(
                                        autofocus: true,
                                        decoration: InputDecoration(
                                          hintText: '搜索文件...',
                                          hintStyle:
                                              const TextStyle(fontSize: 14),
                                          prefixIcon: Icon(
                                            Icons.search,
                                            color:
                                                Theme.of(context).primaryColor,
                                            size: 20,
                                          ),
                                          suffixIcon: IconButton(
                                            icon: const Icon(Icons.close,
                                                size: 20),
                                            onPressed: () =>
                                                presenter.clearSearch(),
                                            tooltip: '清除搜索',
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          filled: true,
                                          fillColor: Theme.of(context)
                                              .colorScheme
                                              .surface,
                                        ),
                                        style: const TextStyle(fontSize: 14),
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
                                    )
                                  : const SizedBox.shrink(),
                            ),

                            // 状态信息栏
                            Container(
                              height: 36,
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
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
                                              color: Theme.of(context)
                                                  .primaryColor,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              presenter.clearSearch(),
                                          child: const Text('清除搜索',
                                              style: TextStyle(fontSize: 12)),
                                        ),
                                      ],
                                    )
                                  : vm.currentTab == TabView.recent
                                      ? Row(
                                          children: [
                                            Icon(
                                              Icons.access_time,
                                              size: 16,
                                              color: Theme.of(context)
                                                  .primaryColor,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '最近访问: ${vm.files.length} 项',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context)
                                                      .primaryColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                      : Row(
                                          children: [
                                            Icon(
                                              Icons.folder_open,
                                              size: 16,
                                              color: Theme.of(context)
                                                  .primaryColor,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${vm.files.length} 项',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context)
                                                      .primaryColor,
                                                ),
                                              ),
                                            ),
                                            if (vm.currentPath.isNotEmpty &&
                                                _canNavigateUp(vm.currentPath))
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.arrow_upward,
                                                    size: 16),
                                                onPressed: () =>
                                                    presenter.navigateUp(),
                                                tooltip: '返回上级',
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                  minWidth: 24,
                                                  minHeight: 24,
                                                ),
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
          );
        },
      ),
    );
  }
}
