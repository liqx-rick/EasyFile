import 'dart:io';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/data/sources/quick_access_local_source.dart';
import 'package:easyfile/data/services/smart_app_scanner.dart';
import 'package:easyfile/data/services/user_folder_detector.dart';
import 'package:easyfile/data/services/alias_recommendation_service.dart';
import 'package:easyfile/viewmodel/quick_access_viewmodel.dart';
import 'package:easyfile/ui/widgets/new_folder_notification.dart';

/// 快速访问业务逻辑处理层
class QuickAccessPresenter {
  final QuickAccessLocalSource _localSource;
  final QuickAccessViewModel _viewModel;
  final SmartAppScanner _appScanner;
  final UserFolderDetector _userDetector;
  final AliasRecommendationService _aliasService;
  final NewFolderNotificationService _notificationService;

  QuickAccessPresenter({
    required QuickAccessLocalSource localSource,
    required QuickAccessViewModel viewModel,
    required SmartAppScanner appScanner,
    required UserFolderDetector userDetector,
    required AliasRecommendationService aliasService,
    required NewFolderNotificationService notificationService,
  }) : _localSource = localSource,
       _viewModel = viewModel,
       _appScanner = appScanner,
       _userDetector = userDetector,
       _aliasService = aliasService,
       _notificationService = notificationService;

  /// 加载所有快速访问文件夹
  Future<void> loadQuickAccessFolders() async {
    logger.i('QuickAccessPresenter.loadQuickAccessFolders called');
    _viewModel.setLoading(true);

    try {
      final folders = await _localSource.getAllFolders();
      _viewModel.setFolders(folders);
      logger.i('Loaded ${folders.length} quick access folders');
    } catch (e, stackTrace) {
      logger.e('Error loading quick access folders: $e\n$stackTrace');
      _viewModel.setError('加载快速访问失败');
    } finally {
      _viewModel.setLoading(false);
    }
  }

  /// 添加文件夹
  Future<bool> addFolder(QuickAccessFolder folder) async {
    logger.i('QuickAccessPresenter.addFolder called: ${folder.path}');
    try {
      final success = await _localSource.addFolder(folder);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error adding folder: $e');
      return false;
    }
  }

  /// 删除文件夹
  Future<bool> removeFolder(String id) async {
    logger.i('QuickAccessPresenter.removeFolder called: $id');
    try {
      final success = await _localSource.removeFolder(id);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error removing folder: $e');
      return false;
    }
  }

  /// 更新文件夹
  Future<bool> updateFolder(QuickAccessFolder folder) async {
    logger.i('QuickAccessPresenter.updateFolder called: ${folder.path}');
    try {
      final success = await _localSource.updateFolder(folder);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error updating folder: $e');
      return false;
    }
  }

  /// 切换置顶状态
  Future<bool> togglePin(String path) async {
    logger.i('QuickAccessPresenter.togglePin called: $path');
    try {
      final success = await _localSource.togglePin(path);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error toggling pin: $e');
      return false;
    }
  }

  /// 设置用户别名
  Future<bool> setUserAlias(String id, String? alias) async {
    logger.i('QuickAccessPresenter.setUserAlias called: $id -> $alias');
    try {
      final success = await _localSource.setAlias(id, alias ?? '');
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error setting user alias: $e');
      return false;
    }
  }

  /// 更新访问信息
  Future<void> updateAccessInfo(String path) async {
    logger.d('QuickAccessPresenter.updateAccessInfo called: $path');
    try {
      await _localSource.updateAccessInfo(path);
      // 不需要刷新整个列表，只更新访问时间
    } catch (e) {
      logger.w('Error updating access info: $e');
    }
  }

