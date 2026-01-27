import 'dart:async';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/data/models/file_item.dart';

/// 流式文件数据源（支持增量加载）
///
/// 功能：
/// - 首批快速返回（100-200个文件）
/// - 后台继续扫描，通过 Stream 推送增量数据
/// - 避免长时间白屏，提升用户体验
///
/// 使用示例：
/// ```dart
/// final dataSource = StreamingAppFilesDataSource(scanner);
///
/// // 监听增量文件
/// dataSource.fileStream.listen((batch) {
///   setState(() {
///     _files.addAll(batch);
///   });
/// });
///
/// // 触发扫描
/// final firstBatch = await dataSource.queryFiles({'appKey': 'wechat'});
/// setState(() {
///   _files = firstBatch; // 先显示首批文件
/// });
/// ```
class StreamingAppFilesDataSource {
  final UnifiedAppScanner _scanner;

  /// 增量文件流
  final StreamController<List<FileItem>> _fileStreamController =
      StreamController<List<FileItem>>.broadcast();

  /// 扫描进度流（当前数量 / 预估总数）
  final StreamController<ScanProgress> _progressStreamController =
      StreamController<ScanProgress>.broadcast();

  /// 首批文件数量（快速返回）
  static const int firstBatchSize = 200;

  /// 后续批次大小
  static const int batchSize = 500;

  /// 是否正在扫描
  bool _isScanning = false;

  StreamingAppFilesDataSource(this._scanner);

  /// 文件增量流
  Stream<List<FileItem>> get fileStream => _fileStreamController.stream;

  /// 扫描进度流
  Stream<ScanProgress> get progressStream => _progressStreamController.stream;

  /// 是否正在扫描
  bool get isScanning => _isScanning;

  /// 分批查询文件（返回首批，后续通过 Stream 推送）
  ///
  /// 返回首批 200 个文件（快速显示），后续批次通过 fileStream 推送
  Future<List<FileItem>> queryFilesStreaming({
    required String appKey,
    List<String>? fileTypes,
    bool useMediaStore = true,
  }) async {
    if (_isScanning) {
      logger.w('StreamingAppFilesDataSource - 已有扫描任务在进行，取消本次请求');
      return [];
    }

    _isScanning = true;
    logger.i('========== 开始流式扫描: $appKey ==========');

    try {
      // 先尝试获取缓存数量（用于进度估算）
      await _scanner.getFileCountFast(appKey: appKey);

      // 启动扫描任务
      final scanResult = await _scanner.scanApp(
        appKey: appKey,
        useMediaStore: useMediaStore,
        updateCache: true,
        forceRefresh: false,
      );

      final allFiles = scanResult.allFiles;
      logger.i('扫描完成: ${allFiles.length} 个文件');

      // 文件类型过滤
      List<FileItem> filteredFiles = allFiles;
      if (fileTypes != null && fileTypes.isNotEmpty) {
        filteredFiles = allFiles
            .where((f) => fileTypes.any((ext) => f.name.toLowerCase().endsWith(ext)))
            .toList();
        logger.d('类型过滤: ${allFiles.length} -> ${filteredFiles.length}');
      }

      // 分批推送
      if (filteredFiles.length <= firstBatchSize) {
        // 文件数量少，直接返回全部
        logger.i('文件数量较少 (${filteredFiles.length}), 直接返回全部');
        _progressStreamController.add(ScanProgress(
          current: filteredFiles.length,
          estimated: filteredFiles.length,
          isComplete: true,
        ));
        return filteredFiles;
      }

      // 返回首批
      final firstBatch = filteredFiles.take(firstBatchSize).toList();
      logger.i('返回首批: $firstBatchSize 个文件');
      _progressStreamController.add(ScanProgress(
        current: firstBatchSize,
        estimated: filteredFiles.length,
        isComplete: false,
      ));

      // 后续批次异步推送
      _pushRemainingBatches(filteredFiles, firstBatchSize);

      return firstBatch;
    } catch (e) {
      logger.e('流式扫描失败: $e');
      _progressStreamController.addError(e);
      return [];
    } finally {
      _isScanning = false;
    }
  }

  /// 推送剩余批次
  Future<void> _pushRemainingBatches(
    List<FileItem> allFiles,
    int startIndex,
  ) async {
    int currentIndex = startIndex;

    while (currentIndex < allFiles.length) {
      // 延迟推送，避免阻塞UI
      await Future.delayed(Duration(milliseconds: 100));

      final endIndex = (currentIndex + batchSize).clamp(0, allFiles.length);
      final batch = allFiles.sublist(currentIndex, endIndex);

      logger.d('推送批次: $currentIndex-$endIndex (${batch.length} 个文件)');
      _fileStreamController.add(batch);

      _progressStreamController.add(ScanProgress(
        current: endIndex,
        estimated: allFiles.length,
        isComplete: endIndex >= allFiles.length,
      ));

      currentIndex = endIndex;
    }

    logger.i('所有批次推送完成: ${allFiles.length} 个文件');
    _progressStreamController.add(ScanProgress(
      current: allFiles.length,
      estimated: allFiles.length,
      isComplete: true,
    ));
  }

  /// 取消扫描
  void cancelScanning() {
    _isScanning = false;
    logger.i('流式扫描已取消');
  }

  /// 释放资源
  void dispose() {
    _fileStreamController.close();
    _progressStreamController.close();
  }
}

/// 扫描进度
class ScanProgress {
  /// 当前已扫描数量
  final int current;

  /// 预估总数量
  final int estimated;

  /// 是否完成
  final bool isComplete;

  ScanProgress({
    required this.current,
    required this.estimated,
    required this.isComplete,
  });

  /// 进度百分比（0.0 - 1.0）
  double get progress => estimated > 0 ? current / estimated : 0.0;

  /// 进度百分比（0 - 100）
  int get progressPercent => (progress * 100).round();
}
