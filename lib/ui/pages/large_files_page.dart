import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/large_file_scan_config.dart';
import 'package:easyfile/core/services/large_file_cache_manager.dart';
import 'package:easyfile/core/services/large_file_service.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/services/batch_operations_service.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/ui/widgets/edit_mode_hint_bar.dart';
import 'package:easyfile/ui/widgets/edit_mode_widgets.dart';
import 'package:easyfile/ui/widgets/image_thumbnail.dart';
import 'package:easyfile/ui/widgets/selection_bottom_bar.dart';
import 'package:easyfile/ui/mixins/edit_mode_mixin.dart';
import 'package:easyfile/ui/mixins/pop_scope_handler_mixin.dart';
import 'package:easyfile/ui/widgets/real_video_thumbnail.dart';
import 'package:easyfile/ui/widgets/audio_cover_widget.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/ui/services/single_file_operations_service.dart';
import 'package:easyfile/ui/widgets/single_file_operations_sheet.dart';

/// 大文件查找页面
///
/// 提供大文件扫描和管理功能，支持：
/// - 🔍 智能扫描：使用智能深度和大小剪枝优化
/// - 📊 可配置阈值：调整最小文件大小
/// - ✅ 批量操作：支持批量删除、移动等
/// - 📱 统一体验：复用现有组件和交互模式
class LargeFilesPage extends StatefulWidget {
  final LargeFileService largeFileService;
  final LargeFileScanConfig? initialConfig;

  const LargeFilesPage({
    super.key,
    required this.largeFileService,
    this.initialConfig,
  });

  @override
  State<LargeFilesPage> createState() => _LargeFilesPageState();
}

class _LargeFilesPageState extends State<LargeFilesPage> with EditModeMixin, PopScopeHandlerMixin {
  // 扫描配置
  late LargeFileScanConfig _config;

  // 缓存管理
  final _cacheManager = LargeFileCacheManager();
  LargeFileScanCache? _cache;

  // 状态管理
  List<FileItem> _largeFiles = [];
  int _totalSize = 0;
  bool _isScanning = false;
  bool _isDifferentialScanning = false;
  int _newFilesCount = 0;
  int _deletedFilesCount = 0; // 本次删除的文件数量

  // 批量操作
  final _selectionController = SelectionController();
  
  @override
  SelectionController get selectionController => _selectionController;
  late final BatchOperationsService _batchService;

