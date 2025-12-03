import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/duplicate_file_scan_config.dart';
import 'package:easyfile/core/models/large_file_scan_config.dart';
import 'package:easyfile/core/services/duplicate_file_cache_manager.dart';
import 'package:easyfile/core/services/enhanced_duplicate_file_scan_service.dart';
import 'package:easyfile/core/services/duplicate_file_scan_manager.dart';
import 'package:easyfile/core/services/file_display_settings_service.dart';
import 'package:easyfile/data/models/duplicate_file_group.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/audio_cover_widget.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';
import 'package:easyfile/ui/widgets/image_thumbnail.dart';
import 'package:easyfile/ui/widgets/real_video_thumbnail.dart';
import 'package:easyfile/data/services/video_thumbnail_load_queue.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';

/// 重复文件检测页面
///
/// 提供重复文件扫描和管理功能，支持：
/// - 🔍 智能扫描：三阶段检测算法
/// - 📊 分组展示：完整检测按类型分组，分类检测直接列表
/// - ✅ 批量操作：支持批量删除
/// - 🎯 智能推荐：自动推荐保留/删除
class DuplicateFilesPage extends StatefulWidget {
  final EnhancedDuplicateFileScanService enhancedScanService;
  final DuplicateFileScanConfig initialConfig;

  const DuplicateFilesPage({
    super.key,
    required this.enhancedScanService,
    required this.initialConfig,
  });

  @override
  State<DuplicateFilesPage> createState() => _DuplicateFilesPageState();
}

class _DuplicateFilesPageState extends State<DuplicateFilesPage> {
  // 扫描配置
  late DuplicateFileScanConfig _config;

  // 初始配置（用于检测配置变化）
  late DuplicateFileScanConfig _initialConfig;

  // 配置缓存管理
  final _cacheManager = DuplicateFileCacheManager();

  // 状态管理
  List<DuplicateFileGroup> _allGroups = [];
  bool _isScanning = false;
  bool _isCheckingUpdates = false; // 新增：是否正在检查更新
  String _updateStatus = ''; // 新增：更新状态文案
  int _currentStage = 0;
  int _currentProgress = 0;
  int _totalProgress = 0;
  String _currentFile = '';
  DateTime? _scanStartTime; // 扫描开始时间（用于估算剩余时间）
  int _lastProgressValue = 0; // 上次进度值（用于检测进度变化）

  // 增量更新状态
  int _filesDetected = 0; // 检测到的文件数
  String _incrementalStage = ''; // 当前增量更新阶段
  bool _showIncrementalSummary = false; // 显示完成摘要
  int _newGroupsCount = 0; // 新增的组数
  int _newFilesCount = 0; // 新增的文件数
  int _oldGroupsCount = 0; // 更新前的组数

  // 选择状态（用于批量删除）
  final Set<String> _selectedFilePaths = {};
  bool _isSelectionMode = false;

  // 折叠状态（完整检测模式）
  final Map<FileTypeFilter, bool> _expandedTypes = {};
  final Map<String, bool> _expandedFiles = {}; // filePath -> expanded

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _initialConfig = widget.initialConfig;

    // 调试日志：打印配置信息
    logger.i('🔧 DuplicateFilesPage 初始化');
    logger.i('   配置: ${_config.toString()}');
    logger.i('   扫描模式: ${_config.scanMode.name}');
    logger.i('   文件类型: ${_config.selectedType?.name ?? "all"}');
    logger.i('   最小大小: ${_config.minSizeInKB}KB');