  /// 执行首次应用扫描（Tier1）
  Future<ScanResult> performFirstTimeScan() async {
    logger.i('QuickAccessPresenter.performFirstTimeScan called');
    _viewModel.setScanning(true);

    try {
      final newFolders = await _appScanner.firstTimeScan();
      logger.i('First-time scan found ${newFolders.length} folders');

      // 批量添加新发现的文件夹
      int addedCount = 0;
      for (final folder in newFolders) {
        final added = await _localSource.addFolder(
          folder.toQuickAccessFolder(),
        );
        if (added) addedCount++;
      }

      await loadQuickAccessFolders();

      return ScanResult(
        totalFound: newFolders.length,
        newlyAdded: addedCount,
        alreadyExists: newFolders.length - addedCount,
      );
    } catch (e, stackTrace) {
      logger.e('Error performing first-time scan: $e\n$stackTrace');
      return ScanResult(totalFound: 0, newlyAdded: 0, alreadyExists: 0);
    } finally {
      _viewModel.setScanning(false);
    }
  }

  /// 执行增量扫描（带通知）
  Future<ScanResult> performIncrementalScanWithNotification() async {
    logger.i(
      'QuickAccessPresenter.performIncrementalScanWithNotification called',
    );
    _viewModel.setScanning(true);

    try {
      final newFolders = await _appScanner.incrementalScan();
      logger.i('Incremental scan found ${newFolders.length} new folders');

      if (newFolders.isNotEmpty) {
        // 转换为 QuickAccessFolder 然后通知用户
        final quickAccessFolders = newFolders
            .map((f) => f.toQuickAccessFolder())
            .toList();
        _notificationService.addNewFolders(quickAccessFolders);
      }

      await loadQuickAccessFolders();

      return ScanResult(
        totalFound: newFolders.length,
        newlyAdded: 0, // 不自动添加，等待用户确认
        alreadyExists: 0,
      );
    } catch (e, stackTrace) {
      logger.e('Error performing incremental scan: $e\n$stackTrace');
      return ScanResult(totalFound: 0, newlyAdded: 0, alreadyExists: 0);
    } finally {
      _viewModel.setScanning(false);
    }
  }

  /// 执行增量扫描（原方法，直接添加）
  Future<ScanResult> performIncrementalScan() async {
    logger.i('QuickAccessPresenter.performIncrementalScan called');
    _viewModel.setScanning(true);

    try {
      final appFolders = await _appScanner.incrementalScan();
      logger.i('Incremental scan found ${appFolders.length} app folders');

      final scannedFolders = appFolders
          .map((f) => f.toQuickAccessFolder())
          .toList();
      final counts = _countFolderTypes(scannedFolders);

      int newlyAdded = 0;
      int alreadyExists = 0;
      int skippedHidden = 0;

      for (final folder in scannedFolders) {
        final result = await _localSource.addFolderWithResult(
          folder,
          unhideIfHidden: false,
        );
        switch (result) {
          case AddFolderResult.added:
            newlyAdded++;
            break;
          case AddFolderResult.exists:
            alreadyExists++;
            break;
          case AddFolderResult.skippedHidden:
            // 跳过隐藏的，不计入有效发现
            skippedHidden++;
            break;
          case AddFolderResult.unhidden:
          case AddFolderResult.error:
            // 这些情况理论上不会发生（unhideIfHidden: false）
            break;
        }
      }

      await loadQuickAccessFolders();

      return ScanResult(
        totalFound: scannedFolders.length - skippedHidden,
        newlyAdded: newlyAdded,
        alreadyExists: alreadyExists,
        unhidden: 0, // 增量扫描不恢复隐藏项
        systemCount: counts['system']!,
        appRootCount: counts['appRoot']!,
        appSubCount: counts['appSub']!,
        userCustomCount: counts['userCustom']!,
      );
    } catch (e, stackTrace) {
      logger.e('Error performing incremental scan: $e\n$stackTrace');
      return ScanResult(totalFound: 0, newlyAdded: 0, alreadyExists: 0);
    } finally {
      _viewModel.setScanning(false);
    }
  }

