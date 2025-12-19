import 'package:flutter/material.dart';
import 'package:easyfile/data/models/recommendation_card.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/services/unified_app_scanner.dart';
import 'package:easyfile/core/services/app_detection_service.dart';
import 'package:easyfile/core/services/app_scan_result.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/platform/mediastore_scanner_channel.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/ui/widgets/file_list_item_builder.dart';

/// 推荐详情页面
///
/// 显示推荐卡片对应的文件列表
/// - 应用类卡片：使用 UnifiedAppScanner 扫描应用文件
/// - 系统类卡片：使用 MediaStore 扫描特定文件（相机照片/视频、录音）
class RecommendationDetailPage extends StatefulWidget {
  /// 推荐卡片
  final RecommendationCard card;

  const RecommendationDetailPage({
    super.key,
    required this.card,
  });

  @override
  State<RecommendationDetailPage> createState() =>
      _RecommendationDetailPageState();
}

class _RecommendationDetailPageState extends State<RecommendationDetailPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<FileItem> _files = [];
  AppScanResult? _scanResult;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  /// 加载文件列表
  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (widget.card.appKey != null) {
        // 应用类卡片：使用统一扫描器
        await _loadAppFiles();
      } else {
        // 系统类卡片：使用分类扫描
        await _loadSystemFiles();
      }
    } catch (e) {
      logger.e('加载文件失败: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '加载失败: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 加载应用文件（应用类卡片）
  Future<void> _loadAppFiles() async {
    final appKey = widget.card.appKey;
    if (appKey == null) {
      throw Exception('应用类卡片缺少 appKey');
    }

    logger.i('加载应用文件: $appKey');

    // 创建扫描器
    final detectionService = AppDetectionService();
    final scanner = UnifiedAppScanner(detectionService);

    // 执行扫描
    final result = await scanner.scanApp(
      appKey: appKey,
      useMediaStore: true,
      updateCache: true,
    );

    if (mounted) {
      setState(() {
        _scanResult = result;
        _files = result.allFiles;
      });
    }

    logger.i('应用文件加载完成: ${_files.length} 个文件');
  }

  /// 加载系统文件（系统类卡片）
  Future<void> _loadSystemFiles() async {
    logger.i('加载系统文件: ${widget.card.type.name}');

    // 使用 MediaStore 扫描，不再使用文件系统扫描
    List<FileItem> files = [];

    switch (widget.card.type) {
      case RecommendationType.memories:
        // 时光记忆：使用包名快速扫描相机照片（优化版本）
        files = await MediaStoreScannerChannel.scanCameraPackagePhotos();
        break;
      case RecommendationType.videos:
        // 生活剪影：使用包名快速扫描相机视频（优化版本）
        files = await MediaStoreScannerChannel.scanCameraPackageVideos();
        break;
      case RecommendationType.recordings:
        // 声音记录：使用 MediaStore 扫描录音文件
        files = await MediaStoreScannerChannel.scanRecordings();
        break;
      case RecommendationType.largeFiles:
        // 大文件：扫描所有文件并过滤（保持原有逻辑）
        final allImages = await MediaStoreScannerChannel.scanImages();
        final allVideos = await MediaStoreScannerChannel.scanVideos();
        final allAudio = await MediaStoreScannerChannel.scanAudio();
        final allDocs = await MediaStoreScannerChannel.scanDocuments();
        
        files = [...allImages, ...allVideos, ...allAudio, ...allDocs];
        // 过滤大于100MB的文件
        files = files.where((f) => f.size > 100 * 1024 * 1024).toList();
        // 按大小降序排序
        files.sort((a, b) => b.size.compareTo(a.size));
        break;
      default:
        throw Exception('未知的推荐类型: ${widget.card.type}');
    }

    if (mounted) {
      setState(() {
        _files = files;
      });
    }

    logger.i('系统文件加载完成: ${_files.length} 个文件');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.card.title),
        actions: [
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadFiles,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildLoadingView();
    }

    if (_errorMessage != null) {
      return _buildErrorView();
    }

    if (_files.isEmpty) {
      return _buildEmptyView();
    }

    return _buildFileList();
  }

  /// 加载中视图
  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            '正在加载文件...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            widget.card.title,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// 错误视图
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              '加载失败',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? '未知错误',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadFiles,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 空视图
  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.card.icon,
            size: 80,
            color: widget.card.color.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 24),
          Text(
            '没有找到文件',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            widget.card.title,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// 文件列表
  Widget _buildFileList() {
    final totalSize = _files.fold<int>(0, (sum, file) => sum + file.size);

    return Column(
      children: [
        // 统计信息卡片
        _buildStatsCard(totalSize),

        // 文件列表
        Expanded(
          child: ListView.builder(
            itemCount: _files.length,
            itemBuilder: (context, index) {
              final file = _files[index];
              return _buildFileItem(file);
            },
          ),
        ),
      ],
    );
  }

  /// 统计信息卡片
  Widget _buildStatsCard(int totalSize) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 显示应用图标或默认图标
            if (widget.card.appIcon != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  widget.card.appIcon!,
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      widget.card.icon,
                      color: widget.card.color,
                      size: 32,
                    );
                  },
                ),
              )
            else
              Icon(
                widget.card.icon,
                color: widget.card.color,
                size: 32,
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_files.length} 个文件',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '总大小: ${FileSizeFormatter.formatBytes(totalSize)}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  // 显示扫描信息（仅应用类）
                  if (_scanResult != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _buildScanInfo(),
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建扫描信息
  String _buildScanInfo() {
    if (_scanResult == null) return '';

    final parts = <String>[];

    if (_scanResult!.mediaStoreFiles.isNotEmpty) {
      parts.add('系统扫描: ${_scanResult!.mediaStoreFiles.length}');
    }

    if (_scanResult!.pathScanFiles.isNotEmpty) {
      parts.add('路径扫描: ${_scanResult!.pathScanFiles.length}');
    }

    if (_scanResult!.differenceFiles.isNotEmpty) {
      parts.add('差异: ${_scanResult!.differenceFiles.length}');
    }

    return parts.join(' · ');
  }

  /// 文件列表项
  Widget _buildFileItem(FileItem file) {
    final mimeType = FileUtils.getMimeType(file.path);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: FileListItemBuilder.buildFileThumbnail(
        filePath: file.path,
        mimeType: mimeType,
        fileName: file.name,
        size: 48,
      ),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${FileSizeFormatter.formatBytes(file.size)} · ${_formatPath(file.path)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      onTap: () {
        // TODO: 打开文件
        // 可以调用 FilePresenter.openFile(file)
      },
    );
  }

  /// 格式化路径（只显示父目录名）
  String _formatPath(String path) {
    final parts = path.split('/');
    if (parts.length >= 2) {
      return parts[parts.length - 2];
    }
    return path;
  }
}
