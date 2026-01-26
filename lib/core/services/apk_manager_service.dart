import 'dart:io';

import 'package:easyfile/core/config/file_types_config.dart';

import '../../data/models/apk_info.dart';
import '../../presenter/file_presenter.dart';
import '../channels/apk_parser_channel.dart';
import '../logger.dart';
import 'apk_cache_service.dart';

typedef PackageChangeCallback = void Function(String packageName, String action);

/// APK管理服务
///
/// 提供APK扫描、解析和管理功能
class ApkManagerService {
  final FilePresenter _filePresenter;
  final ApkCacheService _cacheService = ApkCacheService();

  ApkManagerService({required FilePresenter filePresenter}) : _filePresenter = filePresenter;

  /// 扫描所有APK文件
  ///
  /// 优先使用缓存，缓存过期或不存在时才重新扫描
  /// 返回已解析且检查安装状态的APK列表
  Future<List<ApkInfo>> scanApkFiles({bool forceRefresh = false}) async {
    try {
      // 尝试使用缓存
      if (!forceRefresh) {
        final cachedList = await _cacheService.getCachedApkList();
        if (cachedList != null) {
          logger.i('[ApkManagerService] 使用缓存数据: ${cachedList.length}个APK');
          return cachedList;
        }
      }

      logger.i('[ApkManagerService] 开始扫描APK文件...');
      final scanPaths = await _filePresenter.getCommonScanPaths();
      logger.i('[ApkManagerService] 扫描路径: ${scanPaths.length}个');

      // 优化：限制扫描的目录数量，优先扫描常见APK路径
      final priorityPaths = _getPriorityApkPaths(scanPaths);
      logger.i('[ApkManagerService] 优先扫描: ${priorityPaths.length}个路径');

      // 收集所有APK文件路径
      final apkFilePaths = <String>[];
      for (final scanPath in priorityPaths) {
        final apkFiles = await _findApkFilesInPath(scanPath);
        apkFilePaths.addAll(apkFiles);
      }

      // 去重
      final uniqueApkPaths = apkFilePaths.toSet().toList();
      logger.i('[ApkManagerService] 发现 ${uniqueApkPaths.length} 个APK文件');

      if (uniqueApkPaths.isEmpty) {
        return [];
      }

      // 批量解析APK
      final apkInfoList = await ApkParserChannel.parseApkBatch(uniqueApkPaths);
      logger.i('[ApkManagerService] 成功解析 ${apkInfoList.length} 个APK');

      // 过滤掉 EasyFile 自己的安装包
      final filteredApkList = apkInfoList.where((apk) => apk.packageName != 'com.guangqi.easyfile').toList();

      if (filteredApkList.length < apkInfoList.length) {
        final filtered = apkInfoList.length - filteredApkList.length;
        logger.i('[ApkManagerService] 已过滤 $filtered 个EasyFile自身安装包');
      }

      // 批量检查安装状态
      final apkInfoMap = filteredApkList
          .map((apk) => {
                'packageName': apk.packageName,
                'versionCode': apk.versionCode,
              })
          .toList();

      final statusMap = await ApkParserChannel.checkInstallStatusBatch(apkInfoMap);

      // 更新APK的安装状态
      final apkListWithStatus = filteredApkList.map((apk) {
        final status = statusMap[apk.packageName] ?? ApkInstallStatus.unknown;
        return apk.copyWith(status: status);
      }).toList();

      logger.i('[ApkManagerService] 扫描完成: ${apkListWithStatus.length} 个APK');

      // 保存到缓存
      await _cacheService.saveApkListCache(apkListWithStatus);

      return apkListWithStatus;
    } catch (e) {
      logger.e('[ApkManagerService] 扫描失败: $e');
      rethrow;
    }
  }

  /// 获取优先扫描的APK路径
  ///
  /// 优先扫描常见的APK存放位置，避免扫描整个文件系统
  List<String> _getPriorityApkPaths(List<String> allPaths) {
    final priorityPaths = <String>[];
    final priorityKeywords = [
      'Download',
      'download',
      'apk',
      'APK',
      'tencent', // QQ/微信下载
      'bluetooth', // 蓝牙接收
    ];

    // 优先添加包含关键词的路径
    for (final path in allPaths) {
      final lowerPath = path.toLowerCase();
      if (priorityKeywords.any((keyword) => lowerPath.contains(keyword.toLowerCase()))) {
        priorityPaths.add(path);
      }
    }

    // 如果优先路径太少，添加其他路径（最多20个）
    if (priorityPaths.length < 10) {
      final remainingPaths = allPaths.where((p) => !priorityPaths.contains(p)).take(10);
      priorityPaths.addAll(remainingPaths);
    }

    return priorityPaths;
  }

