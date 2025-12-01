import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/duplicate_file_scan_config.dart';
import 'package:easyfile/core/services/duplicate_file_service.dart';
import 'package:easyfile/data/models/duplicate_file_group.dart';
import 'package:easyfile/data/models/file_item.dart';

/// 重复文件扫描状态
enum DuplicateScanState {
  /// 空闲状态
  idle,

  /// 扫描中
  scanning,

  /// 扫描完成
  completed,

  /// 扫描错误
  error,
}

/// 扫描进度信息
class ScanProgress {
  /// 当前阶段 (1-4)
  final int stage;

  /// 阶段名称
  final String stageName;

  /// 当前进度
  final int current;

  /// 总数
  final int total;

  /// 当前处理的文件
  final String currentFile;

  /// 进度百分比 (0-100)
  double get percentage {
    if (total == 0) return 0;
    return (current / total * 100).clamp(0, 100);
  }

  const ScanProgress({
    required this.stage,
    required this.stageName,
    required this.current,
    required this.total,
    required this.currentFile,
  });

  @override
  String toString() {
    return 'ScanProgress(stage: $stage/$stageName, $current/$total, ${percentage.toStringAsFixed(1)}%)';
  }
}

/// 单个配置的扫描状态（内部类）
class _ConfigScanState {
  /// 当前扫描状态
  DuplicateScanState state = DuplicateScanState.idle;

  /// 缓存的扫描结果
  List<DuplicateFileGroup> cachedGroups = [];

  /// 所有扫描的文件列表
  List<FileItem>? allScannedFiles;

  /// 当前进度
  ScanProgress? currentProgress;

  /// 错误信息
  String? errorMessage;

  /// 扫描开始时间
  DateTime? scanStartTime;

  /// 扫描完成时间
  DateTime? scanCompletionTime;

  /// 当前扫描任务的取消令牌
  Completer<void>? cancelToken;

  /// 是否已请求取消
  bool isCancellationRequested = false;

  /// 状态变化监听器
  final List<VoidCallback> stateListeners = [];

  /// 进度更新监听器
  final List<void Function(ScanProgress)> progressListeners = [];

  /// 完成回调监听器
  final List<void Function(List<DuplicateFileGroup>)> completionListeners = [];

  /// 错误回调监听器
  final List<void Function(String)> errorListeners = [];
}

/// 后台扫描管理器（单例）
///
/// 负责管理重复文件扫描的生命周期，支持：
/// - 🔄 后台扫描：用户可以离开页面，扫描继续进行
/// - 💾 内存缓存：应用未关闭期间，扫描结果保持有效
/// - 📊 进度跟踪：实时更新扫描进度
/// - 🔔 完成通知：扫描完成后通知所有监听者
/// - ✨ 多配置支持：每个配置独立状态和缓存
class DuplicateFileScanManager {
  // 单例实例
  static final DuplicateFileScanManager _instance =
      DuplicateFileScanManager._internal();

  factory DuplicateFileScanManager() => _instance;

  DuplicateFileScanManager._internal();

  // ==================== 多状态管理 ====================

  /// 多配置状态存储（key = 配置缓存key）
  final Map<String, _ConfigScanState> _scanStates = {};

  /// 获取或创建指定配置的状态
  _ConfigScanState _getState(DuplicateFileScanConfig config) {
    final key = _getCacheKey(config);
    return _scanStates.putIfAbsent(key, () => _ConfigScanState());
  }

  /// 生成配置缓存key
  String _getCacheKey(DuplicateFileScanConfig config) {
    return '${config.scanMode.name}_${config.selectedType?.name ?? 'all'}_${config.minSizeInKB}';
  }

  // ==================== 兼容性API（委托到当前活跃配置）====================

  /// 当前活跃的配置（最后一次操作的配置）
  DuplicateFileScanConfig? _activeConfig;

  // ==================== 状态查询API（按配置）====================

