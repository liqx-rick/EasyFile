import 'dart:io';

import 'package:flutter/material.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/trash_file_service.dart';
import 'package:easyfile/data/models/trash_file_item.dart';
import 'package:easyfile/data/models/trash_bin.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/ui/widgets/video_player_widget.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:easyfile/ui/widgets/file_list_item_builder.dart';
import 'package:easyfile/ui/utils/file_details_helper.dart';
import 'package:easyfile/ui/widgets/edit_mode_widgets.dart';

/// 文件类型枚举
enum FileType {
  image, // 图片
  video, // 视频
  audio, // 音频
  document, // 文档
  archive, // 压缩包
  other, // 其他
}

/// 文件类型分类统计
class FileTypeCategory {
  final String name;
  final FileType type;
  final int count;
  final int size;

  FileTypeCategory({
    required this.name,
    required this.type,
    required this.count,
    required this.size,
  });
}

/// 回收站清理页面
class TrashFilesPage extends StatefulWidget {
  const TrashFilesPage({super.key});

  @override
  State<TrashFilesPage> createState() => _TrashFilesPageState();
}

class _TrashFilesPageState extends State<TrashFilesPage> {
  late final TrashFileService _service;

  // 回收站列表
  List<TrashBin> _trashBins = [];

  // 所有文件列表
  List<TrashFileItem> _allFiles = [];

  // 当前过滤的回收站ID（null表示显示所有）
  String? _selectedTrashBinId;

  bool _isScanning = false;

  // 选中的文件
  final Set<String> _selectedPaths = {};

  // 当前选中的分类
  String _currentCategory = 'all'; // all, images, videos, others

  @override
  void initState() {
    super.initState();
    _service = locator<TrashFileService>();
    _initializeAndScan();
  }

  /// 初始化服务并开始扫描
  Future<void> _initializeAndScan() async {
    // 初始化回收站服务（检查MediaStore支持）
    await _service.initialize();
    _startScan();
  }