  /// 执行用户主动扫描（Tier1+2 + 系统目录，不恢复隐藏项）
  Future<ScanResult> performUserInitiatedScan() async {
    logger.i('QuickAccessPresenter.performUserInitiatedScan called');
    _viewModel.setScanning(true);

    try {
      // 1. 扫描应用目录 (Tier1+2)
      final appFolders = await _appScanner.userInitiatedScan();
      logger.i('User-initiated scan found ${appFolders.length} app folders');

      // 2. 扫描系统目录
      final systemFolders = await _scanSystemDirectories();
      logger.i(
        'User-initiated scan found ${systemFolders.length} system folders',
      );

      // 合并扫描结果
      final scannedFolders = [
        ...appFolders.map((f) => f.toQuickAccessFolder()),
        ...systemFolders,
      ];

      final counts = _countFolderTypes(scannedFolders);

      int newlyAdded = 0;
      int alreadyExists = 0;
      int skippedHidden = 0;

      for (final folder in scannedFolders) {
        final result = await _localSource.addFolderWithResult(
          folder,
          unhideIfHidden: false,
        );
        switch (result) {
          case AddFolderResult.added:
            newlyAdded++;
            break;
          case AddFolderResult.exists:
            alreadyExists++;
            break;
          case AddFolderResult.skippedHidden:
            // 跳过隐藏的，不计入有效发现
            skippedHidden++;
            break;
          case AddFolderResult.unhidden:
          case AddFolderResult.error:
            // 这些情况理论上不会发生（unhideIfHidden: false）
            break;
        }
      }

      await loadQuickAccessFolders();

      return ScanResult(
        totalFound: scannedFolders.length - skippedHidden,
        newlyAdded: newlyAdded,
        alreadyExists: alreadyExists,
        unhidden: 0, // 常规扫描不恢复隐藏项
        systemCount: counts['system']!,
        appRootCount: counts['appRoot']!,
        appSubCount: counts['appSub']!,
        userCustomCount: counts['userCustom']!,
      );
    } catch (e, stackTrace) {
      logger.e('Error performing user-initiated scan: $e\n$stackTrace');
      return ScanResult(totalFound: 0, newlyAdded: 0, alreadyExists: 0);
    } finally {
      _viewModel.setScanning(false);
    }
  }

  /// 执行深度扫描（全部Tier + 系统目录 + 用户目录）
  Future<ScanResult> performDeepScan() async {
    logger.i('QuickAccessPresenter.performDeepScan called');
    _viewModel.setScanning(true);

    try {
      // 1. 扫描应用目录
      final appFolders = await _appScanner.deepScan();
      logger.i('Deep scan found ${appFolders.length} app folders');

      // 2. 扫描系统目录
      final systemFolders = await _scanSystemDirectories();
      logger.i('Deep scan found ${systemFolders.length} system folders');

      // 3. 检测用户目录
      final userFolders = await _userDetector.detectUserFolders();
      logger.i('Deep scan found ${userFolders.length} user folders');

      // 合并所有扫描结果
      final allScannedFolders = [
        ...appFolders.map((f) => f.toQuickAccessFolder()),
        ...systemFolders,
        ...userFolders.map((f) => f.toQuickAccessFolder()),
      ];

      logger.i('Deep scan total: ${allScannedFolders.length} folders');

      int newlyAdded = 0;
      int unhidden = 0;
      int alreadyExists = 0;

      // 按类型统计
      int systemCount = 0;
      int appRootCount = 0;
      int appSubCount = 0;
      int userCustomCount = 0;

      for (final folder in allScannedFolders) {
        // 统计类型
        switch (folder.type) {
          case QuickAccessFolderType.system:
            systemCount++;
            break;
          case QuickAccessFolderType.appRoot:
            appRootCount++;
            break;
          case QuickAccessFolderType.appSubfolder:
            appSubCount++;
            break;
          case QuickAccessFolderType.userCustom:
            userCustomCount++;
            break;
        }

        // 深度扫描会恢复隐藏项（unhideIfHidden默认为true）
        final result = await _localSource.addFolderWithResult(folder);
        switch (result) {
          case AddFolderResult.added:
            newlyAdded++;
            break;
          case AddFolderResult.unhidden:
            unhidden++;
            break;
          case AddFolderResult.exists:
            alreadyExists++;
            break;
          case AddFolderResult.skippedHidden:
          case AddFolderResult.error:
            // 这些情况理论上不会发生（深度扫描使用默认的unhideIfHidden: true）
            break;
        }
      }

      await loadQuickAccessFolders();

      return ScanResult(
        totalFound: allScannedFolders.length,
        newlyAdded: newlyAdded,
        alreadyExists: alreadyExists,
        unhidden: unhidden,
        systemCount: systemCount,
        appRootCount: appRootCount,
        appSubCount: appSubCount,
        userCustomCount: userCustomCount,
      );
    } catch (e, stackTrace) {
      logger.e('Error performing deep scan: $e\n$stackTrace');
      return ScanResult(totalFound: 0, newlyAdded: 0, alreadyExists: 0);
    } finally {
      _viewModel.setScanning(false);
    }
  }

