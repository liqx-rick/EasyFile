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

/// 后台扫描管理器（单例）
/// 
/// 负责管理重复文件扫描的生命周期，支持：
/// - 🔄 后台扫描：用户可以离开页面，扫描继续进行
/// - 💾 内存缓存：应用未关闭期间，扫描结果保持有效
/// - 📊 进度跟踪：实时更新扫描进度
/// - 🔔 完成通知：扫描完成后通知所有监听者
class DuplicateFileScanManager {
  // 单例实例
  static final DuplicateFileScanManager _instance = DuplicateFileScanManager._internal();
  
  factory DuplicateFileScanManager() => _instance;
  
  DuplicateFileScanManager._internal();
  
  // ==================== 状态管理 ====================
  
  /// 当前扫描状态
  DuplicateScanState _state = DuplicateScanState.idle;
  DuplicateScanState get state => _state;
  
  /// 缓存的扫描结果
  List<DuplicateFileGroup> _cachedGroups = [];
  List<DuplicateFileGroup> get cachedGroups => List.unmodifiable(_cachedGroups);
  
  /// 所有扫描的文件列表（用于构建完整的文件索引缓存）
  List<FileItem>? _allScannedFiles;
  List<FileItem>? get allScannedFiles => _allScannedFiles != null 
      ? List.unmodifiable(_allScannedFiles!) 
      : null;
  
  /// 当前扫描配置
  DuplicateFileScanConfig? _currentConfig;
  DuplicateFileScanConfig? get currentConfig => _currentConfig;
  
  /// 当前进度
  ScanProgress? _currentProgress;
  ScanProgress? get currentProgress => _currentProgress;
  
  /// 错误信息
  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  
  /// 扫描开始时间
  DateTime? _scanStartTime;
  DateTime? get scanStartTime => _scanStartTime;
  
  /// 扫描完成时间
  DateTime? _scanCompletionTime;
  DateTime? get scanCompletionTime => _scanCompletionTime;
  
  // ==================== 监听器管理 ====================
  
  /// 状态变化监听器
  final List<VoidCallback> _stateListeners = [];
  
  /// 进度更新监听器
  final List<void Function(ScanProgress)> _progressListeners = [];
  
  /// 完成回调监听器
  final List<void Function(List<DuplicateFileGroup>)> _completionListeners = [];
  
  /// 错误回调监听器
  final List<void Function(String)> _errorListeners = [];
  
  // ==================== 扫描控制 ====================
  
  /// 当前扫描任务的取消令牌
  Completer<void>? _cancelToken;
  
  /// 是否已请求取消
  bool _isCancellationRequested = false;
  
  /// 添加状态监听器
  void addStateListener(VoidCallback listener) {
    _stateListeners.add(listener);
  }
  
  /// 移除状态监听器
  void removeStateListener(VoidCallback listener) {
    _stateListeners.remove(listener);
  }
  
  /// 添加进度监听器
  void addProgressListener(void Function(ScanProgress) listener) {
    _progressListeners.add(listener);
  }
  
  /// 移除进度监听器
  void removeProgressListener(void Function(ScanProgress) listener) {
    _progressListeners.remove(listener);
  }
  
  /// 添加完成监听器
  void addCompletionListener(void Function(List<DuplicateFileGroup>) listener) {
    _completionListeners.add(listener);
  }
  
  /// 移除完成监听器
  void removeCompletionListener(void Function(List<DuplicateFileGroup>) listener) {
    _completionListeners.remove(listener);
  }
  
  /// 添加错误监听器
  void addErrorListener(void Function(String) listener) {
    _errorListeners.add(listener);
  }
  
  /// 移除错误监听器
  void removeErrorListener(void Function(String) listener) {
    _errorListeners.remove(listener);
  }
  
  /// 通知状态变化
  void _notifyStateChange() {
    for (final listener in List.from(_stateListeners)) {
      try {
        listener();
      } catch (e) {
        logger.e('Error notifying state listener: $e');
      }
    }
  }
  
  /// 通知进度更新
  void _notifyProgress(ScanProgress progress) {
    _currentProgress = progress;
    for (final listener in List.from(_progressListeners)) {
      try {
        listener(progress);
      } catch (e) {
        logger.e('Error notifying progress listener: $e');
      }
    }
  }
  
  /// 通知扫描完成
  void _notifyCompletion(List<DuplicateFileGroup> groups) {
    for (final listener in List.from(_completionListeners)) {
      try {
        listener(groups);
      } catch (e) {
        logger.e('Error notifying completion listener: $e');
      }
    }
  }
  
  /// 通知错误
  void _notifyError(String message) {
    for (final listener in List.from(_errorListeners)) {
      try {
        listener(message);
      } catch (e) {
        logger.e('Error notifying error listener: $e');
      }
    }
  }
  
