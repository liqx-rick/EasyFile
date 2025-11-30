import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/duplicate_file_scan_config.dart';
import 'package:easyfile/core/models/large_file_scan_config.dart';
import 'package:easyfile/core/services/duplicate_file_scan_manager.dart';
import 'package:easyfile/core/services/duplicate_file_service.dart';
import 'package:easyfile/core/services/duplicate_file_smart_cache.dart';
import 'package:easyfile/data/models/duplicate_file_group.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';

/// 扫描统计信息（用于引用传递）
class _ScanStats {
  int scannedCount = 0;
  int skippedSizeCount = 0;
  int skippedTypeCount = 0;
  int skippedHiddenCount = 0;
}

/// 文件变化信息
class FileChanges {
  final List<String> addedFiles = [];
  final List<String> modifiedFiles = [];
  final List<String> deletedFiles = [];

  bool get isEmpty =>
      addedFiles.isEmpty && modifiedFiles.isEmpty && deletedFiles.isEmpty;

  int get totalChanges =>
      addedFiles.length + modifiedFiles.length + deletedFiles.length;
}

/// 增强的重复文件扫描服务
///
/// 核心功能：
/// 1. 🚀 **并行扫描优化** - 使用Isolate并行处理，提升大文件集扫描速度
/// 2. 💾 **智能缓存系统** - 持久化扫描结果，避免重复计算MD5哈希
/// 3. 🔄 **增量更新检测** - 只扫描变化的文件，大幅减少扫描时间
/// 4. 📊 **后台扫描管理** - 支持后台运行，用户随时可查看结果
///
/// 工作流程：
/// 1. 用户请求扫描 → smartScan()
/// 2. 检查缓存 → 如果有缓存立即返回
/// 3. 后台启动增量扫描 → 检测文件变化
/// 4. 只扫描新增/修改的文件 → 与缓存中所有文件比较
/// 5. 合并结果 → 更新缓存 → UI自动刷新
///
/// 关键优化：
/// - 使用 fileIndex（所有文件指纹）而不是 groups（仅重复文件）进行比较
/// - 三阶段检测：大小分组 → 头部哈希(8KB) → 完整MD5
/// - 状态不阻塞：即使正在扫描，也立即返回缓存结果
class EnhancedDuplicateFileScanService {
  final DuplicateFileService _baseService;
  final DuplicateFileScanManager _scanManager;
  final DuplicateFileSmartCache _smartCache;

  EnhancedDuplicateFileScanService(this._baseService)
      : _scanManager = DuplicateFileScanManager(),
        _smartCache = DuplicateFileSmartCache();

  /// 获取扫描管理器（用于UI监听）
  DuplicateFileScanManager get scanManager => _scanManager;

  /// 智能扫描（整合缓存 + 后台扫描）
  ///
  /// 扫描策略：
  /// 1. 检查该配置的状态（可能正在扫描、有缓存等）
  /// 2. 如果有缓存，立即返回缓存结果
  /// 3. 同时在后台进行增量更新（检查缓存时间后的变化）
  /// 4. 通过监听器通知UI更新
  Future<List<DuplicateFileGroup>> smartScan(
    DuplicateFileScanConfig config, {
    bool forceFullScan = false,
  }) async {
    logger.i('Starting smart scan with config: ${config.toString()}');
    logger.i('  - 扫描模式: ${config.scanMode.name}');
    logger.i('  - 文件类型: ${config.selectedType?.name ?? "all"}');
    logger.i('  - 最小大小: ${config.minSizeInKB}KB');

    // ✅ 检查该配置的扫描状态
    final configState = _scanManager.getStateFor(config);

    // 如果该配置正在扫描，返回缓存结果（召回）
    if (configState == DuplicateScanState.scanning) {
      logger
          .i('✅ This config is scanning, returning cached results for recall');

      // 尝试加载缓存
      final cache = await _smartCache.loadCache(config);
      if (cache != null) {
        logger.i(
            '📱 Recalling scan in progress: ${cache.groups.length} cached groups');
        return cache.groups;
      }

      // 如果没有缓存，返回空列表（让UI显示"正在扫描"）
      logger
          .i('📱 Recalling scan in progress: no cache, showing scan progress');
      return [];
    }

    // 检查是否强制全量扫描
    if (!forceFullScan) {
      // 尝试加载缓存
      final cache = await _smartCache.loadCache(config);

      if (cache != null) {
        final cacheAge = DateTime.now().difference(cache.scanTime);
        logger.i(
            'Cache found (age: ${cacheAge.inMinutes}m), returning cached results immediately');

        // 🚀 立即返回缓存结果
        final cachedGroups = cache.groups;

        // 🔄 异步启动增量更新（不等待，在后台持续运行）
        _performIncrementalUpdate(config, cache).then((needsFullScan) {
          if (needsFullScan) {
            logger.i(
                'Incremental update detected major changes, triggering full scan');
            _fullScanWithCache(config).then((updatedGroups) {
              logger.i('Full scan completed after incremental check');
            }).catchError((e) {
              logger.e('Full scan after incremental update failed: $e');
            });
          } else {
            logger.i('Incremental update completed successfully');
          }
        }).catchError((e) {
          logger.e('Incremental update failed: $e');
          // ✅ 失败时也要触发完成监听器，返回缓存数据
          _scanManager.completeWithResults(config, cachedGroups);
        });

        return cachedGroups;
      }
    }

    // 执行全量扫描
    logger.i('Performing full scan with optimizations');
    return await _fullScanWithCache(config);
  }

