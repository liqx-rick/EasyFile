import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/permission_service.dart';
import 'package:easyfile/core/services/category_sort_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/recommendation_service.dart';
import 'package:easyfile/core/services/app_statistics_cache.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/core/services/startup/startup_orchestrator.dart';
import 'package:easyfile/core/services/startup/app_initialization_service.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/presenter/quick_access_presenter.dart';
import 'package:easyfile/ui/pages/settings_page.dart';
import 'package:easyfile/ui/pages/about_page.dart';
import 'package:easyfile/ui/pages/quick_access_manage_page.dart';
import 'package:easyfile/ui/pages/app_management_page.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/pages/new_files_settings_page.dart';
import 'package:easyfile/ui/pages/trash_page.dart';
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
import 'package:easyfile/ui/widgets/edit_mode_widgets.dart';
import 'package:easyfile/ui/widgets/edit_mode_hint_bar.dart';
import 'package:easyfile/ui/mixins/edit_mode_mixin.dart';
import 'package:easyfile/ui/mixins/create_folder_mixin.dart';
import 'package:easyfile/ui/mixins/pop_scope_handler_mixin.dart';
import 'package:easyfile/utils/file_comparator_util.dart';
import 'package:easyfile/ui/widgets/permission_banner.dart';
import 'package:easyfile/ui/services/batch_operations_service.dart';
import 'package:easyfile/ui/services/single_file_operations_service.dart';
import 'package:easyfile/ui/widgets/single_file_operations_sheet.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/utils/file_grouping_util.dart';
import 'package:easyfile/viewmodel/quick_access_viewmodel.dart';