  /// 检测用户自定义文件夹（不恢复隐藏项）
  Future<ScanResult> detectUserFolders() async {
    logger.i('QuickAccessPresenter.detectUserFolders called');
    _viewModel.setScanning(true);

    try {
      final userFolders = await _userDetector.detectUserFolders();
      logger.i('Detected ${userFolders.length} user folders');

      final scannedFolders = userFolders
          .map((f) => f.toQuickAccessFolder())
          .toList();
      final counts = _countFolderTypes(scannedFolders);

      int newlyAdded = 0;
      int alreadyExists = 0;
      int skippedHidden = 0;

      for (final folder in scannedFolders) {
        final result = await _localSource.addFolderWithResult(
          folder,
          unhideIfHidden: false,
        );
        switch (result) {
          case AddFolderResult.added:
            newlyAdded++;
            break;
          case AddFolderResult.exists:
            alreadyExists++;
            break;
          case AddFolderResult.skippedHidden:
            // 跳过隐藏的，不计入有效发现
            skippedHidden++;
            break;
          case AddFolderResult.unhidden:
          case AddFolderResult.error:
            // 这些情况理论上不会发生（unhideIfHidden: false）
            break;
        }
      }

      await loadQuickAccessFolders();

      return ScanResult(
        totalFound: scannedFolders.length - skippedHidden,
        newlyAdded: newlyAdded,
        alreadyExists: alreadyExists,
        unhidden: 0, // 用户目录检测不恢复隐藏项
        systemCount: counts['system']!,
        appRootCount: counts['appRoot']!,
        appSubCount: counts['appSub']!,
        userCustomCount: counts['userCustom']!,
      );
    } catch (e, stackTrace) {
      logger.e('Error detecting user folders: $e\n$stackTrace');
      return ScanResult(totalFound: 0, newlyAdded: 0, alreadyExists: 0);
    } finally {
      _viewModel.setScanning(false);
    }
  }

  /// 统计文件夹类型
  Map<String, int> _countFolderTypes(List<QuickAccessFolder> folders) {
    int systemCount = 0;
    int appRootCount = 0;
    int appSubCount = 0;
    int userCustomCount = 0;

    for (final folder in folders) {
      switch (folder.type) {
        case QuickAccessFolderType.system:
          systemCount++;
          break;
        case QuickAccessFolderType.appRoot:
          appRootCount++;
          break;
        case QuickAccessFolderType.appSubfolder:
          appSubCount++;
          break;
        case QuickAccessFolderType.userCustom:
          userCustomCount++;
          break;
      }
    }

    return {
      'system': systemCount,
      'appRoot': appRootCount,
      'appSub': appSubCount,
      'userCustom': userCustomCount,
    };
  }