    _setupScanListeners();
    _initializeAndScan();
  }

  /// 设置扫描监听器
  void _setupScanListeners() {
    final manager = widget.enhancedScanService.scanManager;

    // 监听状态变化（传入配置）
    manager.addStateListener(_config, _onStateChange);

    // 监听进度更新
    manager.addProgressListener(_config, _onProgressUpdate);

    // 监听完成
    manager.addCompletionListener(_config, _onScanComplete);

    // 监听错误
    manager.addErrorListener(_config, _onScanError);
  }

  /// 状态变化回调
  void _onStateChange() {
    if (!mounted) return;
    // ✅ 获取当前配置的状态
    final state = widget.enhancedScanService.scanManager.getStateFor(_config);
    setState(() {
      _isScanning = state == DuplicateScanState.scanning;
    });
  }

  /// 进度更新回调
  void _onProgressUpdate(ScanProgress progress) {
    if (!mounted) return;

    setState(() {
      _currentStage = progress.stage;
      _currentProgress = progress.current;
      _totalProgress = progress.total;

      // ✅ 方案2：第一阶段只扫描目标类型，UI直接显示即可
      _currentFile = progress.currentFile;

      // 识别增量更新阶段
      if (progress.stageName == '增量扫描') {
        _incrementalStage = progress.currentFile;
        if (progress.stage == 1 && progress.total > 0) {
          _filesDetected = progress.total;
        }
      }

      // 记录进度变化（用于检测扫描是否还在进行）
      if (_lastProgressValue != progress.current) {
        _lastProgressValue = progress.current;
      }
    });
  }

  /// 扫描完成回调
  void _onScanComplete(List<DuplicateFileGroup> groups) {
    if (!mounted) return;

    final t1 = DateTime.now();
    logger.i(
        '[${t1.toIso8601String()}] 🎯 _onScanComplete called: ${groups.length} groups, _isCheckingUpdates=$_isCheckingUpdates, _updateStatus="$_updateStatus"');

    // ✅ 由于监听器是按配置注册的，这里收到的回调一定是当前配置的
    // 不需要再检查配置匹配性

    // 计算增量统计（如果是增量更新）
    final isIncrementalUpdate = _isCheckingUpdates && _oldGroupsCount > 0;
    if (isIncrementalUpdate) {
      final newCount = groups.length;
      _newGroupsCount = newCount - _oldGroupsCount;

      // 计算新增文件数
      final oldFilesCount =
          _allGroups.fold<int>(0, (sum, g) => sum + g.files.length);
      final newFilesCount =
          groups.fold<int>(0, (sum, g) => sum + g.files.length);
      _newFilesCount = newFilesCount - oldFilesCount;

      logger.i(
          '📊 Incremental summary: old=$_oldGroupsCount, new=$newCount, delta=$_newGroupsCount groups, $_newFilesCount files');
    }

    setState(() {
      _allGroups = groups;
      _isScanning = false;
      _updateStatus = ''; // 清除更新状态提示
      _isCheckingUpdates = false; // 清除检查更新标志
      _incrementalStage = '';

      // 如果是增量更新完成，显示摘要
      if (_newGroupsCount != 0 || _filesDetected > 0) {
        _showIncrementalSummary = true;

        // 8秒后自动隐藏
        Future.delayed(const Duration(seconds: 8), () {
          if (mounted) {
            setState(() => _showIncrementalSummary = false);
          }
        });
      }
    });

    final t2 = DateTime.now();
    logger.i(
        '[${t2.toIso8601String()}] 🎯 setState completed, delay: ${t2.difference(t1).inMilliseconds}ms');

    _initializeDefaultSelection();

    // 🔥 启动后台预热缩略图缓存（异步，不阻塞UI）
    // 全量扫描：立即预热
    // 增量扫描：仅当有更新时预热（避免无意义的预热）
    if (!isIncrementalUpdate) {
      // 全量扫描完成，立即预热所有缩略图
      logger.i('🔥 Full scan completed, starting cache prewarming');
      _prewarmThumbnailCache(groups);
    } else if (_newGroupsCount != 0 || _newFilesCount != 0) {
      // 增量扫描完成且有更新，预热所有缩略图（包括旧的）
      logger.i(
          '🔥 Incremental scan completed with updates, starting cache prewarming');
      _prewarmThumbnailCache(groups);
    } else {
      // 增量扫描无更新，跳过预热
      logger.i(
          '🔥 Incremental scan completed with no updates, skipping cache prewarming');
    }

    // 添加帧回调，确认UI何时真正渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final t3 = DateTime.now();
      logger.i(
          '[${t3.toIso8601String()}] 🎯 UI frame rendered, total delay from _onScanComplete: ${t3.difference(t1).inMilliseconds}ms');
    });
  }

  /// 扫描错误回调
  void _onScanError(String error) {
    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _updateStatus = ''; // 清除更新状态提示
      _isCheckingUpdates = false; // 清除检查更新标志
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('扫描失败: $error'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    final manager = widget.enhancedScanService.scanManager;

    // ✅ 只移除当前配置的监听器
    manager.removeStateListener(_config, _onStateChange);
    manager.removeProgressListener(_config, _onProgressUpdate);
    manager.removeCompletionListener(_config, _onScanComplete);
    manager.removeErrorListener(_config, _onScanError);

    // ⚠️ 不要取消扫描！让扫描在后台继续进行
    // 这样用户切换分类后，原来的扫描仍会继续
    // 当用户返回时，会重新注册监听器并召回状态

    super.dispose();
  }

  /// 初始化并开始扫描
  Future<void> _initializeAndScan() async {
    // 🔍 检查后台扫描管理器的状态
    final manager = widget.enhancedScanService.scanManager;

    // ✅ 使用新API：获取当前配置的状态
    final currentState = manager.getStateFor(_config);
    final currentGroups = manager.getCachedGroupsFor(_config);

    logger.i(
        '📱 _initializeAndScan: state for this config = $currentState, cachedGroups = ${currentGroups.length}');

    // 🔄 检测配置变化（用户返回后调整了参数）
    final configChanged = !_config.isEquivalent(_initialConfig);
    if (configChanged) {
      logger.i('⚙️ Config changed: $_initialConfig -> $_config');

      // 如果旧配置正在扫描，停止旧的扫描
      final oldState = manager.getStateFor(_initialConfig);
      if (oldState == DuplicateScanState.scanning) {
        logger.i('🛑 Stopping previous scan due to config change');
        await manager.cancelScan(_initialConfig);

        // 等待扫描真正停止
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 清除旧配置的缓存并开始新扫描（使用 addPostFrameCallback 避免在 build 中调用）
      manager.clearCache(_initialConfig);
      _initialConfig = _config; // 更新初始配置

      // ✅ 延迟到下一帧执行，避免在 build 中触发导航/setState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startScan();
        }
      });
      return;
    }

    // 🔧 优先策略：无论什么状态，先尝试调用smartScan获取结果
    // smartScan会智能处理各种场景（缓存/增量更新/正在扫描等）
    try {
      // 记录调用前的时间，用于判断是否使用了缓存
      final beforeScan = DateTime.now();

      final groups = await widget.enhancedScanService.smartScan(
        _config,
        forceFullScan: false,
      );

      final scanDuration = DateTime.now().difference(beforeScan);
      final isFromCache = scanDuration.inMilliseconds < 1000; // 小于1秒说明是缓存

      logger.i(
          '📊 smartScan returned ${groups.length} groups (fromCache=$isFromCache, ${scanDuration.inMilliseconds}ms)');

      // ✅ 重新检查状态（可能在smartScan期间状态已改变）
      final updatedState = manager.getStateFor(_config);

      if (mounted) {
        setState(() {
          _allGroups = groups;
          _isScanning = updatedState == DuplicateScanState.scanning;

          if (_isScanning) {
            if (groups.isEmpty) {
              _updateStatus = '正在首次扫描，请稍候...';
            } else {
              // 召回时，如果有缓存且正在扫描，说明是增量更新
              _isCheckingUpdates = true;
              _updateStatus = '正在检查文件更新...';
              _oldGroupsCount = groups.length; // 恢复旧的组数
              _incrementalStage = '正在检查文件更新...';
            }
          } else {
            _updateStatus = '';
          }
        });

        if (groups.isNotEmpty) {
          _initializeDefaultSelection();

          // 如果是从缓存加载的，启动增量更新检查UI
          if (isFromCache) {
            logger.i('📦 Loaded from cache, starting incremental update UI');
            _startIncrementalUpdateCheck();
          }
        } else if (_isScanning) {
          // 正在扫描中，groups为空是正常的（等待结果）
          logger.i('🔄 Scan in progress, waiting for results');
        } else {
          // 既没有结果也不在扫描 → 需要启动新扫描
          logger.i('🚀 No cache and not scanning, starting new scan');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _startScan();
            }
          });
        }
      }
    } catch (e) {
      logger.e('smartScan failed: $e');
      // 如果smartScan失败，开始新的扫描
      // ✅ 使用 addPostFrameCallback 避免在 build 中调用
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startScan();
        }
      });
    }
  }

  /// 初始化默认选中状态（默认不选中，让用户主动选择）
  void _initializeDefaultSelection() {
    _selectedFilePaths.clear();
    _isSelectionMode = false;
  }

  /// 🔥 预热缩略图缓存（后台异步）
  ///
  /// 策略：
  /// 1. 只预热图片和视频（其他类型缓存意义不大）
  /// 2. 分批预热，避免内存峰值
  /// 3. 低优先级，不阻塞UI
  /// 4. 图片使用Flutter的precacheImage
  /// 5. 视频触发缩略图生成（由VideoThumbnailLoadQueue管理缓存）
  Future<void> _prewarmThumbnailCache(List<DuplicateFileGroup> groups) async {
    logger.i(
        '🔥 Starting thumbnail cache prewarming for ${groups.length} groups');

    // 收集所有需要预热的文件
    final imagesToPrewarm = <FileItem>[];
    final videosToPrewarm = <FileItem>[];

    for (final group in groups) {
      for (final file in group.files) {
        if (FileUtils.isImageFile(file.name)) {
          imagesToPrewarm.add(file);
        } else if (FileUtils.isVideoFile(file.name)) {
          videosToPrewarm.add(file);
        }
      }
    }

    logger.i(
        '🔥 Found ${imagesToPrewarm.length} images and ${videosToPrewarm.length} videos to prewarm');

    // 1. 预热图片（使用Flutter的precacheImage，快速）
    if (imagesToPrewarm.isNotEmpty) {
      const batchSize = 30;
      for (int i = 0; i < imagesToPrewarm.length; i += batchSize) {
        final batch = imagesToPrewarm.skip(i).take(batchSize).toList();

        await Future.delayed(const Duration(milliseconds: 50));

        for (final file in batch) {
          try {
            await precacheImage(FileImage(File(file.path)), context);
          } catch (e) {
            // 忽略错误
          }
        }
      }
      logger.i('🔥 Image prewarming completed');
    }

    // 2. 预热视频缩略图（使用更保守的策略）
    if (videosToPrewarm.isNotEmpty) {
      // 优先预热前100个视频（通常是用户最先看到的）
      const maxVideos = 100;
      const batchSize = 5; // 每批5个，避免MediaCodec资源耗尽
      final videosToProcess = videosToPrewarm.take(maxVideos).toList();

      logger.i(
          '🔥 Starting video thumbnail prewarming for ${videosToProcess.length} videos');

      for (int i = 0; i < videosToProcess.length; i += batchSize) {
        final batch = videosToProcess.skip(i).take(batchSize).toList();

        // 较长延迟，确保不影响UI响应
        await Future.delayed(const Duration(milliseconds: 300));

        // 并行处理这一批
        await Future.wait(
          batch.map((file) async {
            try {
              // 触发缩略图生成（会自动缓存到磁盘）
              final queue = VideoThumbnailLoadQueue();
              await queue.loadThumbnail(file.path, 80.0);
            } catch (e) {
              // 忽略错误，继续处理其他视频
            }
          }),
        );

        if (i % 20 == 0) {
          logger.i(
              '🔥 Video prewarming progress: ${i + batchSize}/${videosToProcess.length}');
        }
      }

      logger.i('🔥 Video thumbnail prewarming completed');
    }

    logger.i('🔥 Thumbnail cache prewarming completed');
  }

  /// 开始扫描
  Future<void> _startScan() async {
    // 检查后台扫描管理器状态
    final manager = widget.enhancedScanService.scanManager;

    // 如果后台已经在扫描中，不要重复启动
    if (manager.state == DuplicateScanState.scanning) {
      logger
          .w('Scan already in progress in background, waiting for completion');
      setState(() {
        _isScanning = true;
      });
      return;
    }

    // 防止UI层面的重复调用
    if (_isScanning) {
      logger.w('Scan already in progress (UI state), ignoring duplicate call');
      return;
    }

    setState(() {
      _isScanning = true;
      _allGroups = [];
      _currentStage = 0;
      _currentProgress = 0;
      _totalProgress = 0;
      _currentFile = '';
      _isCheckingUpdates = false;
      _updateStatus = '';
      _scanStartTime = DateTime.now(); // 记录扫描开始时间
      _lastProgressValue = 0;
    });

    try {
      // 记录扫描开始时间，用于判断是否使用了缓存
      final scanStartTime = DateTime.now();

      // 使用增强扫描服务（自动整合缓存 + 后台扫描）
      final groups = await widget.enhancedScanService.smartScan(
        _config,
        forceFullScan: false, // 优先使用缓存
      );

      // 计算扫描耗时，如果很快（< 1秒）说明使用了缓存
      final scanDuration = DateTime.now().difference(scanStartTime);
      final isFromCache = scanDuration.inMilliseconds < 1000;

      if (mounted) {
        setState(() {
          _allGroups = groups;
          _isScanning = false;
        });

        // 初始化默认选中状态
        _initializeDefaultSelection();

        // 保存配置（记住用户的选择）
        await _cacheManager.saveConfig(_config);

        if (groups.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '未找到重复文件（最小大小: ${FileDisplaySettingsService.formatFileSize(_config.minSizeInKB * 1024)}）',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          // 只有在使用缓存时才启动增量更新检测
          // 如果是刚完成的完整扫描，数据已经是最新的，无需再检查更新
          if (isFromCache) {
            logger.i(
                '📦 Loaded from cache in ${scanDuration.inMilliseconds}ms, starting incremental update');
            _startIncrementalUpdateCheck();
          } else {
            logger.i(
                '✅ Fresh scan completed in ${scanDuration.inSeconds}s, no need for incremental update');
          }
        }
      }
    } catch (e) {
      logger.e('Error scanning duplicate files: $e');
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('扫描失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 启动增量更新检测
  void _startIncrementalUpdateCheck() {
    if (!mounted) return;

    logger.i('🔄 Starting incremental update check');

    setState(() {
      _isCheckingUpdates = true;
      _updateStatus = '正在检查文件更新...';
      _oldGroupsCount = _allGroups.length; // 保存当前组数
      _filesDetected = 0;
      _incrementalStage = '正在检查文件更新...';
      _newGroupsCount = 0;
      _newFilesCount = 0;
      _showIncrementalSummary = false;
    });

    logger.i(
        '🔄 After setState: _isCheckingUpdates=$_isCheckingUpdates, _oldGroupsCount=$_oldGroupsCount');

    // 💡 监听器会在增量更新完成时自动清除状态
    // 在Android设备上，文件系统扫描可能需要1-2分钟，不设置timeout
    // _onScanComplete 或 _onScanError 会处理完成/错误情况
  }

  /// 按类型分组重复文件组（完整检测模式）
  Map<FileTypeFilter, List<DuplicateFileGroup>> _groupByType() {
    final result = <FileTypeFilter, List<DuplicateFileGroup>>{};

    for (final type in [
      FileTypeFilter.video,
      FileTypeFilter.image,
      FileTypeFilter.audio,
      FileTypeFilter.document,
      FileTypeFilter.archive,
    ]) {
      result[type] = [];
    }

    for (final group in _allGroups) {
      final type = _getFileType(group.files.first.name);
      if (result.containsKey(type)) {
        result[type]!.add(group);
      }
    }

    // 移除空的类型
    result.removeWhere((_, groups) => groups.isEmpty);

    // 按可释放空间排序
    for (final groups in result.values) {
      groups.sort((a, b) => b.reclaimableSpace.compareTo(a.reclaimableSpace));
    }

    return result;
  }

  /// 获取文件类型
  FileTypeFilter _getFileType(String fileName) {
    final ext = path.extension(fileName).toLowerCase();

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
      '.opus'
    ];
    const imageExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.heic',
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
      '.txt'
    ];
    const archiveExtensions = ['.zip', '.rar', '.7z', '.tar', '.gz', '.bz2'];

    if (videoExtensions.contains(ext)) return FileTypeFilter.video;
    if (audioExtensions.contains(ext)) return FileTypeFilter.audio;
    if (imageExtensions.contains(ext)) return FileTypeFilter.image;
    if (documentExtensions.contains(ext)) return FileTypeFilter.document;
    if (archiveExtensions.contains(ext)) return FileTypeFilter.archive;

    return FileTypeFilter.other;
  }

  /// 获取类型图标
  String _getTypeEmoji(FileTypeFilter type) {
    switch (type) {
      case FileTypeFilter.video:
        return '📹';
      case FileTypeFilter.image:
        return '📷';
      case FileTypeFilter.audio:
        return '🎵';
      case FileTypeFilter.document:
        return '📄';
      case FileTypeFilter.archive:
        return '📦';
      case FileTypeFilter.other:
        return '📁';
    }
  }

  /// 删除选中的文件
  Future<void> _deleteSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('即将删除 ${_selectedFilePaths.length} 个文件，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 执行删除
    int deletedCount = 0;
    for (final filePath in _selectedFilePaths) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          deletedCount++;
        }
      } catch (e) {
        logger.e('Failed to delete file $filePath: $e');
      }
    }

    // 刷新列表
    await _refreshAfterDeletion();

    if (mounted) {
      setState(() {
        _selectedFilePaths.clear();
        _isSelectionMode = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除 $deletedCount 个文件'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// 删除后刷新列表
  Future<void> _refreshAfterDeletion() async {
    // 重新检查所有文件是否存在
    final updatedGroups = <DuplicateFileGroup>[];

    for (final group in _allGroups) {
      final existingFiles = <FileItem>[];

      for (final file in group.files) {
        try {
          if (await File(file.path).exists()) {
            existingFiles.add(file);
          }
        } catch (e) {
          logger.w('Error checking file existence: ${file.path}');
        }
      }

      // 如果仍然有至少2个文件，保留这个组
      if (existingFiles.length >= 2) {
        updatedGroups.add(
          DuplicateFileGroup(
            groupId: group.groupId,
            files: existingFiles,
            fileSize: group.fileSize,
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _allGroups = updatedGroups;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: _buildAppBar(colorScheme),
      body: _buildBody(theme, colorScheme),
      bottomNavigationBar:
          _isSelectionMode ? _buildBottomBar(colorScheme) : null,
    );
  }

  /// 构建AppBar
  PreferredSizeWidget _buildAppBar(ColorScheme colorScheme) {
    if (_isSelectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            setState(() {
              _selectedFilePaths.clear();
              _isSelectionMode = false;
            });
          },
        ),
        title: Text(
          _config.scanMode == DuplicateScanMode.full
              ? '重复文件清理（完整检测）'
              : '重复文件清理（${_config.selectedType!.label}）',
        ),
        centerTitle: true,
      );
    }

    return AppBar(
      title: Text(
        _config.scanMode == DuplicateScanMode.full
            ? '重复文件清理（完整检测）'
            : '重复文件清理（${_config.selectedType!.label}）',
      ),
      centerTitle: true,
    );
  }

  /// 清空所有选择
  void _clearSelection() {
    setState(() {
      _selectedFilePaths.clear();
      _isSelectionMode = false;
    });
  }

  /// 应用推荐选择（选中所有推荐删除的文件，取消选中推荐保留的）
  Future<void> _applyRecommendedSelection() async {
    setState(() {
      _selectedFilePaths.clear();

      if (_config.scanMode == DuplicateScanMode.full) {
        // 完整检测：选择所有已展开类型中的推荐删除文件
        final groupsByType = _groupByType();
        for (final entry in groupsByType.entries) {
          if (_expandedTypes[entry.key] == true) {
            for (final group in entry.value) {
              for (final file in group.recommendedToDelete) {
                _selectedFilePaths.add(file.path);
              }
            }
          }
        }
      } else {
        // 分类检测：选择所有组的推荐删除文件
        for (final group in _allGroups) {
          for (final file in group.recommendedToDelete) {
            _selectedFilePaths.add(file.path);
          }
        }
      }

      _isSelectionMode = _selectedFilePaths.isNotEmpty;
    });
  }

  /// 检查当前选择是否为推荐状态
  bool _isCurrentSelectionRecommended() {
    // 获取所有推荐删除的文件路径
    final recommendedPaths = <String>{};

    if (_config.scanMode == DuplicateScanMode.full) {
      final groupsByType = _groupByType();
      for (final entry in groupsByType.entries) {
        if (_expandedTypes[entry.key] == true) {
          for (final group in entry.value) {
            for (final file in group.recommendedToDelete) {
              recommendedPaths.add(file.path);
            }
          }
        }
      }
    } else {
      for (final group in _allGroups) {
        for (final file in group.recommendedToDelete) {
          recommendedPaths.add(file.path);
        }
      }
    }

    // 检查当前选择是否与推荐完全一致
    if (_selectedFilePaths.length != recommendedPaths.length) {
      return false;
    }

    return _selectedFilePaths.every((path) => recommendedPaths.contains(path));
  }

  /// 构建主体内容
  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_isScanning && _allGroups.isEmpty) {
      return _buildScanningIndicator(theme, colorScheme);
    }

    if (_config.scanMode == DuplicateScanMode.full) {
      return _buildFullScanResult(theme, colorScheme);
    } else {
      return _buildCategoryScanResult(theme, colorScheme);
    }
  }

  /// 构建扫描进度指示器
  Widget _buildScanningIndicator(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        // 主内容区域（可滚动）
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部说明卡片
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.primary.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '正在扫描您的设备，查找重复文件。这可能需要几分钟时间，请耐心等待。您可以随时返回继续其他工作，扫描会在后台持续进行。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 80),
                // 进度指示器（带百分比）
                Stack(
                  alignment: Alignment.center,
                  children: [
                    const SizedBox(
                      width: 60,
                      height: 60,
                      child: CircularProgressIndicator(strokeWidth: 5),
                    ),
                    if (_totalProgress > 0)
                      Text(
                        '${_getProgressPercentage().toStringAsFixed(0)}%',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                // 阶段名称和进度
                Text(
                  _totalProgress > 0
                      ? '${_getStageName(_currentStage)} ($_currentProgress/$_totalProgress)'
                      : _getStageName(_currentStage),
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                // 预计剩余时间
                if (_getEstimatedTimeRemaining().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '预计剩余: ${_getEstimatedTimeRemaining()}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_currentFile.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _currentFile.split('/').last.split('\\').last, // 只显示文件名
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 24), // 底部留白
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getStageName(int stage) {
    switch (stage) {
      case 1:
        return '正在扫描文件...';
      case 2:
        return '正在对比文件...';
      case 3:
        return '正在确认重复...';
      default:
        return '正在处理...';
    }
  }

  /// 计算扫描进度百分比
  double _getProgressPercentage() {
    if (_totalProgress == 0) return 0;
    return (_currentProgress / _totalProgress * 100).clamp(0, 100);
  }

  /// 估算剩余时间
  String _getEstimatedTimeRemaining() {
    if (_scanStartTime == null ||
        _totalProgress == 0 ||
        _currentProgress == 0) {
      return ''; // 没有足够信息估算
    }

    final elapsed = DateTime.now().difference(_scanStartTime!);
    final progress = _currentProgress / _totalProgress;

    if (progress < 0.05) {
      return ''; // 进度太少，估算不准确
    }

    final totalEstimated = elapsed.inSeconds / progress;
    final remaining = totalEstimated - elapsed.inSeconds;

    if (remaining < 60) {
      return '约${remaining.round()}秒';
    } else {
      final minutes = (remaining / 60).round();
      return '约$minutes分钟';
    }
  }

  /// 构建增量更新信息区域
  Widget _buildIncrementalUpdateInfo(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showIncrementalSummary) ...[
          // 完成摘要
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Text(
                '✅ 增量更新完成',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, size: 18),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
                onPressed: () {
                  setState(() => _showIncrementalSummary = false);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 统一的摘要信息
          if (_filesDetected > 0) ...[
            Text(
              '检测到 $_filesDetected 个更新的文件',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (_newGroupsCount != 0 || _newFilesCount != 0) ...[
            Text(
              _newGroupsCount > 0
                  ? '新增 $_newGroupsCount 组重复文件（共 $_newFilesCount 个文件）'
                  : _newGroupsCount < 0
                      ? '减少 ${-_newGroupsCount} 组重复文件（共 ${-_newFilesCount} 个文件）'
                      : '文件已更新，无新增重复',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _newGroupsCount > 0 ? Colors.orange : Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ] else if (_filesDetected > 0) ...[
            // 有文件更新但没有新增重复
            Text(
              '未发现新的重复文件',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ] else if (_incrementalStage.isNotEmpty) ...[
          // 进行中 - 简洁标题
          Text(
            '文件更新检测中',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _incrementalStage,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Divider(height: 1),
        const SizedBox(height: 12),
      ],
    );
  }

  /// 构建完整扫描结果（分类折叠）
  Widget _buildFullScanResult(ThemeData theme, ColorScheme colorScheme) {
    if (_allGroups.isEmpty) {
      return _buildEmptyState();
    }

    final groupsByType = _groupByType();
    final totalFiles = _allGroups.fold<int>(0, (sum, g) => sum + g.count);
    final totalReclaimable =
        _allGroups.fold<int>(0, (sum, g) => sum + g.reclaimableSpace);

    return CustomScrollView(
      slivers: [
        // 总结卡片
        SliverToBoxAdapter(
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 增量更新信息（在顶部）
                  if (_incrementalStage.isNotEmpty || _showIncrementalSummary)
                    _buildIncrementalUpdateInfo(theme, colorScheme),

                  // 标题行：扫描结果
                  Text(
                    '📊 扫描结果',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('找到 ${_allGroups.length} 组重复文件 (共 $totalFiles 个文件)'),
                  const SizedBox(height: 4),
                  Text(
                    '最小文件大小: ${FileDisplaySettingsService.formatFileSize(_config.minSizeInKB * 1024)} · 可释放空间: ${FileSizeFormatter.formatBytes(totalReclaimable)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 按类型分组列表
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final types = groupsByType.keys.toList();
              final type = types[index];
              final groups = groupsByType[type]!;
              final isExpanded = _expandedTypes[type] ?? false;

              return _buildTypeExpansionTile(
                  type, groups, isExpanded, theme, colorScheme);
            },
            childCount: groupsByType.length,
          ),
        ),
      ],
    );
  }

  /// 构建类型折叠卡片
  Widget _buildTypeExpansionTile(
    FileTypeFilter type,
    List<DuplicateFileGroup> groups,
    bool isExpanded,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final totalSize = groups.fold<int>(0, (sum, g) => sum + g.reclaimableSpace);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('type_$type'),
          initiallyExpanded: isExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _expandedTypes[type] = expanded;
            });
          },
          leading: Text(
            _getTypeEmoji(type),
            style: const TextStyle(fontSize: 24),
          ),
          title: Text(
            type.label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${groups.length}组 · ${FileSizeFormatter.formatBytes(totalSize)}',
            style: TextStyle(color: colorScheme.primary, fontSize: 12),
          ),
          children: [
            // 使用单独的列表Widget来优化性能
            _TypeGroupList(
              groups: groups,
              theme: theme,
              colorScheme: colorScheme,
              buildGroupItem: _buildGroupItem,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建分类扫描结果（直接列表）
  Widget _buildCategoryScanResult(ThemeData theme, ColorScheme colorScheme) {
    if (_allGroups.isEmpty) {
      return _buildEmptyState();
    }

    final totalFiles = _allGroups.fold<int>(0, (sum, g) => sum + g.count);
    final totalReclaimable =
        _allGroups.fold<int>(0, (sum, g) => sum + g.reclaimableSpace);

    return CustomScrollView(
      slivers: [
        // 总结卡片
        SliverToBoxAdapter(
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 增量更新信息（在顶部）
                  if (_incrementalStage.isNotEmpty || _showIncrementalSummary)
                    _buildIncrementalUpdateInfo(theme, colorScheme),

                  // 标题行
                  Text(
                    '📊 扫描结果',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                      '找到 ${_allGroups.length} 组重复${_config.selectedType!.label} (共 $totalFiles 个文件)'),
                  const SizedBox(height: 4),
                  Text(
                    '最小文件大小: ${FileDisplaySettingsService.formatFileSize(_config.minSizeInKB * 1024)} · 可释放空间: ${FileSizeFormatter.formatBytes(totalReclaimable)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 重复文件组列表
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              return _buildGroupItem(_allGroups[index], theme, colorScheme);
            },
            childCount: _allGroups.length,
          ),
        ),
      ],
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isAtGlobalMin = (_config.minSizeInKB * 1024) <=
        FileDisplaySettingsService.minFileSizeMin;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 80,
              color: colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              '在当前条件下未找到重复文件',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '扫描条件：',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildConditionRow(
                    Icons.category_outlined,
                    '扫描类型',
                    _config.scanMode == DuplicateScanMode.full
                        ? '完整检测（所有文件类型）'
                        : '分类检测（${_config.selectedType!.label}）',
                    colorScheme,
                  ),
                  const SizedBox(height: 6),
                  _buildConditionRow(
                    Icons.straighten_outlined,
                    '最小文件大小',
                    FileDisplaySettingsService.formatFileSize(
                        _config.minSizeInKB * 1024),
                    colorScheme,
                  ),
                ],
              ),
            ),
            if (!isAtGlobalMin) ...[
              const SizedBox(height: 20),
              Text(
                '建议：尝试降低最小文件大小或选择其他类型',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建条件行
  Widget _buildConditionRow(
      IconData icon, String label, String value, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建重复文件组项
  Widget _buildGroupItem(
    DuplicateFileGroup group,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final recommendedFile = group.recommendedToKeep;

    return Card(
      key: ValueKey('group_${group.groupId}'), // 添加Key优化复用
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部区域（带背景色）
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一行：推荐保留的文件名（增加图标）
                  Row(
                    children: [
                      Icon(
                        Icons.file_present,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          recommendedFile.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 第二行：统计信息
                  Text(
                    '共 ${group.count} 个重复文件，总大小 ${FileSizeFormatter.formatBytes(group.fileSize * group.count)}，可释放 ${FileSizeFormatter.formatBytes(group.reclaimableSpace)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 第三行+：重复文件列表（延迟加载优化）
            ..._buildFileListWithDelay(
                group, recommendedFile, theme, colorScheme),
          ],
        ),
      ),
    );
  }

  /// 构建文件列表（带延迟加载索引）
  List<Widget> _buildFileListWithDelay(
    DuplicateFileGroup group,
    FileItem recommendedFile,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final widgets = <Widget>[];
    for (int i = 0; i < group.files.length; i++) {
      final file = group.files[i];
      final isRecommended = file.path == recommendedFile.path;
      final isSelected = _selectedFilePaths.contains(file.path);

      widgets.add(_buildFileItemWithIndex(
        file,
        i,
        isRecommended,
        isSelected,
        theme,
        colorScheme,
      ));
    }
    return widgets;
  }

  /// 构建文件项（带索引）
  Widget _buildFileItemWithIndex(
    FileItem file,
    int index,
    bool isRecommended,
    bool isSelected,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isExpanded = _expandedFiles[file.path] ?? false;

    return Padding(
      key: ValueKey('file_item_${file.path}'), // 添加唯一Key
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          // 始终显示的行（整行可点击展开/折叠）
          InkWell(
            onTap: () {
              setState(() {
                _expandedFiles[file.path] = !isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 缩略图（延迟加载优化）
                  _LazyThumbnail(
                    file: file,
                    buildThumbnail: _buildThumbnail,
                    index: index,
                  ),
                  const SizedBox(width: 12),
                  // 文件名和大小（三行布局）
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 第一行：文件名
                        Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        // 第二行：文件大小 + 展开状态提示
                        Row(
                          children: [
                            Text(
                              FileSizeFormatter.formatBytes(file.size),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            Text(
                              isExpanded ? '收起' : '详情',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        // 第三行：建议保留徽章
                        if (isRecommended) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.green.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: const Text(
                                  '建议保留',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Checkbox（行尾，添加点击拦截）
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedFilePaths.remove(file.path);
                          if (_selectedFilePaths.isEmpty) {
                            _isSelectionMode = false;
                          }
                        } else {
                          _selectedFilePaths.add(file.path);
                          if (!_isSelectionMode) _isSelectionMode = true;
                        }
                      });
                    },
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedFilePaths.add(file.path);
                            if (!_isSelectionMode) _isSelectionMode = true;
                          } else {
                            _selectedFilePaths.remove(file.path);
                            if (_selectedFilePaths.isEmpty) {
                              _isSelectionMode = false;
                            }
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 展开的详细信息
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: isExpanded ? null : 0,
            child: isExpanded
                ? Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailRow(
                          '完整路径',
                          _formatPath(file.path),
                          theme,
                          colorScheme,
                        ),
                        const SizedBox(height: 8),
                        _buildDetailRow(
                          '大小',
                          '${FileSizeFormatter.formatBytes(file.size)} (${file.size} 字节)',
                          theme,
                          colorScheme,
                        ),
                        const SizedBox(height: 8),
                        _buildDetailRow(
                          '修改时间',
                          _formatDate(file.modified),
                          theme,
                          colorScheme,
                        ),
                        const SizedBox(height: 12),
                        // 打开文件按钮 - 右对齐
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: () => _openFilePreview(file),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('打开文件'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              minimumSize: const Size(0, 32),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// 构建详情行
  Widget _buildDetailRow(
    String label,
    String value,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label：',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  /// 构建底部操作栏
  Widget _buildBottomBar(ColorScheme colorScheme) {
    final isRecommended = _isCurrentSelectionRecommended();
    final hasSelection = _selectedFilePaths.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.5),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // 左侧：选择计数
            Text(
              '已选择 ${_selectedFilePaths.length} 项',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),

            // 右侧：操作按钮组
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 推荐按钮（始终显示，推荐状态时禁用）
                TextButton(
                  onPressed: isRecommended ? null : _applyRecommendedSelection,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: colorScheme.primary,
                    disabledForegroundColor:
                        colorScheme.onSurfaceVariant.withOpacity(0.38),
                  ),
                  child: const Text('推荐', style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 8),

                // 清空按钮（始终显示，无选择时禁用）
                TextButton(
                  onPressed: hasSelection ? _clearSelection : null,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: colorScheme.onSurfaceVariant,
                    disabledForegroundColor:
                        colorScheme.onSurfaceVariant.withOpacity(0.38),
                  ),
                  child: const Text('清空', style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 8),

                // 删除按钮（始终显示，无选择时禁用）
                FilledButton(
                  onPressed: hasSelection ? _deleteSelectedFiles : null,
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                    disabledBackgroundColor:
                        colorScheme.surfaceContainerHighest,
                    disabledForegroundColor:
                        colorScheme.onSurfaceVariant.withOpacity(0.38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.delete_outline, size: 16),
                      const SizedBox(width: 4),
                      const Text('删除', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建缩略图
  ///
  /// 图片和视频使用 80px 大尺寸（便于识别内容）
  /// 其他文件类型使用 40px 小尺寸（图标化显示）
  Widget _buildThumbnail(FileItem file) {
    // 根据文件类型确定缩略图尺寸
    final isImageOrVideo =
        FileUtils.isImageFile(file.name) || FileUtils.isVideoFile(file.name);
    final size = isImageOrVideo ? 80.0 : 40.0;

    // 使用Key来优化Widget复用
    if (FileUtils.isImageFile(file.name)) {
      return ImageThumbnail(
        key: ValueKey('img_${file.path}'),
        imagePath: file.path,
        size: size,
      );
    } else if (FileUtils.isVideoFile(file.name)) {
      return RealVideoThumbnail(
        key: ValueKey('vid_${file.path}'),
        videoPath: file.path,
        size: size,
        showDuration: false,
      );
    } else if (FileUtils.isAudioFile(file.name)) {
      return AudioCoverWidget(
        key: ValueKey('aud_${file.path}'),
        audioPath: file.path,
        size: size,
      );
    } else if (FileUtils.isDocumentFile(file.name) ||
        FileUtils.isTextFile(file.name) ||
        FileUtils.isArchiveFile(file.name)) {
      return DocumentIconWidgetRounded(fileName: file.name, size: size);
    } else {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          Icons.insert_drive_file,
          color: Colors.grey[600],
          size: size * 0.5,
        ),
      );
    }
  }

  /// 格式化路径
  String _formatPath(String fullPath) {
    return fullPath.replaceFirst('/storage/emulated/0/', '内部存储/');
  }

  /// 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// 打开文件预览
  Future<void> _openFilePreview(FileItem file) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FilePreviewPage(
          file: file,
          fileList: [],
          initialIndex: 0,
          viewModel: locator<FileViewModel>(),
          presenter: locator<FilePresenter>(),
        ),
      ),
    );
  }
}

/// 类型分组列表Widget（优化性能）
///
/// 说明：虽然这里仍然一次性生成所有Widget，但通过以下方式优化性能：
/// 1. 使用独立Widget类，避免父Widget重建时重新创建列表
/// 2. 子Widget（_buildGroupItem）内部使用Key优化复用
/// 3. 图片/视频缩略图使用ValueKey避免重复加载
class _TypeGroupList extends StatelessWidget {
  final List<DuplicateFileGroup> groups;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final Widget Function(DuplicateFileGroup, ThemeData, ColorScheme)
      buildGroupItem;

  const _TypeGroupList({
    required this.groups,
    required this.theme,
    required this.colorScheme,
    required this.buildGroupItem,
  });

  @override
  Widget build(BuildContext context) {
    // 直接映射为Widget列表
    // Flutter的渲染引擎会自动优化不可见部分的渲染
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: groups
          .map((group) => buildGroupItem(group, theme, colorScheme))
          .toList(),
    );
  }
}

/// 延迟加载缩略图Widget
///
/// 核心优化：分批延迟加载，避免同时创建大量Widget
/// - 前10个立即加载（首屏可见）
/// - 后续每50ms加载一批（20个）
/// - 不阻塞UI主线程
class _LazyThumbnail extends StatefulWidget {
  final FileItem file;
  final Widget Function(FileItem) buildThumbnail;
  final int index; // 添加索引用于分批加载

  const _LazyThumbnail({
    required this.file,
    required this.buildThumbnail,
    this.index = 0,
  });

  @override
  State<_LazyThumbnail> createState() => _LazyThumbnailState();
}

class _LazyThumbnailState extends State<_LazyThumbnail> {
  bool _shouldLoad = false;

  @override
  void initState() {
    super.initState();

    // 分批加载策略 - 优化为更激进的分批
    if (widget.index < 6) {
      // 前6个立即加载（首屏可见）
      _shouldLoad = true;
    } else {
      // 后续分批延迟加载：每批10个，间隔30ms
      final batchIndex = (widget.index - 6) ~/ 10; // 每批10个
      final delay = Duration(milliseconds: 30 + batchIndex * 30);

      Future.delayed(delay, () {
        if (mounted) {
          setState(() => _shouldLoad = true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldLoad) {
      // 占位Widget：快速渲染
      final isImageOrVideo = FileUtils.isImageFile(widget.file.name) ||
          FileUtils.isVideoFile(widget.file.name);
      final size = isImageOrVideo ? 80.0 : 40.0;

      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // 真正的缩略图
    return widget.buildThumbnail(widget.file);
  }
}