class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({super.key});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage>
    with
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin,
        EditModeMixin,
        CreateFolderMixin,
        PopScopeHandlerMixin {
  late FilePresenter presenter;
  late FileViewModel viewModel;
  QuickAccessPresenter? quickAccessPresenter;
  QuickAccessViewModel? quickAccessViewModel;
  bool _hasCheckedRestore = false; // 标记是否已经检查过恢复
  double _categoryCardSize = 0.0; // 存储分类卡片尺寸
  bool _isInitializing = true; // 标记是否正在初始化

  // 推荐服务（全局实例，复用缓存）
  RecommendationService? _recommendationService;

  // 权限和扫描相关状态
  late PermissionService _permissionService;
  bool _isScanning = false;
  PermissionState _permissionState = PermissionState.unknown;
  bool _isFirstScan = false;
  double _scanProgress = 0.0; // 扫描进度 (0.0 - 1.0)

  // 批量操作相关（SelectionController 内部管理 isSelectionMode 状态）
  Set<String> _selectedItems = {}; // 存储选中的文件/文件夹路径
  late final SelectionController _selectionController;

  // 单文件操作服务
  late final SingleFileOperationsService _singleFileOperationsService;

  // EditModeMixin 要求的 getter
  @override
  SelectionController get selectionController => _selectionController;

  // PopScopeHandlerMixin 重写 - Browser Page 特殊逻辑
  @override
  bool canPopPage() {
    // 优先级1: 有搜索模式 → 不允许pop（需要先退出搜索）
    if (viewModel.currentTab == TabView.browse && viewModel.isSearchMode) {
      return false;
    }
    if (viewModel.currentTab == TabView.favorite && _favoriteSearchMode) {
      return false;
    }
    if (viewModel.currentTab == TabView.newFiles && _newFilesSearchMode) {
      return false;
    }

    // 优先级2: 编辑模式 → 不允许pop（需要先退出编辑）
    if (isEditMode) {
      return false;
    }

    // 优先级3: Browse Tab 在子文件夹 → 不允许pop（需要先返回上级）
    if (viewModel.currentTab == TabView.browse &&
        viewModel.currentPath.isNotEmpty &&
        _canNavigateUp(viewModel.currentPath)) {
      return false;
    }

    // 优先级4: 不在顶部 → 不允许pop（需要先滚动到顶部）
    final currentOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final isAtTop = currentOffset < _scrollThreshold;
    if (!isAtTop) {
      return false;
    }

    // 优先级5: 不在最近Tab → 不允许pop（需要先切换到最近Tab）
    if (viewModel.currentTab != TabView.recent) {
      return false;
    }

    // 优先级6: 已在最近Tab且在顶部且无特殊状态 → 允许pop（退出应用）
    return true;
  }

  @override
  void handlePopInvoked(bool didPop, dynamic result) {
    // 如果系统已经允许pop（canPopPage返回true），说明满足退出条件
    // 此时应该退出应用到后台
    if (didPop) {
      SystemNavigator.pop();
      return;
    }

    // 以下是canPopPage返回false时的处理逻辑
    // 优先级1: 退出搜索模式
    if (viewModel.currentTab == TabView.browse && viewModel.isSearchMode) {
      _searchController.clear();
      presenter.clearSearch();
      return;
    }
    if (viewModel.currentTab == TabView.favorite && _favoriteSearchMode) {
      setState(() {
        _favoriteSearchQuery = '';
        _favoriteSearchController.clear();
        _favoriteSearchMode = false;
      });
      return;
    }
    if (viewModel.currentTab == TabView.newFiles && _newFilesSearchMode) {
      setState(() {
        _newFilesSearchQuery = '';
        _newFilesSearchController.clear();
        _newFilesSearchMode = false;
      });
      return;
    }

    // 优先级2: 编辑模式的返回处理（复杂滚动逻辑）
    if (isEditMode) {
      final enteredFromTop = _editModeEnterScrollOffset < _scrollThreshold;
      final currentOffset =
          _scrollController.hasClients ? _scrollController.offset : 0.0;
      final isAtTop = currentOffset < _scrollThreshold;

      if (enteredFromTop) {
        // 情况A - 从主页进入（进入时在顶部）
        if (!isAtTop) {
          // 当前不在顶部 → 滚动回顶部
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
          return;
        } else {
          // 已在顶部 → 退出编辑模式
          exitEditMode();
          return;
        }
      } else {
        // 情况B - 从浏览区进入（进入时已滚动）→ 直接退出编辑模式
        exitEditMode();
        return;
      }
    }

    // 优先级3: Browse Tab 子文件夹返回上级
    if (viewModel.currentTab == TabView.browse &&
        viewModel.currentPath.isNotEmpty &&
        _canNavigateUp(viewModel.currentPath)) {
      presenter.navigateUp();
      return;
    }

    // 优先级4: 所有Tab - 不在顶部时滚动到顶部
    final currentOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final isAtTop = currentOffset < _scrollThreshold;

    if (!isAtTop) {
      // 不在顶部 → 滚动回顶部
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      return;
    }

    // 优先级5: 不在最近Tab → 切换到最近Tab
    if (viewModel.currentTab != TabView.recent) {
      viewModel.setCurrentTab(TabView.recent);
      return;
    }
  }

  // 编辑模式滚动位置记录
  double _editModeEnterScrollOffset = 0.0; // 记录进入编辑模式时的滚动位置
  static const double _scrollThreshold = 50.0; // 判断是否在顶部的阈值（50像素）
  final ScrollController _scrollController = ScrollController(); // 主滚动控制器
  final ScrollController _landscapeRightScrollController =
      ScrollController(); // 横屏右侧面板滚动控制器

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

  // 新文件Tab的搜索状态
  bool _newFilesSearchMode = false;
  String _newFilesSearchQuery = '';
  final TextEditingController _newFilesSearchController =
      TextEditingController();
  final FocusNode _newFilesSearchFocusNode = FocusNode();

  @override
  bool get wantKeepAlive => true; // 保持状态不被销毁

  @override
  void initState() {
    super.initState();
    _selectionController = SelectionController();
    _selectionController.selectedNotifier.addListener(_onSelectionChanged);
    WidgetsBinding.instance.addObserver(this);
    logger.i('FileBrowserPage initState called');

    // 异步初始化依赖注入的服务
    _initializeDependencies();
  }

  /// 异步初始化依赖注入的服务
  Future<void> _initializeDependencies() async {
    try {
      viewModel = locator<FileViewModel>();
      logger.d('ViewModel obtained: $viewModel');

      // 异步获取 FilePresenter
      presenter = await locator.getAsync<FilePresenter>();
      logger.d('Presenter obtained: $presenter');

      quickAccessViewModel = locator<QuickAccessViewModel>();
      logger.d('QuickAccessViewModel obtained: $quickAccessViewModel');

      quickAccessPresenter = locator<QuickAccessPresenter>();
      logger.d('QuickAccessPresenter obtained: $quickAccessPresenter');

      _permissionService = locator<PermissionService>();
      logger.d('PermissionService obtained: $_permissionService');

      // 初始化推荐服务（全局单例，带缓存）
      await _initializeRecommendationService();

      // Check if widget is still mounted before using context
      if (!mounted) return;

      // 初始化单文件操作服务
      _singleFileOperationsService = SingleFileOperationsService(
        context: context,
        viewModel: viewModel,
        presenter: presenter,
        onRefresh: () async {
          // 根据当前 Tab 刷新对应的数据
          if (viewModel.currentTab == TabView.favorite) {
            await presenter.loadFavoriteFiles();
          } else if (viewModel.currentTab == TabView.recent) {
            await presenter.loadRecentFiles();
          } else {
            // 浏览Tab：重新加载当前目录
            await presenter.loadFiles(viewModel.currentPath);
          }

          // 浏览Tab特殊处理：移动文件后需要从列表移除（因为文件不在当前目录了）
          if (viewModel.currentTab == TabView.browse) {
            final updatedPath = viewModel.lastUpdatedNewFile?.path;
            if (updatedPath != null && viewModel.lastUpdatedOldPath != null) {
              // 检查更新后的文件是否还在当前目录
              final updatedFileDir = Directory(updatedPath).parent.path;
              if (updatedFileDir != viewModel.currentPath) {
                // 文件已移到其他目录，从列表移除
                logger.d(
                    'File moved to another directory, removing from list: $updatedPath');
                viewModel.removeFileFromList(updatedPath);
              }
            }
          }
        },
        onUIUpdate: () {
          // 轻量级UI刷新（不重新加载数据，只更新UI状态）
          if (mounted) {
            setState(() {});
          }
        },
      );
      logger.d('SingleFileOperationsService initialized');

      // 更新状态，标记初始化完成
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }

      // 延迟初始化应用程序数据，先显示UI - 这个优化保留
      Future.microtask(() => _initializeAppWithPermission());

      // 只在首次初始化时检查是否需要恢复文件预览
      if (!_hasCheckedRestore) {
        _checkAndRestoreFilePreview();
        _hasCheckedRestore = true;
      }
    } catch (e) {
      logger.e('Error in _initializeDependencies: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  /// 初始化推荐服务（全局单例，带缓存）
  Future<void> _initializeRecommendationService() async {
    try {
      logger.d('初始化推荐服务...');
      
      // 创建检测服务并初始化
      final detectionService = AppDetectionService();
      await detectionService.initialize();
      
      // 创建统计缓存并初始化
      final statisticsCache = AppStatisticsCache();
      await statisticsCache.initialize();
      
      // 创建扫描器
      final scanner = UnifiedAppScanner(detectionService);
      
      // 创建推荐服务
      _recommendationService = RecommendationService(
        detectionService: detectionService,
        scanner: scanner,
        statisticsCache: statisticsCache,
      );
      
      logger.d('推荐服务初始化完成');
    } catch (e) {
      logger.e('推荐服务初始化失败: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _landscapeRightScrollController.dispose();
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

  // CreateFolderMixin 接口实现
  @override
  String getCurrentPath() => viewModel.currentPath;

  @override
  Future<void> onFolderCreated() async {
    // 退出编辑模式并刷新
    exitEditMode();
    await presenter.refreshCurrent();
  }

  // EditModeMixin 回调实现
  @override
  void onEnterEditMode() {
    // 记录进入编辑模式时的滚动位置
    _editModeEnterScrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    logger.d('FileBrowserPage: App lifecycle changed to $state');

    // 当应用从后台恢复时
    if (state == AppLifecycleState.resumed) {
      // 1. 重新检查权限状态
      _checkPermissionAfterResume();

      // 2. 如果在新文件Tab，自动后台刷新列表
      _refreshNewFilesOnResume();
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
        await _initializeAppWithOrchestrator();
      } else if (newState != _permissionState) {
        setState(() {
          _permissionState = newState;
        });
      }
    }
  }

  /// 应用恢复时刷新新文件列表（如果当前在新文件Tab）
  ///
  /// 当用户从后台返回应用时，如果停留在新文件Tab，自动后台刷新列表。
  /// 这确保用户看到的数据始终是最新的（例如刚下载的文件）。
  void _refreshNewFilesOnResume() {
    // 添加诊断日志
    logger.d('_refreshNewFilesOnResume: currentTab=${viewModel.currentTab}');

    // 只有当前在新文件Tab时才刷新
    if (viewModel.currentTab == TabView.newFiles) {
      logger.i('App resumed on newFiles tab, refreshing in background...');
      presenter.refreshNewFilesInBackground();
    } else {
      logger.d('Not on newFiles tab, skipping refresh');
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
  /// 初始化权限并启动应用
  /// 
  /// 1. 检查权限状态
  /// 2. 初始化主题
  /// 3. 如果权限已授予，调用 StartupOrchestrator 进行三场景路由初始化
  /// 4. 如果没有权限，显示权限提示横幅但不阻塞页面显示
  Future<void> _initializeAppWithPermission() async {
    logger.i('═══════════════════════════════════════');
    logger.i('📱 FileBrowserPage._initializeAppWithPermission started');
    logger.i('═══════════════════════════════════════');

    try {
      // 先检查权限状态
      final permissionState = await _permissionService.checkPermission();
      setState(() {
        _permissionState = permissionState;
      });

      // 同步 ViewModel 主题（MaterialApp 中的主题已从 ThemeSettingsService 加载）
      presenter.initializeTheme();

      if (permissionState.isGranted) {
        logger.i('Permission granted, starting orchestrator...');
        await _initializeAppWithOrchestrator();
      }
    } catch (e) {
      logger.e('Error during app initialization: $e');
    }
  }

  /// 使用 StartupOrchestrator 进行三场景初始化
  /// 
  /// 检测启动场景并路由到相应的初始化流程：
  /// - freshInstall：执行完整初始化（P0→P1→P2）
  /// - reinstall：加载缓存数据（3秒）
  /// - normalOpen：直接加载数据库（2秒）
  Future<void> _initializeAppWithOrchestrator() async {
    logger.i('[FileBrowser] Starting startup orchestration...');

    try {
      // 从 locator 获取服务实例
      final orchestrator = await locator.getAsync<StartupOrchestrator>();
      final appInitService = await locator.getAsync<AppInitializationService>();
      
      // 设置进度回调（用于首次安装时显示进度）
      appInitService.onProgress = (progress) {
        if (mounted) {
          setState(() {
            _isScanning = true;
            _scanProgress = progress;
          });
        }
      };
      
      // 调用编排器进行初始化
      await orchestrator.orchestrate();

      // 初始化完成，隐藏进度UI
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scanProgress = 0.0;
        });
      }

      // 加载初始目录
      await _loadInitialDirectory();

      logger.i('[FileBrowser] Orchestration completed successfully');
    } catch (e) {
      logger.e('[FileBrowser] Error during orchestration: $e');
      
      // 出错时也要隐藏进度UI
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scanProgress = 0.0;
        });
      }
      
      // 降级处理：仍然尝试加载初始目录
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
      await _initializeAppWithOrchestrator();
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
          '/data/data/com.guangqi.easyfile/files',
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
      // 根据当前Tab获取正确的文件列表
      final sourceFiles = viewModel.currentTab == TabView.newFiles
          ? viewModel.newFiles
          : viewModel.files;

      // 根据当前文件类型只过滤同类型文件
      final mediaFiles = sourceFiles.where((f) {
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
      case 'new_files_settings':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const NewFilesSettingsPage(),
          ),
        );
        break;
      case 'settings':
        _navigateToSettings();
        break;
      case 'manage_quick_access':
        _navigateToQuickAccessManagePage();
        break;
      case 'app_management':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const AppManagementPage(
              isFromStorageManagement: false,
            ),
          ),
        );
        break;
      case 'trash':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TrashPage(),
          ),
        );
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
      case TabView.newFiles:
        return PageId.homeNewFiles; // 新文件Tab使用独立设置
      case TabView.browse:
        return PageId.homeBrowse;
      case TabView.appManagement:
        return PageId.homeBrowse; // 占位，实际上不会被调用
    }
  }

  /// 获取当前页面是否为网格视图
  /// 获取当前页面是否启用分组
  bool _isGroupEnabledForCurrentTab() {
    final currentTab =
        Provider.of<FileViewModel>(context, listen: false).currentTab;

    // 新文件Tab：固定启用时间分组
    if (currentTab == TabView.newFiles) return true;

    final pageId = _getPageIdForCurrentTab(currentTab);
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

    // 计算菜单最大高度：从快捷访问栏下方到屏幕底部，留出底部安全边距
    final availableHeight = overlay.size.height - top - 16.0; // 16.0 为底部留白
    final maxMenuHeight = availableHeight.clamp(200.0, 500.0); // 最小200，最大500

    showMenu<QuickAccessFolder>(
      context: context,
      position: RelativeRect.fromLTRB(
        left,
        top,
        right,
        bottom,
      ),
      items: _buildQuickAccessMenuItems(),
      constraints: BoxConstraints(
        maxHeight: maxMenuHeight,
        maxWidth: menuWidth,
      ),
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
    final allAccessFolders =
        allFolders.where((f) => f.isAddedToQuickAccess).toList();

    // 按类型分组：系统文件夹 和 其他文件夹
    final systemFolders = allAccessFolders
        .where((f) => f.type == QuickAccessFolderType.system)
        .toList();
    final otherTypesFolders = allAccessFolders
        .where((f) => f.type == QuickAccessFolderType.other)
        .toList();

    // 系统文件夹
    for (var folder in systemFolders) {
      items.add(_buildFolderMenuItem(folder, Colors.blue));
    }

    // 添加分隔线
    if (systemFolders.isNotEmpty && otherTypesFolders.isNotEmpty) {
      items.add(const PopupMenuDivider());
    }

    // 其他文件夹
    for (var folder in otherTypesFolders) {
      items.add(_buildFolderMenuItem(folder, Colors.orange));
    }

    // 已恢复文件（固定入口，移除分组标题）
    if (_hasRestoredFiles()) {
      if (items.isNotEmpty) {
        items.add(const PopupMenuDivider());
      }

      const restoredPath = '/storage/emulated/0/EasyFile/Restored';

      // 直接添加已恢复文件夹作为可点击项（移除分组标题和文件数量）
      items.add(
        PopupMenuItem<QuickAccessFolder>(
          value: QuickAccessFolder(
            id: 'restored_files',
            originalName: '回收站恢复',
            path: restoredPath,
            type: QuickAccessFolderType.other,
            createdAt: DateTime.now(),
            isAddedToQuickAccess: true,
            isHidden: false,
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
                  '回收站恢复',
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

  /// 获取文件夹显示名称
  /// - 有用户别名：显示别名
  /// - 无别名：显示原名
  String _getFolderDisplayName(QuickAccessFolder folder) {
    // 优先使用用户设置的别名
    if (folder.userAlias != null && folder.userAlias!.isNotEmpty) {
      return folder.userAlias!;
    }
    
    return folder.originalName;
  }

  /// 构建文件夹菜单项
  PopupMenuItem<QuickAccessFolder> _buildFolderMenuItem(
    QuickAccessFolder folder,
    Color color,
  ) {
    final exists = Directory(folder.path).existsSync();
    final folderIcon = _getFolderIcon(folder);
    final isSubfolder = folder.isSystemSubfolder;
    
    // 子目录用黄色，一级目录用蓝色
    final iconColor = isSubfolder ? Colors.amber[700] : Colors.blue[700];

    return PopupMenuItem<QuickAccessFolder>(
      value: folder,
      enabled: exists,
      padding: EdgeInsets.only(
        left: isSubfolder ? 32.0 : 16.0, // 子目录增加左侧缩进
        right: 16.0,
        top: 10.0,
        bottom: 10.0,
      ),
      child: Row(
        children: [
          Icon(
            folderIcon,
            size: 20,
            color: exists ? iconColor : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _getFolderDisplayName(folder),
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
  /// - 子目录：folder_open（黄色）
  /// - 一级目录和其他：folder（蓝色）
  IconData _getFolderIcon(QuickAccessFolder folder) {
    return folder.isSystemSubfolder ? Icons.folder_open : Icons.folder;
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
          // 收藏 Tab
          _buildNavTab(
            context,
            '收藏',
            Icons.star,
            false, // 不显示高亮，保持视觉简洁
            onTap: () {
              viewModel.setCurrentTab(TabView.favorite);
              presenter.loadFavoriteFiles();
            },
            useColoredIcon: vm.currentTab == TabView.favorite, // 当前Tab时显示彩色
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
            false, // 不显示高亮，保持视觉简洁
            onTap: () {
              viewModel.setCurrentTab(TabView.recent);
              presenter.loadRecentFiles();
            },
            useColoredIcon: vm.currentTab == TabView.recent, // 当前Tab时显示彩色
          ),
          Container(
            width: 1,
            height: 16,
            color: theme.dividerColor,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          // 新文件 Tab
          _buildNavTab(
            context,
            '新文件',
            Icons.fiber_new,
            false, // 不显示高亮，保持视觉简洁
            onTap: () async {
              viewModel.setCurrentTab(TabView.newFiles);
              // 方案1：立即加载缓存（0-100ms），后台刷新（不阻塞UI）
              await presenter.loadCachedNewFiles();
              presenter.refreshNewFilesInBackground();
            },
            useColoredIcon: vm.currentTab == TabView.newFiles, // 当前Tab时显示彩色
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
    bool useColoredIcon = false, // 是否使用彩色图标
    double fontSize = 14, // 字体大小，横屏模式下可传入更小值
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
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.8)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != '快捷访问') ...[
                Icon(
                  icon,
                  size: useColoredIcon ? 17 : 15, // 选中时放大图标
                  // 使用填充图标样式增强视觉效果
                  weight: useColoredIcon ? 600 : 400,
                  fill: useColoredIcon ? 1.0 : 0.0,
                  color: useColoredIcon
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
                    fontSize: fontSize,
                    fontWeight:
                        useColoredIcon ? FontWeight.w600 : FontWeight.normal,
                    color: useColoredIcon
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
            color: Colors.black.withValues(alpha: 0.05),
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
            // 快捷访问 Tab - 占30份宽度
            Expanded(
              flex: 30,
              child: _buildNavTab(
                context,
                '快捷访问',
                Icons.folder_special,
                false,
                onTap: () => _showQuickAccessMenu(context),
                enabled: _hasQuickAccessItems(),
                fontSize: 12,
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
                false, // 不显示高亮，保持视觉简洁
                onTap: () {
                  viewModel.setCurrentTab(TabView.favorite);
                  presenter.loadFavoriteFiles();
                },
                useColoredIcon: vm.currentTab == TabView.favorite, // 当前Tab时显示彩色
                fontSize: 12,
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
                false, // 不显示高亮，保持视觉简洁
                onTap: () {
                  viewModel.setCurrentTab(TabView.recent);
                  presenter.loadRecentFiles();
                },
                useColoredIcon: vm.currentTab == TabView.recent, // 当前Tab时显示彩色
                fontSize: 12,
              ),
            ),
            Container(
              width: 1,
              height: 24,
              color: theme.dividerColor,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            // 新文件 Tab - 占26份宽度（比其他Tab多4份，确保文字能完整显示）
            Expanded(
              flex: 26,
              child: _buildNavTab(
                context,
                '新文件',
                Icons.fiber_new,
                false, // 不显示高亮，保持视觉简洁
                onTap: () async {
                  viewModel.setCurrentTab(TabView.newFiles);
                  // 方案1：立即加载缓存（0-100ms），后台刷新（不阻塞UI）
                  await presenter.loadCachedNewFiles();
                  presenter.refreshNewFilesInBackground();
                },
                useColoredIcon: vm.currentTab == TabView.newFiles, // 当前Tab时显示彩色
                fontSize: 12,
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
          // 编辑模式下显示全选checkbox（最左侧）
          if (isEditMode && vm.files.isNotEmpty)
            SelectAllButton(
              selectedCount: _selectedItems.length,
              totalCount: vm.files.length,
              onPressed: () => handleSelectAll(
                vm.files.map((f) => f.path).toList(),
              ),
              iconSize: 22,
            ),
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
              // 编辑/完成按钮
              EditModeToolbarButton(
                isEditMode: isEditMode,
                onEnterEditMode: enterEditMode,
                onExitEditMode: exitEditMode,
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
          // 编辑模式下显示全选checkbox（最左侧）
          if (isEditMode && vm.files.isNotEmpty)
            SelectAllButton(
              selectedCount: _selectedItems.length,
              totalCount: vm.files.length,
              onPressed: () => handleSelectAll(
                vm.files.map((f) => f.path).toList(),
              ),
              iconSize: 22,
            ),
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
                // 编辑/完成按钮
                EditModeToolbarButton(
                  isEditMode: isEditMode,
                  onEnterEditMode: enterEditMode,
                  onExitEditMode: exitEditMode,
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
          // 编辑模式下显示全选checkbox（最左侧）
          if (isEditMode && vm.files.isNotEmpty)
            SelectAllButton(
              selectedCount: _selectedItems.length,
              totalCount: vm.files.length,
              onPressed: () => handleSelectAll(
                vm.files.map((f) => f.path).toList(),
              ),
              iconSize: 22,
            ),
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
                // 编辑/完成按钮
                EditModeToolbarButton(
                  isEditMode: isEditMode,
                  onEnterEditMode: enterEditMode,
                  onExitEditMode: exitEditMode,
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 构建新文件Tab工具栏
  Widget _buildNewFilesToolBar(
    BuildContext context,
    FileViewModel vm,
  ) {
    final theme = Theme.of(context);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
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
          // 编辑模式下显示全选checkbox（最左侧）
          if (isEditMode && vm.newFiles.isNotEmpty)
            SelectAllButton(
              selectedCount: _selectedItems.length,
              totalCount: vm.newFiles.length,
              onPressed: () => handleSelectAll(
                vm.newFiles.map((f) => f.path).toList(),
              ),
              iconSize: 22,
            ),
          // 标题
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.fiber_new,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '新添加的文件',
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
          if (vm.newFiles.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FileToolbar(
                  pageId: PageId.homeNewFiles, // 新文件Tab使用独立的PageId
                  showSearchButton: true, // 支持搜索
                  showSortButton: false, // 新文件固定按时间排序
                  showGroupButton: false, // 新文件不支持分组
                  showViewModeToggle: true, // 支持列表/网格视图切换
                  iconSize: 18,
                  onSearchPressed: () {
                    setState(() {
                      _newFilesSearchMode = !_newFilesSearchMode;
                      if (!_newFilesSearchMode) {
                        _newFilesSearchQuery = '';
                        _newFilesSearchController.clear();
                      }
                    });
                  },
                  isSearchMode: _newFilesSearchMode,
                ),
                // 编辑/完成按钮
                EditModeToolbarButton(
                  isEditMode: isEditMode,
                  onEnterEditMode: enterEditMode,
                  onExitEditMode: exitEditMode,
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
    final ascending =
        PageSettingsService().getSortAscending(PageId.homeFavorite);
    FileComparatorUtil.sortFilesInPlace(result, sortType, ascending: ascending);

    return result;
  }

  /// 获取排序后的浏览文件列表
  List<FileItem> _getSortedBrowseFiles(List<FileItem> files) {
    final sortType = PageSettingsService().getSortType(PageId.homeBrowse);
    final ascending = PageSettingsService().getSortAscending(PageId.homeBrowse);
    return FileComparatorUtil.sortFiles(files, sortType, ascending: ascending);
  }

  /// 获取收藏文件的日期分组
  Map<String, List<FileItem>> _groupFavoriteFilesByDate(List<FileItem> files) {
    final groups = FileGroupingUtil.groupByAddedDate(files, removeEmpty: false);
    // 调试日志：查看分组情况
    logger.d(
        'Favorite files grouping: ${groups.map((key, value) => MapEntry(key, value.length))}');
    groups.forEach((key, files) {
      if (files.isNotEmpty) {
        logger.d(
            'Group "$key": ${files.length} files, first file addedTime: ${files.first.addedTime}');
      }
    });
    return groups;
  }

  /// 获取浏览文件的日期分组
  Map<String, List<FileItem>> _groupBrowseFilesByDate(List<FileItem> files) {
    return FileGroupingUtil.groupByModifiedDate(files, removeEmpty: false);
  }

  /// 获取最近文件的时间分组（基于访问时间）
  /// 构建收藏Tab的分组视图
  /// 显示排序选项（收藏Tab）
  /// 获取排序方向图标
  /// 按名称/类型：ascending=false显示↑(A-Z), ascending=true显示↓(Z-A)
  /// 按时间/大小：ascending=false显示↓(新→旧/大→小), ascending=true显示↑(旧→新/小→大)
  IconData _getSortDirectionIcon(SortType sortType, bool ascending) {
    if (sortType == SortType.name || sortType == SortType.fileType) {
      // 按名称/类型：反转箭头显示
      return ascending ? Icons.arrow_downward : Icons.arrow_upward;
    } else {
      // 按时间/大小：正常箭头显示
      return ascending ? Icons.arrow_upward : Icons.arrow_downward;
    }
  }

  void _showFavoriteSortOptions() {
    final currentSortType =
        PageSettingsService().getSortType(PageId.homeFavorite);
    final currentAscending =
        PageSettingsService().getSortAscending(PageId.homeFavorite);

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
                    ? Icon(
                        _getSortDirectionIcon(SortType.name, currentAscending))
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  if (currentSortType == SortType.name) {
                    await PageSettingsService()
                        .toggleSortDirection(PageId.homeFavorite);
                  } else {
                    await PageSettingsService()
                        .setSortType(PageId.homeFavorite, SortType.name);
                  }
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('按修改时间排序'),
                trailing: currentSortType == SortType.modifiedTime
                    ? Icon(_getSortDirectionIcon(
                        SortType.modifiedTime, currentAscending))
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  if (currentSortType == SortType.modifiedTime) {
                    await PageSettingsService()
                        .toggleSortDirection(PageId.homeFavorite);
                  } else {
                    await PageSettingsService().setSortType(
                        PageId.homeFavorite, SortType.modifiedTime);
                  }
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('按文件大小排序'),
                trailing: currentSortType == SortType.size
                    ? Icon(
                        _getSortDirectionIcon(SortType.size, currentAscending))
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  if (currentSortType == SortType.size) {
                    await PageSettingsService()
                        .toggleSortDirection(PageId.homeFavorite);
                  } else {
                    await PageSettingsService()
                        .setSortType(PageId.homeFavorite, SortType.size);
                  }
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.category),
                title: const Text('按文件类型排序'),
                trailing: currentSortType == SortType.fileType
                    ? Icon(_getSortDirectionIcon(
                        SortType.fileType, currentAscending))
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  if (currentSortType == SortType.fileType) {
                    await PageSettingsService()
                        .toggleSortDirection(PageId.homeFavorite);
                  } else {
                    await PageSettingsService()
                        .setSortType(PageId.homeFavorite, SortType.fileType);
                  }
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
    final currentAscending =
        PageSettingsService().getSortAscending(PageId.homeBrowse);

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
                    ? Icon(
                        _getSortDirectionIcon(SortType.name, currentAscending))
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  if (currentSortType == SortType.name) {
                    await PageSettingsService()
                        .toggleSortDirection(PageId.homeBrowse);
                  } else {
                    await PageSettingsService()
                        .setSortType(PageId.homeBrowse, SortType.name);
                  }
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('按修改时间排序'),
                trailing: currentSortType == SortType.modifiedTime
                    ? Icon(_getSortDirectionIcon(
                        SortType.modifiedTime, currentAscending))
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  if (currentSortType == SortType.modifiedTime) {
                    await PageSettingsService()
                        .toggleSortDirection(PageId.homeBrowse);
                  } else {
                    await PageSettingsService()
                        .setSortType(PageId.homeBrowse, SortType.modifiedTime);
                  }
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('按文件大小排序'),
                trailing: currentSortType == SortType.size
                    ? Icon(
                        _getSortDirectionIcon(SortType.size, currentAscending))
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  if (currentSortType == SortType.size) {
                    await PageSettingsService()
                        .toggleSortDirection(PageId.homeBrowse);
                  } else {
                    await PageSettingsService()
                        .setSortType(PageId.homeBrowse, SortType.size);
                  }
                  setState(() {}); // 刷新列表
                },
              ),
              ListTile(
                leading: const Icon(Icons.category),
                title: const Text('按文件类型排序'),
                trailing: currentSortType == SortType.fileType
                    ? Icon(_getSortDirectionIcon(
                        SortType.fileType, currentAscending))
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  if (currentSortType == SortType.fileType) {
                    await PageSettingsService()
                        .toggleSortDirection(PageId.homeBrowse);
                  } else {
                    await PageSettingsService()
                        .setSortType(PageId.homeBrowse, SortType.fileType);
                  }
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
                  .where((f) => f.isAddedToQuickAccess && !f.isHidden)
                  .toList();

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

      case TabView.newFiles:
        if (isSearchMode) {
          icon = Icons.search_off;
          title = '未找到匹配的文件';
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
          icon = Icons.fiber_new;
          title = '暂无新添加的文件';
          subtitleWidget = Text(
            '这里会显示最近新增的照片、视频、文档等文件',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          );
          actionButton = ElevatedButton.icon(
            onPressed: () async {
              // 刷新新文件列表
              await presenter.refreshNewFiles();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
          );
        }
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
                    .where((f) => f.isAddedToQuickAccess && !f.isHidden)
                    .toList();

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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height * 0.6,
          ),
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
    // 根据不同Tab检查对应的列表是否为空
    final isEmpty = vm.currentTab == TabView.newFiles
        ? vm.newFiles.isEmpty
        : vm.files.isEmpty;

    if (isEmpty) {
      // 空状态
      final isSearchMode =
          (vm.currentTab == TabView.browse && vm.isSearchMode) ||
              (vm.currentTab == TabView.favorite && _favoriteSearchMode) ||
              (vm.currentTab == TabView.newFiles && _newFilesSearchMode);
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
            (file.category == FileCategory.image ||
                file.category == FileCategory.video);
        if (shouldUseCompactMode) {
          final showFileInfo =
              PageSettingsService().getGridShowFileInfo(pageId);
          return UnifiedViewConfig.fromContext(context,
              compactMode: !showFileInfo,
              showCreationTime: vm.currentTab == TabView.newFiles);
        }
        return null;
      };
    }

    // 收藏Tab、浏览Tab、最近Tab、新文件Tab需要应用排序
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
    } else if (vm.currentTab == TabView.newFiles) {
      // 新文件Tab：使用newFiles列表（已按发现时间排序）
      displayFiles = vm.newFiles;

      // 应用搜索过滤
      if (_newFilesSearchMode && _newFilesSearchQuery.isNotEmpty) {
        displayFiles = displayFiles.where((file) {
          return file.name
              .toLowerCase()
              .contains(_newFilesSearchQuery.toLowerCase());
        }).toList();
      }
    }

    // 收藏Tab、浏览Tab、新文件Tab启用分组时使用分组视图
    if (isGroupEnabled) {
      if (vm.currentTab == TabView.favorite) {
        return _buildFavoriteGroupedViewSlivers(
            displayFiles, viewConfigBuilder);
      } else if (vm.currentTab == TabView.browse) {
        return _buildBrowseGroupedViewSlivers(displayFiles, viewConfigBuilder);
      } else if (vm.currentTab == TabView.newFiles) {
        return _buildNewFilesGroupedViewSlivers(
            displayFiles, viewConfigBuilder);
      }
    }

    // 非分组视图：列表或网格
    return _buildSimpleFileViewSlivers(
        displayFiles, isGridView, pageId, viewConfigBuilder);
  }

  /// 构建简单列表/网格的Sliver组件
  List<Widget> _buildSimpleFileViewSlivers(
      List<FileItem> files,
      bool isGridView,
      PageId pageId,
      UnifiedViewConfig? Function(FileItem)? viewConfigBuilder) {
    if (isGridView) {
      // 网格视图 - 根据屏幕方向计算可用宽度
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      final isLandscape = screenWidth > screenHeight;

      // 横屏模式下，右侧文件浏览区约占55%宽度
      final availableWidth = isLandscape ? screenWidth * 0.55 : screenWidth;
      final crossAxisCount = _calculateCrossAxisCount(availableWidth);

      return [
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 1,
              crossAxisSpacing: 1,
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
  int _calculateCrossAxisCount(double availableWidth) {
    const minCardWidth = 95.0; // 最小卡片宽度，平衡清晰度和数量
    const spacing = 1.0;
    const horizontalPadding = 16.0;
    final effectiveWidth = availableWidth - horizontalPadding;

    int crossAxisCount =
        ((effectiveWidth + spacing) / (minCardWidth + spacing)).floor();

    // 动态调整上限：给横屏右侧区域更多列数
    final maxColumns = effectiveWidth < 500 ? 4 : 6;
    return crossAxisCount.clamp(3, maxColumns);
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
        key: ValueKey('browser_grid_${item.path}'),
        file: item,
        isSelected: isSelected,
        showCheckbox: isEditMode,
        isFavorite: vm.isFavoriteFile(item.path),
        showFavoriteButton: true,
        config: viewConfig,
        onTap: () {
          if (isEditMode || isSelectionMode) {
            _selectionController.toggle(item.path);
          } else {
            _onFileTap(item, vm);
          }
        },
        onLongPress: () {
          // 编辑模式下禁用长按（避免与选择操作冲突）
          if (isEditMode) return;

          // 正常模式下显示单文件操作菜单
          _showSingleFileOperationsMenu(context, item);
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
        showCreationTime: vm.currentTab == TabView.newFiles,
        creationTime: vm.currentTab == TabView.newFiles ? item.modified : null,
        isFavorite: vm.isFavoriteFile(item.path),
        isSelected: isSelected,
        showCheckbox: isEditMode,
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
          if (isEditMode || isSelectionMode) {
            _selectionController.toggle(item.path);
          } else {
            _onFileTap(item, vm);
          }
        },
        onLongPress: () {
          // 编辑模式下禁用长按（避免与选择操作冲突）
          if (isEditMode) return;

          // 正常模式下显示单文件操作菜单
          _showSingleFileOperationsMenu(context, item);
        },
      );
    }
  }

  /// 显示单文件操作菜单
  void _showSingleFileOperationsMenu(BuildContext context, FileItem file) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SingleFileOperationsSheet(
        file: file,
        service: _singleFileOperationsService,
      ),
    );
  }

  /// 构建收藏Tab分组视图的Sliver组件
  /// 构建新文件Tab的时间分组视图
  List<Widget> _buildNewFilesGroupedViewSlivers(
    List<FileItem> files,
    UnifiedViewConfig? Function(FileItem)? viewConfigBuilder,
  ) {
    final isGridView =
        PageSettingsService().getViewMode(PageId.homeNewFiles) == ViewMode.grid;

    // 从 viewModel 获取 retentionDays 设置
    final retentionDays = viewModel.newFilesRetentionDays;
    final groups = _groupFilesByDateWithRetention(files, retentionDays);
    final groupKeys = _getGroupKeysForRetention(retentionDays);

    // 根据屏幕方向计算可用宽度
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape = screenWidth > screenHeight;
    final availableWidth = isLandscape ? screenWidth * 0.55 : screenWidth;
    final crossAxisCount = _calculateCrossAxisCount(availableWidth);

    return _buildGroupedSlivers(
      groupKeys: groupKeys,
      groups: groups,
      isGridView: isGridView,
      crossAxisCount: crossAxisCount,
      viewConfigBuilder: viewConfigBuilder,
    );
  }

  List<Widget> _buildGroupedSlivers({
    required List<String> groupKeys,
    required Map<String, List<FileItem>> groups,
    required bool isGridView,
    required int crossAxisCount,
    required UnifiedViewConfig? Function(FileItem)? viewConfigBuilder,
  }) {
    List<Widget> slivers = [];
    for (final key in groupKeys) {
      if (groups.containsKey(key) && groups[key]!.isNotEmpty) {
        final count = groups[key]!.length;
        // 分组头部
        slivers.add(
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                  crossAxisSpacing: 1,
                  mainAxisSpacing: 1,
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
                (context, index) => _buildFileItemWrapper(groups[key]![index],
                    viewConfigBuilder: viewConfigBuilder),
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

  /// 将文件按日期分组（用于新文件Tab）- 根据保留天数动态分组
  /// 分组规则：今天 → 昨天 → 近N天
  Map<String, List<FileItem>> _groupFilesByDateWithRetention(
      List<FileItem> files, int retentionDays) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final groups = <String, List<FileItem>>{
      '今天': [],
      '昨天': [],
      '近$retentionDays天': [],
    };

    for (final file in files) {
      final modifiedDate = file.modified;
      final fileDate =
          DateTime(modifiedDate.year, modifiedDate.month, modifiedDate.day);

      if (fileDate.isAtSameMomentAs(today)) {
        groups['今天']!.add(file);
      } else if (fileDate.isAtSameMomentAs(yesterday)) {
        groups['昨天']!.add(file);
      } else {
        // 其他所有文件都归入"近N天"
        groups['近$retentionDays天']!.add(file);
      }
    }

    return groups;
  }

  /// 获取分组键列表（根据保留天数）
  List<String> _getGroupKeysForRetention(int retentionDays) {
    return ['今天', '昨天', '近$retentionDays天'];
  }

  List<Widget> _buildFavoriteGroupedViewSlivers(
    List<FileItem> files,
    UnifiedViewConfig? Function(FileItem)? viewConfigBuilder,
  ) {
    final isGridView =
        PageSettingsService().getViewMode(PageId.homeFavorite) == ViewMode.grid;
    final groups = _groupFavoriteFilesByDate(files);
    final groupKeys = ['今天', '昨天', '本周', '本月', '更早'];

    // 根据屏幕方向计算可用宽度
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape = screenWidth > screenHeight;
    final availableWidth = isLandscape ? screenWidth * 0.55 : screenWidth;
    final crossAxisCount = _calculateCrossAxisCount(availableWidth);

    return _buildGroupedSlivers(
      groupKeys: groupKeys,
      groups: groups,
      isGridView: isGridView,
      crossAxisCount: crossAxisCount,
      viewConfigBuilder: viewConfigBuilder,
    );
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

    // 根据屏幕方向计算可用宽度
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape = screenWidth > screenHeight;
    final availableWidth = isLandscape ? screenWidth * 0.55 : screenWidth;
    final crossAxisCount = _calculateCrossAxisCount(availableWidth);

    return _buildGroupedSlivers(
      groupKeys: groupKeys,
      groups: groups,
      isGridView: isGridView,
      crossAxisCount: crossAxisCount,
      viewConfigBuilder: viewConfigBuilder,
    );
  }

  /// 构建列表/网格视图（使用FileCollectionView）
  /// 处理文件点击
  void _onFileTap(FileItem file, FileViewModel vm) {
    // 编辑模式下，点击文件/文件夹自动进入选择模式并选中
    if (isEditMode && !_selectionController.isSelectionMode) {
      // 提示会自动隐藏，无需手动设置
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
          // 2. 最近/收藏Tab - 左右滑切换Tab（仅在列表顶部触发）
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity == null) {
              return;
            }

            final velocity = details.primaryVelocity!;
            final isSwipeRight = velocity > 500; // 右滑
            final isSwipeLeft = velocity < -500; // 左滑

            // 搜索模式下禁用所有手势
            if (vm.isSearchMode || _favoriteSearchMode || _newFilesSearchMode) {
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

            // 功能2: 在最近/收藏/新文件Tab之间左右滑动切换
            // 限制：仅在列表顶部（滚动偏移 < 50）时才允许切换Tab，避免滑动列表时误触发
            if (_scrollController.hasClients && _scrollController.offset > 50) {
              return; // 列表已滚动，禁用Tab切换手势
            }

            if (vm.currentTab == TabView.recent) {
              if (isSwipeLeft) {
                // 最近Tab左滑 → 切换到收藏Tab
                viewModel.setCurrentTab(TabView.favorite);
                presenter.loadFavoriteFiles();
              } else if (isSwipeRight) {
                // 最近Tab右滑 → 切换到新文件Tab
                viewModel.setCurrentTab(TabView.newFiles);
                presenter.loadNewFiles();
              }
            } else if (vm.currentTab == TabView.favorite && isSwipeRight) {
              // 收藏Tab右滑 → 切换到最近Tab
              viewModel.setCurrentTab(TabView.recent);
              presenter.loadRecentFiles();
            } else if (vm.currentTab == TabView.newFiles && isSwipeLeft) {
              // 新文件Tab左滑 → 切换到最近Tab
              viewModel.setCurrentTab(TabView.recent);
              presenter.loadRecentFiles();
            }
          },
          child: RefreshIndicator(
            onRefresh: () async {
              await presenter.refreshCurrent();
            },
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // CategoryNavBar 和 QuickAccessSection：可滚动查看（横竖屏都显示）
                if (!(vm.currentTab == TabView.browse && vm.isSearchMode) &&
                    !(vm.currentTab == TabView.favorite &&
                        _favoriteSearchMode) &&
                    !(vm.currentTab == TabView.newFiles &&
                        _newFilesSearchMode)) ...[
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
                      key: QuickAccessSection.globalKey,
                      quickAccessViewModel: quickAccessViewModel!,
                      quickAccessPresenter: quickAccessPresenter!,
                      fileViewModel: vm,
                      filePresenter: presenter,
                      categoryCardSize: _categoryCardSize,
                      recommendationService: _recommendationService,
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
                      height: 40.0,
                    ),
                  ),

                // 编辑模式提示 - 显示在编辑按钮下一行（Recent Tab）
                if (vm.currentTab == TabView.recent &&
                    isEditMode &&
                    showEditModeHint)
                  const SliverToBoxAdapter(
                    child: EditModeHintBar(),
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
                      height: 40.0,
                    ),
                  ),

                // 编辑模式提示 - 显示在编辑按钮下一行（Browse Tab）
                if (vm.currentTab == TabView.browse &&
                    isEditMode &&
                    showEditModeHint &&
                    !vm.isSearchMode)
                  const SliverToBoxAdapter(
                    child: EditModeHintBar(),
                  ),

                // 收藏Tab工具栏 - favorite模式固定显示（包括搜索模式）
                if (vm.currentTab == TabView.favorite)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: PinnedHeaderDelegate(
                      child: _buildFavoriteToolBar(context, vm),
                      height: 40.0,
                    ),
                  ),

                // 新文件Tab工具栏
                if (vm.currentTab == TabView.newFiles)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: PinnedHeaderDelegate(
                      child: _buildNewFilesToolBar(context, vm),
                      height: 40.0,
                    ),
                  ),

                // 编辑模式提示 - 显示在编辑按钮下一行（新文件Tab，搜索时隐藏）
                if (vm.currentTab == TabView.newFiles &&
                    isEditMode &&
                    showEditModeHint &&
                    !_newFilesSearchMode)
                  const SliverToBoxAdapter(
                    child: EditModeHintBar(),
                  ),

                // 编辑模式提示 - 显示在编辑按钮下一行（收藏Tab，搜索时隐藏）
                if (vm.currentTab == TabView.favorite &&
                    isEditMode &&
                    showEditModeHint &&
                    !_favoriteSearchMode)
                  const SliverToBoxAdapter(
                    child: EditModeHintBar(),
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

                // 新文件Tab的搜索栏
                if (vm.currentTab == TabView.newFiles && _newFilesSearchMode)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: PinnedHeaderDelegate(
                      child: FileSearchBar(
                        controller: _newFilesSearchController,
                        focusNode: _newFilesSearchFocusNode,
                        hintText: '搜索新文件...',
                        onSearch: (query) async {
                          setState(() {
                            _newFilesSearchQuery = query;
                          });
                        },
                        onClose: () {
                          setState(() {
                            _newFilesSearchQuery = '';
                            _newFilesSearchController.clear();
                            _newFilesSearchMode = false;
                          });
                        },
                        onChanged: (query) {
                          setState(() {
                            _newFilesSearchQuery = query;
                          });
                        },
                      ),
                      height: 56.0,
                    ),
                  ),

                // 新建文件夹按钮 - 仅在 Browse Tab 编辑模式下显示
                if (vm.currentTab == TabView.browse &&
                    isEditMode &&
                    !vm.isSearchMode)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton.icon(
                        onPressed: showCreateFolderDialog,
                        icon: const Icon(Icons.create_new_folder),
                        label: const Text('新建文件夹'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                      color: Colors.black.withValues(alpha: 0.05),
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
                            key: QuickAccessSection.globalKey,
                            quickAccessViewModel: quickAccessViewModel!,
                            quickAccessPresenter: quickAccessPresenter!,
                            fileViewModel: vm,
                            filePresenter: presenter,
                            categoryCardSize: _categoryCardSize,
                            recommendationService: _recommendationService,
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
                    controller: _landscapeRightScrollController,
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
                      if (vm.currentTab == TabView.recent &&
                          isEditMode &&
                          showEditModeHint &&
                          !_selectionController.isSelectionMode)
                        const SliverToBoxAdapter(
                          child: EditModeHintBar(),
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
                      if (vm.currentTab == TabView.browse &&
                          isEditMode &&
                          showEditModeHint &&
                          !vm.isSearchMode)
                        const SliverToBoxAdapter(
                          child: EditModeHintBar(),
                        ),

                      // 收藏Tab工具栏 - favorite模式固定显示（包括搜索模式）
                      if (vm.currentTab == TabView.favorite)
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: PinnedHeaderDelegate(
                            child: _buildFavoriteToolBar(context, vm),
                            height: 48.0,
                          ),
                        ),

                      // 编辑模式提示 - 显示在编辑按钮下一行（Favorite Tab 横屏，搜索时隐藏）
                      if (vm.currentTab == TabView.favorite &&
                          isEditMode &&
                          showEditModeHint &&
                          !_selectionController.isSelectionMode &&
                          !_favoriteSearchMode)
                        const SliverToBoxAdapter(
                          child: EditModeHintBar(),
                        ),

                      // 新文件Tab工具栏 - 横屏模式
                      if (vm.currentTab == TabView.newFiles)
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: PinnedHeaderDelegate(
                            child: _buildNewFilesToolBar(context, vm),
                            height: 48.0,
                          ),
                        ),

                      // 编辑模式提示 - 显示在编辑按钮下一行（NewFiles Tab 横屏）
                      if (vm.currentTab == TabView.newFiles &&
                          isEditMode &&
                          showEditModeHint &&
                          !_selectionController.isSelectionMode &&
                          !_newFilesSearchMode)
                        const SliverToBoxAdapter(
                          child: EditModeHintBar(),
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

                      // 新文件Tab的搜索栏 - 横屏模式
                      if (vm.currentTab == TabView.newFiles &&
                          _newFilesSearchMode)
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: PinnedHeaderDelegate(
                            child: FileSearchBar(
                              controller: _newFilesSearchController,
                              focusNode: _newFilesSearchFocusNode,
                              hintText: '搜索新文件...',
                              onSearch: (query) async {
                                setState(() {
                                  _newFilesSearchQuery = query;
                                });
                              },
                              onClose: () {
                                setState(() {
                                  _newFilesSearchQuery = '';
                                  _newFilesSearchController.clear();
                                  _newFilesSearchMode = false;
                                });
                              },
                              onChanged: (query) {
                                setState(() {
                                  _newFilesSearchQuery = query;
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
                      if (vm.currentTab == TabView.browse &&
                          isEditMode &&
                          !vm.isSearchMode)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: FilledButton.icon(
                              onPressed: showCreateFolderDialog,
                              icon: const Icon(Icons.create_new_folder),
                              label: const Text('新建文件夹'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
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
            left: leftPaneWidth, // 从右侧区域开始
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

    // 如果正在初始化依赖，显示加载中
    if (_isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 如果正在执行首次初始化扫描，显示进度UI
    if (_isScanning && _scanProgress > 0) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  value: _scanProgress,
                  strokeWidth: 8,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '应用初始化中...',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${(_scanProgress * 100).toInt()}%',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                _getInitStageDescription(_scanProgress),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],
          ),
        ),
      );
    }

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

              return wrapWithPopScope(
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
                              value: 'app_management',
                              child: Row(
                                children: [
                                  Icon(Icons.apps),
                                  SizedBox(width: 8),
                                  Text('应用管理'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'manage_quick_access',
                              child: Row(
                                children: [
                                  Icon(Icons.folder_special),
                                  SizedBox(width: 8),
                                  Text('快速访问管理'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'trash',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline),
                                  SizedBox(width: 8),
                                  Text('回收站'),
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

                      // 计算左侧面板宽度（与 _buildLandscapeLayout 中的逻辑一致）
                      final portraitWidth =
                          math.min(constraints.maxWidth, constraints.maxHeight);
                      final leftPaneWidth = isLandscape
                          ? math.max(portraitWidth, constraints.maxWidth * 0.45)
                          : 0.0;

                      // 根据屏幕方向选择不同的布局
                      return Stack(
                        children: [
                          isLandscape
                              ? _buildLandscapeLayout(viewModel, constraints)
                              : _buildPortraitLayout(viewModel),

                          // 批量操作底部工具栏 - 横屏时只显示在右侧区域
                          if (isEditMode)
                            Positioned(
                              left: leftPaneWidth,
                              right: 0,
                              bottom: 0,
                              child: _buildSelectionBottomBar(),
                            ),
                        ],
                      );
                    },
                  ),
                );
              },
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
        // 批量操作完成后，总是退出编辑模式
        exitEditMode();
      },
    );
  }

  /// 根据初始化进度返回阶段描述
  String _getInitStageDescription(double progress) {
    if (progress < 0.15) {
      return '正在加载基础资源...';
    } else if (progress < 0.30) {
      return '正在加载分类统计...';
    } else if (progress < 0.95) {
      return '正在扫描文件系统...';
    } else {
      return '即将完成...';
    }
  }

}