  /// 执行增量更新（检查缓存时间后的文件变化）
  /// 返回 true 表示需要全量扫描，false 表示缓存仍然有效
  Future<bool> _performIncrementalUpdate(
    DuplicateFileScanConfig config,
    DuplicateFileScanCache cache,
  ) async {
    try {
      // 设置扫描状态为 scanning（让 UI 可以监听）
      _scanManager.setStateManually(config, DuplicateScanState.scanning);

      debugPrint('\n========== 开始增量更新检测 ==========');
      debugPrint('[增量更新] 缓存时间: ${cache.scanTime}');
      debugPrint('[增量更新] 缓存中共有 ${cache.fileIndex.length} 个文件');
      debugPrint('[增量更新] 配置: minSize=${config.minSizeInKB}KB');
      logger.i('Starting incremental update check from ${cache.scanTime}');

      // 检查是否有文件变化
      final detectStart = DateTime.now();
      debugPrint('[增量更新] 🔍 开始检测文件变化...');
      final changes = await _detectFileChanges(config, cache);
      final detectDuration = DateTime.now().difference(detectStart);
      debugPrint('[增量更新] ✅ 文件变化检测完成，耗时: ${detectDuration.inSeconds}s');

      if (changes.isEmpty) {
        final t1 = DateTime.now();
        debugPrint('[增量更新] ✅ 未检测到任何文件变化，缓存数据是最新的');
        debugPrint('========================================\n');
        logger.i(
            '[${t1.toIso8601String()}] No file changes detected, cache is up to date');

        // ✅ 完成并触发监听器（即使没有变化，也要通知UI）
        _scanManager.completeWithResults(config, cache.groups);

        final t2 = DateTime.now();
        logger.i(
            '[${t2.toIso8601String()}] completeWithResults called, delay: ${t2.difference(t1).inMilliseconds}ms');

        return false;
      }

      debugPrint('\n[增量更新] 📊 检测到文件变化:');
      debugPrint('  - 新增: ${changes.addedFiles.length} 个');
      debugPrint('  - 修改: ${changes.modifiedFiles.length} 个');
      debugPrint('  - 删除: ${changes.deletedFiles.length} 个');
      if (changes.addedFiles.isNotEmpty) {
        debugPrint('\n[增量更新] 新增文件列表:');
        for (var i = 0; i < changes.addedFiles.length && i < 10; i++) {
          debugPrint('  ${i + 1}. ${changes.addedFiles[i]}');
        }
        if (changes.addedFiles.length > 10) {
          debugPrint('  ... 还有 ${changes.addedFiles.length - 10} 个文件');
        }
      }
      logger.i(
          'Detected ${changes.addedFiles.length} added, ${changes.modifiedFiles.length} modified, ${changes.deletedFiles.length} deleted files');

      // 🎯 增量扫描策略：
      // 1. 只扫描新增和修改的文件
      // 2. 移除删除的文件
      // 3. 保留缓存中未变化的文件

      final changedFilePaths = <String>{
        ...changes.addedFiles,
        ...changes.modifiedFiles,
      };

      if (changedFilePaths.isEmpty && changes.deletedFiles.isNotEmpty) {
        // 只有删除，没有新增/修改 - 直接更新缓存
        logger.i('Only deletions detected, updating cache without rescan');
        final updatedGroups =
            await _updateCacheWithDeletions(cache, changes.deletedFiles);
        // ✅ 完成并触发监听器
        _scanManager.completeWithResults(config, updatedGroups);
        return false;
      }

      // 有新增或修改的文件，执行增量扫描
      final scanStart = DateTime.now();
      debugPrint('[增量更新] 🔎 开始增量扫描 ${changedFilePaths.length} 个文件...');
      logger.i(
          'Performing incremental scan on ${changedFilePaths.length} changed files');
      final mergedGroups = await _performIncrementalScan(
          config, cache, changedFilePaths, changes.deletedFiles);
      final scanDuration = DateTime.now().difference(scanStart);
      debugPrint('[增量更新] ✅ 增量扫描完成，耗时: ${scanDuration.inSeconds}s');

      // 增量扫描完成，更新manager的缓存并触发完成通知
      logger.i(
          '✅ Incremental update completed with ${mergedGroups.length} groups');
      _scanManager.completeWithResults(config, mergedGroups); // 更新结果并触发完成通知

      return false; // 已完成增量更新，不需要全量扫描
    } catch (e, stack) {
      logger.e('Incremental update error: $e\n$stack');

      // ✅ 错误时也要触发完成监听器，返回缓存数据
      _scanManager.completeWithResults(config, cache.groups);

      // 返回 false，让缓存继续有效
      return false;
    }
  }

