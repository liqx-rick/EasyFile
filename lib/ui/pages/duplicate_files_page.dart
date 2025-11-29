import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/duplicate_file_scan_config.dart';
import 'package:easyfile/core/models/large_file_scan_config.dart';
import 'package:easyfile/core/services/duplicate_file_cache_manager.dart';
import 'package:easyfile/core/services/duplicate_file_service.dart';
import 'package:easyfile/data/models/duplicate_file_group.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/audio_cover_widget.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';
import 'package:easyfile/ui/widgets/image_thumbnail.dart';
import 'package:easyfile/ui/widgets/real_video_thumbnail.dart';
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
  final DuplicateFileService duplicateFileService;
  final DuplicateFileScanConfig initialConfig;

  const DuplicateFilesPage({
    super.key,
    required this.duplicateFileService,
    required this.initialConfig,
  });

  @override
  State<DuplicateFilesPage> createState() => _DuplicateFilesPageState();
}

class _DuplicateFilesPageState extends State<DuplicateFilesPage> {
  // 扫描配置
  late DuplicateFileScanConfig _config;

  // 配置缓存管理
  final _cacheManager = DuplicateFileCacheManager();

  // 状态管理
  List<DuplicateFileGroup> _allGroups = [];
  bool _isScanning = false;
  int _currentStage = 0;
  int _currentProgress = 0;
  int _totalProgress = 0;
  String _currentFile = '';

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
    _initializeAndScan();
  }

  /// 初始化并开始扫描
  Future<void> _initializeAndScan() async {
    // 直接开始扫描（不使用缓存，确保数据实时性）
    await _startScan();
  }

  /// 初始化默认选中状态（推荐删除的文件默认选中）
  void _initializeDefaultSelection() {
    _selectedFilePaths.clear();
    for (final group in _allGroups) {
      for (final file in group.recommendedToDelete) {
        _selectedFilePaths.add(file.path);
      }
    }
    _isSelectionMode = _selectedFilePaths.isNotEmpty;
  }

  /// 开始扫描
  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _allGroups = [];
      _currentStage = 0;
      _currentProgress = 0;
      _totalProgress = 0;
      _currentFile = '';
    });

    try {
      final groups = await widget.duplicateFileService.scanDuplicateFiles(
        config: _config,
        onProgress: (stage, current, total, file) {
          if (mounted) {
            setState(() {
              _currentStage = stage;
              _currentProgress = current;
              _totalProgress = total;
              _currentFile = file;
            });
          }
        },
      );

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
            const SnackBar(
              content: Text('未找到重复文件'),
              duration: Duration(seconds: 2),
            ),
          );
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
      bottomNavigationBar: _isSelectionMode ? _buildBottomBar(colorScheme) : null,
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
          _config.scanMode == DuplicateScanMode.full ? '重复文件清理（完整）' : '重复文件清理（${_config.selectedType!.label}）',
        ),
        centerTitle: true,
      );
    }

    return AppBar(
      title: Text(
        _config.scanMode == DuplicateScanMode.full ? '重复文件清理（完整）' : '重复文件清理（${_config.selectedType!.label}）',
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              _getStageName(_currentStage),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_totalProgress > 0)
              Text(
                '$_currentProgress / $_totalProgress',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 16),
            if (_currentFile.isNotEmpty)
              Text(
                _currentFile,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
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

  /// 构建完整扫描结果（分类折叠）
  Widget _buildFullScanResult(ThemeData theme, ColorScheme colorScheme) {
    if (_allGroups.isEmpty) {
      return _buildEmptyState();
    }

    final groupsByType = _groupByType();
    final totalFiles = _allGroups.fold<int>(0, (sum, g) => sum + g.count);
    final totalReclaimable = _allGroups.fold<int>(0, (sum, g) => sum + g.reclaimableSpace);

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
                    '可释放空间: ${FileSizeFormatter.formatBytes(totalReclaimable)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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

              return _buildTypeExpansionTile(type, groups, isExpanded, theme, colorScheme);
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
        children: groups.map((group) => _buildGroupItem(group, theme, colorScheme)).toList(),
      ),
    );
  }

  /// 构建分类扫描结果（直接列表）
  Widget _buildCategoryScanResult(ThemeData theme, ColorScheme colorScheme) {
    if (_allGroups.isEmpty) {
      return _buildEmptyState();
    }

    final totalFiles = _allGroups.fold<int>(0, (sum, g) => sum + g.count);
    final totalReclaimable = _allGroups.fold<int>(0, (sum, g) => sum + g.reclaimableSpace);

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
                  Text(
                    '📊 扫描结果',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('找到 ${_allGroups.length} 组重复${_config.selectedType!.label} (共 $totalFiles 个文件)'),
                  const SizedBox(height: 4),
                  Text(
                    '可释放空间: ${FileSizeFormatter.formatBytes(totalReclaimable)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '未找到重复文件',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
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
            // 第三行+：重复文件列表
            ...group.files.map((file) {
              final isRecommended = file.path == recommendedFile.path;
              final isSelected = _selectedFilePaths.contains(file.path);

              return _buildFileItem(
                file,
                isRecommended,
                isSelected,
                theme,
                colorScheme,
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 构建文件项（可展开/折叠）
  Widget _buildFileItem(
    FileItem file,
    bool isRecommended,
    bool isSelected,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isExpanded = _expandedFiles[file.path] ?? false;

    return Padding(
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
                  // 缩略图（图片/视频 80px，其他 40px）
                  _buildThumbnail(file),
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
                              isExpanded ? Icons.expand_less : Icons.expand_more,
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
                          if (_selectedFilePaths.isEmpty) _isSelectionMode = false;
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
                            if (_selectedFilePaths.isEmpty) _isSelectionMode = false;
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
                        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: colorScheme.primary,
                    disabledForegroundColor: colorScheme.onSurfaceVariant.withOpacity(0.38),
                  ),
                  child: const Text('推荐', style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 8),
                
                // 清空按钮（始终显示，无选择时禁用）
                TextButton(
                  onPressed: hasSelection ? _clearSelection : null,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: colorScheme.onSurfaceVariant,
                    disabledForegroundColor: colorScheme.onSurfaceVariant.withOpacity(0.38),
                  ),
                  child: const Text('清空', style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 8),
                
                // 删除按钮（始终显示，无选择时禁用）
                FilledButton(
                  onPressed: hasSelection ? _deleteSelectedFiles : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                    disabledBackgroundColor: colorScheme.surfaceContainerHighest,
                    disabledForegroundColor: colorScheme.onSurfaceVariant.withOpacity(0.38),
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
    final isImageOrVideo = FileUtils.isImageFile(file.name) || FileUtils.isVideoFile(file.name);
    final size = isImageOrVideo ? 80.0 : 40.0;
    
    if (FileUtils.isImageFile(file.name)) {
      return ImageThumbnail(imagePath: file.path, size: size);
    } else if (FileUtils.isVideoFile(file.name)) {
      return RealVideoThumbnail(videoPath: file.path, size: size, showDuration: false);
    } else if (FileUtils.isAudioFile(file.name)) {
      return AudioCoverWidget(audioPath: file.path, size: size);
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
