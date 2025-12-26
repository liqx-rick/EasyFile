import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/platform/mediastore_scanner_channel.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/category_info.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';

/// MediaStore vs 文件系统扫描对比测试页面
class MediaStoreScanTestPage extends StatefulWidget {
  final CategoryType categoryType;
  
  const MediaStoreScanTestPage({
    super.key,
    this.categoryType = CategoryType.documents,
  });

  @override
  State<MediaStoreScanTestPage> createState() => _MediaStoreScanTestPageState();
}

class _MediaStoreScanTestPageState extends State<MediaStoreScanTestPage> {
  bool _isScanning = false;
  
  // MediaStore 扫描结果
  List<FileItem>? _mediaStoreResults;
  int? _mediaStoreDuration;
  
  // 文件系统扫描结果
  List<FileItem>? _fileSystemResults;
  int? _fileSystemDuration;
  
  late final FilePresenter _presenter;

  @override
  void initState() {
    super.initState();
    _presenter = locator<FilePresenter>();
  }

  /// 执行 MediaStore 扫描
  Future<void> _scanWithMediaStore() async {
    logger.i('开始 MediaStore 扫描测试 - 类型: ${widget.categoryType}');
    
    final startTime = DateTime.now();
    
    try {
      // 将 CategoryType 转换为 MediaScanType
      final scanType = _categoryTypeToMediaScanType(widget.categoryType);
      
      // 使用统一的扫描方法
      final results = await MediaStoreScannerChannel.scan(scanType);
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      setState(() {
        _mediaStoreResults = results;
        _mediaStoreDuration = duration.inMilliseconds;
      });
      
      final categoryName = _getCategoryName();
      logger.i('MediaStore 扫描完成: ${results.length} 个$categoryName, 耗时: ${duration.inMilliseconds}ms');
    } catch (e) {
      logger.e('MediaStore 扫描失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('MediaStore 扫描失败: $e')),
        );
      }
    }
  }

  /// 执行文件系统扫描
  Future<void> _scanWithFileSystem() async {
    logger.i('开始文件系统扫描测试 - 类型: ${widget.categoryType}');
    
    final startTime = DateTime.now();
    
    try {
      // 强制使用文件系统扫描（不使用 MediaStore）
      final results = await _presenter.scanFilesByCategory(
        widget.categoryType,
        useMediaStore: false,
      );
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      setState(() {
        _fileSystemResults = results;
        _fileSystemDuration = duration.inMilliseconds;
      });
      
      final categoryName = _getCategoryName();
      logger.i('文件系统扫描完成: ${results.length} 个$categoryName, 耗时: ${duration.inMilliseconds}ms');
    } catch (e) {
      logger.e('文件系统扫描失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件系统扫描失败: $e')),
        );
      }
    }
  }

  /// 获取分类名称
  String _getCategoryName() {
    switch (widget.categoryType) {
      case CategoryType.images:
        return '图片';
      case CategoryType.documents:
        return '文档';
      case CategoryType.music:
        return '音频';
      case CategoryType.video:
        return '视频';
      case CategoryType.downloads:
        return '下载';
      case CategoryType.apk:
        return 'APK';
      case CategoryType.archive:
        return '压缩包';
    }
  }

  /// 将 CategoryType 转换为 MediaScanType
  MediaScanType _categoryTypeToMediaScanType(CategoryType type) {
    switch (type) {
      case CategoryType.images:
        return MediaScanType.image;
      case CategoryType.documents:
        return MediaScanType.document;
      case CategoryType.music:
        return MediaScanType.audio;
      case CategoryType.video:
        return MediaScanType.video;
      case CategoryType.apk:
        return MediaScanType.apk;
      case CategoryType.archive:
        return MediaScanType.archive;
      case CategoryType.downloads:
        // downloads 没有对应的 MediaScanType，默认返回 document
        return MediaScanType.document;
    }
  }

  /// 执行对比测试
  Future<void> _runComparisonTest() async {
    if (_isScanning) return;
    
    setState(() {
      _isScanning = true;
      _mediaStoreResults = null;
      _mediaStoreDuration = null;
      _fileSystemResults = null;
      _fileSystemDuration = null;
    });

    // 先执行 MediaStore 扫描
    await _scanWithMediaStore();
    
    // 等待1秒，避免影响性能测试
    await Future.delayed(const Duration(seconds: 1));
    
    // 再执行文件系统扫描
    await _scanWithFileSystem();
    
    setState(() {
      _isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final categoryName = _getCategoryName();
    
    return Scaffold(
      appBar: AppBar(
        title: Text('扫描方式对比测试 - $categoryName'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 测试按钮
            ElevatedButton.icon(
              onPressed: _isScanning ? null : _runComparisonTest,
              icon: _isScanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isScanning ? '扫描中...' : '开始对比测试'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 结果对比
            Expanded(
              child: Row(
                children: [
                  // MediaStore 结果
                  Expanded(
                    child: _buildResultCard(
                      title: 'MediaStore',
                      icon: Icons.storage,
                      color: Colors.blue,
                      results: _mediaStoreResults,
                      duration: _mediaStoreDuration,
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // 文件系统结果
                  Expanded(
                    child: _buildResultCard(
                      title: '文件系统',
                      icon: Icons.folder,
                      color: Colors.orange,
                      results: _fileSystemResults,
                      duration: _fileSystemDuration,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 对比分析
            if (_mediaStoreResults != null && _fileSystemResults != null)
              _buildComparisonAnalysis(),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<FileItem>? results,
    required int? duration,
  }) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            
            const Divider(height: 24),
            
            // 结果数据
            if (results == null && duration == null)
              const Expanded(
                child: Center(
                  child: Text('等待扫描...', style: TextStyle(color: Colors.grey)),
                ),
              )
            else if (results != null) ...[
              _buildStatRow('文件数量', '${results.length} 个'),
              const SizedBox(height: 8),
              _buildStatRow(
                '总大小',
                FileSizeFormatter.formatBytes(
                  results.fold<int>(0, (sum, file) => sum + file.size),
                ),
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                '扫描耗时',
                duration != null 
                    ? '${(duration / 1000).toStringAsFixed(2)}s'
                    : '-',
                highlight: true,
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                '平均速度',
                duration != null && duration > 0
                    ? '${(results.length / (duration / 1000)).toStringAsFixed(0)} 个/秒'
                    : '-',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              color: highlight ? Colors.green : Colors.black87,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonAnalysis() {
    final mediaStoreCount = _mediaStoreResults!.length;
    final fileSystemCount = _fileSystemResults!.length;
    final mediaStoreDuration = _mediaStoreDuration!;
    final fileSystemDuration = _fileSystemDuration!;
    final categoryName = _getCategoryName();
    
    final countDiff = mediaStoreCount - fileSystemCount;
    final speedImprovement = fileSystemDuration / mediaStoreDuration;
    
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  '对比分析',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Text(
              '📊 数量差异: ${countDiff >= 0 ? '+' : ''}$countDiff 个$categoryName',
              style: TextStyle(
                fontSize: 14,
                color: countDiff == 0 ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            
            Text(
              '⚡ 性能提升: ${speedImprovement.toStringAsFixed(1)}x',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            
            Text(
              '⏱️ 时间节省: ${((fileSystemDuration - mediaStoreDuration) / 1000).toStringAsFixed(2)}s',
              style: const TextStyle(fontSize: 14),
            ),
            
            if (countDiff != 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      countDiff > 0
                          ? '⚠️ MediaStore 找到了 $countDiff 个文件系统扫描未找到的$categoryName'
                          : '⚠️ 文件系统扫描找到了 ${-countDiff} 个 MediaStore 未索引的$categoryName',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => _showDifferenceFiles(),
                icon: const Icon(Icons.compare_arrows),
                label: const Text('查看差异文件'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 显示差异文件列表
  void _showDifferenceFiles() {
    if (_mediaStoreResults == null || _fileSystemResults == null) return;

    // 创建路径集合
    final mediaStorePaths = _mediaStoreResults!.map((f) => f.path).toSet();
    final fileSystemPaths = _fileSystemResults!.map((f) => f.path).toSet();

    // 找出只在文件系统中存在的文件
    final onlyInFileSystem = _fileSystemResults!
        .where((f) => !mediaStorePaths.contains(f.path))
        .toList();

    // 找出只在 MediaStore 中存在的文件
    final onlyInMediaStore = _mediaStoreResults!
        .where((f) => !fileSystemPaths.contains(f.path))
        .toList();

    showDialog(
      context: context,
      builder: (context) => _DifferenceFilesDialog(
        onlyInFileSystem: onlyInFileSystem,
        onlyInMediaStore: onlyInMediaStore,
      ),
    );
  }
}

/// 差异文件对话框
class _DifferenceFilesDialog extends StatelessWidget {
  final List<FileItem> onlyInFileSystem;
  final List<FileItem> onlyInMediaStore;

  const _DifferenceFilesDialog({
    required this.onlyInFileSystem,
    required this.onlyInMediaStore,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '差异文件分析',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 统计信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📊 仅在文件系统中: ${onlyInFileSystem.length} 个',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '📊 仅在 MediaStore 中: ${onlyInMediaStore.length} 个',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // 文件列表
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: '仅文件系统'),
                        Tab(text: '仅MediaStore'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildFileList(onlyInFileSystem, '文件系统'),
                          _buildFileList(onlyInMediaStore, 'MediaStore'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList(List<FileItem> files, String source) {
    if (files.isEmpty) {
      return Center(
        child: Text('没有独有文件'),
      );
    }

    // 分析文件路径模式
    final patterns = _analyzePathPatterns(files);

    return Column(
      children: [
        // 路径模式分析
        Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🔍 路径模式分析',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...patterns.entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${entry.key}: ${entry.value} 个',
                  style: const TextStyle(fontSize: 12),
                ),
              )),
            ],
          ),
        ),
        
        // 文件列表
        Expanded(
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final reason = _analyzeWhyNotIndexed(file, source);
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: InkWell(
                  onTap: () => _previewFile(context, file, files),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        // 文件信息
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                file.path,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${FileSizeFormatter.formatBytes(file.size)} | ${_formatDate(file.modified)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (reason.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    reason,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        
                        const SizedBox(width: 8),
                        
                        // 预览图标
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.visibility,
                            size: 20,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 分析路径模式
  Map<String, int> _analyzePathPatterns(List<FileItem> files) {
    final patterns = <String, int>{};
    
    for (final file in files) {
      final path = file.path.toLowerCase();
      
      if (path.contains('/.')) {
        patterns['隐藏目录 (/.xxx)'] = (patterns['隐藏目录 (/.xxx)'] ?? 0) + 1;
      } else if (path.contains('/android/data/')) {
        patterns['应用数据 (/Android/data/)'] = 
            (patterns['应用数据 (/Android/data/)'] ?? 0) + 1;
      } else if (path.contains('/cache/') || path.contains('/temp/')) {
        patterns['缓存/临时目录'] = (patterns['缓存/临时目录'] ?? 0) + 1;
      } else if (path.contains('/download/')) {
        patterns['下载目录'] = (patterns['下载目录'] ?? 0) + 1;
      } else if (path.contains('/dcim/') || path.contains('/pictures/')) {
        patterns['相册目录'] = (patterns['相册目录'] ?? 0) + 1;
      } else {
        patterns['其他位置'] = (patterns['其他位置'] ?? 0) + 1;
      }
    }
    
    return patterns;
  }

  /// 分析为什么没有被索引
  String _analyzeWhyNotIndexed(FileItem file, String source) {
    final path = file.path.toLowerCase();
    final name = file.name.toLowerCase();
    
    if (source == '文件系统') {
      // 分析为什么 MediaStore 没有索引
      if (path.contains('/.')) {
        return '原因: 隐藏目录';
      } else if (name.startsWith('.')) {
        return '原因: 隐藏文件';
      } else if (path.contains('/.nomedia')) {
        return '原因: .nomedia 标记';
      } else if (path.contains('/cache/')) {
        return '原因: 缓存目录';
      } else if (path.contains('/temp/')) {
        return '原因: 临时目录';
      } else if (DateTime.now().difference(file.modified).inSeconds < 5) {
        return '原因: 新创建文件，尚未索引';
      } else {
        return '原因: MediaStore 未扫描此路径';
      }
    } else {
      // 分析为什么文件系统扫描没找到
      return '原因: 可能已被删除或路径被排除';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).floor()}年前';
    } else if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()}个月前';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else {
      return '刚刚';
    }
  }

  /// 预览文件
  void _previewFile(BuildContext context, FileItem file, List<FileItem> fileList) {
    if (!context.mounted) return;

    // 检查文件是否存在
    final fileEntity = File(file.path);
    if (!fileEntity.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('文件不存在: ${file.path}'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 打开预览页面
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FilePreviewPage(
          file: file,
          fileList: fileList,
          initialIndex: fileList.indexOf(file),
        ),
      ),
    );
  }
}