  /// 获取指定配置的扫描状态
  DuplicateScanState getStateFor(DuplicateFileScanConfig config) {
    return _getState(config).state;
  }

  /// 获取指定配置的缓存结果
  ///
  /// 🔑 关键方法：在并发扫描场景下，必须使用此方法而非 cachedGroups getter
  /// 避免读取到错误配置的缓存数据
  List<DuplicateFileGroup> getCachedGroupsFor(DuplicateFileScanConfig config) {
    return List.unmodifiable(_getState(config).cachedGroups);
  }

  /// 获取指定配置的当前进度
  ScanProgress? getCurrentProgressFor(DuplicateFileScanConfig config) {
    return _getState(config).currentProgress;
  }

  // ==================== 兼容性API（委托到当前活跃配置）====================

  /// 当前扫描状态（兼容旧API）
  /// ⚠️ 警告：并发扫描时，_activeConfig 会动态变化，建议使用 getStateFor(config)
  DuplicateScanState get state {
    if (_activeConfig == null) return DuplicateScanState.idle;
    return _getState(_activeConfig!).state;
  }

  /// 缓存的扫描结果（兼容旧API）
  /// ⚠️ 警告：并发扫描时可能返回错误配置的数据，建议使用 getCachedGroupsFor(config)
  List<DuplicateFileGroup> get cachedGroups {
    if (_activeConfig == null) return [];
    return List.unmodifiable(_getState(_activeConfig!).cachedGroups);
  }

  /// 所有扫描的文件列表（兼容旧API）
  /// ⚠️ 警告：并发扫描时可能返回错误配置的数据，建议使用 getAllScannedFilesFor(config)
  List<FileItem>? get allScannedFiles {
    if (_activeConfig == null) return null;
    final files = _getState(_activeConfig!).allScannedFiles;
    return files != null ? List.unmodifiable(files) : null;
  }

  /// 获取指定配置的所有扫描文件列表
  ///
  /// 🔑 关键方法：在并发扫描场景下，必须使用此方法而非 allScannedFiles getter
  /// 确保获取到正确配置的扫描文件列表
  List<FileItem>? getAllScannedFilesFor(DuplicateFileScanConfig config) {
    final files = _getState(config).allScannedFiles;
    return files != null ? List.unmodifiable(files) : null;
  }

  /// 当前扫描配置（兼容旧API）
  DuplicateFileScanConfig? get currentConfig => _activeConfig;

  /// 当前进度（兼容旧API）
  ScanProgress? get currentProgress {
    if (_activeConfig == null) return null;
    return _getState(_activeConfig!).currentProgress;
  }

  /// 错误信息（兼容旧API）
  String? get errorMessage {
    if (_activeConfig == null) return null;
    return _getState(_activeConfig!).errorMessage;
  }

  /// 扫描开始时间（兼容旧API）
  DateTime? get scanStartTime {
    if (_activeConfig == null) return null;
    return _getState(_activeConfig!).scanStartTime;
  }

  /// 扫描完成时间（兼容旧API）
  DateTime? get scanCompletionTime {
    if (_activeConfig == null) return null;
    return _getState(_activeConfig!).scanCompletionTime;
  }

  // ==================== 监听器管理（按配置）====================

  /// 添加状态监听器
  void addStateListener(DuplicateFileScanConfig config, VoidCallback listener) {
    _getState(config).stateListeners.add(listener);
  }

  /// 移除状态监听器
  void removeStateListener(
      DuplicateFileScanConfig config, VoidCallback listener) {
    final state = _getState(config);
    state.stateListeners.remove(listener);
  }

  /// 添加进度监听器
  void addProgressListener(
      DuplicateFileScanConfig config, void Function(ScanProgress) listener) {
    _getState(config).progressListeners.add(listener);
  }

  /// 移除进度监听器
  void removeProgressListener(
      DuplicateFileScanConfig config, void Function(ScanProgress) listener) {
    _getState(config).progressListeners.remove(listener);
  }

