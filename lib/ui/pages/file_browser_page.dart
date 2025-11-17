import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/view_mode_service.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';
import 'package:easyfile/ui/pages/quick_access_manage_page.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/category_nav_bar.dart';
import 'package:easyfile/utils/path_security.dart';
import 'package:easyfile/ui/widgets/enhanced_delete_dialog.dart';
import 'package:easyfile/ui/widgets/quick_access_section.dart';
import 'package:easyfile/ui/widgets/new_folder_notification.dart';
import 'package:easyfile/ui/widgets/file_category_tab_bar.dart';
import 'package:easyfile/ui/widgets/file_toolbar.dart';
import 'package:easyfile/ui/widgets/file_search_bar.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';

import 'package:easyfile/ui/widgets/folder_picker_dialog.dart';
import 'package:easyfile/ui/widgets/image_thumbnail.dart';
import 'package:easyfile/ui/widgets/real_video_thumbnail.dart';
import 'package:easyfile/ui/widgets/audio_cover_widget.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/utils/time_formatter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/viewmodel/quick_access_viewmodel.dart';

class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({super.key});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  late FilePresenter presenter;
  late FileViewModel viewModel;
  QuickAccessPresenter? quickAccessPresenter;
  QuickAccessViewModel? quickAccessViewModel;
  bool _hasCheckedRestore = false; // 标记是否已经检查过恢复
  double _categoryCardSize = 0.0; // 存储分类卡片尺寸

  // 批量操作相关状态
  bool _isSelectionMode = false;
  Set<String> _selectedItems = {}; // 存储选中的文件/文件夹路径
  late final SelectionController _selectionController;

  // 搜索相关状态
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  bool get wantKeepAlive => true; // 保持状态不被销毁

  @override
  void initState() {
    super.initState();
    _selectionController = SelectionController();
    _selectionController.selectedNotifier.addListener(_onSelectionChanged);
    WidgetsBinding.instance.addObserver(this);
    logger.i('FileBrowserPage initState called');

    try {
      viewModel = locator<FileViewModel>();
      logger.d('ViewModel obtained: $viewModel');

      presenter = locator<FilePresenter>();
      logger.d('Presenter obtained: $presenter');

      quickAccessViewModel = locator<QuickAccessViewModel>();
      logger.d('QuickAccessViewModel obtained: $quickAccessViewModel');

      quickAccessPresenter = locator<QuickAccessPresenter>();
      logger.d('QuickAccessPresenter obtained: $quickAccessPresenter');

      // 延迟初始化应用程序数据，先显示UI - 这个优化保留
      Future.microtask(() => _initializeApp());

      // 只在首次初始化时检查是否需要恢复文件预览
      if (!_hasCheckedRestore) {
        _checkAndRestoreFilePreview();
        _hasCheckedRestore = true;
      }
    } catch (e) {
      logger.e('Error in initState: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _selectionController.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    setState(() {
      _selectedItems = _selectionController.selected;
      // 如果选择为空，退出选择模式
      if (_selectedItems.isEmpty && _isSelectionMode) {
        _isSelectionMode = false;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    logger.d('FileBrowserPage: App lifecycle changed to $state');
  }

  /// 检查并恢复文件预览
  Future<void> _checkAndRestoreFilePreview() async {
    // 延迟执行，确保页面构建完成
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final lastFilePath = prefs.getString('last_viewed_file_path');

        if (lastFilePath != null && lastFilePath.isNotEmpty) {
          logger.i('FileBrowserPage: Found last viewed file: $lastFilePath');

          final file = File(lastFilePath);
          if (file.existsSync()) {
            final fileItem = FileItem(
              name: file.path.split(Platform.pathSeparator).last,
              path: file.path,
              size: file.lengthSync(),
              modified: file.lastModifiedSync(),
              isDirectory: false,
            );

            logger.i('FileBrowserPage: Restoring file preview');
            if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => FilePreviewPage(file: fileItem),
                ),
              );
            }
          } else {
            logger.w('FileBrowserPage: Last viewed file no longer exists');
            await prefs.remove('last_viewed_file_path');
          }
        }
      } catch (e) {
        logger.e('FileBrowserPage: Error restoring file preview: $e');
      }
    });
  }

  /// 初始化应用程序数据
  Future<void> _initializeApp() async {
    logger.i('Initializing app data...');

    try {
      // 并行初始化收藏夹、收藏文件和主题
      await Future.wait([
        presenter.initializeFavorites(),
        presenter.initializeFavoriteFiles(), // 初始化收藏文件
        presenter.initializeTheme(),
      ]);

      // 最后加载初始目录（根据保存的状态恢复）
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
      // 检查是否有保存的 tab 状态
      final savedTab = viewModel.currentTab;
      logger.i('Loading initial directory, saved tab: $savedTab');

      if (savedTab == TabView.browse) {
        // 如果上次在浏览模式，尝试恢复到上次的路径
        final lastPath = viewModel.lastBrowsePath;
        if (lastPath != null && lastPath.isNotEmpty) {
          logger.i('Restoring browse mode to: $lastPath');
          await presenter.navigateToFolder(lastPath);
          return;
        }
      }

      // 默认或恢复失败时，显示最近访问的文件
      logger.i('Loading recent files as default view');
      await presenter.loadRecentFiles();
    } catch (e) {
      logger.e('Error loading initial directory: $e');
      // 如果加载失败，使用目录浏览作为后备
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

  void _previewFile(FileItem file) {
    logger.d('Previewing file: ${file.path}');
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(builder: (context) => FilePreviewPage(file: file)),
        )
        .then((refresh) async {
          if (refresh == true) {
            // 返回后主动刷新主界面文件列表
            if (viewModel.currentTab == TabView.recent) {
              await presenter.loadRecentFiles();
            } else {
              await presenter.loadFiles(viewModel.currentPath);
            }
          }
        });
  }

  bool _canNavigateUp(String currentPath) {
    if (currentPath.isEmpty) return false;

    // 检查是否已经回到了导航起始路径（快速访问根路径）
    if (currentPath == viewModel.rootPath) {
      return false;
    }

    // 🔑 检查当前目录的上一级是否是 Android 系统根目录
    if (Platform.isAndroid) {
      final parentPath = currentPath.substring(
        0,
        currentPath.lastIndexOf(Platform.pathSeparator),
      );
      // 如果上一级是 /storage/emulated/0 或 /storage/emulated/0/ ，不显示返回按钮
      if (parentPath == '/storage/emulated/0' ||
          parentPath == '/storage/emulated/0/') {
        return false;
      }
      // 如果当前就是系统根目录，不显示返回按钮
      if (currentPath == '/storage/emulated/0' ||
          currentPath == '/storage/emulated/0/') {
        return false;
      }
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
      case 'theme':
        presenter.toggleTheme();
        break;
      case 'manage_quick_access':
        _navigateToQuickAccessManagePage();
        break;
      case 'about':
        _showAboutDialog();
        break;
    }
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

  /// 导航到快速访问管理页面
  void _navigateToQuickAccessManagePage() {
    if (quickAccessPresenter == null || quickAccessViewModel == null) {
      logger.e('QuickAccessPresenter or ViewModel is null');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuickAccessManagePage(
          presenter: quickAccessPresenter!,
          viewModel: quickAccessViewModel!,
        ),
      ),
    );
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

  /// 获取主题菜单文本
  String _getThemeMenuText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '切换主题（当前：浅色）';
      case ThemeMode.dark:
        return '切换主题（当前：深色）';
      case ThemeMode.system:
        return '切换主题（跟随系统）';
    }
  }

  /// 构建 Tab 按钮
  Widget _buildTabButton(
    BuildContext context,
    String label,
    TabView tab,
    bool isSelected, {
    VoidCallback? onTap,
    int? count,
  }) {
    // 如果是不可点击的Tab（文件浏览），使用特殊样式
    final isClickable = onTap != null;

    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: !isClickable && isSelected ? 0.85 : 1.0, // 不可点击的Tab稍微降低透明度
        child: Container(
          height: 20, // 限制高度与分割线一致
          padding: const EdgeInsets.symmetric(horizontal: 4), // 减小水平padding
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 不可点击的Tab添加一个位置图标
              if (!isClickable && isSelected) ...[
                Icon(
                  Icons.folder_open,
                  size: 14,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                count != null ? '$label（$count）' : label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14, // 普通正文大小
                  fontWeight: isSelected ? FontWeight.w400 : FontWeight.normal,
                  color: isSelected && isClickable
                      ? Theme.of(context).colorScheme.primary
                      : (isSelected && !isClickable
                            ? Theme.of(context).colorScheme.tertiary
                            : Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 获取文件浏览Tab的标签文本
  String _getBrowseTabLabel(FileViewModel vm) {
    if (vm.currentTab == TabView.browse && vm.currentPath.isNotEmpty) {
      // 查找快速访问文件夹（包括子目录）
      if (quickAccessViewModel != null) {
        // 遍历所有快速访问文件夹，查找当前路径所属的根文件夹
        for (final folder in quickAccessViewModel!.folders) {
          // 检查当前路径是否等于或在该快速访问文件夹内
          if (vm.currentPath == folder.path || 
              vm.currentPath.startsWith(folder.path + Platform.pathSeparator)) {
            // 限制名称长度，防止溢出（最多8个字符）
            final displayName = folder.displayName;
            final truncatedName = displayName.length > 8 
                ? '${displayName.substring(0, 8)}...' 
                : displayName;
            return '文件浏览 - $truncatedName';
          }
        }
      }

      // 如果不在快速访问中，从路径中提取文件夹名
      final pathSegments = vm.currentPath.split(Platform.pathSeparator);
      final folderName = pathSegments.last.isEmpty
          ? (pathSegments.length > 1
                ? pathSegments[pathSegments.length - 2]
                : '')
          : pathSegments.last;

      if (folderName.isNotEmpty) {
        // 同样限制长度
        final truncatedName = folderName.length > 8 
            ? '${folderName.substring(0, 8)}...' 
            : folderName;
        return '文件浏览 - $truncatedName';
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
                      size: 48,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      vm.isSearchMode ? '未找到匹配的文件' : '此文件夹为空',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      vm.isSearchMode
                          ? '尝试使用不同的搜索关键词'
                          : '当前路径: ${vm.currentPath.isEmpty ? '最近文件' : vm.currentPath}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '下拉刷新',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
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
      child: _buildFileView(vm),
    );
  }

  /// 构建列表/网格视图（使用FileCollectionView）
  Widget _buildFileView(FileViewModel vm) {
    final viewModeService = ViewModeService();
    return FileCollectionView(
      items: vm.files,
      gridMode: viewModeService.isGridView,
      padding: viewModeService.isGridView
          ? const EdgeInsets.all(8)
          : const EdgeInsets.symmetric(vertical: 0),
      selectionController: _isSelectionMode ? _selectionController : null,
      // 列表模式显示选项
      showFullPath: vm.isSearchMode,
      showAccessTime: vm.currentTab == TabView.recent,
      getAccessTime: (file) => file.accessedAt,
      showFavoriteButton: true,
      isFavorite: (path) => vm.isFavoriteFile(path),
      onFavoriteToggle: (file) async {
        return await presenter.toggleFavoriteFile(file);
      },
      // 网格模式使用自定义构建器
      itemBuilder: viewModeService.isGridView ? (file) {
        final isSelected = _selectionController.contains(file.path);
        return _buildGridItem(file, vm, isSelected);
      } : null, // 列表模式使用默认实现
      onTap: (file) => _onFileTap(file, vm),
      onLongPress: (file) {
        // 长按进入多选模式并选中当前项
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
          });
        }
      },
    );
  }

  /// 构建网格项（用于网格视图）
  Widget _buildGridItem(FileItem file, FileViewModel vm, bool isSelected) {
    final isImage = !file.isDirectory && FileUtils.isImageFile(file.name);
    final isVideo = !file.isDirectory && FileUtils.isVideoFile(file.name);
    final isAudio = !file.isDirectory && FileUtils.isAudioFile(file.name);
    final isDocument = !file.isDirectory && FileUtils.isDocumentFile(file.name);
    final isFavorite = vm.isFavoriteFile(file.path);

    return InkWell(
      onTap: () => _onFileTap(file, vm),
      onLongPress: () {
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            _selectionController.select(file.path);
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: 2,  // 固定宽度，避免选中时溢出
          ),
        ),
        child: Stack(
        children: [
          // 主内容区域 - 图标在上，文件名和大小在下
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 文件图标或缩略图
                  if (isImage)
                    ImageThumbnail(imagePath: file.path, size: 64)
                  else if (isVideo)
                    RealVideoThumbnail(videoPath: file.path, size: 64)
                  else if (isAudio)
                    AudioCoverWidget(audioPath: file.path, size: 64)
                  else if (isDocument)
                    DocumentIconWidget(fileName: file.name, size: 64)
                  else
                    Icon(
                      file.isDirectory ? Icons.folder : Icons.insert_drive_file,
                      size: 48,
                      color: file.isDirectory ? Colors.amber : Colors.blue,
                    ),
                  const SizedBox(height: 8),
                  // 文件名
                  Text(
                    file.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  // 文件大小或访问时间
                  if (vm.currentTab == TabView.recent && file.accessedAt != null)
                    Text(
                      TimeFormatter.formatRelativeTime(file.accessedAt!),
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (!file.isDirectory)
                    Text(
                      FileUtils.formatFileSize(file.size),
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
          // 收藏按钮（右上角）- 非文件夹才显示
          if (!file.isDirectory)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                width: 26,
                height: 26,
                child: Transform.scale(
                  scale: 0.75,  // 与复选框使用相同的缩放比例
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final isFavoriteNew = await presenter.toggleFavoriteFile(file);
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(isFavoriteNew ? '已添加到收藏' : '已取消收藏'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          isFavorite ? Icons.star : Icons.star_border,
                          color: isFavorite ? Colors.amber : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // 多选模式下的Checkbox（右下角）
          if (_isSelectionMode)
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                width: 26,
                height: 26,
                child: Transform.scale(
                  scale: 0.75,  // 缩放到18px，与收藏按钮大小一致
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (bool? value) {
                      if (value == true) {
                        _selectionController.select(file.path);
                      } else {
                        _selectionController.deselect(file.path);
                      }
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  }

  /// 构建网格项（用于网格视图）
  /// 获取文件图标
  /// 处理文件点击
  void _onFileTap(FileItem file, FileViewModel vm) {
    // 多选模式下的点击由FileCollectionView处理，这里只处理导航
    if (_isSelectionMode) {
      return; // FileCollectionView已处理选择逻辑
    }

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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 如果 QuickAccess 相关还未初始化，只显示加载中
    if (quickAccessViewModel == null || quickAccessPresenter == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<FileViewModel>.value(value: viewModel),
        ChangeNotifierProvider<QuickAccessViewModel>.value(
          value: quickAccessViewModel!,
        ),
        ChangeNotifierProvider<NewFolderNotificationService>.value(
          value: locator<NewFolderNotificationService>(),
        ),
      ],
      child: Consumer3<FileViewModel, QuickAccessViewModel, ViewModeService>(
        builder: (context, vm, quickVm, viewModeService, _) {
          if (vm.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return Scaffold(
            appBar: AppBar(
              leading: _isSelectionMode
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _isSelectionMode = false;
                          _selectionController.clear();
                        });
                      },
                    )
                  : null,
              title: _isSelectionMode
                  ? Text('已选中 ${_selectedItems.length} 项')
                  : Row(
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
              actions: _isSelectionMode
                  ? [
                      // 全选按钮
                      IconButton(
                        icon: Icon(
                          _selectedItems.length == vm.files.length
                              ? Icons.deselect
                              : Icons.select_all,
                        ),
                        onPressed: () {
                          if (_selectedItems.length == vm.files.length) {
                            _selectionController.clear();
                          } else {
                            _selectionController.selectAll(
                              vm.files.map((f) => f.path).toList(),
                            );
                          }
                        },
                        tooltip: _selectedItems.length == vm.files.length
                            ? '取消全选'
                            : '全选',
                      ),
                    ]
                  : [
                      PopupMenuButton<String>(
                        onSelected: _handleMenuAction,
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'theme',
                            child: Row(
                              children: [
                                Icon(_getThemeIcon(vm.themeMode)),
                                const SizedBox(width: 8),
                                Text(_getThemeMenuText(vm.themeMode)),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'manage_quick_access',
                            child: Row(
                              children: [
                                Icon(Icons.folder_special),
                                SizedBox(width: 8),
                                Text('管理快速访问'),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'about',
                            child: Row(
                              children: [
                                Icon(Icons.info_outline),
                                SizedBox(width: 8),
                                Text('关于'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                // 捕获主题数据，避免在嵌套builder中多次调用Theme.of
                final theme = Theme.of(context);
                final colorScheme = theme.colorScheme;

                return Column(
                  children: [
                    // 上半部分固定区域 - 搜索模式下隐藏，避免溢出
                    if (!vm.isSearchMode)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxWidth > constraints.maxHeight
                              ? constraints.maxHeight * 0.35  // 横屏：35%
                              : constraints.maxHeight * 0.5,  // 竖屏：50%
                        ),
                        child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 分类导航区（快速入口）
                            CategoryNavBar(
                              presenter: presenter,
                              viewModel: vm,
                              onCardSizeCalculated: (size) {
                                if (mounted && _categoryCardSize != size) {
                                  setState(() {
                                    _categoryCardSize = size;
                                  });
                                }
                              },
                            ),
                            const Divider(height: 1),

                            // 快速访问区域（新）
                            QuickAccessSection(
                              quickAccessViewModel: quickAccessViewModel!,
                              quickAccessPresenter: quickAccessPresenter!,
                              fileViewModel: vm,
                              filePresenter: presenter,
                              categoryCardSize: _categoryCardSize,
                            ),
                            const Divider(height: 1),
                          ],
                        ),
                      ),
                    ),

                    // Tab 切换栏和工具按钮 - 搜索模式下也隐藏
                    if (!vm.isSearchMode)
                      Container(
                        height: 32, // 固定高度
                        color: colorScheme.surface,
                        padding: const EdgeInsets.only(right: 4),
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
                            count: vm.currentTab == TabView.recent
                                ? vm.files.length
                                : null,
                          ),
                          // 分割线
                          Container(
                            width: 1,
                            height: 20,
                            color: theme.dividerColor,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                          ),
                          // 收藏 Tab
                          _buildTabButton(
                            context,
                            '收藏',
                            TabView.favorite,
                            vm.currentTab == TabView.favorite,
                            onTap: () {
                              viewModel.setCurrentTab(TabView.favorite);
                              presenter.loadFavoriteFiles();
                            },
                            count: vm.currentTab == TabView.favorite
                                ? vm.files.length
                                : null,
                          ),
                          // 分割线和文件浏览Tab - 仅在browse模式下显示
                          if (vm.currentTab == TabView.browse) ...[
                            Container(
                              width: 1,
                              height: 20,
                              color: theme.dividerColor,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                            ),
                            _buildTabButton(
                              context,
                              _getBrowseTabLabel(vm),
                              TabView.browse,
                              vm.currentTab == TabView.browse,
                              onTap: null, // 文件浏览 Tab 不可点击，只能通过收藏夹激活
                              count: null, // 不显示数量，避免与下方标签栏重复
                            ),
                          ],
                          // 占位空间
                          const Spacer(),
                          // 工具按钮组（使用统一的FileToolbar组件）
                          FileToolbar(
                            showBackButton: vm.currentTab == TabView.browse &&
                                vm.currentPath.isNotEmpty &&
                                _canNavigateUp(vm.currentPath),
                            onBackPressed: () => presenter.navigateUp(),
                            showSearchButton: vm.currentTab == TabView.browse,
                            onSearchPressed: () => presenter.toggleSearch(),
                            isSearchMode: vm.isSearchMode,
                            iconSize: 20,
                          ),
                        ],
                      ),
                    ),

                    // 搜索栏（使用统一的FileSearchBar组件）
                    if (vm.isSearchMode)
                      FileSearchBar(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        hintText: '搜索文件...',
                        onSearch: (query) async {
                          if (query.isNotEmpty) {
                            presenter.searchFiles(query);
                          }
                        },
                        onClose: () {
                          _searchController.clear();
                          presenter.clearSearch();
                        },
                      ),

                    // 文件类型筛选Tab栏（仅在浏览模式显示）
                    if (vm.currentTab == TabView.browse && !vm.isSearchMode)
                      FileCategoryTabBar(
                        stats: vm.fileTypeStats,
                        selectedCategory: vm.selectedCategory,
                        onCategoryChanged: (category) {
                          vm.setSelectedCategory(category);
                        },
                      ),

                    // 文件列表区域（占据剩余空间）
                    Expanded(
                      child: GestureDetector(
                        onHorizontalDragEnd: (details) {
                          // 右滑返回上级（速度 > 500 或距离 > 100）
                          // 搜索模式下禁用手势返回
                          if (!vm.isSearchMode &&
                              details.primaryVelocity != null &&
                              details.primaryVelocity! > 500 &&
                              vm.currentPath.isNotEmpty &&
                              _canNavigateUp(vm.currentPath)) {
                            presenter.navigateUp();
                          }
                        },
                        child: _buildFileList(vm),
                      ),
                    ),
                  ],
                );
              },
            ),
            // 批量操作底部工具栏
            bottomNavigationBar: _isSelectionMode
                ? _buildSelectionBottomBar()
                : null,
          );
        },
      ),
    );
  }

  /// 构建批量选择底部工具栏
  Widget _buildSelectionBottomBar() {
    // 统计选中的文件和文件夹数量
    int fileCount = 0;
    int folderCount = 0;
    int totalSize = 0;

    for (final path in _selectedItems) {
      final entity = FileSystemEntity.typeSync(path);
      if (entity == FileSystemEntityType.directory) {
        folderCount++;
      } else if (entity == FileSystemEntityType.file) {
        fileCount++;
        try {
          totalSize += File(path).lengthSync();
        } catch (e) {
          logger.w('Failed to get file size: $path');
        }
      }
    }

    // 判断是否只选中了文件（可以分享）
    final hasOnlyFiles = folderCount == 0 && fileCount > 0;
    // 判断是否只选中了一个项（可以重命名）
    final isSingleSelection = _selectedItems.length == 1;

    return BottomAppBar(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // 显示选中信息
            Expanded(
              child: Text(
                _buildSelectionInfo(fileCount, folderCount, totalSize),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 操作按钮 - 紧凑排列
            // 复制按钮（单个文件/文件夹）
            if (isSingleSelection)
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: _batchCopy,
                tooltip: '复制',
                padding: EdgeInsets.zero,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
              ),
            // 重命名按钮（单个文件/文件夹）
            if (isSingleSelection)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: _batchRename,
                tooltip: '重命名',
                padding: EdgeInsets.zero,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
              ),
            // 分享按钮（只有文件可以分享）
            if (hasOnlyFiles)
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: _batchShare,
                tooltip: '分享',
                padding: EdgeInsets.zero,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
              ),
            // 移动按钮
            IconButton(
              icon: const Icon(Icons.drive_file_move),
              onPressed: _selectedItems.isEmpty ? null : _batchMove,
              tooltip: '移动',
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
            // 批量收藏/取消收藏按钮（只有文件可以收藏）
            if (hasOnlyFiles)
              IconButton(
                icon: Icon(_isAllSelectedFavorite() ? Icons.star : Icons.star_border),
                onPressed: _batchToggleFavorite,
                tooltip: _isAllSelectedFavorite() ? '取消收藏' : '添加收藏',
                color: _isAllSelectedFavorite() ? Colors.amber : null,
                padding: EdgeInsets.zero,
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              ),
            // 删除按钮
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selectedItems.isEmpty ? null : _batchDelete,
              tooltip: '删除',
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建选中信息文本
  String _buildSelectionInfo(int fileCount, int folderCount, int totalSize) {
    final parts = <String>[];
    if (fileCount > 0) parts.add('$fileCount 个文件');
    if (folderCount > 0) parts.add('$folderCount 个文件夹');
    final info = parts.join('，');
    if (totalSize > 0) {
      return '$info · ${FileUtils.formatFileSize(totalSize)}';
    }
    return info;
  }

  /// 检查选中的文件是否全部已收藏
  bool _isAllSelectedFavorite() {
    if (_selectedItems.isEmpty) return false;
    return _selectedItems.every((path) => viewModel.isFavoriteFile(path));
  }

  /// 批量添加/取消收藏
  void _batchToggleFavorite() async {
    if (_selectedItems.isEmpty) return;

    final allFavorite = _isAllSelectedFavorite();
    final action = allFavorite ? '取消收藏' : '添加到收藏';
    
    int successCount = 0;
    int failCount = 0;

    for (final path in _selectedItems) {
      // 只处理文件，跳过文件夹
      final entity = FileSystemEntity.typeSync(path);
      if (entity != FileSystemEntityType.file) continue;

      try {
        final file = FileItem(
          name: path.split(Platform.pathSeparator).last,
          path: path,
          size: File(path).lengthSync(),
          modified: File(path).lastModifiedSync(),
          isDirectory: false,
        );

        if (allFavorite) {
          // 全部已收藏，则取消收藏
          await presenter.toggleFavoriteFile(file);
          successCount++;
        } else {
          // 有未收藏的，则添加收藏
          final isFav = viewModel.isFavoriteFile(path);
          if (!isFav) {
            await presenter.toggleFavoriteFile(file);
            successCount++;
          }
        }
      } catch (e) {
        logger.e('Failed to toggle favorite: $path, error: $e');
        failCount++;
      }
    }

    if (mounted) {
      final message = failCount > 0
          ? '$action完成：成功 $successCount 个，失败 $failCount 个'
          : '已${action} $successCount 个文件';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 批量删除
  void _batchDelete() async {
    if (_selectedItems.isEmpty) return;

    // 🔒 安全检查：验证所有选中项是否允许删除
    for (final path in _selectedItems) {
      final riskLevel = PathSecurity.getPathRiskLevel(path);

      if (riskLevel == PathRiskLevel.forbidden ||
          riskLevel == PathRiskLevel.danger) {
        final fileName = path.split(Platform.pathSeparator).last;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🛑 禁止删除'),
            content: Text(
              '选中的文件包含受保护的系统目录 "$fileName"！\n\n'
              '删除系统目录会导致：\n'
              '• 系统功能损坏\n'
              '• 应用无法运行\n'
              '• 数据永久丢失\n\n'
              '为保护您的设备，此操作已被阻止。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
        logger.w('Delete blocked by UI: $path (Risk: ${riskLevel.name})');
        return;
      }

      // 检查是否为系统关键文件夹
      final fileName = path.split(Platform.pathSeparator).last;
      if (PathSecurity.isSystemFolderName(fileName)) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🔒 禁止删除'),
            content: Text(
              '"$fileName" 是系统重要文件夹！\n\n'
              '删除此文件夹会导致系统功能异常。\n\n'
              '为保护您的设备，此操作已被阻止。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
        logger.w('Delete blocked: "$fileName" is a system folder');
        return;
      }
    }

    // 统计文件和文件夹数量
    int fileCount = 0;
    int folderCount = 0;
    for (final path in _selectedItems) {
      final entity = FileSystemEntity.typeSync(path);
      if (entity == FileSystemEntityType.directory) {
        folderCount++;
      } else if (entity == FileSystemEntityType.file) {
        fileCount++;
      }
    }

    // 预先捕获 messenger，避免在 await 后使用 BuildContext
    final messenger = ScaffoldMessenger.of(context);

    // 使用增强的删除确认对话框
    final confirmed = await EnhancedDeleteDialog.showBatchDeleteConfirmation(
      context: context,
      paths: _selectedItems.toList(),
      fileCount: fileCount,
      folderCount: folderCount,
    );

    if (!confirmed || !mounted) return;

    // 显示进度
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在删除...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      int successCount = 0;
      int failCount = 0;

      for (final path in _selectedItems) {
        try {
          // 🔒 记录操作日志
          final riskLevel = PathSecurity.getPathRiskLevel(path);
          PathSecurity.logOperation(
            operation: 'DELETE (UI)',
            path: path,
            riskLevel: riskLevel,
            allowed: true,
          );

          final entity = FileSystemEntity.typeSync(path);
          if (entity == FileSystemEntityType.directory) {
            await Directory(path).delete(recursive: true);
          } else if (entity == FileSystemEntityType.file) {
            await File(path).delete();
          }
          successCount++;
        } catch (e) {
          logger.e('Failed to delete: $path, error: $e');
          failCount++;
        }
      }

      if (mounted) {
        navigator.pop(); // 关闭进度对话框

        // 刷新文件列表
        await presenter.loadFiles(viewModel.currentPath);

        // 退出多选模式
        setState(() {
          _isSelectionMode = false;
          _selectedItems.clear();
        });

        // 显示结果提示
        if (failCount == 0) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('成功删除 $successCount 项'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text('成功删除 $successCount 项，失败 $failCount 项'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        navigator.pop(); // 关闭进度对话框
        messenger.showSnackBar(
          SnackBar(content: Text('删除失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 批量移动
  void _batchMove() async {
    if (_selectedItems.isEmpty) return;

    // 🔒 安全检查：验证所有选中项是否允许移动
    for (final path in _selectedItems) {
      final riskLevel = PathSecurity.getPathRiskLevel(path);

      if (riskLevel == PathRiskLevel.forbidden ||
          riskLevel == PathRiskLevel.danger) {
        final fileName = path.split(Platform.pathSeparator).last;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('无法移动 "$fileName"：这是受保护的系统目录'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        logger.w('Move blocked by UI: $path (Risk: ${riskLevel.name})');
        return;
      }

      // 检查是否为系统关键文件夹
      final fileName = path.split(Platform.pathSeparator).last;
      if (PathSecurity.isSystemFolderName(fileName)) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🔒 禁止移动'),
            content: Text(
              '"$fileName" 是系统重要文件夹！\n\n'
              '移动此文件夹会导致系统功能异常。\n\n'
              '为保护您的设备，此操作已被阻止。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
        logger.w('Move blocked: "$fileName" is a system folder');
        return;
      }
    }

    // 预先捕获 messenger，避免在 await 后使用 BuildContext
    final messenger = ScaffoldMessenger.of(context);

    // 显示文件夹选择对话框
    final destinationPath = await showDialog<String>(
      context: context,
      builder: (context) =>
          FolderPickerDialog(currentPath: viewModel.currentPath),
    );

    if (destinationPath == null || !mounted) return;

    // 🔒 验证目标路径安全性
    final targetRiskLevel = PathSecurity.getPathRiskLevel(destinationPath);
    if (targetRiskLevel == PathRiskLevel.forbidden ||
        targetRiskLevel == PathRiskLevel.danger) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('目标位置不安全，无法移动文件'),
          backgroundColor: Colors.red,
        ),
      );
      logger.w('Move blocked: target path $destinationPath is protected');
      return;
    }

    // 检查是否要移动到子目录（会造成循环）
    for (final path in _selectedItems) {
      if (FileSystemEntity.typeSync(path) == FileSystemEntityType.directory) {
          if (destinationPath.startsWith(path + Platform.pathSeparator) ||
            destinationPath == path) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('不能将文件夹移动到自己的子目录中'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }

    // 显示进度
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在移动...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      int successCount = 0;
      int failCount = 0;

      for (final path in _selectedItems) {
        try {
          final entity = FileSystemEntity.typeSync(path);
          final baseName = path.split(Platform.pathSeparator).last;
          final targetPath =
              '$destinationPath${Platform.pathSeparator}$baseName';

          // 🔒 记录操作日志
          final riskLevel = PathSecurity.getPathRiskLevel(path);
          PathSecurity.logOperation(
            operation: 'MOVE (UI)',
            path: '$path -> $targetPath',
            riskLevel: riskLevel,
            allowed: true,
          );

          if (entity == FileSystemEntityType.directory) {
            await Directory(path).rename(targetPath);
          } else if (entity == FileSystemEntityType.file) {
            await File(path).rename(targetPath);
          }
          successCount++;
        } catch (e) {
          logger.e('Failed to move: $path, error: $e');
          failCount++;
        }
      }

      if (mounted) {
                          navigator.pop(); // 关闭进度对话框

        // 刷新文件列表
        await presenter.loadFiles(viewModel.currentPath);

        // 退出多选模式
        setState(() {
          _isSelectionMode = false;
          _selectedItems.clear();
        });

        // 显示结果提示
        if (failCount == 0) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('成功移动 $successCount 项'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text('成功移动 $successCount 项，失败 $failCount 项'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
                          navigator.pop(); // 关闭进度对话框
        messenger.showSnackBar(
          SnackBar(content: Text('移动失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 批量复制
  void _batchCopy() async {
    if (_selectedItems.length != 1) return;

    final sourcePath = _selectedItems.first;

    // 预先捕获 messenger 和 navigator，避免在 await 后使用 BuildContext
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // 显示文件夹选择对话框
    final destinationPath = await showDialog<String>(
      context: context,
      builder: (context) =>
          FolderPickerDialog(currentPath: viewModel.currentPath),
    );

    if (destinationPath == null || !mounted) return;

    // 显示进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在复制...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final entity = FileSystemEntity.typeSync(sourcePath);
      final baseName = sourcePath.split(Platform.pathSeparator).last;
      final targetPath = '$destinationPath${Platform.pathSeparator}$baseName';

      if (entity == FileSystemEntityType.directory) {
        // 递归复制文件夹
        await _copyDirectory(Directory(sourcePath), Directory(targetPath));
      } else if (entity == FileSystemEntityType.file) {
        await File(sourcePath).copy(targetPath);
      }

      if (mounted) {
        navigator.pop(); // 关闭进度对话框

        // 刷新文件列表
        await presenter.loadFiles(viewModel.currentPath);

        // 退出多选模式
        setState(() {
          _isSelectionMode = false;
          _selectedItems.clear();
        });

        messenger.showSnackBar(
          const SnackBar(content: Text('复制成功'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        navigator.pop(); // 关闭进度对话框
        messenger.showSnackBar(
          SnackBar(content: Text('复制失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 递归复制文件夹
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }

    await for (final entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDirectory = Directory(
          '${destination.path}${Platform.pathSeparator}${entity.path.split(Platform.pathSeparator).last}',
        );
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy(
          '${destination.path}${Platform.pathSeparator}${entity.path.split(Platform.pathSeparator).last}',
        );
      }
    }
  }

  /// 批量重命名
  void _batchRename() async {
    if (_selectedItems.length != 1) return;

    final sourcePath = _selectedItems.first;
    final entity = FileSystemEntity.typeSync(sourcePath);
    final currentName = sourcePath.split(Platform.pathSeparator).last;
    final isDirectory = entity == FileSystemEntityType.directory;

    // 🔒 安全检查：验证是否允许重命名
    final riskLevel = PathSecurity.getPathRiskLevel(sourcePath);

    // 禁止重命名系统关键目录
    if (riskLevel == PathRiskLevel.forbidden ||
        riskLevel == PathRiskLevel.danger) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              PathSecurity.getOperationDeniedMessage(sourcePath, '重命名'),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      logger.w('Rename blocked by UI: $sourcePath (Risk: ${riskLevel.name})');
      return;
    }

    // 检查是否为系统关键文件夹名称
    if (PathSecurity.isSystemFolderName(currentName)) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🔒 禁止重命名'),
            content: Text(
              '"$currentName" 是系统重要文件夹！\n\n'
              '重命名此文件夹会导致：\n'
              '• 系统功能异常\n'
              '• 应用无法访问文件\n'
              '• 媒体库损坏\n\n'
              '为保护您的设备，此操作已被阻止。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('我知道了'),
              ),
            ],
          ),
        );
      }
      logger.w('Rename blocked: "$currentName" is a system folder');
      return;
    }

    // 显示重命名对话框
    final TextEditingController controller = TextEditingController(
      text: currentName,
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isDirectory ? '重命名文件夹' : '重命名文件'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: '新名称', hintText: '请输入新名称'),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              Navigator.pop(context, value);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (newName == null || newName.trim().isEmpty || !mounted) return;
    if (newName == currentName) return; // 名称没有改变

    // 显示进度
    // 预先捕获 messenger 和 navigator
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在重命名...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final parentPath = sourcePath.substring(
        0,
        sourcePath.lastIndexOf(Platform.pathSeparator),
      );
      final targetPath =
          '$parentPath${Platform.pathSeparator}${newName.trim()}';

      // 🔒 验证目标路径安全性
      final targetRiskLevel = PathSecurity.getPathRiskLevel(targetPath);
      if (targetRiskLevel == PathRiskLevel.forbidden ||
          targetRiskLevel == PathRiskLevel.danger) {
        if (mounted) {
          Navigator.pop(context); // 关闭进度对话框
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('重命名失败：目标路径不安全'),
              backgroundColor: Colors.red,
            ),
          );
        }
        logger.w('Rename blocked: target path $targetPath is protected');
        return;
      }

      // 🔒 记录操作日志
      PathSecurity.logOperation(
        operation: 'RENAME (UI)',
        path: '$sourcePath -> $targetPath',
        riskLevel: riskLevel,
        allowed: true,
      );

      if (entity == FileSystemEntityType.directory) {
        await Directory(sourcePath).rename(targetPath);
      } else if (entity == FileSystemEntityType.file) {
        await File(sourcePath).rename(targetPath);
      }

      if (mounted) {
        navigator.pop(); // 关闭进度对话框

        // 刷新文件列表
        await presenter.loadFiles(viewModel.currentPath);

        // 退出多选模式
        setState(() {
          _isSelectionMode = false;
          _selectedItems.clear();
        });

        messenger.showSnackBar(
          const SnackBar(content: Text('重命名成功'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        navigator.pop(context); // 关闭进度对话框
        messenger.showSnackBar(
          SnackBar(content: Text('重命名失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 批量分享
  void _batchShare() async {
    if (_selectedItems.isEmpty) return;

    // 只分享文件，过滤掉文件夹
    final filePaths = _selectedItems.where((path) {
      return FileSystemEntity.typeSync(path) == FileSystemEntityType.file;
    }).toList();

    if (filePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请选择至少一个文件进行分享'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 预先捕获 messenger
    final messenger = ScaffoldMessenger.of(context);

    try {
      // 使用presenter批量分享
      final success = await presenter.batchShareFiles(filePaths);

      if (mounted) {
        if (success) {
          // 分享成功后退出多选模式
          setState(() {
            _isSelectionMode = false;
            _selectedItems.clear();
          });
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('分享失败，请检查是否有有效的文件'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      logger.e('Failed to share files: $e');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('分享失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