  @override
  void initState() {
    super.initState();

    // 初始化批量操作服务
    _batchService = BatchOperationsService(
      viewModel: locator<FileViewModel>(),
      presenter: locator<FilePresenter>(),
      onRefresh: _refresh,
      onExitSelectionMode: () {
        if (!mounted) return;
        // 延迟到下一帧执行，确保所有 notifyListeners() 完成
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // 批量操作完成后，完全退出编辑模式
          if (isEditMode) {
            exitEditMode();
          } else {
            _selectionController.clear();
          }
        });
      },
    );

    // 监听ViewModel变化，同步文件操作
    locator<FileViewModel>().addListener(_onViewModelChanged);

    // 自动加载缓存并开始扫描
    _initializeAndScan();
  }

  /// 初始化并开始扫描
  ///
  /// 双入口架构：
  /// 1. 快速扫描：initialConfig = null，使用固定的默认配置（全部类型，>50MB）
  /// 2. 自定义扫描：initialConfig != null，使用用户自定义的配置
  ///
  /// 扫描策略：
  /// - 优先加载缓存并显示，提供即时响应
  /// - 如果有有效缓存，启动后台差异扫描检测变化
  /// - 如果无缓存或配置不匹配，执行完整扫描
  Future<void> _initializeAndScan() async {
    // 1. 先尝试加载缓存
    await _loadCache();

    // 2. 确定使用的配置
    if (widget.initialConfig != null) {
      // 自定义扫描：使用传入的配置
      _config = widget.initialConfig!;
      logger.i('Using custom config from settings');
    } else {
      // 快速扫描：使用固定默认配置
      _config = const LargeFileScanConfig();
      logger.i('Using default config for quick scan');
    }

    // 记录当前配置
    logger.i('Scan config: ${_config.toString()}');
    logger.i(
        'File types enabled: ${_config.fileTypes.map((t) => t.label).join(", ")}');

    // 3. 根据缓存状态决定扫描策略
    if (_cache != null && _cache!.config.isEquivalent(_config)) {
      // 有有效缓存：显示缓存 + 后台差异扫描
      if (mounted) {
        setState(() {
          _largeFiles = List.from(_cache!.files);
          // 按文件大小降序排序
          _largeFiles.sort((a, b) => b.size.compareTo(a.size));
          _totalSize = _largeFiles.fold<int>(0, (sum, f) => sum + f.size);
        });
      }

      logger.i(
          'Cache loaded: ${_largeFiles.length} files, starting differential scan...');
      // 启动差异扫描（不阻塞，后台运行）
      unawaited(_startDifferentialScan());
    } else {
      // 无缓存或配置不匹配：执行完整扫描
      logger.i('No valid cache, starting full scan...');
      await _startFullScan();
    }
  }

  /// 加载缓存
  Future<void> _loadCache() async {
    try {
      _cache = await _cacheManager.loadCache();
      if (_cache != null) {
        logger.i(
            'Cache loaded: ${_cache!.files.length} files, age: ${_cache!.formattedAge}');
      }
    } catch (e) {
      logger.e('Failed to load cache: $e');
    }
  }

  @override
  void dispose() {
    locator<FileViewModel>().removeListener(_onViewModelChanged);
    _selectionController.dispose();
    super.dispose();
  }

  /// ViewModel变化回调 - 同步文件列表
  void _onViewModelChanged() {
    if (!mounted) return;
    
    final viewModel = locator<FileViewModel>();

    // 处理文件删除
    final deletedPath = viewModel.lastDeletedFilePath;
    if (deletedPath != null) {
      setState(() {
        final initialLength = _largeFiles.length;
        _largeFiles.removeWhere((f) => f.path == deletedPath);
        final removed = initialLength - _largeFiles.length;
        if (removed > 0) {
          _totalSize = _largeFiles.fold<int>(0, (sum, f) => sum + f.size);
          // 更新缓存
          _cacheManager.saveCache(files: _largeFiles, config: _config);
        }
      });
      return;
    }

    // 处理文件更新（重命名/移动）
    final oldPath = viewModel.lastUpdatedOldPath;
    final newFile = viewModel.lastUpdatedNewFile;
    if (oldPath != null && newFile != null) {
      setState(() {
        final index = _largeFiles.indexWhere((f) => f.path == oldPath);
        if (index != -1) {
          final minSizeBytes = _config.minSizeInMB * 1024 * 1024;
          // 检查文件大小是否还符合阈值
          if (newFile.size >= minSizeBytes) {
            _largeFiles[index] = newFile;
          } else {
            // 文件大小不再符合，移除
            _largeFiles.removeAt(index);
            _totalSize = _largeFiles.fold<int>(0, (sum, f) => sum + f.size);
          }
          // 更新缓存
          _cacheManager.saveCache(files: _largeFiles, config: _config);
        }
      });
      return;
    }

    // 处理文件添加（复制操作）- 只添加符合大文件阈值的文件
    final addedFile = viewModel.lastAddedFile;
    if (addedFile != null && !addedFile.isDirectory) {
      final minSizeBytes = _config.minSizeInMB * 1024 * 1024;
      
      if (addedFile.size >= minSizeBytes) {
        setState(() {
          // 检查是否已存在（避免重复添加）
          if (!_largeFiles.any((f) => f.path == addedFile.path)) {
            _largeFiles.add(addedFile);
            // 按文件大小降序排序
            _largeFiles.sort((a, b) => b.size.compareTo(a.size));
            _totalSize = _largeFiles.fold<int>(0, (sum, f) => sum + f.size);
            // 更新缓存
            _cacheManager.saveCache(files: _largeFiles, config: _config);
          }
        });
      }
    }
  }

  /// 刷新列表（删除后）
  /// 智能刷新：只移除已删除的文件，不重新扫描
  Future<void> _refresh() async {
    final originalCount = _largeFiles.length;

    // 过滤出仍然存在的文件
    final existingFiles = <FileItem>[];
    for (final file in _largeFiles) {
      try {
        if (await File(file.path).exists()) {
          existingFiles.add(file);
        }
      } catch (e) {
        logger.w('Error checking file existence: ${file.path}, error: $e');
      }
    }

    // 更新状态
    if (mounted) {
      final deletedCount = originalCount - existingFiles.length;
      setState(() {
        _largeFiles = existingFiles;
        _totalSize = existingFiles.fold<int>(0, (sum, f) => sum + f.size);
        _deletedFilesCount = deletedCount;
        
        // 建议 #10：如果列表变空且处于编辑模式，自动退出编辑模式
        if (_largeFiles.isEmpty && isEditMode) {
          exitEditMode();
          logger.d('Auto-exited edit mode: no files left');
        }
      });

      // 保存到缓存
      await _cacheManager.saveCache(files: _largeFiles, config: _config);

      // 3秒后清除删除提示
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _deletedFilesCount = 0;
          });
        }
      });
    }
  }

  /// 执行完全扫描
  Future<void> _startFullScan() async {
    setState(() {
      _isScanning = true;
      _largeFiles = [];
      _totalSize = 0;
      _newFilesCount = 0;
    });

    try {
      final files = await widget.largeFileService
          .scanLargeFiles(
        minSizeInMB: _config.minSizeInMB,
        maxResults: _config.maxResults,
        useSizePruning: true,
        fileTypes: _config.fileTypes,
      )
          .timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          logger.w('Large file scan timeout after 90s');
          return [];
        },
      );

      if (mounted) {
        setState(() {
          _largeFiles = files;
          // 按文件大小降序排序
          _largeFiles.sort((a, b) => b.size.compareTo(a.size));
          _totalSize = files.fold<int>(0, (sum, f) => sum + f.size);
          _isScanning = false;
        });

        // 保存到缓存
        await _cacheManager.saveCache(files: _largeFiles, config: _config);

        if (files.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('未找到大于 ${_config.minSizeInMB} MB 的文件'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      logger.e('Error scanning large files: $e');
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

  /// 执行差异扫描（后台）
  ///
  /// 差异扫描会在后台执行完整的文件扫描，然后与缓存的结果进行对比，
  /// 找出新增、删除和修改的文件。这样可以在显示缓存结果的同时，
  /// 检测文件系统的变化，提供更好的用户体验。
  Future<void> _startDifferentialScan() async {
    setState(() {
      _isDifferentialScanning = true;
      _newFilesCount = 0;
    });

    try {
      // 执行完整扫描获取当前所有大文件
      final allFiles = await widget.largeFileService
          .scanLargeFiles(
        minSizeInMB: _config.minSizeInMB,
        maxResults: _config.maxResults,
        useSizePruning: true,
        fileTypes: _config.fileTypes,
      )
          .timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          logger.w('Differential scan timeout');
          return [];
        },
      );

      if (!mounted) return;

      // 构建路径集合用于快速查找
      final currentPaths = _largeFiles.map((f) => f.path).toSet();
      final newPaths = allFiles.map((f) => f.path).toSet();

      // 新增的文件
      final addedPaths = newPaths.difference(currentPaths);
      final addedFiles =
          allFiles.where((f) => addedPaths.contains(f.path)).toList();

      logger.i('Differential scan results:');
      logger.i('  Current files: ${currentPaths.length}');
      logger.i('  Scanned files: ${newPaths.length}');
      logger.i('  New files found: ${addedFiles.length}');

      // 记录新文件的详细信息
      if (addedFiles.isNotEmpty) {
        logger.i('  New files details:');
        for (final file in addedFiles) {
          logger.i(
              '    - ${file.name} (${FileSizeFormatter.formatBytes(file.size)}, ${file.path})');
        }
      }

      // 删除的文件
      final removedPaths = currentPaths.difference(newPaths);
      if (removedPaths.isNotEmpty) {
        logger.i('  Removed files: ${removedPaths.length}');
      }

      // 检查文件大小或修改时间变化
      final modifiedFiles = <FileItem>[];
      for (final newFile in allFiles) {
        if (!currentPaths.contains(newFile.path)) continue;

        final oldFile = _largeFiles.firstWhere((f) => f.path == newFile.path);
        if (oldFile.size != newFile.size ||
            oldFile.modified != newFile.modified) {
          modifiedFiles.add(newFile);
        }
      }

      // 构建更新后的文件列表
      // 关键步骤：
      // 1. 移除已删除的文件
      // 2. 更新修改的文件
      // 3. 添加新文件
      // 4. 重新按大小排序（重要！确保新文件出现在正确位置）
      logger.i('Building updated file list...');
      logger.i('  Starting with ${_largeFiles.length} cached files');
      logger.i('  Removing ${removedPaths.length} deleted files');
      logger.i('  Updating ${modifiedFiles.length} modified files');
      logger.i('  Adding ${addedFiles.length} new files');

      final updatedFiles = _largeFiles
          .where((f) => !removedPaths.contains(f.path)) // 移除已删除的文件
          .map((f) {
        // 用新数据更新修改的文件
        final modified = modifiedFiles.firstWhere(
          (mf) => mf.path == f.path,
          orElse: () => f,
        );
        return modified;
      }).toList()
        ..addAll(addedFiles); // 添加新发现的文件

      // 【关键】重新按大小降序排序
      // 原因：新文件被添加到列表末尾，如果不排序，小文件会出现在底部看不到
      // 必须重新排序才能保证所有文件按大小正确排列
      updatedFiles.sort((a, b) => b.size.compareTo(a.size));

      logger.i(
          'Updated file list built: ${updatedFiles.length} total files (sorted by size)');

      if (mounted) {
        setState(() {
          _largeFiles = updatedFiles;
          _totalSize = updatedFiles.fold<int>(0, (sum, f) => sum + f.size);
          _isDifferentialScanning = false;
          _newFilesCount = addedFiles.length;
        });

        logger.i(
            'UI updated with ${_largeFiles.length} files, newFilesCount=$_newFilesCount');

        // 保存到缓存
        await _cacheManager.saveCache(files: _largeFiles, config: _config);

        // 如果有变化，显示提示
        if (addedFiles.isNotEmpty ||
            removedPaths.isNotEmpty ||
            modifiedFiles.isNotEmpty) {
          logger.i(
              'Differential scan: +${addedFiles.length} -${removedPaths.length} ~${modifiedFiles.length}');

          // 记录新文件信息
          if (addedFiles.isNotEmpty) {
            logger.i('New files added:');
            for (final file in addedFiles) {
              logger.i(
                  '  - ${file.name} (${FileSizeFormatter.formatBytes(file.size)})');
            }
          }

          if (mounted && (addedFiles.isNotEmpty || removedPaths.isNotEmpty)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  addedFiles.isNotEmpty
                      ? '发现 ${addedFiles.length} 个新文件'
                      : '${removedPaths.length} 个文件已不存在',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          logger.i('Differential scan: No changes detected');
        }
      }
    } catch (e) {
      logger.e('Differential scan failed: $e');
      if (mounted) {
        setState(() => _isDifferentialScanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return wrapWithPopScope(
      child: Scaffold(
        appBar: _buildAppBar(colorScheme),
        body: Column(
          children: [
            // 编辑模式提示栏
            if (isEditMode && showEditModeHint)
              const EditModeHintBar(),

            // 主体：卡片 + 列表（统一滚动）
            Expanded(
              child: _buildScrollableContent(theme, colorScheme),
            ),
          ],
        ),
        // 批量操作底部工具栏
        bottomNavigationBar: _selectionController.isSelectionMode
            ? _buildSelectionBottomBar()
            : null,
      ),
    );
  }

  /// 构建AppBar
  PreferredSizeWidget _buildAppBar(ColorScheme colorScheme) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: isEditMode
          ? AppBar(
              // 编辑/选择模式
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: exitEditMode,
                tooltip: '完成',
              ),
              title: const Text('大文件查找'),
              centerTitle: true,
              actions: [
                // 全选按钮
                SelectAllButton(
                  selectedCount: _selectionController.selected.length,
                  totalCount: _largeFiles.length,
                  onPressed: () {
                    setState(() {
                      handleSelectAll(
                        _largeFiles.map((f) => f.path).toList(),
                      );
                    });
                  },
                ),
              ],
            )
          : AppBar(
              // 普通模式
              title: const Text('大文件查找'),
              centerTitle: true,
              actions: [
                // 扫描中或空列表时隐藏编辑按钮
                if (!_isScanning && _largeFiles.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: enterEditMode,
                    tooltip: '编辑',
                  ),
              ],
            ),
    );
  }

  /// 构建可滚动内容（卡片 + 列表）
  Widget _buildScrollableContent(ThemeData theme, ColorScheme colorScheme) {
    return ValueListenableBuilder<bool>(
      valueListenable: _selectionController.selectionModeNotifier,
      builder: (context, isSelectionMode, _) {
        if (_isScanning && _largeFiles.isEmpty) {
          // 首次扫描时显示居中加载状态
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在扫描大文件...'),
              ],
            ),
          );
        }

        return CustomScrollView(
          slivers: [
            // 状态卡片（空列表时不显示，避免重复）
            if (_largeFiles.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildScanConfigArea(theme, colorScheme),
              ),
            // 文件列表或空状态
            if (_largeFiles.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '未找到大于 ${_config.minSizeInMB} MB 的文件',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final file = _largeFiles[index];
                    return _buildFileItem(file, isSelectionMode, colorScheme);
                  },
                  childCount: _largeFiles.length,
                ),
              ),
          ],
        );
      },
    );
  }

  /// 构建扫描状态和统计卡片
  Widget _buildScanConfigArea(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8), // 减小下边距
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：扫描类型次标题（置顶）
            Row(
              children: [
                Expanded(
                  child: Text(
                    _buildScanTypeSubtitle(),
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // 右上角：新文件提示或删除提示
                if (_deletedFilesCount > 0)
                  Text(
                    '已删除 $_deletedFilesCount 个文件',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[700],
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else if (_newFilesCount > 0)
                  Text(
                    '🆕 发现 $_newFilesCount 个新文件',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),

            // 分隔线
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant,
            ),
            const SizedBox(height: 12),

            // 第二行：扫描状态（放在分隔线下方）
            Row(
              children: [
                Icon(
                  _buildStatusIcon(),
                  color: _buildStatusColor(colorScheme),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _buildStatusTitle(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            // 进度条（仅完全扫描时显示）
            if (_isScanning) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],

            // 详细信息
            if (_largeFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              // 文件数量（左） + 总大小（右）
              Row(
                children: [
                  Text(
                    '找到 ${_largeFiles.length} 个文件',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Expanded(child: Container()),
                  Text(
                    '总大小',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    FileSizeFormatter.formatBytes(_totalSize),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],

            // 空状态提示
            if (_largeFiles.isEmpty && !_isScanning) ...[
              const SizedBox(height: 12),
              Text(
                '未找到大于 ${_config.minSizeInMB} MB 的文件',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 获取状态图标
  IconData _buildStatusIcon() {
    if (_isScanning) {
      return Icons.hourglass_empty;
    }
    if (_isDifferentialScanning) {
      return Icons.refresh;
    }
    if (_deletedFilesCount > 0) {
      return Icons.delete_outline;
    }
    return Icons.check_circle;
  }

  /// 获取状态颜色
  Color _buildStatusColor(ColorScheme colorScheme) {
    if (_isScanning || _isDifferentialScanning) {
      return colorScheme.primary;
    }
    if (_deletedFilesCount > 0) {
      return Colors.red;
    }
    return Colors.green;
  }

  /// 构建状态标题文本
  String _buildStatusTitle() {
    if (_isScanning) {
      return '正在扫描...';
    }
    if (_isDifferentialScanning) {
      return '正在后台检查文件变化...';
    }
    if (_deletedFilesCount > 0) {
      return '文件已删除';
    }
    if (_largeFiles.isEmpty) {
      return '暂无数据';
    }
    // 扫描完成状态
    return '扫描完成';
  }

  /// 构建扫描类型次标题
  String _buildScanTypeSubtitle() {
    // 判断是快速扫描还是自定义扫描
    final isQuickScan = widget.initialConfig == null;

    if (isQuickScan) {
      return '快速扫描';
    } else {
      // 自定义扫描：显示配置信息
      final typeLabels = _config.fileTypes.map((t) => t.label).join(' · ');
      return '自定义扫描：大于 ${_config.minSizeInMB}MB · $typeLabels';
    }
  }

  /// 构建文件列表项
  Widget _buildFileItem(
      FileItem file, bool isSelectionMode, ColorScheme colorScheme) {
    final isSelected = _selectionController.contains(file.path);
    final displayPath = _formatPath(file.path);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      selected: isSelected,
      selectedTileColor: colorScheme.primaryContainer.withOpacity(0.3),
      leading: _buildThumbnail(file, 48),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        displayPath,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      trailing: isEditMode
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      FileSizeFormatter.formatBytes(file.size),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(file.modified),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Checkbox(
                  value: isSelected,
                  onChanged: (bool? value) {
                    setState(() {
                      _selectionController.toggle(file.path);
                    });
                  },
                ),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  FileSizeFormatter.formatBytes(file.size),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(file.modified),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
      onTap: isEditMode
          ? () {
              setState(() {
                _selectionController.toggle(file.path);
              });
            }
          : () => _openFilePreview(file),
      onLongPress: isEditMode
          ? () {} // 编辑模式：禁用长按
          : () {
              // 长按：显示单文件操作面板
              _showSingleFileOperationsMenu(context, file);
            },
    );
  }

  /// 构建扫描结果卡片（在列表顶部显示）
  /// 构建批量操作栏
  /// 构建批量选择底部工具栏
  Widget _buildSelectionBottomBar() {
    return SelectionBottomBar(
      selectedPaths: _selectionController.selected,
      isAllFavorite: _batchService.isAllSelectedFavorite(_selectionController.selected),
      onCopy: () {
        if (!mounted) return;
        _batchService.batchCopy(context, _selectionController.selected, '/storage/emulated/0');
      },
      onRename: () {
        if (!mounted) return;
        _batchService.batchRename(context, _selectionController.selected);
      },
      onShare: () {
        if (!mounted) return;
        _batchService.batchShare(context, _selectionController.selected);
      },
      onMove: () {
        if (!mounted) return;
        _batchService.batchMove(context, _selectionController.selected, '/storage/emulated/0');
      },
      onToggleFavorite: () {
        if (!mounted) return;
        _batchService.batchToggleFavorite(context, _selectionController.selected);
      },
      onDelete: () {
        if (!mounted) return;
        _batchService.batchDelete(context, _selectionController.selected);
      },
    );
  }

  /// 获取文件图标（与分类页面保持一致）
  IconData _getFileIcon(FileItem file) {
    final ext = path.extension(file.name).toLowerCase();

    // 视频
    if ([
      '.mp4',
      '.avi',
      '.mkv',
      '.mov',
      '.wmv',
      '.flv',
      '.webm',
      '.3gp',
      '.m4v'
    ].contains(ext)) {
      return Icons.videocam;
    }
    // 音频
    else if (['.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma', '.opus']
        .contains(ext)) {
      return Icons.music_note;
    }
    // 图片
    else if (['.jpg', '.png', '.gif', '.jpeg', '.bmp', '.webp', '.heic']
        .contains(ext)) {
      return Icons.image;
    }
    // PDF
    else if (ext == '.pdf') {
      return Icons.picture_as_pdf;
    }
    // Word
    else if (['.doc', '.docx'].contains(ext)) {
      return Icons.article;
    }
    // Excel
    else if (['.xls', '.xlsx', '.csv'].contains(ext)) {
      return Icons.table_chart;
    }
    // PPT
    else if (['.ppt', '.pptx'].contains(ext)) {
      return Icons.slideshow;
    }
    // 文本
    else if (['.txt', '.log', '.md', '.rtf'].contains(ext)) {
      return Icons.description;
    }
    // 压缩包
    else if (['.zip', '.rar', '.7z', '.tar', '.gz'].contains(ext)) {
      return Icons.folder_zip;
    }
    // APK
    else if (ext == '.apk') {
      return Icons.android;
    }
    // 其他
    return Icons.insert_drive_file;
  }

  /// 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 构建文件缩略图
  Widget _buildThumbnail(FileItem file, double size) {
    if (FileUtils.isImageFile(file.name)) {
      return ImageThumbnail(
        imagePath: file.path,
        size: size,
      );
    } else if (FileUtils.isVideoFile(file.name)) {
      return RealVideoThumbnail(
        videoPath: file.path,
        size: size,
        showDuration: false,
      );
    } else if (FileUtils.isAudioFile(file.name)) {
      return AudioCoverWidget(
        audioPath: file.path,
        size: size,
      );
    } else if (FileUtils.isDocumentFile(file.name) ||
        FileUtils.isTextFile(file.name) ||
        FileUtils.isArchiveFile(file.name)) {
      // 文档类型文件使用带颜色的图标组件
      return DocumentIconWidgetRounded(
        fileName: file.name,
        size: size,
      );
    } else {
      // APK 和其他文件类型显示灰色图标
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          _getFileIcon(file),
          color: Colors.grey[600],
          size: size * 0.5,
        ),
      );
    }
  }

  /// 显示单文件操作菜单
  void _showSingleFileOperationsMenu(BuildContext context, FileItem file) {
    final service = SingleFileOperationsService(
      context: context,
      viewModel: locator<FileViewModel>(),
      presenter: locator<FilePresenter>(),
      onRefresh: () async {
        if (mounted) {
          await _refresh();
        }
      },
      onUIUpdate: () {
        if (mounted) {
          setState(() {});
        }
      },
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SingleFileOperationsSheet(
        file: file,
        service: service,
      ),
    );
  }

  /// 格式化文件路径，将 /storage/emulated/0/ 替换为 内部存储/
  String _formatPath(String fullPath) {
    return fullPath.replaceFirst('/storage/emulated/0/', '内部存储/');
  }

  /// 打开文件预览页
  Future<void> _openFilePreview(FileItem file) async {
    final needsRefresh = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => FilePreviewPage(
          file: file,
          fileList: _largeFiles,
          initialIndex: _largeFiles.indexWhere((f) => f.path == file.path),
          viewModel: locator<FileViewModel>(),
          presenter: locator<FilePresenter>(),
        ),
      ),
    );

    // 如果文件被修改（删除、移动等），刷新列表
    if (needsRefresh == true) {
      await _refresh();
    }
  }
}