  /// 只更新删除的文件
  Future<List<DuplicateFileGroup>> _updateCacheWithDeletions(
    DuplicateFileScanCache cache,
    List<String> deletedFiles,
  ) async {
    final deletedSet = deletedFiles.toSet();

    // 从所有组中移除删除的文件
    final updatedGroups = <DuplicateFileGroup>[];

    for (final group in cache.groups) {
      final remainingFiles =
          group.files.where((file) => !deletedSet.contains(file.path)).toList();

      // 如果组中仍有至少2个文件，保留该组
      if (remainingFiles.length >= 2) {
        updatedGroups.add(DuplicateFileGroup(
          groupId: group.groupId,
          files: remainingFiles,
          fileSize: group.fileSize,
        ));
      }
    }

    // ✅ 对更新后的组排序：按可释放空间从大到小
    updatedGroups
        .sort((a, b) => b.reclaimableSpace.compareTo(a.reclaimableSpace));

    // 更新缓存
    final updatedCache = DuplicateFileScanCache(
      scanTime: DateTime.now(),
      config: cache.config,
      groups: updatedGroups,
      fileIndex: Map.from(cache.fileIndex)
        ..removeWhere((k, v) => deletedSet.contains(k)),
    );

    await _smartCache.saveCache(updatedCache);
    logger.i(
        'Cache updated with deletions: ${cache.groups.length} -> ${updatedGroups.length} groups (sorted)');

    return updatedGroups;
  }