  /// 扫描系统预定义目录
  Future<List<QuickAccessFolder>> _scanSystemDirectories() async {
    logger.i('Scanning system directories');
    final systemDirs = <QuickAccessFolder>[];

    // 定义系统目录路径
    final systemPaths = Platform.isAndroid
        ? [
            '/storage/emulated/0/DCIM',
            '/storage/emulated/0/Pictures',
            '/storage/emulated/0/Music',
            '/storage/emulated/0/Movies',
            '/storage/emulated/0/Documents',
            '/storage/emulated/0/Download',
          ]
        : Platform.isWindows
        ? () {
            final userProfile = Platform.environment['USERPROFILE'];
            return userProfile != null
                ? [
                    '$userProfile\\Documents',
                    '$userProfile\\Downloads',
                    '$userProfile\\Pictures',
                    '$userProfile\\Music',
                    '$userProfile\\Videos',
                  ]
                : <String>[];
          }()
        : [];

    for (final path in systemPaths) {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        logger.d('System directory does not exist: $path');
        continue;
      }

      try {
        final name = path.split(Platform.pathSeparator).last;
        final folder = QuickAccessFolder(
          id: '${DateTime.now().millisecondsSinceEpoch}_$name',
          path: path,
          originalName: name,
          type: QuickAccessFolderType.system,
          createdAt: DateTime.now(),
          isAddedToQuickAccess: false,
          isHidden: false,
          homeDisplayOrder: null,
        );
        systemDirs.add(folder);
        logger.d('Found system directory: $name at $path');
      } catch (e) {
        logger.w('Error processing system directory $path: $e');
      }
    }