  /// 开始扫描
  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _trashBins = [];
      _allFiles = [];
      _selectedPaths.clear();
      _selectedTrashBinId = null;
    });

    try {
      final result = await _service.scanTrashBinsWithFiles(
        onProgress: (current, total, path) {
          // 扫描进度回调，仅用于记录，UI不显示
        },
      );

      if (mounted) {
        setState(() {
          _trashBins = result.trashBins;
          _allFiles = result.allFiles;
        });

        // 延迟关闭加载状态，确保UI完全构建完成后再停止动画
        await Future.delayed(const Duration(milliseconds: 100));

        if (mounted) {
          setState(() {
            _isScanning = false;
          });
        }
      }
    } catch (e) {
      logger.e('扫描回收站失败: $e');
      if (mounted) {
        setState(() => _isScanning = false);
        _showError('扫描失败: $e');
      }
    }
  }

  /// 按文件类型聚合
  List<FileTypeCategory> _aggregateByFileType() {
    final categories = <FileTypeCategory>[];

    // 统计各类型文件
    int imageSize = 0, imageCount = 0;
    int videoSize = 0, videoCount = 0;
    int audioSize = 0, audioCount = 0;
    int documentSize = 0, documentCount = 0;
    int archiveSize = 0, archiveCount = 0;
    int otherSize = 0, otherCount = 0;

    for (final file in _allFiles) {
      final mimeType = file.mimeType.toLowerCase();
      final ext = file.name.split('.').last.toLowerCase();

      if (mimeType.startsWith('image/')) {
        imageSize += file.size;
        imageCount++;
      } else if (mimeType.startsWith('video/')) {
        videoSize += file.size;
        videoCount++;
      } else if (mimeType.startsWith('audio/')) {
        audioSize += file.size;
        audioCount++;
      } else if (mimeType.contains('pdf') ||
          mimeType.contains('document') ||
          mimeType.contains('word') ||
          mimeType.contains('excel') ||
          mimeType.contains('powerpoint') ||
          mimeType.contains('text/') ||
          ['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'].contains(ext)) {
        documentSize += file.size;
        documentCount++;
      } else if (mimeType.contains('zip') ||
          mimeType.contains('rar') ||
          mimeType.contains('7z') ||
          mimeType.contains('tar') ||
          mimeType.contains('gzip') ||
          ['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
        archiveSize += file.size;
        archiveCount++;
      } else {
        otherSize += file.size;
        otherCount++;
      }
    }

    // 创建分类（只添加非空分类）
    if (imageCount > 0) {
      categories.add(FileTypeCategory(
        name: '图片',
        type: FileType.image,
        count: imageCount,
        size: imageSize,
      ));
    }
    if (videoCount > 0) {
      categories.add(FileTypeCategory(
        name: '视频',
        type: FileType.video,
        count: videoCount,
        size: videoSize,
      ));
    }
    if (audioCount > 0) {
      categories.add(FileTypeCategory(
        name: '音频',
        type: FileType.audio,
        count: audioCount,
        size: audioSize,
      ));
    }
    if (documentCount > 0) {
      categories.add(FileTypeCategory(
        name: '文档',
        type: FileType.document,
        count: documentCount,
        size: documentSize,
      ));
    }
    if (archiveCount > 0) {
      categories.add(FileTypeCategory(
        name: '压缩包',
        type: FileType.archive,
        count: archiveCount,
        size: archiveSize,
      ));
    }
    if (otherCount > 0) {
      categories.add(FileTypeCategory(
        name: '其他',
        type: FileType.other,
        count: otherCount,
        size: otherSize,
      ));
    }

    return categories;
  }

  /// 获取当前显示的文件列表（根据过滤条件）
  List<TrashFileItem> _getDisplayedFiles() {
    var files = _allFiles;

    // 1. 根据选中的回收站过滤
    if (_selectedTrashBinId != null) {
      files = files.where((f) => f.trashBinId == _selectedTrashBinId).toList();
    }

    // 2. 根据分类过滤
    if (_currentCategory != 'all') {
      files = files.where((f) {
        final mimeType = f.mimeType.toLowerCase();
        final ext = f.name.split('.').last.toLowerCase();

        switch (_currentCategory) {
          case 'images':
            return mimeType.startsWith('image/');
          case 'videos':
            return mimeType.startsWith('video/');
          case 'audios':
            return mimeType.startsWith('audio/');
          case 'documents':
            return mimeType.contains('pdf') ||
                mimeType.contains('document') ||
                mimeType.contains('word') ||
                mimeType.contains('excel') ||
                mimeType.contains('powerpoint') ||
                mimeType.contains('text/') ||
                ['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt']
                    .contains(ext);
          case 'archives':
            return mimeType.contains('zip') ||
                mimeType.contains('rar') ||
                mimeType.contains('7z') ||
                mimeType.contains('tar') ||
                mimeType.contains('gzip') ||
                ['zip', 'rar', '7z', 'tar', 'gz'].contains(ext);
          case 'others':
            // 其他：不属于以上任何类型
            return !mimeType.startsWith('image/') &&
                !mimeType.startsWith('video/') &&
                !mimeType.startsWith('audio/') &&
                !mimeType.contains('pdf') &&
                !mimeType.contains('document') &&
                !mimeType.contains('word') &&
                !mimeType.contains('excel') &&
                !mimeType.contains('powerpoint') &&
                !mimeType.contains('text/') &&
                !['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt']
                    .contains(ext) &&
                !mimeType.contains('zip') &&
                !mimeType.contains('rar') &&
                !mimeType.contains('7z') &&
                !mimeType.contains('tar') &&
                !mimeType.contains('gzip') &&
                !['zip', 'rar', '7z', 'tar', 'gz'].contains(ext);
          default:
            return true;
        }
      }).toList();
    }

    // 3. 按删除时间倒序排序（最新删除的在前）
    files.sort((a, b) {
      final aTime = a.trashedTime ?? a.modified;
      final bTime = b.trashedTime ?? b.modified;
      return bTime.compareTo(aTime); // 倒序：新的在前
    });

    return files;
  }

  /// 一键清空所有回收站
  Future<void> _emptyAllTrash() async {
    if (_trashBins.isEmpty) return;

    final totalSize = _allFiles.fold<int>(0, (sum, f) => sum + f.size);
    final totalCount = _allFiles.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: Text(
          '确定要清空所有回收站吗？\n\n'
          '$totalCount 个文件，${FileSizeFormatter.formatBytes(totalSize)}\n\n'
          '⚠️ 这些文件将永久删除，无法恢复！',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在清空回收站...'),
          ],
        ),
      ),
    );

    try {
      final result = await _service.deleteTrashBinFiles(
        trashBinIds: _trashBins.map((b) => b.id).toList(),
        allFiles: _allFiles,
      );

      if (!mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('清空完成'),
          content: Text(
            '成功删除 ${result['success']} 个文件\n'
            '失败 ${result['failed']} 个\n'
            '释放空间: ${result['formattedSize']}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );

      _startScan();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('清空失败: $e');
    }
  }

  /// 删除选中的文件
  Future<void> _deleteSelected() async {
    if (_selectedPaths.isEmpty) return;

    final confirmed = await _showDeleteConfirmDialog();
    if (confirmed != true || !mounted) return;

    final toDelete =
        _allFiles.where((f) => _selectedPaths.contains(f.path)).toList();

    // 显示加载对话框
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在删除...'),
          ],
        ),
      ),
    );

    final result = await _service.deleteMultiple(toDelete);

    if (mounted) {
      Navigator.of(context).pop(); // 关闭加载对话框

      _showResultDialog(result);

      // 刷新列表
      setState(() {
        _allFiles.removeWhere((f) => _selectedPaths.contains(f.path));
        _selectedPaths.clear();
      });
    }
  }

  /// 恢复选中的文件
  Future<void> _restoreSelected() async {
    if (_selectedPaths.isEmpty) return;

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认恢复'),
        content: Text(
          '确定要恢复选中的 ${_selectedPaths.length} 个文件吗？\n\n'
          '文件将恢复到原位置或默认目录',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('恢复'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在恢复...'),
          ],
        ),
      ),
    );

    try {
      final toRestore =
          _allFiles.where((f) => _selectedPaths.contains(f.path)).toList();

      final result = await _service.restoreMultiple(toRestore);

      if (mounted) {
        Navigator.of(context).pop(); // 关闭加载对话框

        final success = result['success'] as int;
        final failed = result['failed'] as int;
        final errors = result['errors'] as List<String>;
        final restoredPaths = result['restoredPaths'] as List<dynamic>;

        // 显示恢复结果对话框
        if (success > 0) {
          // 收集恢复的文件名
          final restoredFileNames = <String>[];
          for (var item in restoredPaths) {
            final fileName = item['fileName'] as String;
            restoredFileNames.add(fileName);
          }

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 28),
                  const SizedBox(width: 12),
                  Text('恢复成功 ($success个文件)'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '文件已保存到：',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.folder,
                              size: 20, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'EasyFile/Restored/',
                              style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '恢复的文件：',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    ...restoredFileNames.map((name) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            name,
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[700]),
                          ),
                        )),
                    const SizedBox(height: 16),
                    Text(
                      '请移步至快捷访问菜单的 "已恢复" 入口查看。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (failed > 0) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        '失败 $failed 个文件',
                        style: const TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      ...errors.map((e) => Text(
                            '• $e',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[700]),
                          )),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        } else {
          // 全部失败，显示错误
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('恢复失败'),
              backgroundColor: Colors.red,
            ),
          );
          if (errors.isNotEmpty) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('恢复失败'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: errors.map((e) => Text('• $e')).toList(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('确定'),
                  ),
                ],
              ),
            );
          }
        }

        // 刷新列表
        setState(() {
          _allFiles.removeWhere((f) => _selectedPaths.contains(f.path));
          _selectedPaths.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // 关闭加载对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('恢复失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 显示删除确认对话框
  Future<bool?> _showDeleteConfirmDialog() {
    final totalSize = _allFiles
        .where((f) => _selectedPaths.contains(f.path))
        .fold<int>(0, (sum, f) => sum + f.size);

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          '确定要永久删除选中的 ${_selectedPaths.length} 个文件吗？\n'
          '共计 ${FileSizeFormatter.formatBytes(totalSize)}\n\n'
          '⚠️ 这些文件将从系统回收站中永久删除，无法恢复！',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 显示清空回收站确认对话框
  /// 显示删除结果对话框
  void _showResultDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除完成'),
        content: Text(
          '成功删除: ${result['success']} 个\n'
          '失败: ${result['failed']} 个\n'
          '释放空间: ${result['formattedSize']}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示错误消息
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站清理'),
        actions: [
          // 刷新按钮（扫描时隐藏）
          if (!_isScanning)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: _startScan,
            ),
          // 全选/取消全选
          if (!_isScanning && _filteredFiles.isNotEmpty)
            SelectAllButton(
              selectedCount: _filteredFiles
                  .where((f) => _selectedPaths.contains(f.path))
                  .length,
              totalCount: _filteredFiles.length,
              onPressed: () {
                setState(() {
                  final filteredPaths =
                      _filteredFiles.map((f) => f.path).toSet();
                  if (_selectedPaths.containsAll(filteredPaths)) {
                    // 取消选择当前过滤的文件
                    _selectedPaths.removeAll(filteredPaths);
                  } else {
                    // 选择当前过滤的文件
                    _selectedPaths.addAll(filteredPaths);
                  }
                });
              },
            ),
        ],
      ),
      body: _isScanning
          ? _buildScanningView()
          : _allFiles.isEmpty
              ? _buildEmptyView()
              : CustomScrollView(
                  slivers: [
                    // 统计卡片
                    SliverToBoxAdapter(
                      child: _buildSummaryCard(),
                    ),

                    // 分类筛选 - 置顶显示
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _CategoryFilterDelegate(
                        child: _buildCategoryFilter(),
                      ),
                    ),

                    // 提示信息（如果需要）
                    if (_getDisplayedFiles().isEmpty)
                      SliverFillRemaining(
                        child: _buildEmptyCategoryView(),
                      )
                    else
                      // 文件列表
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final files = _getDisplayedFiles();
                            final file = files[index];
                            final isSelected =
                                _selectedPaths.contains(file.path);

                            return InkWell(
                              onLongPress: () {
                                FileDetailsHelper.showTrashFileDetailsBottomSheet(
                                  context,
                                  file,
                                  trashBinName: _getTrashBinName(file),
                                  fileTypeLabel: _getFileTypeLabel(file),
                                );
                              },
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedPaths.remove(file.path);
                                  } else {
                                    _selectedPaths.add(file.path);
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 左侧图标或缩略图
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          right: 12, top: 4),
                                      child: FileListItemBuilder
                                          .buildFileThumbnail(
                                        filePath: file.path,
                                        mimeType: file.mimeType,
                                        fileName: file.name,
                                        onTap: () => _previewFile(file),
                                        size: 48.0,
                                      ),
                                    ),
                                    // 中间内容区域
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // 第一行：文件名 + 勾选框
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  FileListItemBuilder
                                                      .truncateFileName(
                                                          file.name,
                                                          maxLength: 35),
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              // 勾选框
                                              SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: Checkbox(
                                                  value: isSelected,
                                                  onChanged: (checked) {
                                                    setState(() {
                                                      if (checked == true) {
                                                        _selectedPaths
                                                            .add(file.path);
                                                      } else {
                                                        _selectedPaths
                                                            .remove(file.path);
                                                      }
                                                    });
                                                  },
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          // 第二行：类型和大小
                                          Text(
                                            '${_getFileTypeLabel(file)} · ${FileSizeFormatter.formatBytes(file.size)}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF757575),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          // 第三行：回收站位置 · 删除时间 · 详情
                                          GestureDetector(
                                            onTapUp: (details) {
                                              final trashBinName =
                                                  _getTrashBinName(file);
                                              final textPainter = TextPainter(
                                                text: TextSpan(
                                                  text:
                                                      '$trashBinName · ${FileListItemBuilder.formatRelativeDate(file.trashedTime ?? file.modified)} · ',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF757575),
                                                  ),
                                                ),
                                                textDirection:
                                                    TextDirection.ltr,
                                              );
                                              textPainter.layout();
                                              final offset = textPainter.width;

                                              if (details.localPosition.dx >=
                                                  offset) {
                                                FileDetailsHelper.showTrashFileDetailsBottomSheet(
                                                  context,
                                                  file,
                                                  trashBinName: _getTrashBinName(file),
                                                  fileTypeLabel: _getFileTypeLabel(file),
                                                );
                                              }
                                            },
                                            child: RichText(
                                              text: TextSpan(
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Color(0xFF757575),
                                                  fontFamily: 'Roboto',
                                                ),
                                                children: [
                                                  TextSpan(
                                                    text:
                                                        '${_getTrashBinName(file)} · ${FileListItemBuilder.formatRelativeDate(file.trashedTime ?? file.modified)} · ',
                                                  ),
                                                  const TextSpan(
                                                    text: '详情',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.blue,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: _getDisplayedFiles().length,
                        ),
                      ),
                  ],
                ),
      // 底部操作工具栏（恢复和删除）
      bottomNavigationBar: _selectedPaths.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _restoreSelected,
                        icon: const Icon(Icons.restore_from_trash),
                        label: Text('恢复 (${_selectedPaths.length})'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green,
                          side: const BorderSide(color: Colors.green),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _deleteSelected,
                        icon: const Icon(Icons.delete_forever),
                        label: Text('删除 (${_selectedPaths.length})'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// 获取过滤后的文件列表（使用_getDisplayedFiles替代）
  List<TrashFileItem> get _filteredFiles => _getDisplayedFiles();

  /// 统计各类文件数量（基于所有文件，不受当前分类筛选影响）
  Map<String, int> get _categoryStats {
    int images = 0,
        videos = 0,
        audios = 0,
        documents = 0,
        archives = 0,
        others = 0;

    for (var file in _allFiles) {
      final mimeType = file.mimeType.toLowerCase();
      final ext = file.name.split('.').last.toLowerCase();

      if (mimeType.startsWith('image/')) {
        images++;
      } else if (mimeType.startsWith('video/')) {
        videos++;
      } else if (mimeType.startsWith('audio/')) {
        audios++;
      } else if (mimeType.contains('pdf') ||
          mimeType.contains('document') ||
          mimeType.contains('word') ||
          mimeType.contains('excel') ||
          mimeType.contains('powerpoint') ||
          mimeType.contains('text/') ||
          ['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'].contains(ext)) {
        documents++;
      } else if (mimeType.contains('zip') ||
          mimeType.contains('rar') ||
          mimeType.contains('7z') ||
          mimeType.contains('tar') ||
          mimeType.contains('gzip') ||
          ['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
        archives++;
      } else {
        others++;
      }
    }

    return {
      'all': _allFiles.length,
      'images': images,
      'videos': videos,
      'audios': audios,
      'documents': documents,
      'archives': archives,
      'others': others
    };
  }

  /// 获取文件所属的回收站名称
  String _getTrashBinName(TrashFileItem file) {
    if (file.trashBinId == null) {
      return file.trashDirectoryName; // 兜底使用旧的目录名
    }

    final bin = _trashBins.firstWhere(
      (b) => b.id == file.trashBinId,
      orElse: () => TrashBin(
        id: '',
        path: '',
        name: file.trashDirectoryName,
        type: TrashBinType.system,
        fileCount: 0,
        totalSize: 0,
      ),
    );

    return bin.name;
  }

  /// 统计卡片（带饼图）
  Widget _buildSummaryCard() {
    final totalSize = _allFiles.fold<int>(0, (sum, f) => sum + f.size);
    final totalCount = _allFiles.length;
    final categories = _aggregateByFileType();

    // 计算饼图/空状态图标的大小（横屏时限制最大高度）
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    // 使用可用空间的较小值，避免横屏时溢出
    final maxSize = screenWidth < screenHeight
        ? (screenWidth / 2) * 0.9
        : screenHeight * 0.35;
    final iconSize = maxSize;

    return Card(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // 左侧：饼图
            Expanded(
              flex: 5,
              child: totalCount > 0
                  ? _buildPieChart(categories)
                  : Center(
                      child: Icon(
                        Icons.pie_chart_outline,
                        size: iconSize * 0.6, // 空状态图标稍小一点，占饼图容器的60%
                        color: Colors.grey[300],
                      ),
                    ),
            ),
            // 中间分割线
            Container(
              width: 1,
              height: 140,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: Colors.grey[300],
            ),
            // 右侧：总览信息
            Expanded(
              flex: 5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '共发现 $totalCount 个文件',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    FileSizeFormatter.formatBytes(totalSize),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: totalCount > 0 ? _emptyAllTrash : null,
                    icon: const Icon(Icons.delete_sweep, size: 20),
                    label: const Text('一键清空'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      minimumSize: const Size(double.infinity, 44),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '不可恢复，请谨慎操作',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建饼图
  Widget _buildPieChart(List<FileTypeCategory> categories) {
    if (categories.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalSize = _allFiles.fold<int>(0, (sum, f) => sum + f.size);
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    // 横屏时使用高度限制，竖屏时使用宽度
    final pieChartSize = screenWidth < screenHeight
        ? (screenWidth / 2) * 0.9
        : screenHeight * 0.35;
    final radius = pieChartSize / 2.5; // 动态计算半径

    final sections = categories.map((category) {
      final percentage = (category.size / totalSize) * 100;
      return PieChartSectionData(
        value: category.size.toDouble(),
        title: '${percentage.toStringAsFixed(0)}%',
        color: _getFileTypeColor(category.type),
        radius: radius,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 饼图 - 使用固定高度
        SizedBox(
          width: pieChartSize,
          height: pieChartSize,
          child: PieChart(
            PieChartData(
              sections: sections,
              sectionsSpace: 2,
              centerSpaceRadius: 0,
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // 图例：2行3列网格布局
        LayoutBuilder(
          builder: (context, constraints) {
            // 使用LayoutBuilder获取实际可用宽度
            final actualWidth = constraints.maxWidth;
            // 每列宽度 = (实际宽度 - 2个间距6*2) / 3
            final legendItemWidth = ((actualWidth - 12) / 3).clamp(46.0, 68.0);

            return Wrap(
              spacing: 6,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: categories.map((category) {
                return SizedBox(
                  width: legendItemWidth,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _getFileTypeColor(category.type),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          category.name,
                          style: const TextStyle(fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  /// 获取文件类型颜色
  Color _getFileTypeColor(FileType type) {
    switch (type) {
      case FileType.image:
        return Colors.blue[400]!;
      case FileType.video:
        return Colors.purple[400]!;
      case FileType.audio:
        return Colors.green[400]!;
      case FileType.document:
        return Colors.red[400]!;
      case FileType.archive:
        return Colors.amber[700]!;
      case FileType.other:
        return Colors.grey[400]!;
    }
  }

  /// 扫描中视图
  Widget _buildScanningView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              '正在扫描回收站...',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '请稍候',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 空状态视图
  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.delete_outline,
            size: 64,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          Text(
            '回收站为空',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('未发现回收站文件'),
        ],
      ),
    );
  }

  /// 获取文件类型显示名称（根据验证状态显示不同标签）
  String _getFileTypeLabel(TrashFileItem file) {
    if (file.isDirectory) {
      return '文件夹';
    }

    final mimeType = file.mimeType.toLowerCase();
    final ext = file.name.split('.').last.toLowerCase();
    final verified = file.mimeTypeVerified; // 是否通过文件头验证（已有默认值false）

    // 图片类型
    if (mimeType.startsWith('image/')) {
      if (mimeType.contains('jpeg') || mimeType.contains('jpg')) {
        return verified ? 'JPEG图片' : 'JPG文件';
      } else if (mimeType.contains('png')) {
        return verified ? 'PNG图片' : 'PNG文件';
      } else if (mimeType.contains('gif')) {
        return verified ? 'GIF图片' : 'GIF文件';
      } else if (mimeType.contains('webp')) {
        return verified ? 'WebP图片' : 'WEBP文件';
      } else if (mimeType.contains('bmp')) {
        return verified ? 'BMP图片' : 'BMP文件';
      } else if (mimeType.contains('svg')) {
        return 'SVG文件'; // SVG通常是文本格式，不需要验证
      } else if (mimeType.contains('heic') || mimeType.contains('heif')) {
        return verified ? 'HEIC图片' : 'HEIC文件';
      } else {
        return verified ? '图片文件' : '图像文件';
      }
    }

    // 视频类型
    if (mimeType.startsWith('video/')) {
      if (mimeType.contains('mp4')) {
        return verified ? 'MP4视频' : 'MP4文件';
      } else if (mimeType.contains('avi')) {
        return verified ? 'AVI视频' : 'AVI文件';
      } else if (mimeType.contains('mov') || mimeType.contains('quicktime')) {
        return verified ? 'MOV视频' : 'MOV文件';
      } else if (mimeType.contains('mkv')) {
        return verified ? 'MKV视频' : 'MKV文件';
      } else if (mimeType.contains('webm')) {
        return verified ? 'WebM视频' : 'WEBM文件';
      } else if (mimeType.contains('flv')) {
        return verified ? 'FLV视频' : 'FLV文件';
      } else if (mimeType.contains('wmv')) {
        return verified ? 'WMV视频' : 'WMV文件';
      } else if (mimeType.contains('3gp')) {
        return verified ? '3GP视频' : '3GP文件';
      } else {
        return verified ? '视频文件' : '媒体文件';
      }
    }

    // 音频类型
    if (mimeType.startsWith('audio/')) {
      if (mimeType.contains('mp3') || mimeType.contains('mpeg')) {
        return verified ? 'MP3音频' : 'MP3文件';
      } else if (mimeType.contains('wav')) {
        return verified ? 'WAV音频' : 'WAV文件';
      } else if (mimeType.contains('flac')) {
        return verified ? 'FLAC音频' : 'FLAC文件';
      } else if (mimeType.contains('aac')) {
        return verified ? 'AAC音频' : 'AAC文件';
      } else if (mimeType.contains('ogg')) {
        return verified ? 'OGG音频' : 'OGG文件';
      } else if (mimeType.contains('m4a')) {
        return verified ? 'M4A音频' : 'M4A文件';
      } else if (mimeType.contains('wma')) {
        return verified ? 'WMA音频' : 'WMA文件';
      } else {
        return verified ? '音频文件' : '音频文件';
      }
    }

    // 文档类型
    if (mimeType.contains('pdf')) {
      return verified ? 'PDF文档' : 'PDF文件';
    } else if (mimeType.contains('word') || ext == 'doc' || ext == 'docx') {
      return 'Word文档'; // 通常不验证文档
    } else if (mimeType.contains('excel') || ext == 'xls' || ext == 'xlsx') {
      return 'Excel表格';
    } else if (mimeType.contains('powerpoint') ||
        ext == 'ppt' ||
        ext == 'pptx') {
      return 'PPT演示';
    } else if (mimeType.contains('text/') || ext == 'txt') {
      return '文本文件';
    }

    // 压缩文件
    if (mimeType.contains('zip') || ext == 'zip') {
      return verified ? 'ZIP压缩包' : 'ZIP文件';
    } else if (mimeType.contains('rar') || ext == 'rar') {
      return verified ? 'RAR压缩包' : 'RAR文件';
    } else if (mimeType.contains('7z') || ext == '7z') {
      return verified ? '7Z压缩包' : '7Z文件';
    } else if (mimeType.contains('tar') || ext == 'tar') {
      return verified ? 'TAR压缩包' : 'TAR文件';
    } else if (mimeType.contains('gzip') || ext == 'gz') {
      return verified ? 'GZ压缩包' : 'GZ文件';
    }

    // APK文件
    if (mimeType.contains('application/vnd.android.package-archive') ||
        ext == 'apk') {
      return verified ? 'Android应用' : 'APK文件';
    }

    // 根据扩展名识别
    if (ext.isNotEmpty && ext != file.name) {
      return '${ext.toUpperCase()}文件';
    }

    return '文件';
  }

  /// 分类为空视图
  Widget _buildEmptyCategoryView() {
    String message;
    switch (_currentCategory) {
      case 'images':
        message = '此分类中没有图片文件';
        break;
      case 'videos':
        message = '此分类中没有视频文件';
        break;
      case 'others':
        message = '此分类中没有其他文件';
        break;
      default:
        message = '此分类为空';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.filter_list_off,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  /// 预览文件（图片/视频）
  void _previewFile(TrashFileItem file) {
    final mimeType = file.mimeType.toLowerCase();

    if (mimeType.startsWith('image/')) {
      // 图片预览
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: Image.file(
                    File(file.path),
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error,
                                color: Colors.white, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              '无法加载图片\n${error.toString()}',
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        file.name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        FileSizeFormatter.formatBytes(file.size),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (mimeType.startsWith('video/')) {
      // 视频文件：使用内置播放器打开
      _openVideoInPlayer(file);
    }
  }

  /// 使用内置视频播放器打开视频
  void _openVideoInPlayer(TrashFileItem file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              // 文件信息按钮
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('视频信息'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('文件名: ${file.name}'),
                          const SizedBox(height: 8),
                          Text(
                              '大小: ${FileSizeFormatter.formatBytes(file.size)}'),
                          const SizedBox(height: 8),
                          Text('类型: ${file.mimeType}'),
                          const SizedBox(height: 8),
                          Text('路径: ${file.path}'),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          body: VideoPlayerWidget(
            videoPath: file.path,
            videoId: file.path, // 使用路径作为ID，记忆播放位置
            autoPlay: true,
            looping: false,
            onError: (error) {
              logger.e('视频播放错误: $error');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('播放错误: $error'),
                  backgroundColor: Colors.red,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 分类筛选器
  Widget _buildCategoryFilter() {
    final stats = _categoryStats;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildCategoryChip(
              label: '全部',
              category: 'all',
              count: stats['all']!,
              icon: Icons.all_inclusive,
            ),
            if (stats['images']! > 0) ...[
              const SizedBox(width: 8),
              _buildCategoryChip(
                label: '图片',
                category: 'images',
                count: stats['images']!,
                icon: Icons.image,
                color: Colors.blue[400],
              ),
            ],
            if (stats['videos']! > 0) ...[
              const SizedBox(width: 8),
              _buildCategoryChip(
                label: '视频',
                category: 'videos',
                count: stats['videos']!,
                icon: Icons.videocam,
                color: Colors.purple[400],
              ),
            ],
            if (stats['audios']! > 0) ...[
              const SizedBox(width: 8),
              _buildCategoryChip(
                label: '音频',
                category: 'audios',
                count: stats['audios']!,
                icon: Icons.audiotrack,
                color: Colors.green[400],
              ),
            ],
            if (stats['documents']! > 0) ...[
              const SizedBox(width: 8),
              _buildCategoryChip(
                label: '文档',
                category: 'documents',
                count: stats['documents']!,
                icon: Icons.description,
                color: Colors.red[400],
              ),
            ],
            if (stats['archives']! > 0) ...[
              const SizedBox(width: 8),
              _buildCategoryChip(
                label: '压缩包',
                category: 'archives',
                count: stats['archives']!,
                icon: Icons.folder_zip,
                color: Colors.amber[700],
              ),
            ],
            if (stats['others']! > 0) ...[
              const SizedBox(width: 8),
              _buildCategoryChip(
                label: '其他',
                category: 'others',
                count: stats['others']!,
                icon: Icons.insert_drive_file,
                color: Colors.grey[400],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 分类筛选chip
  Widget _buildCategoryChip({
    required String label,
    required String category,
    required int count,
    required IconData icon,
    Color? color,
  }) {
    final isSelected = _currentCategory == category;
    final chipColor = color ?? Theme.of(context).colorScheme.primary;

    return FilterChip(
      selected: isSelected,
      label: Text('$label ($count)'),
      onSelected: (selected) {
        setState(() {
          _currentCategory = category;
          _selectedPaths.clear(); // 切换分类时清空选择
        });
      },
      selectedColor: chipColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
      ),
      showCheckmark: false,
    );
  }
}

/// 文件类型检测器页面
class _FileTypeDetectorPage extends StatefulWidget {
  final TrashFileService service;

  const _FileTypeDetectorPage({required this.service});

  @override
  State<_FileTypeDetectorPage> createState() => _FileTypeDetectorPageState();
}

class _FileTypeDetectorPageState extends State<_FileTypeDetectorPage> {
  final _pathController = TextEditingController(
    text: '/storage/emulated/0/.RecycleBinHW/f20040d3a88f40d16eb35276395c19c2',
  );
  bool _isDetecting = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _detectFile() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入文件路径')),
      );
      return;
    }

    setState(() {
      _isDetecting = true;
      _result = null;
    });

    try {
      final result = await widget.service.detectFileType(path);
      if (mounted) {
        setState(() {
          _result = result;
          _isDetecting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDetecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检测失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件类型检测器'),
      ),
      body: Column(
        children: [
          // 输入区域
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '文件路径',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pathController,
                  decoration: InputDecoration(
                    hintText: '输入文件绝对路径',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.insert_drive_file),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _pathController.clear(),
                    ),
                  ),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  maxLines: 3,
                  minLines: 1,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _isDetecting ? null : _detectFile,
                  icon: _isDetecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(_isDetecting ? '检测中...' : '开始检测'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),

          // 结果区域
          Expanded(
            child: _buildResultArea(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultArea() {
    if (_result == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '输入文件路径后点击"开始检测"',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_result!['error'] != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                '错误: ${_result!['error']}',
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 文件类型卡片
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    _getFileIcon(_result!['mimeType']),
                    size: 64,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _result!['description'] ?? '未知类型',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _result!['mimeType'] ?? 'unknown',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 文件信息
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '文件信息',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('路径', _result!['path'], isPath: true),
                  const Divider(),
                  _buildInfoRow('大小', _result!['sizeFormatted']),
                  const Divider(),
                  _buildInfoRow('修改时间', _result!['modified']),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 文件头信息
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '文件头 (十六进制)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _result!['hexHeader'] ?? '',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value, {bool isPath = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value ?? 'N/A',
            style: TextStyle(
              fontSize: 14,
              fontFamily: isPath ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String? mimeType) {
    if (mimeType == null) return Icons.help_outline;

    if (mimeType.startsWith('image/')) {
      return Icons.image;
    } else if (mimeType.startsWith('video/')) {
      return Icons.videocam;
    } else if (mimeType.startsWith('audio/')) {
      return Icons.audiotrack;
    } else if (mimeType.contains('pdf')) {
      return Icons.picture_as_pdf;
    } else if (mimeType.contains('zip') || mimeType.contains('rar')) {
      return Icons.folder_zip;
    } else if (mimeType.contains('text')) {
      return Icons.description;
    } else if (mimeType.contains('android.package')) {
      return Icons.android;
    } else {
      return Icons.insert_drive_file;
    }
  }
}

/// 分类筛选器的 SliverPersistentHeaderDelegate
class _CategoryFilterDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _CategoryFilterDelegate({required this.child});

  @override
  double get minExtent => 56.0;

  @override
  double get maxExtent => 56.0;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_CategoryFilterDelegate oldDelegate) {
    return true; // 允许重建以更新Tab数字
  }
}