  /// 开始扫描
  /// 
  /// 如果已有扫描在进行，会先取消旧扫描
  Future<void> startScan(
    DuplicateFileService service,
    DuplicateFileScanConfig config,
  ) async {
    // 如果正在扫描，先取消
    if (_state == DuplicateScanState.scanning) {
      logger.w('Previous scan is still running, cancelling it');
      await cancelScan();
    }
    
    // 重置状态
    _state = DuplicateScanState.scanning;
    _currentConfig = config;
    _currentProgress = null;
    _errorMessage = null;
    _scanStartTime = DateTime.now();
    _scanCompletionTime = null;
    _isCancellationRequested = false;
    _cancelToken = Completer<void>();
    
    _notifyStateChange();
    
    logger.i('Starting background scan with config: $config');
    
    try {
      // 📊 临时存储：用于收集扫描过程中的所有文件
      List<FileItem>? collectedFiles;
      
      // 执行扫描
      final groups = await service.scanDuplicateFiles(
        config: config,
        onProgress: (stage, current, total, currentFile) {
          // 检查是否已取消
          if (_isCancellationRequested) {
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
          
          _notifyProgress(progress);
        },
        onFilesCollected: (files) {
          // 📊 保存收集到的所有文件
          collectedFiles = files;
          logger.d('Files collected in scan manager: ${files.length} files');
        },
      );
      
      // 检查是否已取消
      if (_isCancellationRequested) {
        logger.i('Scan was cancelled');
        _state = DuplicateScanState.idle;
        _currentConfig = null;
        _notifyStateChange();
        return;
      }
      
      // 扫描成功
      _cachedGroups = groups;
      _allScannedFiles = collectedFiles; // 保存所有扫描的文件
      _state = DuplicateScanState.completed;
      _scanCompletionTime = DateTime.now();
      
      final duration = _scanCompletionTime!.difference(_scanStartTime!);
      logger.i('Scan completed successfully in ${duration.inSeconds} seconds, found ${groups.length} groups');
      
      // 📊 诊断日志 + 验证
      if (_allScannedFiles != null) {
        logger.i('✅ All scanned files stored in manager: ${_allScannedFiles!.length} files');
      } else {
        logger.w('⚠️ WARNING: allScannedFiles is null! onFilesCollected callback may not have been called');
      }
      
      _notifyStateChange();
      _notifyCompletion(groups);
      
    } catch (e, stackTrace) {
      logger.e('Scan failed: $e\n$stackTrace');
      
      _state = DuplicateScanState.error;
      _errorMessage = e.toString();
      _cachedGroups = [];
      
      _notifyStateChange();
      _notifyError(_errorMessage!);
    } finally {
      _cancelToken?.complete();
      _cancelToken = null;
    }
  }
  
  /// 取消当前扫描
  Future<void> cancelScan() async {
    if (_state != DuplicateScanState.scanning) {
      logger.w('No scan to cancel');
      return;
    }
    
    logger.i('Cancelling scan');
    _isCancellationRequested = true;
    
    // 等待扫描任务完成或超时
    if (_cancelToken != null && !_cancelToken!.isCompleted) {
      await _cancelToken!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          logger.w('Cancel operation timed out');
        },
      );
    }
  }
  
  /// 手动设置扫描状态（用于增量更新等场景）
  void setStateManually(DuplicateScanState newState) {
    if (_state == newState) return;
    
    logger.d('Manually setting state: $_state -> $newState');
    _state = newState;
    
    if (newState == DuplicateScanState.scanning) {
      _scanStartTime = DateTime.now();
      _scanCompletionTime = null;
    } else if (newState == DuplicateScanState.completed) {
      _scanCompletionTime = DateTime.now();
    }
    
    _notifyStateChange();
  }
  
  /// 手动设置错误状态
  void setErrorManually(String errorMessage) {
    logger.e('Manually setting error: $errorMessage');
    _state = DuplicateScanState.error;
    _errorMessage = errorMessage;
    _scanCompletionTime = DateTime.now();
    
    _notifyStateChange();
    _notifyError(errorMessage);
  }
  
  /// 清除缓存的结果
  void clearCache() {
    logger.i('Clearing cache');
    _cachedGroups = [];
    _allScannedFiles = null; // 清除所有文件列表
    _currentConfig = null;
    _currentProgress = null;
    _errorMessage = null;
    _scanStartTime = null;
    _scanCompletionTime = null;
    
    if (_state == DuplicateScanState.completed || _state == DuplicateScanState.error) {
      _state = DuplicateScanState.idle;
      _notifyStateChange();
    }
  }
  
  /// 检查是否有缓存的结果
  bool hasCachedResults() {
    return _state == DuplicateScanState.completed && _cachedGroups.isNotEmpty;
  }
  
  /// 检查缓存是否仍然有效（配置是否匹配）
  bool isCacheValidFor(DuplicateFileScanConfig config) {
    if (!hasCachedResults()) return false;
    if (_currentConfig == null) return false;
    
    // 检查配置是否相同
    return _currentConfig!.isEquivalent(config);
  }
  
  /// 清除扫描的文件列表（用于在保存缓存后释放内存）
  void clearScannedFiles() {
    if (_allScannedFiles != null) {
      logger.d('Clearing scanned files list (${_allScannedFiles!.length} files)');
      _allScannedFiles = null;
    }
  }
  
  /// 获取扫描耗时
  Duration? getScanDuration() {
    if (_scanStartTime == null) return null;
    
    if (_scanCompletionTime != null) {
      return _scanCompletionTime!.difference(_scanStartTime!);
    } else if (_state == DuplicateScanState.scanning) {
      return DateTime.now().difference(_scanStartTime!);
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
    
    // 取消正在进行的扫描
    if (_state == DuplicateScanState.scanning) {
      cancelScan();
    }
    
    // 清除所有监听器
    _stateListeners.clear();
    _progressListeners.clear();
    _completionListeners.clear();
    _errorListeners.clear();
    
    // 清除缓存
    clearCache();
  }
}
