import 'dart:io';

import 'package:easyfile/core/config/file_types_config.dart';
import 'package:easyfile/core/platform/mediastore_scanner_channel.dart';

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
  ///
  /// 扫描策略（混合模式）：
  /// 1. MediaStore扫描（快速，系统权限，可访问所有APK包括660权限的）
  /// 2. 文件系统扫描补充（覆盖MediaStore未索引的新文件）
  /// 3. 合并去重，确保完整性
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

      logger.i('[ApkManagerService] 🔄 开始混合扫描APK文件...');
      final startTime = DateTime.now();

      // 使用Set去重
      final apkFilePaths = <String>{};
      int mediaStoreCount = 0;
      int fileSystemCount = 0;

      // ========== 方案1: MediaStore扫描（优先，系统权限）==========
      try {
        logger.i('[ApkManagerService] 📱 阶段1: MediaStore扫描...');
        final mediaStoreStartTime = DateTime.now();

        final mediaStoreFiles = await MediaStoreScannerChannel.scanApks();

        // 🔍 打印MediaStore扫描到的APK详情
        logger.i('[ApkManagerService] MediaStore返回 ${mediaStoreFiles.length} 个文件:');
        for (var i = 0; i < mediaStoreFiles.length; i++) {
          final file = mediaStoreFiles[i];
          logger.i('[ApkManagerService]   [$i] ${file.path}');
          apkFilePaths.add(file.path);
        }

        mediaStoreCount = apkFilePaths.length;
        final mediaStoreDuration = DateTime.now().difference(mediaStoreStartTime);
        logger
            .i('[ApkManagerService] ✅ MediaStore扫描完成: $mediaStoreCount 个APK (${mediaStoreDuration.inMilliseconds}ms)');
      } catch (e) {
        logger.e('[ApkManagerService] ⚠️ MediaStore扫描失败: $e');
        logger.e('[ApkManagerService] 将继续使用文件系统扫描...');
      }

      // ========== 方案2: 文件系统扫描补充（覆盖未索引文件）==========
      try {
        logger.i('[ApkManagerService] 📁 阶段2: 文件系统扫描补充...');
        final fileSystemStartTime = DateTime.now();

        final scanPaths = await _filePresenter.getCommonScanPaths();
        logger.i('[ApkManagerService] 扫描路径: ${scanPaths.length}个');

        // 优化：限制扫描的目录数量，优先扫描常见APK路径
        final priorityPaths = _getPriorityApkPaths(scanPaths);
        logger.i('[ApkManagerService] 优先扫描: ${priorityPaths.length}个路径');

        // 🔍 打印优先路径详情
        logger.i('[ApkManagerService] 优先路径列表:');
        for (var i = 0; i < priorityPaths.length && i < 20; i++) {
          logger.i('[ApkManagerService]   [$i] ${priorityPaths[i]}');
        }

        // 收集文件系统中的APK
        final beforeCount = apkFilePaths.length;
        int scannedPaths = 0;
        int totalApksFound = 0;

        for (final scanPath in priorityPaths) {
          scannedPaths++;
          logger.i('[ApkManagerService] 正在扫描路径 $scannedPaths/${priorityPaths.length}: $scanPath');

          try {
            final pathApks = await _findApkFilesInPath(scanPath);
            logger.i('[ApkManagerService]   └─ 发现 ${pathApks.length} 个APK文件');

            // 🔍 打印找到的APK详情
            if (pathApks.isNotEmpty) {
              for (var apk in pathApks) {
                final isNew = !apkFilePaths.contains(apk);
                logger.i('[ApkManagerService]      ${isNew ? "✨ 新增" : "⚪ 重复"}: $apk');
                apkFilePaths.add(apk);
              }
            }

            totalApksFound += pathApks.length;
          } catch (e) {
            logger.w('[ApkManagerService]   └─ ⚠️ 扫描失败: $e');
          }
        }

        fileSystemCount = apkFilePaths.length - beforeCount;
        final fileSystemDuration = DateTime.now().difference(fileSystemStartTime);
        logger.i(
            '[ApkManagerService] ✅ 文件系统扫描完成: 补充 $fileSystemCount 个APK (总共找到 $totalApksFound 个，${fileSystemDuration.inMilliseconds}ms)');
      } catch (e) {
        logger.e('[ApkManagerService] ⚠️ 文件系统扫描失败: $e');
      }

      // ========== 统计结果 ==========
      final uniqueApkPaths = apkFilePaths.toList();
      final totalDuration = DateTime.now().difference(startTime);

      logger.i('[ApkManagerService] ========== 扫描统计 ==========');
      logger.i('[ApkManagerService] 总文件数: ${uniqueApkPaths.length} 个APK');
      logger.i('[ApkManagerService] MediaStore: $mediaStoreCount 个');
      logger.i('[ApkManagerService] 文件系统补充: $fileSystemCount 个 (MediaStore未索引)');
      logger.i('[ApkManagerService] 总耗时: ${totalDuration.inMilliseconds}ms');

      // 🔍 特别检查目标APK
      const targetApk = '/storage/emulated/0/Download/QQ/app-release/app-release.apk';
      final hasTarget = uniqueApkPaths.any((path) => path.contains('app-release.apk'));
      final hasTargetExact = uniqueApkPaths.contains(targetApk);
      logger.i('[ApkManagerService] 🎯 目标APK检查:');
      logger.i('[ApkManagerService]   包含app-release.apk: ${hasTarget ? "✅ 是" : "❌ 否"}');
      logger.i('[ApkManagerService]   精确匹配目标路径: ${hasTargetExact ? "✅ 是" : "❌ 否"}');

      if (hasTarget && !hasTargetExact) {
        final similar = uniqueApkPaths.where((path) => path.contains('app-release.apk')).toList();
        logger.i('[ApkManagerService]   找到相似路径: ${similar.length} 个');
        for (var path in similar) {
          logger.i('[ApkManagerService]     - $path');
        }
      }

      logger.i('[ApkManagerService] ===============================');

      if (uniqueApkPaths.isEmpty) {
        return [];
      }

      // 批量解析APK
      final apkInfoList = await ApkParserChannel.parseApkBatch(uniqueApkPaths);
      logger.i('[ApkManagerService] 成功解析 ${apkInfoList.length} 个APK');

      // 过滤掉 EasyFile 自己的安装包 - 暂时注释掉用于测试
      // final filteredApkList = apkInfoList.where((apk) => apk.packageName != 'com.guangqi.easyfile').toList();
      final filteredApkList = apkInfoList; // 测试用：暂不过滤

      // if (filteredApkList.length < apkInfoList.length) {
      //   final filtered = apkInfoList.length - filteredApkList.length;
      //   logger.i('[ApkManagerService] 已过滤 $filtered 个EasyFile自身安装包');
      // }

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

  /// 快速更新APK列表的安装状态（不重新扫描文件）
  ///
  /// 用于从安装页面返回时快速更新状态，避免完整扫描
  Future<List<ApkInfo>> updateInstallStatus(List<ApkInfo> currentList) async {
    if (currentList.isEmpty) {
      return currentList;
    }

    try {
      logger.i('[ApkManagerService] 🔄 快速更新安装状态...');

      // 批量检查安装状态
      final apkInfoMap = currentList
          .map((apk) => {
                'packageName': apk.packageName,
                'versionCode': apk.versionCode,
              })
          .toList();

      final statusMap = await ApkParserChannel.checkInstallStatusBatch(apkInfoMap);

      // 更新APK的安装状态
      final updatedList = currentList.map((apk) {
        final status = statusMap[apk.packageName] ?? ApkInstallStatus.unknown;
        return apk.copyWith(status: status);
      }).toList();

      logger.i('[ApkManagerService] ✅ 安装状态更新完成');

      // 更新缓存
      await _cacheService.saveApkListCache(updatedList);

      return updatedList;
    } catch (e) {
      logger.e('[ApkManagerService] 更新安装状态失败: $e');
      return currentList; // 返回原列表
    }
  }

  /// 获取优先扫描的APK路径
  ///
  /// 只扫描 Download 目录，忽略其他路径
  List<String> _getPriorityApkPaths(List<String> allPaths) {
    final priorityPaths = <String>[];

    // 只扫描 Download 路径
    for (final path in allPaths) {
      final lowerPath = path.toLowerCase();
      if (lowerPath.contains('/download')) {
        priorityPaths.add(path);
      }
    }

    logger.i('[ApkManagerService] 🎯 只扫描Download路径: ${priorityPaths.length} 个');

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
          // 记录访问错误（特别是权限问题）
          final errorMsg = e.toString();
          if (errorMsg.contains('Permission denied') || errorMsg.contains('Access denied')) {
            logger.w('[ApkManagerService] ⚠️ 权限被拒: ${entity is File ? entity.path : entity.toString()}');
          } else {
            logger.e('[ApkManagerService] 文件访问失败: ${entity is File ? entity.path : entity.toString()}, 错误: $e');
          }
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
  /// 注意：由于使用了MediaStore混合扫描，文件系统扫描主要用于补充，可以适当增加深度
  int _getMaxDepthForPath(String path) {
    final normalizedPath = path.toLowerCase();

    // Download目录适当增加深度（QQ/app-release/这样的结构需要至少3-4层）
    if (normalizedPath.contains('download')) {
      return 5; // 从3增加到5，确保能扫描到深层目录
    }

    // Android/data目录使用浅扫描
    if (normalizedPath.contains('android/data') || normalizedPath.contains('android\\data')) {
      return 2; // 只扫描2层
    }

    // 其他目录使用中等深度
    return 6; // 从5增加到6
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