  /// 执行增量扫描（只扫描变化的文件）
  Future<List<DuplicateFileGroup>> _performIncrementalScan(
    DuplicateFileScanConfig config,
    DuplicateFileScanCache cache,
    Set<String> changedFilePaths,
    List<String> deletedFiles,
  ) async {
    try {
      final overallStart = DateTime.now();
      logger.i(
          '📊 Starting incremental scan for ${changedFilePaths.length} files');
      debugPrint('[增量扫描] ========== 开始执行 ==========');
      debugPrint('[增量扫描] 变化文件数: ${changedFilePaths.length}');
      debugPrint('[增量扫描] 删除文件数: ${deletedFiles.length}');

      // 通知UI：开始增量扫描
      _scanManager.updateProgress(
          config,
          ScanProgress(
            stage: 1,
            stageName: '增量扫描',
            current: 0,
            total: changedFilePaths.length,
            currentFile: '正在准备扫描...',
          ));

      // 1. 从变化的文件中创建 FileItem 对象
      final changedFiles = <FileItem>[];
      int processedCount = 0;
      for (final filePath in changedFilePaths) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            final stat = await file.stat();
            changedFiles.add(FileItem(
              path: filePath,
              name: filePath.split('/').last,
              size: stat.size,
              modified: stat.modified,
              isDirectory: false,
            ));
          }

          // 每10个文件更新一次进度
          processedCount++;
          if (processedCount % 10 == 0 ||
              processedCount == changedFilePaths.length) {
            _scanManager.updateProgress(
                config,
                ScanProgress(
                  stage: 1,
                  stageName: '增量扫描',
                  current: processedCount,
                  total: changedFilePaths.length,
                  currentFile: filePath.split('/').last,
                ));
          }
        } catch (e) {
          logger.w('Failed to create FileItem for $filePath: $e');
        }
      }

      if (changedFiles.isEmpty) {
        logger.w('No valid changed files to scan');
        debugPrint('[增量扫描] ⚠️ 没有有效的变化文件');
        return cache.groups; // 返回原缓存结果
      }

      debugPrint('[增量扫描] ✅ 准备完成，有效文件: ${changedFiles.length}');
      logger.i('Scanning ${changedFiles.length} changed files for duplicates');

      // 通知UI：开始扫描重复文件
      _scanManager.updateProgress(
          config,
          ScanProgress(
            stage: 2,
            stageName: '增量扫描',
            current: 0,
            total: changedFiles.length,
            currentFile: '正在检测重复文件...',
          ));

      // 2. 对变化的文件执行重复检测（与缓存中的所有文件比较）
      final scanDupStart = DateTime.now();
      debugPrint('[增量扫描] 🔍 开始检测重复文件...');
      final newDuplicateGroups =
          await _scanChangedFilesAgainstCache(config, changedFiles, cache);
      final scanDupDuration = DateTime.now().difference(scanDupStart);
      debugPrint('[增量扫描] ✅ 重复检测完成，耗时: ${scanDupDuration.inSeconds}s');

      logger.i(
          'Found ${newDuplicateGroups.length} duplicate groups in changed files');

      // 通知UI：合并结果
      _scanManager.updateProgress(
          config,
          ScanProgress(
            stage: 3,
            stageName: '增量扫描',
            current: changedFiles.length,
            total: changedFiles.length,
            currentFile: '正在合并扫描结果...',
          ));

      // 3. 合并结果：缓存 + 新扫描结果 - 删除的文件
      debugPrint('[增量扫描] 🔀 开始合并结果...');
      final mergeStart = DateTime.now();
      final mergedGroups =
          _mergeResults(cache.groups, newDuplicateGroups, deletedFiles.toSet());
      final mergeDuration = DateTime.now().difference(mergeStart);
      debugPrint('[增量扫描] ✅ 合并完成，耗时: ${mergeDuration.inMilliseconds}ms');

      // 4. 更新文件索引：保留原索引 + 新增文件 - 删除文件
      final updatedFileIndex =
          Map<String, FileFingerprint>.from(cache.fileIndex);

      // 删除已删除的文件
      final deletedSet = deletedFiles.toSet();
      updatedFileIndex.removeWhere((path, _) => deletedSet.contains(path));

      // 添加/更新变化的文件
      for (final file in changedFiles) {
        updatedFileIndex[file.path] = FileFingerprint.fromFileItem(file);
      }

      logger.d(
          '🔄 File index updated: ${cache.fileIndex.length} -> ${updatedFileIndex.length} files');

      // 5. 保存更新后的缓存
      final updatedCache = DuplicateFileScanCache(
        scanTime: DateTime.now(),
        config: cache.config,
        groups: mergedGroups,
        fileIndex: updatedFileIndex, // ✅ 使用完整的文件索引
      );

      await _smartCache.saveCache(updatedCache);

      final overallDuration = DateTime.now().difference(overallStart);
      logger.i(
          'Incremental scan completed: ${cache.groups.length} -> ${mergedGroups.length} groups');
      debugPrint('[增量扫描] ========== 完成 ==========');
      debugPrint(
          '[增量扫描] 结果: ${cache.groups.length} -> ${mergedGroups.length} 组');
      debugPrint('[增量扫描] 总耗时: ${overallDuration.inSeconds}s');
      debugPrint('[增量扫描] ===============================\n');

      return mergedGroups; // 返回合并后的结果
    } catch (e, stack) {
      logger.e('Incremental scan failed: $e\n$stack');
      return cache.groups; // 出错时返回原缓存结果
    }
  }

  /// 扫描变化的文件（与缓存中的所有文件比较）
  ///
  /// 核心逻辑：
  /// 1. 从 cache.fileIndex 重建所有文件（包括唯一文件）
  /// 2. 按大小分组（阶段1）
  /// 3. 只处理包含新文件的大小组
  /// 4. 阶段2：计算头部8KB哈希
  /// 5. 阶段3：计算完整MD5哈希
  /// 6. 返回包含新文件的重复组
  ///
  /// 关键修复：之前只使用 cache.groups（重复文件），导致漏检
  /// 现在使用 cache.fileIndex（所有文件），确保准确检测
  Future<List<DuplicateFileGroup>> _scanChangedFilesAgainstCache(
    DuplicateFileScanConfig config,
    List<FileItem> changedFiles,
    DuplicateFileScanCache cache,
  ) async {
    if (changedFiles.isEmpty) return [];

    try {
      logger.i(
          '🔍 Detecting duplicates: ${changedFiles.length} changed files vs ${cache.fileIndex.length} cached files');

      // 1. 从缓存重建所有文件列表（按大小分组）
      debugPrint('[重复检测] 第1步：重建缓存文件列表...');
      final allFilesBySize = <int, List<FileItem>>{};

      // ✅ 使用 fileIndex 获取缓存中的所有文件（包括唯一文件）
      for (final fingerprint in cache.fileIndex.values) {
        allFilesBySize.putIfAbsent(fingerprint.size, () => []).add(FileItem(
              path: fingerprint.path,
              name: fingerprint.path.split('/').last,
              size: fingerprint.size,
              modified: DateTime.fromMillisecondsSinceEpoch(
                  fingerprint.modifiedMillis),
              isDirectory: false,
            ));
      }

      logger.d(
          '📂 Loaded ${cache.fileIndex.length} cached files into ${allFilesBySize.length} size groups');

      // 2. 将新文件加入对应的大小组
      debugPrint('[重复检测] 第2步：合并新文件到大小组...');
      for (final file in changedFiles) {
        allFilesBySize.putIfAbsent(file.size, () => []).add(file);
      }

      // 3. 只处理包含新文件的大小组
      debugPrint('[重复检测] 第3步：筛选候选组...');
      final newFilePathsSet = changedFiles.map((f) => f.path).toSet();
      final candidateGroups = <int, List<FileItem>>{};

      for (final entry in allFilesBySize.entries) {
        final size = entry.key;
        final filesInGroup = entry.value;

        // 必须有至少2个文件，且至少有1个是新文件
        if (filesInGroup.length >= 2 &&
            filesInGroup.any((f) => newFilePathsSet.contains(f.path))) {
          candidateGroups[size] = filesInGroup;
        }
      }

      logger.d(
          '📊 Found ${candidateGroups.length} size groups with potential duplicates');
      debugPrint('[重复检测] 找到 ${candidateGroups.length} 个候选大小组');

      // 4. 使用三阶段检测（复用 DuplicateFileService 的逻辑）
      debugPrint('[重复检测] 第4步：开始计算哈希值...');
      final duplicateGroups = <DuplicateFileGroup>[];

      int processedGroups = 0;
      final totalGroups = candidateGroups.length;

      for (final sizeGroup in candidateGroups.values) {
        processedGroups++;

        // 定期更新进度
        if (processedGroups % 5 == 0 || processedGroups == totalGroups) {
          _scanManager.updateProgress(
              config,
              ScanProgress(
                stage: 2,
                stageName: '增量扫描',
                current: processedGroups,
                total: totalGroups,
                currentFile: '正在处理第 $processedGroups/$totalGroups 组文件...',
              ));
          debugPrint('[重复检测] 进度: $processedGroups/$totalGroups');
        }

        // 阶段2: 计算头部哈希（8KB）
        final headerHashGroups = await _groupByHeaderHash(sizeGroup);

        for (final headerGroup in headerHashGroups.values) {
          if (headerGroup.length < 2) continue;

          // 阶段3: 计算完整哈希（MD5）
          final fullHashGroups = await _groupByFullHash(headerGroup);

          for (final fullHashGroup in fullHashGroups.values) {
            if (fullHashGroup.length >= 2) {
              // 检查这个组是否包含至少一个新文件
              if (fullHashGroup.any((f) => newFilePathsSet.contains(f.path))) {
                duplicateGroups.add(DuplicateFileGroup(
                  groupId:
                      '${fullHashGroup.first.size}_${DateTime.now().millisecondsSinceEpoch}',
                  files: fullHashGroup,
                  fileSize: fullHashGroup.first.size,
                ));
              }
            }
          }
        }
      }

      logger.i(
          '✅ Found ${duplicateGroups.length} duplicate groups involving changed files');
      return duplicateGroups;
    } catch (e, stack) {
      logger.e('Failed to scan changed files: $e\n$stack');
      return [];
    }
  }

  /// 按头部哈希分组（8KB）
  Future<Map<String, List<FileItem>>> _groupByHeaderHash(
      List<FileItem> files) async {
    final groups = <String, List<FileItem>>{};

    for (final file in files) {
      try {
        final hash = await _baseService.calculateHeaderHash(file.path);
        groups.putIfAbsent(hash, () => []).add(file);
      } catch (e) {
        logger.w('Failed to calculate header hash for ${file.path}: $e');
      }
    }

    return groups;
  }

  /// 按完整哈希分组（MD5）
  Future<Map<String, List<FileItem>>> _groupByFullHash(
      List<FileItem> files) async {
    final groups = <String, List<FileItem>>{};

    for (final file in files) {
      try {
        final hash = await _baseService.calculateFullHash(file.path);
        groups.putIfAbsent(hash, () => []).add(file);
      } catch (e) {
        logger.w('Failed to calculate full hash for ${file.path}: $e');
      }
    }

    return groups;
  }

  /// 合并扫描结果
  ///
  /// 智能合并逻辑：
  /// 1. 清理缓存组：移除删除的文件
  /// 2. 检测新组与缓存组的重叠
  /// 3. 如果有文件路径重叠 → 合并到同一组
  /// 4. 如果完全不重叠 → 作为新组添加
  ///
  /// 关键场景：
  /// - 用户复制文件到新位置 → 原文件和新文件会被合并到同一组
  /// - 用户删除部分重复文件 → 自动清理，保持组的准确性
  /// - 多个重复组合并 → 避免同一内容被分散到不同组
  List<DuplicateFileGroup> _mergeResults(
    List<DuplicateFileGroup> cachedGroups,
    List<DuplicateFileGroup> newGroups,
    Set<String> deletedFiles,
  ) {
    final result = <DuplicateFileGroup>[];
    final processedPaths = <String>{};

    // 1. 从缓存组中移除删除的文件
    final cleanedCachedGroups = <DuplicateFileGroup>[];
    for (final group in cachedGroups) {
      final remainingFiles = group.files
          .where((file) => !deletedFiles.contains(file.path))
          .toList();

      if (remainingFiles.length >= 2) {
        cleanedCachedGroups.add(DuplicateFileGroup(
          groupId: group.groupId,
          files: remainingFiles,
          fileSize: group.fileSize,
        ));
      }
    }

    // 2. 处理新组：检查是否与缓存组有重叠
    for (final newGroup in newGroups) {
      final newGroupPaths = newGroup.files.map((f) => f.path).toSet();
      DuplicateFileGroup? matchedCachedGroup;

      // 查找是否有缓存组包含新组中的任何文件
      for (final cachedGroup in cleanedCachedGroups) {
        final cachedGroupPaths = cachedGroup.files.map((f) => f.path).toSet();

        // 如果有任何文件路径重叠，说明这是同一组
        if (newGroupPaths.intersection(cachedGroupPaths).isNotEmpty) {
          matchedCachedGroup = cachedGroup;
          break;
        }
      }

      if (matchedCachedGroup != null) {
        // 合并：缓存组的文件 + 新组中不重复的文件
        final cachedPaths = matchedCachedGroup.files.map((f) => f.path).toSet();
        final additionalFiles =
            newGroup.files.where((f) => !cachedPaths.contains(f.path)).toList();

        if (additionalFiles.isNotEmpty) {
          // 创建合并后的组
          final mergedFiles = [...matchedCachedGroup.files, ...additionalFiles];
          final mergedGroup = DuplicateFileGroup(
            groupId: matchedCachedGroup.groupId,
            files: mergedFiles,
            fileSize: matchedCachedGroup.fileSize,
          );

          // 替换缓存组
          cleanedCachedGroups.remove(matchedCachedGroup);
          cleanedCachedGroups.add(mergedGroup);

          logger.d(
              '📦 Merged group: ${matchedCachedGroup.files.length} + ${additionalFiles.length} = ${mergedFiles.length} files');
        }

        // 标记这些路径已处理
        processedPaths.addAll(newGroupPaths);
      } else {
        // 这是一个完全新的组（新文件之间互相重复）
        result.add(newGroup);
        processedPaths.addAll(newGroupPaths);
        logger.d('✨ New group: ${newGroup.files.length} files');
      }
    }

    // 3. 添加所有清理后的缓存组
    result.addAll(cleanedCachedGroups);

    // ✅ 对合并后的结果排序：按可释放空间从大到小
    result.sort((a, b) => b.reclaimableSpace.compareTo(a.reclaimableSpace));

    logger.i(
        '🔄 Merge complete: ${cachedGroups.length} cached + ${newGroups.length} new = ${result.length} total groups (sorted)');

    return result;
  }

  /// 构建文件索引
  /// 检测文件变化
  Future<FileChanges> _detectFileChanges(
    DuplicateFileScanConfig config,
    DuplicateFileScanCache cache,
  ) async {
    try {
      final changes = FileChanges();
      final cacheTime = cache.scanTime;
      final minSizeInBytes = config.minSizeInKB * 1024;

      debugPrint('\n[文件变化检测] 开始扫描文件系统...');
      debugPrint('[文件变化检测] 最小文件大小: ${config.minSizeInKB}KB');

      // 重新获取扫描路径（使用相同的逻辑）
      debugPrint('[文件变化检测] 正在获取扫描路径...');
      final scanPaths = await _baseService.presenter.getCommonScanPaths();
      debugPrint('[文件变化检测] ✅ 获取扫描路径成功');

      debugPrint('\n[文件变化检测] 🔍 本次使用的扫描路径列表 (${scanPaths.length} 个):');
      for (var i = 0; i < scanPaths.length; i++) {
        debugPrint('  [路径 ${i + 1}] ${scanPaths[i]}');
      }

      for (final scanPath in scanPaths) {
        debugPrint('\n[文件变化检测] 正在扫描: $scanPath');
        await _scanPathForChanges(
          scanPath,
          cacheTime,
          minSizeInBytes,
          config.fileTypes,
          cache.fileIndex,
          changes,
        );
        debugPrint(
            '[文件变化检测] 扫描完成: $scanPath (当前累计: +${changes.addedFiles.length} ~${changes.modifiedFiles.length} -${changes.deletedFiles.length})');
      }

      debugPrint('\n[文件变化检测] 所有路径扫描完成');
      return changes;
    } catch (e, stack) {
      logger.e('[文件变化检测] ❌ 发生异常: $e\n$stack');
      debugPrint('[文件变化检测] ❌ 异常: $e');
      rethrow;
    }
  }

  /// 扫描指定路径的文件变化
  Future<void> _scanPathForChanges(
    String pathStr,
    DateTime cacheTime,
    int minSizeInBytes,
    Set<FileTypeFilter> fileTypes,
    Map<String, FileFingerprint> cacheIndex,
    FileChanges changes,
  ) async {
    try {
      final directory = Directory(pathStr);
      if (!directory.existsSync()) {
        debugPrint('[路径扫描] ⚠️ 路径不存在: $pathStr');
        return;
      }

      final currentFiles = <String>{};

      // 🔧 使用对象包装计数器，实现引用传递
      final stats = _ScanStats();

      // 🔧 使用递归函数手动控制扫描，与第一次扫描逻辑保持一致
      await _scanDirectoryForChanges(
        directory,
        minSizeInBytes,
        fileTypes,
        cacheIndex,
        changes,
        currentFiles,
        stats,
        0, // currentDepth
        15, // maxDepth（与第一次扫描保持一致）
      );

      debugPrint('\n[路径扫描] 统计信息:');
      debugPrint('  - 扫描文件总数: ${stats.scannedCount}');
      debugPrint('  - 跳过(大小过小): ${stats.skippedSizeCount}');
      debugPrint('  - 跳过(类型不符): ${stats.skippedTypeCount}');
      debugPrint('  - 跳过(隐藏文件): ${stats.skippedHiddenCount}');
      debugPrint('  - 符合条件文件: ${currentFiles.length}');
      debugPrint(
          '  - 最小大小阈值: ${(minSizeInBytes / 1024).toStringAsFixed(0)} KB');
      debugPrint('  - 缓存时间: $cacheTime');

      // 检查删除的文件
      for (final cachedPath in cacheIndex.keys) {
        if (cachedPath.startsWith(pathStr) &&
            !currentFiles.contains(cachedPath)) {
          changes.deletedFiles.add(cachedPath);
        }
      }
    } catch (e) {
      logger.w('Error scanning path for changes: $pathStr, $e');
    }
  }

  /// 递归扫描目录检测变化（与第一次扫描逻辑保持一致）
  Future<void> _scanDirectoryForChanges(
    Directory directory,
    int minSizeInBytes,
    Set<FileTypeFilter> fileTypes,
    Map<String, FileFingerprint> cacheIndex,
    FileChanges changes,
    Set<String> currentFiles,
    _ScanStats stats,
    int currentDepth,
    int maxDepth,
  ) async {
    if (currentDepth >= maxDepth) {
      debugPrint('[目录扫描] ⚠️ 已达最大深度限制: $maxDepth');
      return;
    }

    try {
      if (currentDepth == 0) {
        debugPrint('[目录扫描] 开始扫描根目录: ${directory.path}');
      }

      await for (final entity in directory.list(followLinks: false)) {
        try {
          final name = path.basename(entity.path);

          // 🔧 跳过隐藏文件和目录（与第一次扫描保持一致）
          if (name.startsWith('.')) {
            stats.skippedHiddenCount++;
            continue;
          }

          if (entity is File) {
            stats.scannedCount++;
            final stat = await entity.stat();

            // 🔧 跳过临时下载文件
            final fileName = path.basename(entity.path).toLowerCase();
            if (fileName.endsWith('.downloading') ||
                fileName.endsWith('.download') ||
                fileName.endsWith('.tmp') ||
                fileName.endsWith('.temp') ||
                fileName.contains('.p.downloading')) {
              stats.skippedTypeCount++; // 统计跳过数量
              continue;
            }

            // 检查文件大小
            if (stat.size < minSizeInBytes) {
              stats.skippedSizeCount++;
              continue;
            }

            // 检查文件类型
            if (!_matchesFileType(entity.path, fileTypes)) {
              stats.skippedTypeCount++;
              continue;
            }

            currentFiles.add(entity.path);

            final cachedFingerprint = cacheIndex[entity.path];

            if (cachedFingerprint == null) {
              // 新文件：缓存中不存在的文件
              changes.addedFiles.add(entity.path);
              debugPrint('\n[新文件] ✨ ${entity.path}');
              debugPrint(
                  '  - 大小: ${(stat.size / 1024 / 1024).toStringAsFixed(2)} MB');
              debugPrint('  - 修改时间: ${stat.modified}');
              debugPrint('  - 在缓存中: ❌ 不存在');
            } else {
              // 检查是否修改
              final currentFingerprint = FileFingerprint(
                path: entity.path,
                size: stat.size,
                modifiedMillis: stat.modified.millisecondsSinceEpoch,
              );

              if (cachedFingerprint.hasChanged(currentFingerprint)) {
                changes.modifiedFiles.add(entity.path);
                debugPrint('\n[修改文件] 🔄 ${entity.path}');
                debugPrint(
                    '  - 缓存大小: ${cachedFingerprint.size} → 当前大小: ${stat.size}');
                debugPrint(
                    '  - 缓存时间: ${DateTime.fromMillisecondsSinceEpoch(cachedFingerprint.modifiedMillis)} → 当前时间: ${stat.modified}');
              }
            }
          } else if (entity is Directory) {
            // 🔧 跳过排除的文件夹（与第一次扫描保持一致）
            if (FilePresenter.excludedFolders.contains(name)) {
              // Android目录特殊处理：只扫描Android/data
              if (name == 'Android') {
                final dataDir = Directory(path.join(entity.path, 'data'));
                if (dataDir.existsSync()) {
                  await _scanDirectoryForChanges(
                    dataDir,
                    minSizeInBytes,
                    fileTypes,
                    cacheIndex,
                    changes,
                    currentFiles,
                    stats,
                    currentDepth + 1,
                    maxDepth + 5, // ✅ Android/data额外增加5层深度（总共20层）
                  );
                }
              }
              continue;
            }

            // 递归扫描子目录
            await _scanDirectoryForChanges(
              entity,
              minSizeInBytes,
              fileTypes,
              cacheIndex,
              changes,
              currentFiles,
              stats,
              currentDepth + 1,
              maxDepth,
            );
          }
        } catch (e) {
          // 忽略单个文件/目录的错误
        }
      }
    } catch (e) {
      logger.w('Error listing directory ${directory.path}: $e');
    }
  }

  /// 判断文件类型是否匹配（与第一次扫描逻辑保持一致）
  bool _matchesFileType(String filePath, Set<FileTypeFilter> fileTypes) {
    // 🔧 如果没有指定文件类型（所有类型），接受所有文件
    if (fileTypes.isEmpty) return true;

    final ext = path.extension(filePath).toLowerCase();

    const videoExtensions = [
      '.mp4',
      '.avi',
      '.mkv',
      '.mov',
      '.wmv',
      '.flv',
      '.webm',
      '.m4v',
      '.3gp'
    ];
    const audioExtensions = [
      '.mp3',
      '.m4a',
      '.wav',
      '.flac',
      '.aac',
      '.ogg',
      '.wma',
      '.opus',
      '.amr'
    ];
    const imageExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.heic',
      '.heif',
      '.svg'
    ];
    const documentExtensions = [
      '.pdf',
      '.doc',
      '.docx',
      '.xls',
      '.xlsx',
      '.ppt',
      '.pptx',
      '.txt',
      '.html', // 网页文件
      '.htm',
      '.md', // Markdown
      '.rtf', // 富文本
      '.csv', // 数据表格
      '.json', // 配置文件
      '.xml', // 配置文件
    ];
    const archiveExtensions = [
      '.zip',
      '.rar',
      '.7z',
      '.tar',
      '.gz',
      '.bz2',
      '.apk', // Android 安装包（实际是 zip 格式）
      '.xz', // 现代压缩格式
      '.zst', // Zstandard 压缩
    ];

    for (final type in fileTypes) {
      switch (type) {
        case FileTypeFilter.video:
          if (videoExtensions.contains(ext)) return true;
          break;
        case FileTypeFilter.audio:
          if (audioExtensions.contains(ext)) return true;
          break;
        case FileTypeFilter.image:
          if (imageExtensions.contains(ext)) return true;
          break;
        case FileTypeFilter.document:
          if (documentExtensions.contains(ext)) return true;
          break;
        case FileTypeFilter.archive:
          if (archiveExtensions.contains(ext)) return true;
          break;
        case FileTypeFilter.other:
          if (!videoExtensions.contains(ext) &&
              !audioExtensions.contains(ext) &&
              !imageExtensions.contains(ext) &&
              !documentExtensions.contains(ext) &&
              !archiveExtensions.contains(ext)) {
            return true;
          }
          break;
      }
    }

    return false;
  }

  /// 全量扫描并缓存结果
  Future<List<DuplicateFileGroup>> _fullScanWithCache(
    DuplicateFileScanConfig config,
  ) async {
    // 使用后台扫描管理器执行扫描
    await _scanManager.startScan(_baseService, config);

    // 等待扫描完成
    while (_scanManager.state == DuplicateScanState.scanning) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 检查结果
    if (_scanManager.state == DuplicateScanState.error) {
      throw Exception(_scanManager.errorMessage ?? '扫描失败');
    }

    final groups = _scanManager.getCachedGroupsFor(config);

    // 保存到缓存
    await _saveScanResultsToCache(config, groups);

    return groups;
  }

  /// 保存扫描结果到缓存
  Future<void> _saveScanResultsToCache(
    DuplicateFileScanConfig config,
    List<DuplicateFileGroup> groups,
  ) async {
    try {
      // 📊 统计重复组中的文件总数（用于诊断）
      final filesInGroups =
          groups.fold<int>(0, (sum, group) => sum + group.files.length);

      // 🔧 获取指定配置的所有扫描文件列表（而不是使用 _activeConfig）
      final allFiles = _scanManager.getAllScannedFilesFor(config) ?? [];

      if (allFiles.isEmpty) {
        logger.e(
            '❌ CRITICAL: No scanned files available for config: ${config.description}');
        logger.e(
            '   This means onFilesCollected callback was not called properly.');
        logger.w('⚠️ Falling back to files in groups only (OLD BEHAVIOR)');
      }

      // 构建文件索引（使用所有扫描的文件）
      final fileIndex = <String, FileFingerprint>{};

      if (allFiles.isNotEmpty) {
        // ✅ 新方案：从所有扫描的文件构建索引
        for (final file in allFiles) {
          fileIndex[file.path] = FileFingerprint.fromFileItem(file);
        }
        logger.d(
            '✅ Built file index from all scanned files: ${fileIndex.length} unique files');
      } else {
        // ❌ 降级方案：只从重复组构建索引（旧逻辑）
        for (final group in groups) {
          for (final file in group.files) {
            fileIndex[file.path] = FileFingerprint.fromFileItem(file);
          }
        }
        logger.w(
            '⚠️ Built file index from duplicate groups only: ${fileIndex.length} unique files');
      }

      // 📊 诊断日志：检测差异
      if (allFiles.isNotEmpty) {
        logger.i('📊 Cache Statistics:');
        logger.i('   - Total files scanned: ${allFiles.length}');
        logger.i('   - Files in duplicate groups: $filesInGroups');
        logger.i('   - Unique file paths cached: ${fileIndex.length}');
        logger.i('   - Duplicate groups: ${groups.length}');

        if (allFiles.length != fileIndex.length) {
          logger.w(
              '   ⚠️ Path deduplication: ${allFiles.length - fileIndex.length} duplicate paths removed');
        }

        if (filesInGroups != fileIndex.length && allFiles.isEmpty) {
          logger.w(
              '   ⚠️ File count mismatch: $filesInGroups in groups → ${fileIndex.length} unique paths');
        }
      }

      // 创建缓存对象
      final cache = DuplicateFileScanCache(
        scanTime: DateTime.now(),
        config: config,
        groups: groups,
        fileIndex: fileIndex,
      );

      // 保存
      await _smartCache.saveCache(cache);

      // ✅ 最终验证：确保缓存的文件数量符合预期
      if (allFiles.isNotEmpty && fileIndex.length < allFiles.length * 0.9) {
        logger.w(
            '⚠️ WARNING: Cached file count (${fileIndex.length}) is significantly less than scanned files (${allFiles.length})');
        logger
            .w('   This may indicate a problem with file index construction.');
      } else if (allFiles.isNotEmpty) {
        logger.i(
            '✅ Scan results cached successfully (${groups.length} groups, ${fileIndex.length} files)');
      } else {
        logger.w(
            '⚠️ Scan results cached with fallback (${groups.length} groups, ${fileIndex.length} files from duplicate groups only)');
      }

      // ⚡ 优化：保存完成后立即清除内存中的文件列表
      _scanManager.clearScannedFiles(config);
    } catch (e) {
      logger.e('Failed to save cache: $e');
    }
  }

  /// 获取稳定的扫描路径（只返回系统预定义目录，不做动态发现）
  ///
  /// 这避免了动态发现用户文件夹导致的路径不一致问题
  /// 清除缓存
  Future<void> clearCache(DuplicateFileScanConfig config) async {
    logger.i('Clearing cache for config: ${config.description}');

    // 1. 取消该配置的扫描（如果正在进行）
    final state = _scanManager.getStateFor(config);
    if (state == DuplicateScanState.scanning) {
      logger.i('  - Cancelling ongoing scan for this config');
      _scanManager.cancelScan(config);
    }

    // 2. 清除缓存
    await _smartCache.clearCache(config);

    // 3. 清除扫描管理器的缓存状态
    _scanManager.clearCache(config);

    logger.i('✅ Cache cleared for config: ${config.description}');
  }

  /// 清除所有缓存
  Future<void> clearAllCaches() async {
    logger.i('Clearing all caches');

    // 1. 取消所有正在进行的扫描
    logger.i('  - Cancelling all ongoing scans');
    _scanManager.cancelAllScans();

    // 2. 清除持久化缓存
    await _smartCache.clearAllCaches();

    logger.i('✅ All caches cleared');
  }

  /// 获取缓存大小
  Future<int> getCacheSize() async {
    return await _smartCache.getTotalCacheSize();
  }
}
