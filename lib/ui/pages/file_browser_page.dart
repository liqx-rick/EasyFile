import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyfile/utils/file_utils.dart';

import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/permission_service.dart';
import 'package:easyfile/core/services/first_scan_service.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';
import 'package:easyfile/ui/pages/settings_page.dart';
import 'package:easyfile/ui/pages/about_page.dart';
import 'package:easyfile/ui/pages/quick_access_manage_page.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/category_nav_bar.dart';
import 'package:easyfile/ui/widgets/quick_access_section.dart';
import 'package:easyfile/ui/widgets/new_folder_notification.dart';
import 'package:easyfile/ui/widgets/file_category_tab_bar.dart';
import 'package:easyfile/ui/widgets/file_toolbar.dart';
import 'package:easyfile/ui/widgets/file_search_bar.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/ui/widgets/selection_bottom_bar.dart';
import 'package:easyfile/ui/widgets/first_scan_card_overlay.dart';
import 'package:easyfile/ui/widgets/folder_navigation_bar.dart';
import 'package:easyfile/utils/file_comparator_util.dart';
import 'package:easyfile/ui/widgets/permission_banner.dart';
import 'package:easyfile/ui/services/batch_operations_service.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/utils/file_grouping_util.dart';
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

  // 权限和扫描相关状态
  late PermissionService _permissionService;
  bool _isScanning = false;
  PermissionState _permissionState = PermissionState.unknown;
  bool _isFirstScan = false;
  double _scanProgress = 0.0; // 扫描进度 (0.0 - 1.0)

  // 批量操作相关（SelectionController 内部管理 isSelectionMode 状态）
  Set<String> _selectedItems = {}; // 存储选中的文件/文件夹路径
  late final SelectionController _selectionController;

  // 搜索相关状态
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // 收藏Tab的搜索和过滤状态
  bool _favoriteSearchMode = false;
  String _favoriteSearchQuery = '';
  final TextEditingController _favoriteSearchController =
      TextEditingController();
  final FocusNode _favoriteSearchFocusNode = FocusNode();

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

      _permissionService = locator<PermissionService>();
      logger.d('PermissionService obtained: $_permissionService');

      // 延迟初始化应用程序数据，先显示UI - 这个优化保留
      Future.microtask(() => _initializeAppWithPermission());

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
    _favoriteSearchController.dispose();
    _favoriteSearchFocusNode.dispose();
    _selectionController.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    setState(() {
      _selectedItems = _selectionController.selected;
      // SelectionController 自动管理 isSelectionMode 状态
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    logger.d('FileBrowserPage: App lifecycle changed to $state');

    // 当应用从后台恢复时，重新检查权限状态
    if (state == AppLifecycleState.resumed) {
      _checkPermissionAfterResume();
    }
  }

  /// 应用恢复时检查权限（用户可能从设置页面授权返回）
  ///
  /// 当应用从后台恢复到前台时，如果之前没有权限，重新检查权限状态。
  /// 这允许用户在系统设置中授权后，返回应用时自动初始化。
  Future<void> _checkPermissionAfterResume() async {
    // 如果当前是无权限状态，重新检查
    if (_permissionState != PermissionState.granted) {
      logger.i('App resumed, rechecking permission...');
      final newState = await _permissionService.checkPermission();

      if (newState.isGranted && newState != _permissionState) {
        // 权限状态改变为已授权，开始初始化
        logger.i('Permission granted after resume, initializing...');
        setState(() {
          _permissionState = newState;
        });
        await _initializeApp();
      } else if (newState != _permissionState) {
        setState(() {
          _permissionState = newState;
        });
      }
    }
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
                  builder: (context) => FilePreviewPage(
                    file: fileItem,
                    viewModel: viewModel,
                    presenter: presenter,
                  ),
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

  /// 初始化应用程序数据（带权限检查）
  ///
  /// 该方法是应用启动时的入口点，会：
  /// 1. 检查文件系统访问权限
  /// 2. 初始化UI主题（无论是否有权限）
  /// 3. 如果有权限，进行完整的应用初始化
  /// 4. 如果没有权限，显示权限提示横幅但不阻塞页面显示
  Future<void> _initializeAppWithPermission() async {
    logger.i('Initializing app with permission check...');

    try {
      // 先检查权限状态
      final permissionState = await _permissionService.checkPermission();
      setState(() {
        _permissionState = permissionState;
      });

      // 无论是否有权限，都初始化UI（不阻塞显示）
      await presenter.initializeTheme();

      if (permissionState.isGranted) {
        // 权限已授予，开始扫描和初始化
        await _initializeApp();
      } else {
        // 没有权限，显示权限提示框，但不阻塞页面显示
        logger.i('Permission not granted, showing permission banner');
      }
    } catch (e) {
      logger.e('Error during app initialization with permission: $e');
    }
  }

  /// 初始化应用程序数据
  ///
  /// 该方法执行以下任务：
  /// 1. 并行初始化收藏夹、收藏文件和主题
  /// 2. 加载快速访问文件夹
  /// 3. 检查是否需要首次深度扫描，如果需要则执行扫描并显示进度
  /// 4. 加载初始目录
  Future<void> _initializeApp() async {
    logger.i('Initializing app data...');

    try {
      // 并行初始化收藏夹、收藏文件和主题
      await Future.wait([
        presenter.initializeFavorites(),
        presenter.initializeFavoriteFiles(), // 初始化收藏文件
        presenter.initializeTheme(),
      ]);

      // 初始化快速访问（加载已有的快速访问目录）
      if (quickAccessPresenter != null) {
        await quickAccessPresenter!.loadQuickAccessFolders();

        // 检查是否需要执行首次深度扫描
        // 首次扫描会发现系统目录、应用目录，并对所有文件进行分类
        final needsScan = await FirstScanService().needsFirstScan();
        logger.i('First scan needed: $needsScan');

        if (needsScan) {
          logger.i('Performing first-time comprehensive scan...');

          // 显示首次扫描进度卡片 UI
          setState(() {
            _isScanning = true;
            _isFirstScan = true;
            _scanProgress = 0.0;
          });

          // 执行综合扫描（同时扫描快速访问和分类文件）
          // onProgress 回调会实时更新 UI 进度显示 (0.0 - 1.0)
          final scanResult =
              await quickAccessPresenter!.performFirstTimeComprehensiveScan(
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _scanProgress = progress;
                });
              }
            },
            scanCategoryFiles: () async {
              // 使用 FilePresenter 的完整扫描逻辑
              logger.i('Scanning all category files using FilePresenter...');
              final Map<FileCategory, int> counts = {};

              // 初始化所有分类计数
              for (final category in FileCategory.values) {
                counts[category] = 0;
              }

              // 扫描所有分类类型
              final categoriesToScan = [
                CategoryType.images,
                CategoryType.video,
                CategoryType.music,
                CategoryType.documents,
                CategoryType.downloads,
              ];

              int totalFiles = 0;
              final prefs = await SharedPreferences.getInstance();

              // 分类扫描的进度范围: 30% - 95%
              // 每个分类占约 13% 进度 (65% / 5 = 13%)
              final progressPerCategory = 0.13;
              var currentCategoryIndex = 0;

              for (final categoryType in categoriesToScan) {
                try {
                  // 更新当前分类扫描的进度
                  final baseProgress =
                      0.30 + (currentCategoryIndex * progressPerCategory);
                  if (mounted) {
                    setState(() {
                      _scanProgress = baseProgress;
                    });
                  }

                  final files =
                      await presenter.scanFilesByCategory(categoryType);
                  final count = files.length;

                  // 映射到 FileCategory
                  FileCategory fileCategory;
                  switch (categoryType) {
                    case CategoryType.images:
                      fileCategory = FileCategory.image;
                      break;
                    case CategoryType.video:
                      fileCategory = FileCategory.video;
                      break;
                    case CategoryType.music:
                      fileCategory = FileCategory.audio;
                      break;
                    case CategoryType.documents:
                      fileCategory = FileCategory.document;
                      break;
                    case CategoryType.downloads:
                      fileCategory = FileCategory.other;
                      break;
                  }

                  counts[fileCategory] = count;
                  totalFiles = totalFiles + count;

                  // 同时保存文件列表到分类页面缓存
                  try {
                    final key = 'category_cache_${categoryType.name}';
                    final cacheData = {
                      'timestamp': DateTime.now().millisecondsSinceEpoch,
                      'categoryType': categoryType.name,
                      'files': files
                          .map((file) => {
                                'name': file.name,
                                'path': file.path,
                                'size': file.size,
                                'modified':
                                    file.modified.millisecondsSinceEpoch,
                              })
                          .toList(),
                    };
                    await prefs.setString(key, json.encode(cacheData));
                    logger.i('Cached $count files for ${categoryType.name}');
                  } catch (e) {
                    logger
                        .e('Error caching files for ${categoryType.name}: $e');
                  }

                  logger.i(
                      'Category ${categoryType.toString().split('.').last}: $count files');

                  currentCategoryIndex++;
                } catch (e) {
                  logger.e('Error scanning category $categoryType: $e');
                  currentCategoryIndex++;
                }
              }

              counts[FileCategory.all] = totalFiles;
              logger
                  .i('Total files scanned across all categories: $totalFiles');

              return counts;
            },
          );
          logger.i(
              'Comprehensive scan completed: ${scanResult.quickAccessFoldersFound} folders, ${scanResult.totalFilesScanned} files');

          // 标记首次扫描已完成
          await FirstScanService().markScanCompleted();

          // 重要：不要立即关闭扫描状态
          // 让 FirstScanCardOverlay 组件的 onComplete 回调来关闭
          // 这样用户才能看到完成状态停留 2.5 秒，体验更友好
        } else {
          logger.i('First scan not needed, skipping...');
        }
      }

      // 加载初始目录
      await _loadInitialDirectory();

      logger.i('App initialization completed');
    } catch (e) {
      logger.e('Error during app initialization: $e');
      setState(() {
        _isScanning = false;
        _isFirstScan = false;
      });
      // 即使初始化失败，也要尝试加载目录
      await _loadInitialDirectory();
    }
  }

  /// 请求权限并重新初始化
  Future<void> _requestPermissionAndInit() async {
    logger.i('Requesting permission and re-initializing...');

    final permissionState = await _permissionService.requestPermission();
    setState(() {
      _permissionState = permissionState;
    });

    if (permissionState.isGranted) {
      // 权限授予成功，开始初始化
      await _initializeApp();
    } else if (permissionState.isPermanentlyDenied) {
      // 永久拒绝，引导用户去设置
      logger.w('Permission permanently denied');
    } else {
      // 拒绝，保持空状态
      logger.w('Permission denied');
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

  /// 预览文件
  ///
  /// 对于图片和视频文件，支持左右滑动浏览相邻文件
  /// 其他类型文件使用单文件预览模式
  void _previewFile(FileItem file) {
    logger.d('Previewing file: ${file.path}');

    // 判断是否是图片或视频文件
    final isImageOrVideo =
        FileUtils.isImageFile(file.name) || FileUtils.isVideoFile(file.name);

    // 如果是图片、视频或音频，传递文件列表以支持滑动切换
    if (isImageOrVideo || FileUtils.isAudioFile(file.name)) {
      // 根据当前文件类型只过滤同类型文件
      final mediaFiles = viewModel.files.where((f) {
        if (FileUtils.isImageFile(file.name)) {
          return FileUtils.isImageFile(f.name);
        } else if (FileUtils.isVideoFile(file.name)) {
          return FileUtils.isVideoFile(f.name);
        } else if (FileUtils.isAudioFile(file.name)) {
          return FileUtils.isAudioFile(f.name);
        }
        return false;
      }).toList();

      final initialIndex = mediaFiles.indexWhere((f) => f.path == file.path);

      Navigator.of(context)
          .push<bool>(
        MaterialPageRoute(
          builder: (context) => FilePreviewPage(
            file: file,
            fileList: mediaFiles,
            initialIndex: initialIndex >= 0 ? initialIndex : 0,
            viewModel: viewModel,
            presenter: presenter,
          ),
        ),
      )
          .then((refresh) async {
        if (refresh == true) {
          // 根据当前Tab刷新对应的数据
          if (viewModel.currentTab == TabView.favorite) {
            await presenter.loadFavoriteFiles();
          } else if (viewModel.currentTab == TabView.recent) {
            await presenter.loadRecentFiles();
          } else {
            await presenter.loadFiles(viewModel.currentPath);
          }
        }
      });
    } else {
      // 其他文件类型使用单文件模式
      Navigator.of(context)
          .push<bool>(
        MaterialPageRoute(
          builder: (context) => FilePreviewPage(
            file: file,
            viewModel: viewModel,
            presenter: presenter,
          ),
        ),
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
      case 'settings':
        _navigateToSettings();
        break;
      case 'manage_quick_access':
        _navigateToQuickAccessManagePage();
        break;
      case 'about':
        _navigateToAbout();
        break;
    }
  }

  /// 导航到关于页面
  void _navigateToAbout() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AboutPage(),
      ),
    );
  }

  /// 根据当前Tab获取对应的PageId
  PageId _getPageIdForCurrentTab(TabView tab) {
    switch (tab) {
      case TabView.recent:
        return PageId.homeRecent;
      case TabView.favorite:
        return PageId.homeFavorite;
      case TabView.browse:
        return PageId.homeBrowse;
    }
  }

  /// 获取当前页面是否为网格视图
  /// 获取当前页面是否启用分组
  bool _isGroupEnabledForCurrentTab() {
    final pageId = _getPageIdForCurrentTab(
        Provider.of<FileViewModel>(context, listen: false).currentTab);
    // Recent Tab固定分组
    if (pageId == PageId.homeRecent) return true;
    return PageSettingsService().getGroupEnabled(pageId);
  }

  /// 导航到设置页面
  void _navigateToSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SettingsPage(),
      ),
    );

    // 从设置页面返回后，刷新当前视图
    if (viewModel.currentTab == TabView.browse &&
        viewModel.currentPath.isNotEmpty) {
      await presenter.loadFiles(viewModel.currentPath);
    } else if (viewModel.currentTab == TabView.recent) {
      await presenter.loadRecentFiles();
    } else if (viewModel.currentTab == TabView.favorite) {
      await presenter.loadFavoriteFiles();
    }
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

  /// 构建响应式Tab栏 - 根据可用宽度动态调整布局
  Widget _buildResponsiveTabBar(
    BuildContext context,
    FileViewModel vm,
    double availableWidth,
  ) {
    final theme = Theme.of(context);

    // 固定预留宽度（根据实际测量）
    const recentTabWidth = 36.0; // "最近" Tab固定宽度
    const favoriteTabWidth = 36.0; // "收藏" Tab固定宽度（不考虑括号和数字）
    const dividerWidth = 5.0; // 分隔符宽度（单个）
    const toolbarWidth = 150.0; // 工具栏宽度
    const folderTabMinWidth = 10.0; // 文件夹Tab最小预留宽度
    const extraMargin = 10.0; // 其余空格

    // 计算文件夹名Tab可用的最大宽度
    // 公式: 可用总宽度 - 最近(36) - 分隔符(5) - 收藏(36) - 分隔符(5) - 工具栏(150) - 文件夹最小(10) - 空格(10)
    final fixedWidth = recentTabWidth +
        dividerWidth +
        favoriteTabWidth +
        dividerWidth +
        toolbarWidth +
        folderTabMinWidth +
        extraMargin;
    final maxBrowseTabWidth = availableWidth - fixedWidth;

    // 动态计算文件夹名的最大字符数
    int calculateMaxLength(double maxWidth) {
      // 每个字符大约占用8-10px（取决于字体），加上padding和图标
      const charWidth = 10.0;
      const iconWidth = 18.0; // folder_open图标
      const padding = 24.0; // 左右padding
      final availableForText = maxWidth - iconWidth - padding;
      final maxChars = (availableForText / charWidth).floor();
      return maxChars.clamp(8, 20); // 最少8个字符，最多20个字符
    }

    final dynamicMaxLength = calculateMaxLength(maxBrowseTabWidth);

    return Row(
      children: [
        // 左侧Tab区域 - 使用Expanded + SingleChildScrollView防止溢出
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                  // 使用ConstrainedBox限制文件夹名Tab的最大宽度
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxBrowseTabWidth.clamp(
                          80.0, 150.0), // 最小80px，最大150px
                    ),
                    child: _buildTabButton(
                      context,
                      _getBrowseTabLabelWithDynamicLength(vm, dynamicMaxLength),
                      TabView.browse,
                      vm.currentTab == TabView.browse,
                      onTap: null, // 文件浏览 Tab 不可点击，只能通过收藏夹激活
                      count: null, // 不显示数量，避免与下方标签栏重复
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // 右侧工具栏 - 仅在文件列表不为空时显示
        if (vm.files.isNotEmpty)
          FileToolbar(
            pageId: _getPageIdForCurrentTab(vm.currentTab),
            showBackButton: false, // 移除工具栏返回按钮，使用底部导航栏代替
            onBackPressed: () => presenter.navigateUp(),
            showSearchButton: vm.currentTab == TabView.browse ||
                vm.currentTab == TabView.favorite,
            onSearchPressed: () {
              if (vm.currentTab == TabView.browse) {
                presenter.toggleSearch();
              } else if (vm.currentTab == TabView.favorite) {
                setState(() {
                  _favoriteSearchMode = !_favoriteSearchMode;
                  if (!_favoriteSearchMode) {
                    _favoriteSearchQuery = '';
                    _favoriteSearchController.clear();
                  }
                });
              }
            },
            isSearchMode: vm.currentTab == TabView.browse
                ? vm.isSearchMode
                : _favoriteSearchMode,
            showSortButton: vm.currentTab == TabView.favorite ||
                vm.currentTab == TabView.browse,
            onSortPressed: vm.currentTab == TabView.favorite
                ? _showFavoriteSortOptions
                : _showBrowseSortOptions,
            showGroupButton: vm.currentTab == TabView.favorite ||
                vm.currentTab == TabView.browse,
            onGroupToggle: () => setState(() {}),
            iconSize: 18,
          ),
      ],
    );
  }

  /// 获取文件浏览Tab的标签文本（动态长度版本）
  String _getBrowseTabLabelWithDynamicLength(FileViewModel vm, int maxLength) {
    if (vm.currentTab == TabView.browse && vm.currentPath.isNotEmpty) {
      // 查找快速访问文件夹（包括子目录）
      if (quickAccessViewModel != null) {
        // 遍历所有快速访问文件夹，查找当前路径所属的根文件夹
        for (final folder in quickAccessViewModel!.folders) {
          // 检查当前路径是否等于或在该快速访问文件夹内
          if (vm.currentPath == folder.path ||
              vm.currentPath.startsWith(folder.path + Platform.pathSeparator)) {
            // 使用动态计算的maxLength
            final displayName = folder.displayName;
            final truncatedName = displayName.length > maxLength
                ? '${displayName.substring(0, maxLength - 3)}...'
                : displayName;
            return truncatedName;
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
        // 使用动态计算的maxLength
        final truncatedName = folderName.length > maxLength
            ? '${folderName.substring(0, maxLength - 3)}...'
            : folderName;
        return truncatedName;
      }
    }
    return '浏览';
  }

  /// 获取过滤和排序后的收藏文件列表
  List<FileItem> _getFilteredFavoriteFiles(List<FileItem> files) {
    var result = files;

    // 应用搜索过滤
    if (_favoriteSearchMode && _favoriteSearchQuery.isNotEmpty) {
      result = files.where((file) {
        return file.name
            .toLowerCase()
            .contains(_favoriteSearchQuery.toLowerCase());
      }).toList();
    }

    // 应用页面级排序
    final sortType = PageSettingsService().getSortType(PageId.homeFavorite);
    FileComparatorUtil.sortFilesInPlace(result, sortType);

    return result;
  }

  /// 获取排序后的浏览文件列表
  List<FileItem> _getSortedBrowseFiles(List<FileItem> files) {
    final sortType = PageSettingsService().getSortType(PageId.homeBrowse);
    return FileComparatorUtil.sortFiles(files, sortType);
  }

  /// 获取收藏文件的日期分组
  Map<String, List<FileItem>> _groupFavoriteFilesByDate(List<FileItem> files) {
    return FileGroupingUtil.groupByAddedDate(files, removeEmpty: false);
  }

  /// 获取浏览文件的日期分组
  Map<String, List<FileItem>> _groupBrowseFilesByDate(List<FileItem> files) {
    return FileGroupingUtil.groupByModifiedDate(files, removeEmpty: false);
  }

  /// 获取最近文件的时间分组（基于访问时间）
  Map<String, List<FileItem>> _groupRecentFilesByDate(List<FileItem> files) {
    return FileGroupingUtil.groupByAccessDate(files, removeEmpty: false);
  }

  /// 构建收藏Tab的分组视图
  Widget _buildFavoriteGroupedView(List<FileItem> files) {
    final isGridView =
        PageSettingsService().getViewMode(PageId.homeFavorite) == ViewMode.grid;
    final groups = _groupFavoriteFilesByDate(files);
    final groupKeys = ['今天', '昨天', '本周', '本月', '更早'];

    final fileGroups = groupKeys
        .where((key) => groups.containsKey(key) && groups[key]!.isNotEmpty)
        .map((key) {
      final count = groups[key]!.length;
      return FileGroup(
        key: key,
        title: '$key（$count个文件）',
        items: groups[key]!,
        isCollapsible: false,
      );
    }).toList();

    return FileCollectionView(
      groups: fileGroups,
      gridMode: isGridView,
      padding: isGridView
          ? const EdgeInsets.symmetric(vertical: 4)
          : const EdgeInsets.symmetric(vertical: 0),
      selectionController: _selectionController,
      showFullPath: false, // 收藏Tab不显示路径
      showFavoriteButton: true,
      isFavorite: (path) => viewModel.isFavoriteFile(path),
      onFavoriteToggle: (file) async {
        return await presenter.toggleFavoriteFile(file);
      },
      useUnifiedGridItem: true,
      onTap: (file) => _onFileTap(file, viewModel),
      // onLongPress 移除，由 FileCollectionView 内部处理
    );
  }

  /// 构建浏览Tab的分组视图
  Widget _buildBrowseGroupedView(List<FileItem> files) {
    final isGridView =
        PageSettingsService().getViewMode(PageId.homeBrowse) == ViewMode.grid;
    final groups = _groupBrowseFilesByDate(files);
    final groupKeys = ['今天', '昨天', '本周', '本月', '更早'];

    final fileGroups = groupKeys
        .where((key) => groups.containsKey(key) && groups[key]!.isNotEmpty)
        .map((key) {
      final count = groups[key]!.length;
      return FileGroup(
        key: key,
        title: '$key（$count个文件）',
        items: groups[key]!,
        isCollapsible: false,
      );
    }).toList();

    return FileCollectionView(
      groups: fileGroups,
      gridMode: isGridView,
      padding: isGridView
          ? const EdgeInsets.symmetric(vertical: 4)
          : const EdgeInsets.symmetric(vertical: 0),
      selectionController: _selectionController,
      showFullPath: false, // 搜索模式下不显示路径文本
      showFavoriteButton: true,
      isFavorite: (path) => viewModel.isFavoriteFile(path),
      onFavoriteToggle: (file) async {
        return await presenter.toggleFavoriteFile(file);
      },
      useUnifiedGridItem: true,
      onTap: (file) => _onFileTap(file, viewModel),
      // onLongPress 移除，由 FileCollectionView 内部处理
    );
  }

  /// 构建最近Tab的分组视图
  Widget _buildRecentGroupedView(List<FileItem> files) {
    final isGridView =
        PageSettingsService().getViewMode(PageId.homeRecent) == ViewMode.grid;
    final groups = _groupRecentFilesByDate(files);
    final groupKeys = ['今天', '昨天', '本周', '更早'];

    final fileGroups = groupKeys
        .where((key) => groups.containsKey(key) && groups[key]!.isNotEmpty)
        .map((key) {
      final count = groups[key]!.length;
      return FileGroup(
        key: key,
        title: '$key（$count个文件）',
        items: groups[key]!,
        isCollapsible: false,
      );
    }).toList();

    return FileCollectionView(
      groups: fileGroups,
      gridMode: isGridView,
      padding: isGridView
          ? const EdgeInsets.symmetric(vertical: 4)
          : const EdgeInsets.symmetric(vertical: 0),
      selectionController: _selectionController,
      showFullPath: false,
      showAccessTime: true,
      getAccessTime: (file) => file.accessedAt,
      showFavoriteButton: true,
      isFavorite: (path) => viewModel.isFavoriteFile(path),
      onFavoriteToggle: (file) async {
        return await presenter.toggleFavoriteFile(file);
      },
      useUnifiedGridItem: true,
      onTap: (file) => _onFileTap(file, viewModel),
      // onLongPress 移除，由 FileCollectionView 内部处理
    );
  }

  /// 显示排序选项（收藏Tab）
  void _showFavoriteSortOptions() {
    final currentSortType =
        PageSettingsService().getSortType(PageId.homeFavorite);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('按名称排序'),
                trailing: currentSortType == SortType.name
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  PageSettingsService()
                      .setSortType(PageId.homeFavorite, SortType.name);
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('按修改时间排序'),
                trailing: currentSortType == SortType.modifiedTime
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  PageSettingsService()
                      .setSortType(PageId.homeFavorite, SortType.modifiedTime);
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('按文件大小排序'),
                trailing: currentSortType == SortType.size
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  PageSettingsService()
                      .setSortType(PageId.homeFavorite, SortType.size);
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.category),
                title: const Text('按文件类型排序'),
                trailing: currentSortType == SortType.fileType
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  PageSettingsService()
                      .setSortType(PageId.homeFavorite, SortType.fileType);
                  setState(() {}); // 刷新列表
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示排序选项（浏览Tab）
  void _showBrowseSortOptions() {
    final currentSortType =
        PageSettingsService().getSortType(PageId.homeBrowse);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('按名称排序'),
                trailing: currentSortType == SortType.name
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  PageSettingsService()
                      .setSortType(PageId.homeBrowse, SortType.name);
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('按修改时间排序'),
                trailing: currentSortType == SortType.modifiedTime
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  PageSettingsService()
                      .setSortType(PageId.homeBrowse, SortType.modifiedTime);
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('按文件大小排序'),
                trailing: currentSortType == SortType.size
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  PageSettingsService()
                      .setSortType(PageId.homeBrowse, SortType.size);
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.category),
                title: const Text('按文件类型排序'),
                trailing: currentSortType == SortType.fileType
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  PageSettingsService()
                      .setSortType(PageId.homeBrowse, SortType.fileType);
                  setState(() {}); // 刷新列表
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建空状态UI
  Widget _buildEmptyState(TabView tab, bool isSearchMode, FileViewModel vm) {
    logger.d('_buildEmptyState - tab: $tab, isSearchMode: $isSearchMode, errorMessage: ${vm.errorMessage}');
    
    IconData icon;
    String title;
    Widget subtitleWidget;
    Widget? actionButton;

    switch (tab) {
      case TabView.recent:
        icon = Icons.history;
        title = '暂无最近访问的文件';
        subtitleWidget = Text(
          '浏览或打开文件后，这里会显示您最近访问的内容',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
                height: 1.5,
              ),
          textAlign: TextAlign.center,
        );
        actionButton = TextButton.icon(
          onPressed: () async {
            // 跳转到浏览Tab并选择首页推荐区显示的第一个文件夹
            viewModel.setCurrentTab(TabView.browse);
            if (quickAccessViewModel != null &&
                quickAccessViewModel!.folders.isNotEmpty) {
              // 获取首页推荐区实际显示的文件夹（与QuickAccessSection逻辑一致）
              final folders = quickAccessViewModel!.folders;
              final userCustomizedHomeFolders = folders
                  .where((f) => f.homeDisplayOrder != null)
                  .toList()
                ..sort((a, b) => (a.homeDisplayOrder ?? 999)
                    .compareTo(b.homeDisplayOrder ?? 999));

              QuickAccessFolder? firstFolder;
              if (userCustomizedHomeFolders.isNotEmpty) {
                // 用户已定制过首页，使用用户定制的第一个
                firstFolder = userCustomizedHomeFolders.first;
              } else {
                // 用户未定制，从系统目录中按优先级选择第一个
                final systemFolders = folders
                    .where((f) => f.type == QuickAccessFolderType.system)
                    .toList();
                if (systemFolders.isNotEmpty) {
                  systemFolders.sort((a, b) {
                    int getPriority(QuickAccessFolder folder) {
                      final path = folder.path.toLowerCase();
                      if (path.contains('download')) return 99;
                      if (path.contains('document')) return 1;
                      if (path.contains('picture') || path.contains('photo')) {
                        return 2;
                      }
                      if (path.contains('music')) return 3;
                      if (path.contains('movie') || path.contains('video')) {
                        return 4;
                      }
                      if (path.contains('dcim') || path.contains('camera')) {
                        return 5;
                      }
                      return 98;
                    }

                    return getPriority(a).compareTo(getPriority(b));
                  });
                  firstFolder = systemFolders
                      .where((f) => !f.path.toLowerCase().contains('download'))
                      .firstOrNull;
                }
              }

              if (firstFolder != null) {
                await presenter.navigateToFolder(firstFolder.path);
              }
            }
          },
          icon: const Icon(Icons.arrow_forward),
          label: const Text('开始浏览'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        break;

      case TabView.favorite:
        if (isSearchMode) {
          icon = Icons.search_off;
          title = '未找到匹配的收藏文件';
          subtitleWidget = Text(
            '尝试使用不同的搜索关键词',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          );
          actionButton = null;
        } else {
          icon = Icons.star_border;
          title = '暂无收藏的文件';
          subtitleWidget = RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
              children: [
                const TextSpan(text: '长按文件进入编辑模式，在底部操作栏点击 '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(
                    Icons.star_border,
                    size: 18,
                    color: Colors.grey[600],
                  ),
                ),
                const TextSpan(text: ' 图标即可收藏文件，方便快速访问'),
              ],
            ),
          );
          actionButton = TextButton.icon(
            onPressed: () async {
              // 跳转到浏览Tab并选择首页推荐区显示的第一个文件夹
              viewModel.setCurrentTab(TabView.browse);
              if (quickAccessViewModel != null &&
                  quickAccessViewModel!.folders.isNotEmpty) {
                // 获取首页推荐区实际显示的文件夹（与QuickAccessSection逻辑一致）
                final folders = quickAccessViewModel!.folders;
                final userCustomizedHomeFolders = folders
                    .where((f) => f.homeDisplayOrder != null)
                    .toList()
                  ..sort((a, b) => (a.homeDisplayOrder ?? 999)
                      .compareTo(b.homeDisplayOrder ?? 999));

                QuickAccessFolder? firstFolder;
                if (userCustomizedHomeFolders.isNotEmpty) {
                  // 用户已定制过首页，使用用户定制的第一个
                  firstFolder = userCustomizedHomeFolders.first;
                } else {
                  // 用户未定制，从系统目录中按优先级选择第一个
                  final systemFolders = folders
                      .where((f) => f.type == QuickAccessFolderType.system)
                      .toList();
                  if (systemFolders.isNotEmpty) {
                    systemFolders.sort((a, b) {
                      int getPriority(QuickAccessFolder folder) {
                        final path = folder.path.toLowerCase();
                        if (path.contains('download')) return 99;
                        if (path.contains('document')) return 1;
                        if (path.contains('picture') ||
                            path.contains('photo')) {
                          return 2;
                        }
                        if (path.contains('music')) return 3;
                        if (path.contains('movie') || path.contains('video')) {
                          return 4;
                        }
                        if (path.contains('dcim') || path.contains('camera')) {
                          return 5;
                        }
                        return 98;
                      }

                      return getPriority(a).compareTo(getPriority(b));
                    });
                    firstFolder = systemFolders
                        .where(
                            (f) => !f.path.toLowerCase().contains('download'))
                        .firstOrNull;
                  }
                }

                if (firstFolder != null) {
                  await presenter.navigateToFolder(firstFolder.path);
                }
              }
            },
            icon: const Icon(Icons.arrow_forward),
            label: const Text('去浏览文件'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
        break;

      case TabView.browse:
        if (isSearchMode) {
          icon = Icons.search_off;
          title = '未找到匹配的文件';
          subtitleWidget = Text(
            '尝试使用不同的搜索关键词或筛选条件',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          );
          actionButton = null;
        } else if (vm.errorMessage != null) {
          // 显示错误消息（如系统保护的目录）
          icon = Icons.lock_outline;
          title = '无法访问此目录';
          subtitleWidget = Column(
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[200]!, width: 2),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 48,
                      color: Colors.orange[700],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      vm.errorMessage!,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.orange[900],
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Android 11+ 系统限制了对某些系统目录的直接访问',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[800],
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          );
          actionButton = TextButton.icon(
            onPressed: () => presenter.navigateUp(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('返回上级'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        } else {
          icon = Icons.folder_open;
          title = '此文件夹为空';
          subtitleWidget = Text(
            '下拉刷新',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          );
          actionButton = null;
        }
        break;
    }

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
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  subtitleWidget,
                  if (actionButton != null) ...[
                    const SizedBox(height: 24),
                    actionButton,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建文件列表视图
  Widget _buildFileList(FileViewModel vm) {
    logger.d('_buildFileList - files.isEmpty: ${vm.files.isEmpty}, errorMessage: ${vm.errorMessage}, currentPath: ${vm.currentPath}');
    
    if (vm.files.isEmpty) {
      // 使用新的空状态UI
      final isSearchMode =
          (vm.currentTab == TabView.browse && vm.isSearchMode) ||
              (vm.currentTab == TabView.favorite && _favoriteSearchMode);
      return _buildEmptyState(vm.currentTab, isSearchMode, vm);
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
    final pageId = _getPageIdForCurrentTab(vm.currentTab);
    final isGridView =
        PageSettingsService().getViewMode(pageId) == ViewMode.grid;
    final isGroupEnabled = _isGroupEnabledForCurrentTab();

    // 收藏Tab和浏览Tab需要应用排序
    var displayFiles = vm.files;

    if (vm.currentTab == TabView.favorite) {
      // 收藏Tab：应用过滤和排序
      displayFiles = _getFilteredFavoriteFiles(vm.files);
    } else if (vm.currentTab == TabView.browse) {
      // 浏览Tab：应用排序
      displayFiles = _getSortedBrowseFiles(vm.files);
    }

    // 最近Tab始终使用时间分组显示
    if (vm.currentTab == TabView.recent) {
      return _buildRecentGroupedView(displayFiles);
    }

    // 收藏Tab、浏览Tab启用分组时使用分组视图
    if (isGroupEnabled) {
      if (vm.currentTab == TabView.favorite) {
        return _buildFavoriteGroupedView(displayFiles);
      } else if (vm.currentTab == TabView.browse) {
        return _buildBrowseGroupedView(displayFiles);
      }
    }

    return FileCollectionView(
      items: displayFiles,
      gridMode: isGridView,
      padding: isGridView
          ? const EdgeInsets.all(8)
          : const EdgeInsets.symmetric(vertical: 0),
      selectionController: _selectionController,
      // 列表模式显示选项
      showFullPath: false, // 搜索模式下不显示路径文本
      showAccessTime: vm.currentTab == TabView.recent,
      getAccessTime: (file) => file.accessedAt,
      showFavoriteButton: true,
      isFavorite: (path) => vm.isFavoriteFile(path),
      onFavoriteToggle: (file) async {
        return await presenter.toggleFavoriteFile(file);
      },
      useUnifiedGridItem: true,
      onTap: (file) => _onFileTap(file, vm),
      // onLongPress 移除，由 FileCollectionView 内部处理
    );
  }

  /// 处理文件点击
  void _onFileTap(FileItem file, FileViewModel vm) {
    // 多选模式下的点击由FileCollectionView处理，这里只处理导航
    if (_selectionController.isSelectionMode) {
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
      child:
          Consumer3<FileViewModel, QuickAccessViewModel, PageSettingsService>(
        builder: (context, vm, quickVm, pageSettingsService, _) {
          if (vm.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return WillPopScope(
            onWillPop: () async {
              // 优先级1: 退出批量选择模式
              if (_selectionController.isSelectionMode) {
                setState(() {
                  _selectionController.clear();
                });
                return false;
              }

              // 优先级2: 退出搜索模式
              if (vm.currentTab == TabView.browse && vm.isSearchMode) {
                _searchController.clear();
                presenter.clearSearch();
                return false;
              }
              if (vm.currentTab == TabView.favorite && _favoriteSearchMode) {
                setState(() {
                  _favoriteSearchQuery = '';
                  _favoriteSearchController.clear();
                  _favoriteSearchMode = false;
                });
                return false;
              }

              // 优先级3: 子文件夹返回上级
              if (vm.currentTab == TabView.browse &&
                  vm.currentPath.isNotEmpty &&
                  _canNavigateUp(vm.currentPath)) {
                presenter.navigateUp();
                return false;
              }

              // 优先级4: 浏览Tab根目录切换到最近Tab
              if (vm.currentTab == TabView.browse) {
                vm.setCurrentTab(TabView.recent);
                await presenter.loadRecentFiles();
                return false;
              }

              // 优先级5: 其他情况允许系统默认行为
              return true;
            },
            child: Scaffold(
              appBar: AppBar(
                leading: _selectionController.isSelectionMode
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _selectionController.clear();
                          });
                        },
                      )
                    : null,
                title: _selectionController.isSelectionMode
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
                actions: _selectionController.isSelectionMode
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

                  return Stack(
                    children: [
                      Column(
                        children: [
                          // 上半部分固定区域 - 在搜索模式下隐藏，避免溢出
                          if (!(vm.currentTab == TabView.browse &&
                                  vm.isSearchMode) &&
                              !(vm.currentTab == TabView.favorite &&
                                  _favoriteSearchMode))
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    constraints.maxWidth > constraints.maxHeight
                                        ? constraints.maxHeight * 0.35 // 横屏：35%
                                        : constraints.maxHeight * 0.5, // 竖屏：50%
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
                                        if (mounted &&
                                            _categoryCardSize != size) {
                                          setState(() {
                                            _categoryCardSize = size;
                                          });
                                        }
                                      },
                                    ),
                                    const Divider(height: 1),

                                    // 快速访问区域（新）
                                    QuickAccessSection(
                                      quickAccessViewModel:
                                          quickAccessViewModel!,
                                      quickAccessPresenter:
                                          quickAccessPresenter!,
                                      fileViewModel: vm,
                                      filePresenter: presenter,
                                      categoryCardSize: _categoryCardSize,
                                    ),
                                    const Divider(height: 1),
                                  ],
                                ),
                              ),
                            ),

                          // Tab 切换栏和工具按钮 - 在搜索模式下隐藏
                          if (!(vm.currentTab == TabView.browse &&
                                  vm.isSearchMode) &&
                              !(vm.currentTab == TabView.favorite &&
                                  _favoriteSearchMode))
                            Container(
                              height: 32, // 固定高度
                              color: colorScheme.surface,
                              padding: const EdgeInsets.only(right: 4),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return _buildResponsiveTabBar(
                                    context,
                                    vm,
                                    constraints.maxWidth,
                                  );
                                },
                              ),
                            ),

                          // 浏览Tab的搜索栏
                          if (vm.currentTab == TabView.browse &&
                              vm.isSearchMode)
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

                          // 收藏Tab的搜索栏
                          if (vm.currentTab == TabView.favorite &&
                              _favoriteSearchMode)
                            FileSearchBar(
                              controller: _favoriteSearchController,
                              focusNode: _favoriteSearchFocusNode,
                              hintText: '搜索收藏的文件...',
                              onSearch: (query) async {
                                setState(() {
                                  _favoriteSearchQuery = query;
                                });
                              },
                              onClose: () {
                                setState(() {
                                  _favoriteSearchQuery = '';
                                  _favoriteSearchController.clear();
                                  _favoriteSearchMode = false;
                                });
                              },
                              onChanged: (query) {
                                setState(() {
                                  _favoriteSearchQuery = query;
                                });
                              },
                            ),

                          // 文件类型筛选Tab栏（仅在浏览模式显示）
                          if (vm.currentTab == TabView.browse &&
                              !vm.isSearchMode)
                            FileCategoryTabBar(
                              stats: vm.fileTypeStats,
                              selectedCategory: vm.selectedCategory,
                              onCategoryChanged: (category) {
                                vm.setSelectedCategory(category);
                              },
                            ),

                          // 文件列表区域（占据剩余空间）
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    // 手势功能说明：
                                    // 1. 浏览Tab - 左右滑切换分类Tab（全部|文档|图片|视频等）
                                    // 2. 最近/收藏Tab - 左右滑切换Tab
                                    onHorizontalDragEnd: (details) {
                                      if (details.primaryVelocity == null) {
                                        return;
                                      }

                                      final velocity = details.primaryVelocity!;
                                      final isSwipeRight = velocity > 500; // 右滑
                                      final isSwipeLeft = velocity < -500; // 左滑

                                      // 搜索模式下禁用所有手势
                                      if (vm.isSearchMode ||
                                          _favoriteSearchMode) {
                                        return;
                                      }

                                      // 功能1: 浏览Tab - 左右滑切换分类Tab
                                      if (vm.currentTab == TabView.browse) {
                                        final visibleCategories = [
                                          FileCategory.all,
                                          ...vm.fileTypeStats
                                              .getVisibleCategories(),
                                        ];
                                        if (visibleCategories.length > 1) {
                                          final currentIndex = visibleCategories
                                              .indexOf(vm.selectedCategory);
                                          if (currentIndex != -1) {
                                            if (isSwipeLeft &&
                                                currentIndex <
                                                    visibleCategories.length -
                                                        1) {
                                              // 左滑切换到下一个分类
                                              vm.setSelectedCategory(
                                                  visibleCategories[
                                                      currentIndex + 1]);
                                              return;
                                            } else if (isSwipeRight &&
                                                currentIndex > 0) {
                                              // 右滑切换到上一个分类
                                              vm.setSelectedCategory(
                                                  visibleCategories[
                                                      currentIndex - 1]);
                                              return;
                                            }
                                          }
                                        }
                                      }

                                      // 功能2: 在最近/收藏Tab之间左右滑动切换
                                      if (vm.currentTab == TabView.recent &&
                                          isSwipeLeft) {
                                        // 最近Tab左滑 → 切换到收藏Tab
                                        viewModel
                                            .setCurrentTab(TabView.favorite);
                                        presenter.loadFavoriteFiles();
                                      } else if (vm.currentTab ==
                                              TabView.favorite &&
                                          isSwipeRight) {
                                        // 收藏Tab右滑 → 切换到最近Tab
                                        viewModel.setCurrentTab(TabView.recent);
                                        presenter.loadRecentFiles();
                                      }
                                    },
                                    child: _buildFileList(vm),
                                  ),
                                ),

                                // 底部文件夹导航栏（子文件夹中显示）
                                if (vm.currentTab == TabView.browse &&
                                    !_selectionController.isSelectionMode &&
                                    !vm.isSearchMode &&
                                    vm.currentPath.isNotEmpty &&
                                    _canNavigateUp(vm.currentPath))
                                  FolderNavigationBar(
                                    currentPath: vm.currentPath,
                                    onBackPressed: () => presenter.navigateUp(),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // 权限提示横幅（在顶部显示）
                      if (_permissionState == PermissionState.denied ||
                          _permissionState == PermissionState.permanentlyDenied)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: PermissionBanner(
                            onTap: () async {
                              if (_permissionState ==
                                  PermissionState.permanentlyDenied) {
                                await _permissionService.openAppSettings();
                              } else {
                                await _requestPermissionAndInit();
                              }
                            },
                          ),
                        ),

                      // 首次扫描卡片覆盖层
                      if (_isFirstScan)
                        FirstScanCardOverlay(
                          isScanning: _isScanning,
                          progress: _scanProgress,
                          onComplete: () {
                            if (mounted) {
                              setState(() {
                                _isScanning = false;
                                _isFirstScan = false;
                              });
                            }
                          },
                        ),
                    ],
                  );
                },
              ),
              // 批量操作底部工具栏
              bottomNavigationBar: _selectionController.isSelectionMode
                  ? _buildSelectionBottomBar()
                  : null,
            ),
          );
        },
      ),
    );
  }

  /// 构建批量选择底部工具栏
  Widget _buildSelectionBottomBar() {
    final batchService = _getBatchOperationsService();
    return SelectionBottomBar(
      selectedPaths: _selectedItems,
      isAllFavorite: batchService.isAllSelectedFavorite(_selectedItems),
      onCopy: () =>
          batchService.batchCopy(_selectedItems, viewModel.currentPath),
      onRename: () => batchService.batchRename(_selectedItems),
      onShare: () => batchService.batchShare(_selectedItems),
      onMove: () =>
          batchService.batchMove(_selectedItems, viewModel.currentPath),
      onToggleFavorite: () => batchService.batchToggleFavorite(_selectedItems),
      onDelete: () => batchService.batchDelete(_selectedItems),
    );
  }

  /// 获取批量操作服务实例
  BatchOperationsService _getBatchOperationsService() {
    return BatchOperationsService(
      context: context,
      viewModel: viewModel,
      presenter: presenter,
      onRefresh: () async {
        if (viewModel.currentTab == TabView.browse) {
          await presenter.loadFiles(viewModel.currentPath);
        } else if (viewModel.currentTab == TabView.favorite) {
          await presenter.loadFavoriteFiles();
        }
      },
      onExitSelectionMode: () {
        setState(() {
          _selectionController.clear();
        });
      },
    );
  }
}