  /// 添加完成监听器
  void addCompletionListener(DuplicateFileScanConfig config,
      void Function(List<DuplicateFileGroup>) listener) {
    _getState(config).completionListeners.add(listener);
  }

  /// 移除完成监听器
  void removeCompletionListener(DuplicateFileScanConfig config,
      void Function(List<DuplicateFileGroup>) listener) {
    _getState(config).completionListeners.remove(listener);
  }

  /// 添加错误监听器
  void addErrorListener(
      DuplicateFileScanConfig config, void Function(String) listener) {
    _getState(config).errorListeners.add(listener);
  }

  /// 移除错误监听器
  void removeErrorListener(
      DuplicateFileScanConfig config, void Function(String) listener) {
    _getState(config).errorListeners.remove(listener);
  }

  /// 通知状态变化
  void _notifyStateChange(DuplicateFileScanConfig config) {
    final state = _getState(config);
    for (final listener in List.from(state.stateListeners)) {
      try {
        listener();
      } catch (e) {
        logger.e('Error notifying state listener: $e');
      }
    }
  }

  /// 通知进度更新
  void _notifyProgress(DuplicateFileScanConfig config, ScanProgress progress) {
    final state = _getState(config);
    state.currentProgress = progress;
    for (final listener in List.from(state.progressListeners)) {
      try {
        listener(progress);
      } catch (e) {
        logger.e('Error notifying progress listener: $e');
      }
    }
  }

  /// 手动更新进度（用于增量更新等场景）
  void updateProgress(DuplicateFileScanConfig config, ScanProgress progress) {
    _notifyProgress(config, progress);
  }

  /// 通知扫描完成
  void _notifyCompletion(
      DuplicateFileScanConfig config, List<DuplicateFileGroup> groups) {
    final state = _getState(config);
    for (final listener in List.from(state.completionListeners)) {
      try {
        listener(groups);
      } catch (e) {
        logger.e('Error notifying completion listener: $e');
      }
    }
  }

  /// 通知错误
  void _notifyError(DuplicateFileScanConfig config, String message) {
    final state = _getState(config);
    for (final listener in List.from(state.errorListeners)) {
      try {
        listener(message);
      } catch (e) {
        logger.e('Error notifying error listener: $e');
      }
    }
  }

  /// 开始扫描
  ///
  /// 如果同配置已有扫描在进行，会先取消旧扫描
  Future<void> startScan(
    DuplicateFileService service,
    DuplicateFileScanConfig config,
  ) async {
    // 设置为活跃配置
    _activeConfig = config;

    final state = _getState(config);

    // 如果该配置正在扫描，先取消
    if (state.state == DuplicateScanState.scanning) {
      logger.w('Previous scan for this config is still running, cancelling it');
      await cancelScan(config);
    }

    // 重置该配置的状态
    state.state = DuplicateScanState.scanning;
    state.currentProgress = null;
    state.errorMessage = null;
    state.scanStartTime = DateTime.now();
    state.scanCompletionTime = null;
    state.isCancellationRequested = false;
    state.cancelToken = Completer<void>();

    _notifyStateChange(config);

    logger.i('Starting background scan with config: $config');

    try {
      // 📊 临时存储：用于收集扫描过程中的所有文件
      List<FileItem>? collectedFiles;

      // 执行扫描
      final groups = await service.scanDuplicateFiles(
        config: config,
        onProgress: (stage, current, total, currentFile) {
          // 检查是否已取消
          if (state.isCancellationRequested) {
            throw Exception('Scan cancelled by user');
          }

          // 更新进度
          final stageName = _getStageName(stage);
          final progress = ScanProgress(
            stage: stage,
            stageName: stageName,
            current: current,
            total: total,
            currentFile: currentFile,
          );

          _notifyProgress(config, progress);
        },
        onFilesCollected: (files) {
          // 📊 保存收集到的所有文件
          collectedFiles = files;
          logger.d('Files collected in scan manager: ${files.length} files');
        },
      );

      // 检查是否已取消
      if (state.isCancellationRequested) {
        logger.i('Scan was cancelled');
        state.state = DuplicateScanState.idle;
        _notifyStateChange(config);
        return;
      }

      // 扫描成功
      state.cachedGroups = groups;
      state.allScannedFiles = collectedFiles; // 保存所有扫描的文件
      state.state = DuplicateScanState.completed;
      state.scanCompletionTime = DateTime.now();

      final duration =
          state.scanCompletionTime!.difference(state.scanStartTime!);
      logger.i(
          'Scan completed successfully in ${duration.inSeconds} seconds, found ${groups.length} groups');

      // 📊 诊断日志 + 验证
      if (state.allScannedFiles != null) {
        logger.i(
            '✅ All scanned files stored in manager: ${state.allScannedFiles!.length} files');
      } else {
        logger.w(
            '⚠️ WARNING: allScannedFiles is null! onFilesCollected callback may not have been called');
      }

      _notifyStateChange(config);
      _notifyCompletion(config, groups);
    } catch (e, stackTrace) {
      logger.e('Scan failed: $e\n$stackTrace');

      state.state = DuplicateScanState.error;
      state.errorMessage = e.toString();
      state.cachedGroups = [];

      _notifyStateChange(config);
      _notifyError(config, state.errorMessage!);
    } finally {
      state.cancelToken?.complete();
      state.cancelToken = null;
    }
  }