  /// 在指定路径查找APK文件
  ///
  /// 递归扫描，使用与FilePresenter相同的深度控制策略
  Future<List<String>> _findApkFilesInPath(String path) async {
    final apkFiles = <String>[];

    try {
      final directory = Directory(path);
      if (!directory.existsSync()) {
        return apkFiles;
      }

      // 根据路径决定扫描深度
      final maxDepth = _getMaxDepthForPath(path);

      await _scanDirectory(
        directory.path,
        apkFiles,
        currentDepth: 0,
        maxDepth: maxDepth,
      );
    } catch (e) {
      logger.e('[ApkManagerService] 扫描路径失败 ($path): $e');
    }

    return apkFiles;
  }

  /// 递归扫描目录
  Future<void> _scanDirectory(
    String dirPath,
    List<String> apkFiles, {
    required int currentDepth,
    required int maxDepth,
  }) async {
    if (currentDepth > maxDepth) {
      return;
    }

    try {
      final directory = Directory(dirPath);
      if (!await directory.exists()) {
        return;
      }

      // 使用异步list替代同步listSync
      final entities = await directory.list().toList();

      for (final entity in entities) {
        try {
          if (entity is File) {
            // 检查是否为APK文件
            if (FileTypesConfig().isApkFile(entity.path)) {
              apkFiles.add(entity.path);
            }
          } else if (entity is Directory) {
            // 递归扫描子目录
            await _scanDirectory(
              entity.path,
              apkFiles,
              currentDepth: currentDepth + 1,
              maxDepth: maxDepth,
            );
          }
        } catch (e) {
          // 忽略单个文件/文件夹的访问错误
          continue;
        }
      }
    } catch (e) {
      logger.e('[ApkManagerService] 扫描目录失败 ($dirPath): $e');
    }
  }

  /// 获取路径的最大扫描深度
  ///
  /// APK扫描使用较浅的深度，加快扫描速度
  int _getMaxDepthForPath(String path) {
    final normalizedPath = path.toLowerCase();

    // Download目录使用浅扫描
    if (normalizedPath.contains('download')) {
      return 3; // 只扫描3层
    }

    // Android/data目录使用浅扫描
    if (normalizedPath.contains('android/data') || normalizedPath.contains('android\\data')) {
      return 2; // 只扫描2层
    }

    // 其他目录也使用较浅的扫描
    return 5; // 从10减少到5
  }

  /// 跳转系统安装页面
  Future<bool> launchInstall(ApkInfo apkInfo) async {
    return await ApkParserChannel.launchInstall(apkInfo.filePath);
  }

  /// 跳转应用详情页
  Future<bool> launchAppSettings(ApkInfo apkInfo) async {
    if (apkInfo.status == ApkInstallStatus.installed ||
        apkInfo.status == ApkInstallStatus.upgradable ||
        apkInfo.status == ApkInstallStatus.signatureMismatch) {
      return await ApkParserChannel.launchAppSettings(apkInfo.packageName);
    }
    return false;
  }

  /// 删除APK文件
  Future<bool> deleteApk(ApkInfo apkInfo) async {
    try {
      final file = File(apkInfo.filePath);
      if (file.existsSync()) {
        await file.delete();
        logger.i('[ApkManagerService] 删除APK: ${apkInfo.filePath}');
        return true;
      }
      return false;
    } catch (e) {
      logger.e('[ApkManagerService] 删除APK失败: $e');
      return false;
    }
  }

  /// 开始监听应用包变化（页面级）
  void startPackageListener(PackageChangeCallback callback) {
    ApkParserChannel.setPackageChangeCallback(callback);
    ApkParserChannel.startPackageListener();
  }

  /// 停止监听应用包变化
  void stopPackageListener() {
    ApkParserChannel.stopPackageListener();
  }
}
