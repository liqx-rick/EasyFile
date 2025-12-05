import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:path/path.dart' as path;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/utils/file_size_formatter.dart';

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
import 'package:easyfile/ui/pages/app_management_page.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/category_nav_bar.dart';
import 'package:easyfile/ui/widgets/quick_access_section.dart';
import 'package:easyfile/ui/widgets/new_folder_notification.dart';
import 'package:easyfile/ui/widgets/file_category_tab_bar.dart';
import 'package:easyfile/ui/widgets/pinned_header_delegate.dart';
import 'package:easyfile/ui/widgets/file_toolbar.dart';
import 'package:easyfile/ui/widgets/file_search_bar.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/ui/widgets/unified_grid_item.dart';
import 'package:easyfile/ui/widgets/unified_view_config.dart';
import 'package:easyfile/ui/widgets/file_item_tile.dart';
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

  // 编辑模式状态
  bool _isEditMode = false;
  
  // 编辑模式提示状态
  bool _showEditModeHint = false;

  // 批量操作相关（SelectionController 内部管理 isSelectionMode 状态）
  Set<String> _selectedItems = {}; // 存储选中的文件/文件夹路径
  late final SelectionController _selectionController;

  // 搜索相关状态
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // 快捷访问按钮的GlobalKey，用于定位菜单弹出位置
  final GlobalKey _quickAccessButtonKey = GlobalKey();

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

  /// 进入编辑模式
  void _enterEditMode() {
    setState(() {
      _isEditMode = true;
      // 不自动进入选择模式，只有点击文件时才进入
      
      // 显示编辑模式提示
      _showEditModeHint = true;
    });

    // 5秒后自动隐藏提示
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _showEditModeHint) {
        setState(() {
          _showEditModeHint = false;
        });
      }
    });
  }

  /// 退出编辑模式
  void _exitEditMode() {
    if (!mounted) return;
    setState(() {
      _isEditMode = false;
      _selectionController.clear();
    });
  }

  /// 显示新建文件夹对话框
  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '文件夹名称',
            hintText: '请输入文件夹名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
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
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _createFolder(result);
    }
  }

  /// 创建文件夹
  Future<void> _createFolder(String name) async {
    try {
      // 验证文件夹名称
      if (name.contains('/') || name.contains('\\')) {
        _showMessage('文件夹名称不能包含 / 或 \\');
        return;
      }

      final currentPath = viewModel.currentPath;
      if (currentPath.isEmpty) {
        _showMessage('无法在当前位置创建文件夹');
        return;
      }

      final newPath = path.join(currentPath, name);
      final dir = Directory(newPath);

      if (await dir.exists()) {
        _showMessage('文件夹已存在');
        return;
      }

      await dir.create(recursive: true);
      _showMessage('创建成功');

      // 刷新文件列表
      await presenter.refreshCurrent();
    } catch (e) {
      logger.e('Failed to create folder: $e');
      _showMessage('创建失败: $e');
    }
  }

  /// 显示提示消息
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
      case TabView.appManagement:
        return PageId.homeBrowse; // 占位，实际上不会被调用
    }
  }

  /// 获取当前页面是否为网格视图
  /// 获取当前页面是否启用分组
  bool _isGroupEnabledForCurrentTab() {
    final pageId = _getPageIdForCurrentTab(
        Provider.of<FileViewModel>(context, listen: false).currentTab);
    // 最近Tab不分组，始终按时间排序
    if (pageId == PageId.homeRecent) return false;
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

  /// 检查是否有快捷访问项（包括文件夹和已恢复文件）
  bool _hasQuickAccessItems() {
    // 检查是否有快捷访问文件夹
    if (quickAccessViewModel != null &&
        quickAccessViewModel!.folders.any((f) => f.isAddedToQuickAccess)) {
      return true;
    }

    // 检查是否有已恢复文件
    return _hasRestoredFiles();
  }

  /// 检查是否有已恢复文件
  bool _hasRestoredFiles() {
    const restoredPath = '/storage/emulated/0/EasyFile/Restored';
    final restoredDir = Directory(restoredPath);

    if (!restoredDir.existsSync()) return false;

    try {
      final files = restoredDir.listSync();
      return files.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// 显示快捷访问菜单
  void _showQuickAccessMenu(BuildContext context) async {
    if (quickAccessViewModel == null) return;

    // 获取快捷访问按钮的位置
    final RenderBox? buttonBox =
        _quickAccessButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (buttonBox == null) return;

    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset buttonPosition = buttonBox.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );
    final Size buttonSize = buttonBox.size;

    // 计算菜单位置：显示在tab栏下方的内容区域（红框位置）
    const menuWidth = 250.0;

    // 计算菜单左边缘位置：从"快捷访问"按钮左边缘开始
    final left = buttonPosition.dx;

    // 计算菜单顶部位置：tab栏下方（按钮底部 + 小间距）
    final top = buttonPosition.dy + buttonSize.height + 4.0;

    // 计算right和bottom（从屏幕边缘算起的距离）
    final right = overlay.size.width - left - menuWidth;
    final bottom = overlay.size.height - top;

    showMenu<QuickAccessFolder>(
      context: context,
      position: RelativeRect.fromLTRB(
        left,
        top,
        right,
        bottom,
      ),
      items: _buildQuickAccessMenuItems(),
    ).then((selectedFolder) {
      if (selectedFolder != null && mounted) {
        _onQuickAccessItemTap(selectedFolder);
      }
    });
  }

  /// 构建快捷访问菜单项
  List<PopupMenuEntry<QuickAccessFolder>> _buildQuickAccessMenuItems() {
    if (quickAccessViewModel == null) return [];

    final allFolders = quickAccessViewModel!.folders;
    final items = <PopupMenuEntry<QuickAccessFolder>>[];

    // 获取所有已添加到快捷访问的文件夹
    final otherFolders =
        allFolders.where((f) => f.isAddedToQuickAccess).toList();

    // 按类型分组
    final systemFolders = otherFolders
        .where((f) => f.type == QuickAccessFolderType.system)
        .toList();
    final appFolders = otherFolders
        .where((f) =>
            f.type == QuickAccessFolderType.appRoot ||
            f.type == QuickAccessFolderType.appSubfolder)
        .toList();
    final userFolders = otherFolders
        .where((f) => f.type == QuickAccessFolderType.userCustom)
        .toList();

    // 系统文件夹（移除标题，直接显示）
    for (var folder in systemFolders) {
      items.add(_buildFolderMenuItem(folder, Colors.blue));
    }

    // 添加分隔线（如果有应用文件夹或自定义文件夹）
    if (systemFolders.isNotEmpty &&
        (appFolders.isNotEmpty || userFolders.isNotEmpty)) {
      items.add(const PopupMenuDivider());
    }

    // 应用文件夹（移除标题，直接显示）
    for (var folder in appFolders) {
      items.add(_buildFolderMenuItem(folder, Colors.orange));
    }

    // 添加分隔线（如果有自定义文件夹）
    if (appFolders.isNotEmpty && userFolders.isNotEmpty) {
      items.add(const PopupMenuDivider());
    }

    // 自定义文件夹（移除标题，直接显示）
    for (var folder in userFolders) {
      items.add(_buildFolderMenuItem(folder, Colors.green));
    }

    // 已恢复文件（固定入口，移除分组标题）
    if (_hasRestoredFiles()) {
      if (items.isNotEmpty) {
        items.add(const PopupMenuDivider());
      }

      const restoredPath = '/storage/emulated/0/EasyFile/Restored';
      final restoredDir = Directory(restoredPath);
      final fileCount = restoredDir.listSync().length;

      // 直接添加已恢复文件夹作为可点击项（移除分组标题）
      items.add(
        PopupMenuItem<QuickAccessFolder>(
          value: QuickAccessFolder(
            id: 'restored_files',
            originalName: '回收站恢复',
            path: restoredPath,
            type: QuickAccessFolderType.userCustom,
            createdAt: DateTime.now(),
            isAddedToQuickAccess: true,
            pinned: false,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.folder_special,
                size: 18,
                color: Colors.purple,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '回收站恢复 ($fileCount)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return items;
  }

  /// 构建文件夹菜单项
  PopupMenuItem<QuickAccessFolder> _buildFolderMenuItem(
    QuickAccessFolder folder,
    Color color,
  ) {
    final exists = Directory(folder.path).existsSync();
    final folderIcon = _getFolderIcon(folder);

    return PopupMenuItem<QuickAccessFolder>(
      value: folder,
      enabled: exists,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            folderIcon,
            size: 18,
            color: exists ? color : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              folder.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: exists ? null : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 获取文件夹图标
  IconData _getFolderIcon(QuickAccessFolder folder) {
    switch (folder.type) {
      case QuickAccessFolderType.system:
        final path = folder.path.toLowerCase();
        if (path.contains('dcim') || path.contains('camera')) {
          return Icons.camera_alt;
        }
        if (path.contains('download')) return Icons.download;
        if (path.contains('picture') || path.contains('photo')) {
          return Icons.photo;
        }
        if (path.contains('document')) return Icons.description;
        if (path.contains('music')) return Icons.music_note;
        if (path.contains('movie') || path.contains('video')) {
          return Icons.video_library;
        }
        return Icons.folder_special;
      case QuickAccessFolderType.appRoot:
      case QuickAccessFolderType.appSubfolder:
        return Icons.apps;
      case QuickAccessFolderType.userCustom:
        return Icons.folder;
    }
  }

  /// 处理快捷访问项点击
  void _onQuickAccessItemTap(QuickAccessFolder folder) {
    // 导航到文件夹并切换到浏览Tab
    if (quickAccessPresenter != null) {
      quickAccessPresenter!.updateAccessInfo(folder.path);
    }
    presenter.loadFiles(folder.path, isRootNavigation: true);
    viewModel.setCurrentTab(TabView.browse);
  }

  /// 构建快捷访问栏（导航功能栏）- 第一行
  Widget _buildQuickAccessBar(
    BuildContext context,
    FileViewModel vm,
  ) {
    final theme = Theme.of(context);

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest, // 功能栏背景
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 快捷访问 Tab
          _buildNavTab(
            context,
            '快捷访问',
            Icons.folder_special,
            false, // 快捷访问不是传统意义的Tab，总是显示为未选中
            onTap: () => _showQuickAccessMenu(context),
            enabled: _hasQuickAccessItems(),
          ),
          Container(
            width: 1,
            height: 16,
            color: theme.dividerColor,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          // 最近 Tab
          _buildNavTab(
            context,
            '最近',
            Icons.access_time,
            vm.currentTab == TabView.recent,
            onTap: () {
              viewModel.setCurrentTab(TabView.recent);
              presenter.loadRecentFiles();
            },
          ),
          Container(
            width: 1,
            height: 16,
            color: theme.dividerColor,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          // 收藏 Tab
          _buildNavTab(
            context,
            '收藏',
            Icons.star,
            vm.currentTab == TabView.favorite,
            onTap: () {
              viewModel.setCurrentTab(TabView.favorite);
              presenter.loadFavoriteFiles();
            },
          ),
          Container(
            width: 1,
            height: 16,
            color: theme.dividerColor,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          // 应用管理入口（不是真正的Tab，点击跳转到独立页面）
          _buildNavTab(
            context,
            '应用',
            Icons.apps,
            false, // 始终不选中状态，因为它是独立页面
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const AppManagementPage(
                    isFromStorageManagement: false,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 构建导航Tab（用于快捷访问栏）
  Widget _buildNavTab(
    BuildContext context,
    String label,
    IconData icon,
    bool isSelected, {
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      key: label == '快捷访问' ? _quickAccessButtonKey : null,
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primaryContainer.withOpacity(0.8)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != '快捷访问') ...[
                Icon(
                  icon,
                  size: 15,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w500 : FontWeight.normal,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (label == '快捷访问' && enabled)
                Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建横屏专用快捷访问栏（圆角大卡片样式）
  Widget _buildQuickAccessBarLandscape(
    BuildContext context,
    FileViewModel vm,
  ) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
        height: 66, // 原来44的1.5倍
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            // 快捷访问 Tab - 占34份宽度
            Expanded(
              flex: 34,
              child: _buildNavTab(
                context,
                '快捷访问',
                Icons.folder_special,
                false,
                onTap: () => _showQuickAccessMenu(context),
                enabled: _hasQuickAccessItems(),
              ),
            ),
            Container(
              width: 1,
              height: 24,
              color: theme.dividerColor,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            // 最近 Tab - 占22份宽度
            Expanded(
              flex: 22,
              child: _buildNavTab(
                context,
                '最近',
                Icons.access_time,
                vm.currentTab == TabView.recent,
                onTap: () {
                  viewModel.setCurrentTab(TabView.recent);
                  presenter.loadRecentFiles();
                },
              ),
            ),
            Container(
              width: 1,
              height: 24,
              color: theme.dividerColor,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            // 收藏 Tab - 占22份宽度
            Expanded(
              flex: 22,
              child: _buildNavTab(
                context,
                '收藏',
                Icons.star,
                vm.currentTab == TabView.favorite,
                onTap: () {
                  viewModel.setCurrentTab(TabView.favorite);
                  presenter.loadFavoriteFiles();
                },
              ),
            ),
            Container(
              width: 1,
              height: 24,
              color: theme.dividerColor,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            // 应用管理入口 - 占22份宽度
            Expanded(
              flex: 22,
              child: _buildNavTab(
                context,
                '应用',
                Icons.apps,
                false,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AppManagementPage(
                        isFromStorageManagement: false,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建浏览控制栏（文件夹名+工具栏）- 第二行，仅browse模式显示
  Widget _buildBrowseControlBar(
    BuildContext context,
    FileViewModel vm,
    double availableWidth,
  ) {
    final theme = Theme.of(context);

    // 计算文件夹名的最大宽度
    const toolbarWidth = 150.0;
    const extraMargin = 20.0;
    final maxFolderNameWidth = availableWidth - toolbarWidth - extraMargin;

    // 动态计算文件夹名的最大字符数
    int calculateMaxLength(double maxWidth) {
      const charWidth = 10.0;
      const padding = 24.0;
      final availableForText = maxWidth - padding;
      final maxChars = (availableForText / charWidth).floor();
      return maxChars.clamp(8, 30); // 更宽的显示范围
    }

    final dynamicMaxLength = calculateMaxLength(maxFolderNameWidth);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor, // 白色背景，突出当前操作区域
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 文件夹名称
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.folder_open,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _getBrowseTabLabelWithDynamicLength(vm, dynamicMaxLength),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          // 工具栏
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 只在有文件时显示文件管理工具
              if (vm.files.isNotEmpty)
                FileToolbar(
                  pageId: _getPageIdForCurrentTab(vm.currentTab),
                  showBackButton: false,
                  onBackPressed: () => presenter.navigateUp(),
                  showSearchButton: true,
                  onSearchPressed: () => presenter.toggleSearch(),
                  isSearchMode: vm.isSearchMode,
                  showSortButton: true,
                  onSortPressed: _showBrowseSortOptions,
                  showGroupButton: true,
                  onGroupToggle: () => setState(() {}),
                  iconSize: 18,
                ),
              // 编辑按钮始终显示（用于新建文件夹）
              IconButton(
                icon: Icon(
                  _isEditMode ? Icons.close : Icons.edit_outlined,
                  size: 18,
                ),
                onPressed: _isEditMode ? _exitEditMode : _enterEditMode,
                tooltip: _isEditMode ? '完成' : '编辑',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建最近Tab工具栏 - 仅recent模式显示
  Widget _buildRecentToolBar(
    BuildContext context,
    FileViewModel vm,
  ) {
    final theme = Theme.of(context);

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor, // 白色背景，突出当前操作区域
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 标题
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '最近访问',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          // 工具栏
          if (vm.files.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 编辑按钮
                IconButton(
                  icon: Icon(
                    _isEditMode ? Icons.close : Icons.edit_outlined,
                    size: 18,
                  ),
                  onPressed: _isEditMode ? _exitEditMode : _enterEditMode,
                  tooltip: _isEditMode ? '完成' : '编辑',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 构建收藏Tab工具栏 - 仅favorite模式显示
  Widget _buildFavoriteToolBar(
    BuildContext context,
    FileViewModel vm,
  ) {
    final theme = Theme.of(context);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor, // 白色背景，突出当前操作区域
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 标题
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.star,
                  size: 18,
                  color: Colors.amber,
                ),
                const SizedBox(width: 8),
                Text(
                  '收藏的文件',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          // 工具栏
          if (vm.files.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FileToolbar(
                  pageId: PageId.homeFavorite,
                  showBackButton: false,
                  onBackPressed: () {},
                  showSearchButton: true,
                  onSearchPressed: () {
                    setState(() {
                      _favoriteSearchMode = !_favoriteSearchMode;
                      if (!_favoriteSearchMode) {
                        _favoriteSearchQuery = '';
                        _favoriteSearchController.clear();
                      }
                    });
                  },
                  isSearchMode: _favoriteSearchMode,
                  showSortButton: true,
                  onSortPressed: _showFavoriteSortOptions,
                  showGroupButton: true,
                  onGroupToggle: () => setState(() {}),
                  iconSize: 18,
                ),
                // 编辑按钮
                IconButton(
                  icon: Icon(
                    _isEditMode ? Icons.close : Icons.edit_outlined,
                    size: 18,
                  ),
                  onPressed: _isEditMode ? _exitEditMode : _enterEditMode,
                  tooltip: _isEditMode ? '完成' : '编辑',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 获取文件浏览Tab的标签文本（动态长度版本）
  String _getBrowseTabLabelWithDynamicLength(FileViewModel vm, int maxLength) {
    if (vm.currentTab == TabView.browse && vm.currentPath.isNotEmpty) {
      // 查找快速访问文件夹（精确匹配当前路径）
      if (quickAccessViewModel != null) {
        // 先精确匹配当前路径
        for (final folder in quickAccessViewModel!.folders) {
          if (vm.currentPath == folder.path) {
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
      // 特殊处理：回收站恢复目录
      if (vm.currentPath == '/storage/emulated/0/EasyFile/Restored') {
        const displayName = '回收站恢复';
        final truncatedName = displayName.length > maxLength
            ? '${displayName.substring(0, maxLength - 3)}...'
            : displayName;
        return truncatedName;
      }

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
  /// 构建收藏Tab的分组视图
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
    logger.d(
        '_buildEmptyState - tab: $tab, isSearchMode: $isSearchMode, errorMessage: ${vm.errorMessage}');

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

      case TabView.appManagement:
        // 应用管理现在是独立页面，不会走到这里
        icon = Icons.apps;
        title = '';
        subtitleWidget = const SizedBox.shrink();
        actionButton = null;
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

  /// 构建文件列表的Sliver组件列表（用于CustomScrollView）
  List<Widget> _buildFileListSlivers(FileViewModel vm) {
    if (vm.files.isEmpty) {
      // 空状态
      final isSearchMode =
          (vm.currentTab == TabView.browse && vm.isSearchMode) ||
              (vm.currentTab == TabView.favorite && _favoriteSearchMode);
      return [
        SliverFillRemaining(
          child: _buildEmptyState(vm.currentTab, isSearchMode, vm),
        ),
      ];
    }

    // 获取文件视图的Sliver组件
    final slivers = _buildFileViewSlivers(vm);
    
    // 在浏览Tab子目录中，添加底部padding以防止路径栏遮挡内容
    final shouldAddBottomPadding = vm.currentTab == TabView.browse &&
        !_selectionController.isSelectionMode &&
        !vm.isSearchMode &&
        vm.currentPath.isNotEmpty &&
        _canNavigateUp(vm.currentPath);
    
    if (shouldAddBottomPadding) {
      return [
        ...slivers,
        const SliverToBoxAdapter(
          child: SizedBox(height: 48), // 路径栏高度
        ),
      ];
    }
    
    return slivers;
  }

  /// 构建文件视图的Sliver组件（列表/网格/分组）
  List<Widget> _buildFileViewSlivers(FileViewModel vm) {
    final pageId = _getPageIdForCurrentTab(vm.currentTab);
    final isGridView =
        PageSettingsService().getViewMode(pageId) == ViewMode.grid;
    final isGroupEnabled = _isGroupEnabledForCurrentTab();

    // 为图片/视频构建视图配置（简洁模式支持）
    UnifiedViewConfig? Function(FileItem)? viewConfigBuilder;
    if (isGridView) {
      viewConfigBuilder = (file) {
        final shouldUseCompactMode = !file.isDirectory &&
            (file.category == FileCategory.image || file.category == FileCategory.video);
        if (shouldUseCompactMode) {
          final showFileInfo = PageSettingsService().getGridShowFileInfo(pageId);
          return UnifiedViewConfig.fromContext(context, compactMode: !showFileInfo);
        }
        return null;
      };
    }

    // 收藏Tab、浏览Tab、最近Tab需要应用排序
    var displayFiles = vm.files;

    if (vm.currentTab == TabView.favorite) {
      // 收藏Tab：应用过滤和排序
      displayFiles = _getFilteredFavoriteFiles(vm.files);
    } else if (vm.currentTab == TabView.browse) {
      // 浏览Tab：应用排序
      displayFiles = _getSortedBrowseFiles(vm.files);
    } else if (vm.currentTab == TabView.recent) {
      // 最近Tab：始终按访问时间降序显示，不受用户排序设置影响
      displayFiles = List<FileItem>.from(vm.files)
        ..sort((a, b) {
          final aTime = a.accessedAt ?? DateTime(1970);
          final bTime = b.accessedAt ?? DateTime(1970);
          return bTime.compareTo(aTime); // 降序：最新的在最前
        });
    }

    // 收藏Tab、浏览Tab启用分组时使用分组视图
    if (isGroupEnabled) {
      if (vm.currentTab == TabView.favorite) {
        return _buildFavoriteGroupedViewSlivers(displayFiles, viewConfigBuilder);
      } else if (vm.currentTab == TabView.browse) {
        return _buildBrowseGroupedViewSlivers(displayFiles, viewConfigBuilder);
      }
    }

    // 非分组视图：列表或网格
    return _buildSimpleFileViewSlivers(displayFiles, isGridView, pageId, viewConfigBuilder);
  }

  /// 构建简单列表/网格的Sliver组件
  List<Widget> _buildSimpleFileViewSlivers(
      List<FileItem> files, bool isGridView, PageId pageId, 
      UnifiedViewConfig? Function(FileItem)? viewConfigBuilder) {
    if (isGridView) {
      // 网格视图
      final crossAxisCount = _calculateCrossAxisCount();
      return [
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.70,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildFileItemWrapper(
                files[index],
                viewConfigBuilder: viewConfigBuilder,
              ),
              childCount: files.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              addSemanticIndexes: false,
            ),
          ),
        ),
      ];
    } else {
      // 列表视图
      return [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              return DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 0.5,
                    ),
                  ),
                ),
                child: _buildFileItemWrapper(
                  files[index],
                  viewConfigBuilder: viewConfigBuilder,
                ),
              );
            },
            childCount: files.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            addSemanticIndexes: false,
          ),
        ),
      ];
    }
  }

  /// 计算网格视图的列数
  int _calculateCrossAxisCount() {
    final width = MediaQuery.sizeOf(context).width;
    const minCardWidth = 100.0;
    const spacing = 8.0;
    const horizontalPadding = 16.0;
    final availableWidth = width - horizontalPadding;
    int crossAxisCount =
        ((availableWidth + spacing) / (minCardWidth + spacing)).floor();
    return crossAxisCount.clamp(3, 6);
  }

  /// 构建文件项的包装器（处理点击、选择等）
  Widget _buildFileItemWrapper(
    FileItem item, {
    UnifiedViewConfig? Function(FileItem)? viewConfigBuilder,
  }) {
    final isSelectionMode = _selectionController.isSelectionMode;
    final isSelected = _selectionController.contains(item.path);
    final vm = viewModel;

    // 网格模式且使用统一组件
    final pageId = _getPageIdForCurrentTab(vm.currentTab);
    final isGridView =
        PageSettingsService().getViewMode(pageId) == ViewMode.grid;

    if (isGridView) {
      // 优先使用传入的 viewConfigBuilder
      final viewConfig = viewConfigBuilder?.call(item);

      return UnifiedGridItem(
        key: ValueKey('grid_item_${item.path}'),
        file: item,
        isSelected: isSelected,
        isFavorite: vm.isFavoriteFile(item.path),
        showFavoriteButton: true,
        config: viewConfig,
        onTap: () {
          if (isSelectionMode) {
            _selectionController.toggle(item.path);
          } else {
            _onFileTap(item, vm);
          }
        },
        onLongPress: () {
          // 编辑模式下：仅对文件显示详情面板 + 自动选中
          if (_isEditMode && !item.isDirectory) {
            if (!_selectionController.contains(item.path)) {
              setState(() {
                _selectionController.select(item.path);
              });
            }
            _showFileDetailsBottomSheet(item);
          } else {
            // 非编辑模式：仅进入选择模式（快速选择）
            _selectionController.select(item.path);
          }
        },
        onFavoriteToggle: !item.isDirectory
            ? () async {
                final messenger = ScaffoldMessenger.of(context);
                final isFav = await presenter.toggleFavoriteFile(item);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(isFav ? '已添加到收藏' : '已取消收藏'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              }
            : null,
      );
    } else {
      // 列表模式
      return FileItemTile(
        file: item,
        showFullPath: false,
        showAccessTime: vm.currentTab == TabView.recent,
        accessTime: vm.currentTab == TabView.recent ? item.accessedAt : null,
        isFavorite: vm.isFavoriteFile(item.path),
        isSelected: isSelected,
        showCheckbox: isSelectionMode,
        onFavoriteToggle: !item.isDirectory
            ? () async {
                final messenger = ScaffoldMessenger.of(context);
                final isFav = await presenter.toggleFavoriteFile(item);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(isFav ? '已添加到收藏' : '已取消收藏'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              }
            : null,
        onTap: () {
          if (isSelectionMode) {
            _selectionController.toggle(item.path);
          } else {
            _onFileTap(item, vm);
          }
        },
        onLongPress: () {
          // 编辑模式下：仅对文件显示详情面板 + 自动选中
          if (_isEditMode && !item.isDirectory) {
            if (!_selectionController.contains(item.path)) {
              setState(() {
                _selectionController.select(item.path);
              });
            }
            _showFileDetailsBottomSheet(item);
          } else {
            // 非编辑模式：仅进入选择模式（快速选择）
            _selectionController.select(item.path);
          }
        },
      );
    }
  }

  /// 构建收藏Tab分组视图的Sliver组件
  List<Widget> _buildFavoriteGroupedViewSlivers(
    List<FileItem> files,
    UnifiedViewConfig? Function(FileItem)? viewConfigBuilder,
  ) {
    final isGridView =
        PageSettingsService().getViewMode(PageId.homeFavorite) == ViewMode.grid;
    final groups = _groupFavoriteFilesByDate(files);
    final groupKeys = ['今天', '昨天', '本周', '本月', '更早'];
    final crossAxisCount = _calculateCrossAxisCount();

    List<Widget> slivers = [];
    for (final key in groupKeys) {
      if (groups.containsKey(key) && groups[key]!.isNotEmpty) {
        final count = groups[key]!.length;
        // 分组头部
        slivers.add(
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFFF0F0F0), // 明显的灰色，与文件列表区分
              child: Text(
                '$key（$count个文件）',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        );
        // 分组内容
        if (isGridView) {
          slivers.add(
            SliverPadding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.70,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildFileItemWrapper(
                    groups[key]![index],
                    viewConfigBuilder: viewConfigBuilder,
                  ),
                  childCount: groups[key]!.length,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  addSemanticIndexes: false,
                ),
              ),
            ),
          );
        } else {
          slivers.add(
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: _buildFileItemWrapper(
                      groups[key]![index],
                      viewConfigBuilder: viewConfigBuilder,
                    ),
                  );
                },
                childCount: groups[key]!.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                addSemanticIndexes: false,
              ),
            ),
          );
        }
      }
    }
    return slivers;
  }

  /// 构建浏览Tab分组视图的Sliver组件
  List<Widget> _buildBrowseGroupedViewSlivers(
    List<FileItem> files,
    UnifiedViewConfig? Function(FileItem)? viewConfigBuilder,
  ) {
    final isGridView =
        PageSettingsService().getViewMode(PageId.homeBrowse) == ViewMode.grid;
    final groups = _groupBrowseFilesByDate(files);
    final groupKeys = ['今天', '昨天', '本周', '本月', '更早'];
    final crossAxisCount = _calculateCrossAxisCount();

    List<Widget> slivers = [];
    for (final key in groupKeys) {
      if (groups.containsKey(key) && groups[key]!.isNotEmpty) {
        final count = groups[key]!.length;
        // 分组头部
        slivers.add(
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFFF0F0F0), // 明显的灰色，与文件列表区分
              child: Text(
                '$key（$count个文件）',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        );
        // 分组内容
        if (isGridView) {
          slivers.add(
            SliverPadding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.70,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildFileItemWrapper(
                    groups[key]![index],
                    viewConfigBuilder: viewConfigBuilder,
                  ),
                  childCount: groups[key]!.length,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  addSemanticIndexes: false,
                ),
              ),
            ),
          );
        } else {
          slivers.add(
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: _buildFileItemWrapper(
                      groups[key]![index],
                      viewConfigBuilder: viewConfigBuilder,
                    ),
                  );
                },
                childCount: groups[key]!.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                addSemanticIndexes: false,
              ),
            ),
          );
        }
      }
    }
    return slivers;
  }

  /// 构建列表/网格视图（使用FileCollectionView）
  /// 处理文件点击
  void _onFileTap(FileItem file, FileViewModel vm) {
    // 编辑模式下，点击文件/文件夹自动进入选择模式并选中
    if (_isEditMode && !_selectionController.isSelectionMode) {
      setState(() {
        _showEditModeHint = false; // 隐藏提示
      });
      _selectionController.select(file.path);
      return;
    }

    // 选择模式下的点击由FileCollectionView处理，这里只处理导航
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

  /// 构建竖屏布局（使用单个CustomScrollView）
  Widget _buildPortraitLayout(FileViewModel vm) {
    return Stack(
      children: [
        GestureDetector(
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
            if (vm.isSearchMode || _favoriteSearchMode) {
              return;
            }

            // 功能1: 浏览Tab - 左右滑切换分类Tab
            if (vm.currentTab == TabView.browse) {
              final visibleCategories = [
                FileCategory.all,
                ...vm.fileTypeStats.getVisibleCategories(),
              ];
              if (visibleCategories.length > 1) {
                final currentIndex =
                    visibleCategories.indexOf(vm.selectedCategory);
                if (currentIndex != -1) {
                  if (isSwipeLeft &&
                      currentIndex < visibleCategories.length - 1) {
                    // 左滑切换到下一个分类
                    vm.setSelectedCategory(visibleCategories[currentIndex + 1]);
                    return;
                  } else if (isSwipeRight && currentIndex > 0) {
                    // 右滑切换到上一个分类
                    vm.setSelectedCategory(visibleCategories[currentIndex - 1]);
                    return;
                  }
                }
              }
            }

            // 功能2: 在最近/收藏Tab之间左右滑动切换
            if (vm.currentTab == TabView.recent && isSwipeLeft) {
              // 最近Tab左滑 → 切换到收藏Tab
              viewModel.setCurrentTab(TabView.favorite);
              presenter.loadFavoriteFiles();
            } else if (vm.currentTab == TabView.favorite && isSwipeRight) {
              // 收藏Tab右滑 → 切换到最近Tab
              viewModel.setCurrentTab(TabView.recent);
              presenter.loadRecentFiles();
            }
          },
          child: RefreshIndicator(
            onRefresh: () async {
              await presenter.refreshCurrent();
            },
            child: CustomScrollView(
              slivers: [
                // CategoryNavBar 和 QuickAccessSection：可滚动查看（横竖屏都显示）
                if (!(vm.currentTab == TabView.browse && vm.isSearchMode) &&
                    !(vm.currentTab == TabView.favorite &&
                        _favoriteSearchMode)) ...[
                  SliverToBoxAdapter(
                    child: CategoryNavBar(
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
                  ),
                  const SliverToBoxAdapter(
                    child: Divider(height: 1),
                  ),
                  SliverToBoxAdapter(
                    child: QuickAccessSection(
                      quickAccessViewModel: quickAccessViewModel!,
                      quickAccessPresenter: quickAccessPresenter!,
                      fileViewModel: vm,
                      filePresenter: presenter,
                      categoryCardSize: _categoryCardSize,
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Divider(height: 1),
                  ),
                ],

                // 快捷访问栏（导航功能栏）- 可滚动隐藏
                if (!(vm.currentTab == TabView.browse && vm.isSearchMode) &&
                    !(vm.currentTab == TabView.favorite && _favoriteSearchMode))
                  SliverToBoxAdapter(
                    child: _buildQuickAccessBar(context, vm),
                  ),

                // 最近Tab工具栏 - recent模式固定显示
                if (vm.currentTab == TabView.recent)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: PinnedHeaderDelegate(
                      child: _buildRecentToolBar(context, vm),
                      height: 52.0,
                    ),
                  ),

                // 编辑模式提示 - 显示在编辑按钮下一行（Recent Tab）
                if (vm.currentTab == TabView.recent && _isEditMode && _showEditModeHint && !_selectionController.isSelectionMode)
                  SliverToBoxAdapter(
                    child: _buildEditModeHint(),
                  ),

                // 浏览控制栏（文件夹名+工具栏）- browse模式固定显示（包括搜索模式）
                if (vm.currentTab == TabView.browse)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: PinnedHeaderDelegate(
                      child: LayoutBuilder(
                        builder: (context, localConstraints) {
                          return _buildBrowseControlBar(
                            context,
                            vm,
                            localConstraints.maxWidth,
                          );
                        },
                      ),
                      height: 44.0,
                    ),
                  ),

                // 编辑模式提示 - 显示在编辑按钮下一行（Browse Tab）
                if (vm.currentTab == TabView.browse && _isEditMode && _showEditModeHint && !_selectionController.isSelectionMode && !vm.isSearchMode)
                  SliverToBoxAdapter(
                    child: _buildEditModeHint(),
                  ),

                // 收藏Tab工具栏 - favorite模式固定显示
                if (vm.currentTab == TabView.favorite && !_favoriteSearchMode)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: PinnedHeaderDelegate(
                      child: _buildFavoriteToolBar(context, vm),
                      height: 52.0,
                    ),
                  ),

                // 编辑模式提示 - 显示在编辑按钮下一行
                if (vm.currentTab == TabView.favorite && _isEditMode && _showEditModeHint && !_selectionController.isSelectionMode)
                  SliverToBoxAdapter(
                    child: _buildEditModeHint(),
                  ),

                // 浏览Tab的搜索栏
                if (vm.currentTab == TabView.browse && vm.isSearchMode)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: PinnedHeaderDelegate(
                      child: FileSearchBar(
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
                      height: 56.0,
                    ),
                  ),

                // 收藏Tab的搜索栏
                if (vm.currentTab == TabView.favorite && _favoriteSearchMode)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: PinnedHeaderDelegate(
                      child: FileSearchBar(
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
                      height: 56.0,
                    ),
                  ),

                // 新建文件夹按钮 - 仅在 Browse Tab 编辑模式下显示
                if (vm.currentTab == TabView.browse && _isEditMode && !vm.isSearchMode)
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: OutlinedButton.icon(
                        onPressed: _showCreateFolderDialog,
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('新建文件夹'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
                  ),

                // 文件类型筛选Tab栏（browse模式固定显示）
                if (vm.currentTab == TabView.browse && !vm.isSearchMode)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: PinnedHeaderDelegate(
                      child: FileCategoryTabBar(
                        stats: vm.fileTypeStats,
                        selectedCategory: vm.selectedCategory,
                        onCategoryChanged: (category) {
                          vm.setSelectedCategory(category);
                        },
                      ),
                      height: (vm.fileTypeStats.hasMultipleTypes ||
                              vm.fileTypeStats.totalFileCount > 0)
                          ? 35.0
                          : 0.0,
                    ),
                  ),

                // 文件列表区域
                ..._buildFileListSlivers(vm),
              ],
            ),
          ),
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
                if (_permissionState == PermissionState.permanentlyDenied) {
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

        // 底部返回路径栏 - 固定在底部
        if (vm.currentTab == TabView.browse &&
            !_selectionController.isSelectionMode &&
            !vm.isSearchMode &&
            vm.currentPath.isNotEmpty &&
            _canNavigateUp(vm.currentPath))
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FolderNavigationBar(
              currentPath: vm.currentPath,
              onBackPressed: () => presenter.navigateUp(),
            ),
          ),
      ],
    );
  }

  /// 构建横屏布局（左右分栏）
  Widget _buildLandscapeLayout(FileViewModel vm, BoxConstraints constraints) {
    // 左侧功能区宽度 = 屏幕宽度的 45%（但不小于竖屏宽度）
    final portraitWidth = math.min(constraints.maxWidth, constraints.maxHeight);
    final leftPaneWidth = math.max(portraitWidth, constraints.maxWidth * 0.45);

    return Stack(
      children: [
        Row(
          children: [
            // 左侧功能区：包含CategoryNavBar、QuickAccessSection、快捷访问栏
            Container(
              width: leftPaneWidth,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              padding: const EdgeInsets.all(4),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // CategoryNavBar（分类导航栏）
                        if (!(vm.currentTab == TabView.browse &&
                                vm.isSearchMode) &&
                            !(vm.currentTab == TabView.favorite &&
                                _favoriteSearchMode)) ...[
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
                          const SizedBox(height: 2),

                          // QuickAccessSection（快捷访问推荐区）
                          QuickAccessSection(
                            quickAccessViewModel: quickAccessViewModel!,
                            quickAccessPresenter: quickAccessPresenter!,
                            fileViewModel: vm,
                            filePresenter: presenter,
                            categoryCardSize: _categoryCardSize,
                          ),
                          const SizedBox(height: 2),

                          // 快捷访问栏（4个Tab导航）- 横屏专用布局
                          _buildQuickAccessBarLandscape(context, vm),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 竖向分隔线
            const VerticalDivider(width: 1, thickness: 1),

            // 右侧浏览区：包含控制栏和文件列表
            Expanded(
              child: GestureDetector(
                // 手势功能：左右滑切换分类Tab
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity == null) {
                    return;
                  }

                  final velocity = details.primaryVelocity!;
                  final isSwipeRight = velocity > 500;
                  final isSwipeLeft = velocity < -500;

                  // 搜索模式下禁用手势
                  if (vm.isSearchMode || _favoriteSearchMode) {
                    return;
                  }

                  // 浏览Tab - 左右滑切换分类Tab
                  if (vm.currentTab == TabView.browse) {
                    final visibleCategories = [
                      FileCategory.all,
                      ...vm.fileTypeStats.getVisibleCategories(),
                    ];
                    if (visibleCategories.length > 1) {
                      final currentIndex =
                          visibleCategories.indexOf(vm.selectedCategory);
                      if (currentIndex != -1) {
                        if (isSwipeLeft &&
                            currentIndex < visibleCategories.length - 1) {
                          vm.setSelectedCategory(
                              visibleCategories[currentIndex + 1]);
                          return;
                        } else if (isSwipeRight && currentIndex > 0) {
                          vm.setSelectedCategory(
                              visibleCategories[currentIndex - 1]);
                          return;
                        }
                      }
                    }
                  }

                  // 在最近/收藏Tab之间左右滑动切换
                  if (vm.currentTab == TabView.recent && isSwipeLeft) {
                    viewModel.setCurrentTab(TabView.favorite);
                    presenter.loadFavoriteFiles();
                  } else if (vm.currentTab == TabView.favorite &&
                      isSwipeRight) {
                    viewModel.setCurrentTab(TabView.recent);
                    presenter.loadRecentFiles();
                  }
                },
                child: RefreshIndicator(
                  onRefresh: () async {
                    await presenter.refreshCurrent();
                  },
                  child: CustomScrollView(
                    slivers: [
                      // 最近Tab工具栏 - recent模式固定显示
                      if (vm.currentTab == TabView.recent)
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: PinnedHeaderDelegate(
                            child: _buildRecentToolBar(context, vm),
                            height: 52.0,
                          ),
                        ),

                      // 编辑模式提示 - 显示在编辑按钮下一行（Recent Tab 横屏）
                      if (vm.currentTab == TabView.recent && _isEditMode && _showEditModeHint && !_selectionController.isSelectionMode)
                        SliverToBoxAdapter(
                          child: _buildEditModeHint(),
                        ),

                      // 浏览控制栏（文件夹名+工具栏）- browse模式固定显示（包括搜索模式）
                      if (vm.currentTab == TabView.browse)
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: PinnedHeaderDelegate(
                            child: LayoutBuilder(
                              builder: (context, localConstraints) {
                                return _buildBrowseControlBar(
                                  context,
                                  vm,
                                  localConstraints.maxWidth,
                                );
                              },
                            ),
                            height: 48.0,
                          ),
                        ),

                      // 编辑模式提示 - 显示在编辑按钮下一行（Browse Tab 横屏）
                      if (vm.currentTab == TabView.browse && _isEditMode && _showEditModeHint && !_selectionController.isSelectionMode && !vm.isSearchMode)
                        SliverToBoxAdapter(
                          child: _buildEditModeHint(),
                        ),

                      // 收藏Tab工具栏 - favorite模式固定显示
                      if (vm.currentTab == TabView.favorite &&
                          !_favoriteSearchMode)
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: PinnedHeaderDelegate(
                            child: _buildFavoriteToolBar(context, vm),
                            height: 48.0,
                          ),
                        ),

                      // 编辑模式提示 - 显示在编辑按钮下一行（Favorite Tab 横屏）
                      if (vm.currentTab == TabView.favorite && _isEditMode && _showEditModeHint && !_selectionController.isSelectionMode)
                        SliverToBoxAdapter(
                          child: _buildEditModeHint(),
                        ),

                      // 浏览Tab的搜索栏
                      if (vm.currentTab == TabView.browse && vm.isSearchMode)
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: PinnedHeaderDelegate(
                            child: FileSearchBar(
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
                            height: 56.0,
                          ),
                        ),

                      // 收藏Tab的搜索栏
                      if (vm.currentTab == TabView.favorite &&
                          _favoriteSearchMode)
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: PinnedHeaderDelegate(
                            child: FileSearchBar(
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
                            height: 56.0,
                          ),
                        ),

                      // 文件类型筛选Tab栏（browse模式固定显示）
                      if (vm.currentTab == TabView.browse && !vm.isSearchMode)
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: PinnedHeaderDelegate(
                            child: FileCategoryTabBar(
                              stats: vm.fileTypeStats,
                              selectedCategory: vm.selectedCategory,
                              onCategoryChanged: (category) {
                                vm.setSelectedCategory(category);
                              },
                            ),
                            height: (vm.fileTypeStats.hasMultipleTypes ||
                                    vm.fileTypeStats.totalFileCount > 0)
                                ? 35.0
                                : 0.0,
                          ),
                        ),

                      // 新建文件夹按钮 - 仅在 Browse Tab 编辑模式下显示
                      if (vm.currentTab == TabView.browse && _isEditMode && !vm.isSearchMode)
                        SliverToBoxAdapter(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: OutlinedButton.icon(
                              onPressed: _showCreateFolderDialog,
                              icon: const Icon(Icons.create_new_folder_outlined),
                              label: const Text('新建文件夹'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                                alignment: Alignment.centerLeft,
                              ),
                            ),
                          ),
                        ),

                      // 文件列表区域
                      ..._buildFileListSlivers(vm),
                    ],
                  ),
                ),
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
                if (_permissionState == PermissionState.permanentlyDenied) {
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

        // 底部返回路径栏 - 固定在底部（横屏布局下只在右侧区域显示）
        if (vm.currentTab == TabView.browse &&
            !_selectionController.isSelectionMode &&
            !vm.isSearchMode &&
            vm.currentPath.isNotEmpty &&
            _canNavigateUp(vm.currentPath))
          Positioned(
            left: leftPaneWidth,  // 从右侧区域开始
            right: 0,
            bottom: 0,
            child: FolderNavigationBar(
              currentPath: vm.currentPath,
              onBackPressed: () => presenter.navigateUp(),
            ),
          ),
      ],
    );
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

              // 优先级3: 退出编辑模式
              if (_isEditMode) {
                _exitEditMode();
                return false;
              }

              // 优先级4: 子文件夹返回上级
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 判断是否为横屏模式
                final isLandscape =
                    constraints.maxWidth > constraints.maxHeight;
                // 横屏使用较小的 AppBar 高度
                final appBarHeight = isLandscape ? 28.0 : 56.0;

                return Scaffold(
                  appBar: PreferredSize(
                    preferredSize: Size.fromHeight(appBarHeight),
                    child: AppBar(
                      toolbarHeight: appBarHeight,
                      leadingWidth: _selectionController.isSelectionMode ? 40 : null,  // 缩小 leading 宽度
                      leading: _selectionController.isSelectionMode
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              padding: EdgeInsets.zero,  // 移除内边距
                              onPressed: () {
                                setState(() {
                                  _selectionController.clear();
                                });
                              },
                            )
                          : null,
                      titleSpacing: _selectionController.isSelectionMode ? 0 : null,  // 移除 title 的左侧间距
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
                      actions: _selectionController.isSelectionMode
                          ? [
                              // 全选按钮（三态设计）
                              IconButton(
                                icon: Icon(
                                  _selectedItems.isEmpty
                                      ? Icons.check_box_outline_blank  // 未选
                                      : _selectedItems.length == vm.files.length
                                          ? Icons.check_box  // 全选
                                          : Icons.indeterminate_check_box,  // 部分选
                                ),
                                onPressed: () {
                                  if (_selectedItems.length == vm.files.length) {
                                    // 全选状态 -> 取消全选
                                    _selectionController.clear();
                                  } else {
                                    // 未选或部分选 -> 全选
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
                  ),
                  body: LayoutBuilder(
                    builder: (context, constraints) {
                      // 判断是否为横屏模式
                      final isLandscape =
                          constraints.maxWidth > constraints.maxHeight;

                      // 根据屏幕方向选择不同的布局
                      return isLandscape
                          ? _buildLandscapeLayout(viewModel, constraints)
                          : _buildPortraitLayout(viewModel);
                    },
                  ),
                  // 批量操作底部工具栏
                  bottomNavigationBar: _selectionController.isSelectionMode
                      ? _buildSelectionBottomBar()
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// 构建编辑模式提示
  Widget _buildEditModeHint() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '您已进入编辑模式，点击任一项进行选择',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建批量选择底部工具栏
  Widget _buildSelectionBottomBar() {
    final batchService = _getBatchOperationsService();
    return SelectionBottomBar(
      selectedPaths: _selectedItems,
      isAllFavorite: batchService.isAllSelectedFavorite(_selectedItems),
      onCopy: () {
        if (!mounted) return;
        batchService.batchCopy(context, _selectedItems, viewModel.currentPath);
      },
      onRename: () {
        if (!mounted) return;
        batchService.batchRename(context, _selectedItems);
      },
      onShare: () {
        if (!mounted) return;
        batchService.batchShare(context, _selectedItems);
      },
      onMove: () {
        if (!mounted) return;
        batchService.batchMove(context, _selectedItems, viewModel.currentPath);
      },
      onToggleFavorite: () {
        if (!mounted) return;
        batchService.batchToggleFavorite(context, _selectedItems);
      },
      onDelete: () {
        if (!mounted) return;
        batchService.batchDelete(context, _selectedItems);
      },
    );
  }

  /// 获取批量操作服务实例
  BatchOperationsService _getBatchOperationsService() {
    return BatchOperationsService(
      viewModel: viewModel,
      presenter: presenter,
      onRefresh: () async {
        if (!mounted) return;
        if (viewModel.currentTab == TabView.browse) {
          await presenter.loadFiles(viewModel.currentPath);
        } else if (viewModel.currentTab == TabView.favorite) {
          await presenter.loadFavoriteFiles();
        }
      },
      onExitSelectionMode: () {
        if (!mounted) return;
        // 批量操作完成后，同时退出编辑模式和选择模式
        setState(() {
          _isEditMode = false;
          _selectionController.clear();
        });
      },
    );
  }

  /// 显示文件详情底部面板
  void _showFileDetailsBottomSheet(FileItem file) {
    final colorScheme = Theme.of(context).colorScheme;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  '文件详情',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // 文件名
            _buildDetailRow(
              '文件名',
              file.name,
              colorScheme,
              isSelectable: true,
            ),
            const SizedBox(height: 16),
            
            // 完整路径
            _buildDetailRow(
              '完整路径',
              file.path,
              colorScheme,
              isSelectable: true,
            ),
            const SizedBox(height: 16),
            
            // 文件大小
            _buildDetailRow(
              '文件大小',
              FileSizeFormatter.formatBytes(file.size),
              colorScheme,
            ),
            const SizedBox(height: 16),
            
            // 修改时间
            _buildDetailRow(
              '修改时间',
              '${file.modified.year}-${file.modified.month.toString().padLeft(2, '0')}-${file.modified.day.toString().padLeft(2, '0')} '
              '${file.modified.hour.toString().padLeft(2, '0')}:${file.modified.minute.toString().padLeft(2, '0')}',
              colorScheme,
            ),
            const SizedBox(height: 24),
            
            // 关闭按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建详情行
  Widget _buildDetailRow(
    String label,
    String value,
    ColorScheme colorScheme, {
    bool isSelectable = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label：',
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: isSelectable
              ? SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface,
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface,
                  ),
                ),
        ),
      ],
    );
  }
}