  /// 取消指定配置的扫描
  Future<void> cancelScan(DuplicateFileScanConfig config) async {
    final state = _getState(config);

    if (state.state != DuplicateScanState.scanning) {
      logger.w('No scan to cancel for this config');
      return;
    }

    logger.i('Cancelling scan for config: ${config.description}');
    state.isCancellationRequested = true;

    // 等待扫描任务完成或超时
    if (state.cancelToken != null && !state.cancelToken!.isCompleted) {
      await state.cancelToken!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          logger.w('Cancel operation timed out');
        },
      );
    }
  }

  /// 取消所有正在进行的扫描
  Future<void> cancelAllScans() async {
    logger.i('Cancelling all ongoing scans');

    final cancelFutures = <Future<void>>[];

    for (final entry in _scanStates.entries) {
      final state = entry.value;
      if (state.state == DuplicateScanState.scanning) {
        final configKey = entry.key;
        logger.i('  - Cancelling scan: $configKey');
        state.isCancellationRequested = true;

        if (state.cancelToken != null && !state.cancelToken!.isCompleted) {
          cancelFutures.add(
            state.cancelToken!.future.timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                logger.w('Cancel operation timed out for: $configKey');
              },
            ),
          );
        }
      }
    }

    if (cancelFutures.isNotEmpty) {
      await Future.wait(cancelFutures);
      logger.i('✅ All scans cancelled (${cancelFutures.length} scans)');
    } else {
      logger.i('No ongoing scans to cancel');
    }
  }

  /// 手动设置扫描状态（用于增量更新等场景）
  void setStateManually(
      DuplicateFileScanConfig config, DuplicateScanState newState) {
    _activeConfig = config;
    final state = _getState(config);

    if (state.state == newState) return;

    logger.d('Manually setting state for config: ${state.state} -> $newState');
    state.state = newState;

    if (newState == DuplicateScanState.scanning) {
      state.scanStartTime = DateTime.now();
      state.scanCompletionTime = null;
    } else if (newState == DuplicateScanState.completed) {
      state.scanCompletionTime = DateTime.now();
    }

    _notifyStateChange(config);
  }

  /// 手动设置错误状态
  void setErrorManually(DuplicateFileScanConfig config, String errorMessage) {
    _activeConfig = config;
    final state = _getState(config);

    logger.e('Manually setting error: $errorMessage');
    state.state = DuplicateScanState.error;
    state.errorMessage = errorMessage;
    state.scanCompletionTime = DateTime.now();

    _notifyStateChange(config);
    _notifyError(config, errorMessage);
  }

  /// 手动完成扫描（用于增量更新等场景）
  void completeWithResults(
      DuplicateFileScanConfig config, List<DuplicateFileGroup> groups) {
    final t1 = DateTime.now();
    logger.i(
        '[${t1.toIso8601String()}] completeWithResults started with ${groups.length} groups');

    _activeConfig = config;
    final state = _getState(config);

    state.cachedGroups = groups;
    state.state = DuplicateScanState.completed;
    state.scanCompletionTime = DateTime.now();

    final t2 = DateTime.now();
    logger.i(
        '[${t2.toIso8601String()}] About to notify state change, delay: ${t2.difference(t1).inMilliseconds}ms');
    _notifyStateChange(config);

    final t3 = DateTime.now();
    logger.i(
        '[${t3.toIso8601String()}] About to notify completion, delay: ${t3.difference(t2).inMilliseconds}ms');
    _notifyCompletion(config, groups);

    final t4 = DateTime.now();
    logger.i(
        '[${t4.toIso8601String()}] All notifications sent, total delay: ${t4.difference(t1).inMilliseconds}ms');
  }

  /// 清除指定配置的缓存
  void clearCache(DuplicateFileScanConfig config) {
    logger.i('Clearing cache for config: ${config.description}');
    final key = _getCacheKey(config);

    final state = _scanStates[key];
    if (state != null) {
      state.cachedGroups = [];
      state.allScannedFiles = null;
      state.currentProgress = null;
      state.errorMessage = null;
      state.scanStartTime = null;
      state.scanCompletionTime = null;

      if (state.state == DuplicateScanState.completed ||
          state.state == DuplicateScanState.error) {
        state.state = DuplicateScanState.idle;
        _notifyStateChange(config);
      }
    }

    // 如果清除的是当前活跃配置，重置活跃配置
    if (_activeConfig != null && _activeConfig!.isEquivalent(config)) {
      _activeConfig = null;
    }
  }

  /// 检查指定配置是否有缓存的结果
  bool hasCachedResults(DuplicateFileScanConfig config) {
    final state = _getState(config);
    return state.state == DuplicateScanState.completed &&
        state.cachedGroups.isNotEmpty;
  }

  /// 清除扫描的文件列表（用于在保存缓存后释放内存）
  void clearScannedFiles(DuplicateFileScanConfig config) {
    final state = _getState(config);
    if (state.allScannedFiles != null) {
      logger.d(
          'Clearing scanned files list (${state.allScannedFiles!.length} files)');
      state.allScannedFiles = null;
    }
  }

  /// 获取扫描耗时
  Duration? getScanDuration(DuplicateFileScanConfig config) {
    final state = _getState(config);
    if (state.scanStartTime == null) return null;

    if (state.scanCompletionTime != null) {
      return state.scanCompletionTime!.difference(state.scanStartTime!);
    } else if (state.state == DuplicateScanState.scanning) {
      return DateTime.now().difference(state.scanStartTime!);
    }

    return null;
  }

  /// 获取阶段名称
  String _getStageName(int stage) {
    switch (stage) {
      case 1:
        return '收集文件';
      case 2:
        return '按大小分组';
      case 3:
        return '计算头部哈希';
      case 4:
        return '计算完整哈希';
      default:
        return '处理中';
    }
  }

  /// 释放所有资源
  void dispose() {
    logger.d('DuplicateFileScanManager disposing');

    // 取消所有正在进行的扫描
    for (final entry in _scanStates.entries) {
      if (entry.value.state == DuplicateScanState.scanning) {
        // 设置取消标志
        entry.value.isCancellationRequested = true;
        entry.value.cancelToken?.complete();
      }
    }

    // 清除所有状态和监听器
    for (final state in _scanStates.values) {
      state.stateListeners.clear();
      state.progressListeners.clear();
      state.completionListeners.clear();
      state.errorListeners.clear();
    }
    _scanStates.clear();

    _activeConfig = null;
  }
}