    logger.i('Found ${systemDirs.length} system directories');
    return systemDirs;
  }

  /// 为文件夹推荐别名
  String recommendAlias({
    required String path,
    required String originalName,
    QuickAccessFolderType? type,
  }) {
    return _aliasService.recommendAlias(
      path: path,
      originalName: originalName,
      type: type,
    );
  }

  /// 批量添加文件夹（用于通知确认后的批量添加）
  Future<int> batchAddFolders(List<QuickAccessFolder> folders) async {
    logger.i(
      'QuickAccessPresenter.batchAddFolders called: ${folders.length} folders',
    );
    int addedCount = 0;

    for (final folder in folders) {
      try {
        final success = await _localSource.addFolder(folder);
        if (success) addedCount++;
      } catch (e) {
        logger.w('Error adding folder ${folder.path}: $e');
      }
    }

    await loadQuickAccessFolders();
    return addedCount;
  }

  /// 批量删除文件夹
  Future<int> batchRemoveFolders(List<String> ids) async {
    logger.i(
      'QuickAccessPresenter.batchRemoveFolders called: ${ids.length} folders',
    );
    int removedCount = 0;

    for (final id in ids) {
      try {
        final success = await _localSource.removeFolder(id);
        if (success) removedCount++;
      } catch (e) {
        logger.w('Error removing folder $id: $e');
      }
    }

    await loadQuickAccessFolders();
    return removedCount;
  }

  /// 获取按类型分组的文件夹
  Map<QuickAccessFolderType, List<QuickAccessFolder>> getFoldersByType() {
    final folders = _viewModel.folders;
    final grouped = <QuickAccessFolderType, List<QuickAccessFolder>>{};

    for (final type in QuickAccessFolderType.values) {
      grouped[type] = folders.where((f) => f.type == type).toList();
    }

    return grouped;
  }

  /// 获取应用根目录及其子目录的映射
  Map<String, List<QuickAccessFolder>> getAppFolderHierarchy() {
    final folders = _viewModel.folders;
    final appRoots = folders
        .where((f) => f.type == QuickAccessFolderType.appRoot)
        .toList();
    final appSubfolders = folders
        .where((f) => f.type == QuickAccessFolderType.appSubfolder)
        .toList();

    final hierarchy = <String, List<QuickAccessFolder>>{};

    for (final root in appRoots) {
      hierarchy[root.path] = appSubfolders
          .where((sub) => sub.path.startsWith('${root.path}/'))
          .toList();
    }

    return hierarchy;
  }

  // ==================== 新增方法 ====================

  /// 加入快速访问
  Future<bool> addToQuickAccess(String id) async {
    logger.i('QuickAccessPresenter.addToQuickAccess called: $id');
    try {
      final success = await _localSource.addToQuickAccess(id);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error adding to quick access: $e');
      return false;
    }
  }

  /// 批量加入快速访问
  Future<int> batchAddToQuickAccess(List<String> ids) async {
    logger.i(
      'QuickAccessPresenter.batchAddToQuickAccess called: ${ids.length} items',
    );
    try {
      final count = await _localSource.batchAddToQuickAccess(ids);
      await loadQuickAccessFolders();
      return count;
    } catch (e) {
      logger.e('Error batch adding to quick access: $e');
      return 0;
    }
  }

  /// 移出快速访问
  Future<bool> removeFromQuickAccess(String id) async {
    logger.i('QuickAccessPresenter.removeFromQuickAccess called: $id');
    try {
      final success = await _localSource.removeFromQuickAccess(id);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error removing from quick access: $e');
      return false;
    }
  }

  /// 批量移出快速访问
  Future<int> batchRemoveFromQuickAccess(List<String> ids) async {
    logger.i(
      'QuickAccessPresenter.batchRemoveFromQuickAccess called: ${ids.length} items',
    );
    try {
      final count = await _localSource.batchRemoveFromQuickAccess(ids);
      await loadQuickAccessFolders();
      return count;
    } catch (e) {
      logger.e('Error batch removing from quick access: $e');
      return 0;
    }
  }

  /// 忽略文件夹
  Future<bool> hideFolder(String id) async {
    logger.i('QuickAccessPresenter.hideFolder called: $id');
    try {
      final success = await _localSource.hideFolder(id);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error hiding folder: $e');
      return false;
    }
  }

  /// 批量忽略
  Future<int> batchHideFolders(List<String> ids) async {
    logger.i(
      'QuickAccessPresenter.batchHideFolders called: ${ids.length} items',
    );
    try {
      final count = await _localSource.batchHideFolders(ids);
      await loadQuickAccessFolders();
      return count;
    } catch (e) {
      logger.e('Error batch hiding folders: $e');
      return 0;
    }
  }

  /// 设置首页展示顺序
  Future<bool> setHomeDisplayOrder(String id, int? order) async {
    logger.i('QuickAccessPresenter.setHomeDisplayOrder called: $id -> $order');
    try {
      final success = await _localSource.setHomeDisplayOrder(id, order);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error setting home display order: $e');
      return false;
    }
  }

  /// 批量更新首页展示顺序（拖拽排序）
  Future<bool> updateHomeDisplayOrders(Map<String, int?> orderMap) async {
    logger.i(
      'QuickAccessPresenter.updateHomeDisplayOrders called: ${orderMap.length} items',
    );
    try {
      final success = await _localSource.updateHomeDisplayOrders(orderMap);
      if (success) {
        await loadQuickAccessFolders();
        return true;
      }
      return false;
    } catch (e) {
      logger.e('Error updating home display orders: $e');
      return false;
    }
  }

  /// 获取首页文件夹
  Future<List<QuickAccessFolder>> getHomeFolders() async {
    try {
      return await _localSource.getHomeFolders();
    } catch (e) {
      logger.e('Error getting home folders: $e');
      return [];
    }
  }

  /// 获取已加入快速访问的文件夹
  Future<List<QuickAccessFolder>> getAddedFolders() async {
    try {
      return await _localSource.getAddedFolders();
    } catch (e) {
      logger.e('Error getting added folders: $e');
      return [];
    }
  }

  /// 获取仅扫描但未加入的文件夹
  Future<List<QuickAccessFolder>> getScannedOnlyFolders() async {
    try {
      return await _localSource.getScannedOnlyFolders();
    } catch (e) {
      logger.e('Error getting scanned only folders: $e');
      return [];
    }
  }
}

/// 扫描结果
class ScanResult {
  final int totalFound;
  final int newlyAdded;
  final int alreadyExists;
  final int unhidden;

  // 按类型统计
  final int systemCount;
  final int appRootCount;
  final int appSubCount;
  final int userCustomCount;

  ScanResult({
    required this.totalFound,
    required this.newlyAdded,
    required this.alreadyExists,
    this.unhidden = 0,
    this.systemCount = 0,
    this.appRootCount = 0,
    this.appSubCount = 0,
    this.userCustomCount = 0,
  });

  bool get hasNewFolders => newlyAdded > 0;
  bool get hasUnhidden => unhidden > 0;

  @override
  String toString() {
    return 'ScanResult(total: $totalFound, new: $newlyAdded, exists: $alreadyExists, unhidden: $unhidden, system: $systemCount, appRoot: $appRootCount, appSub: $appSubCount)';
  }
}
