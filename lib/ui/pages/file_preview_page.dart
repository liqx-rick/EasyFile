import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:charset_converter/charset_converter.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/utils/media_info_extractor.dart';
import 'package:easyfile/ui/widgets/video_player_widget.dart';
import 'package:easyfile/ui/widgets/audio_player_widget.dart';
import 'package:easyfile/ui/widgets/detailed_media_info_view.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:open_file/open_file.dart';
import 'package:pdfx/pdfx.dart';

class FilePreviewPage extends StatefulWidget {
  final FileItem file;
  final List<FileItem>? fileList; // 可选：用于滑动切换
  final int? initialIndex; // 可选：初始索引

  const FilePreviewPage({
    super.key,
    required this.file,
    this.fileList,
    this.initialIndex,
  });

  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  // 滑动切换相关状态
  late PageController _pageController;
  late int _currentIndex;
  bool _showPageIndicator = true; // 是否显示页码指示器
  double _pageIndicatorOpacity = 1.0; // 页码指示器透明度
  
  // 沉浸式UI控制
  bool _showUI = true; // 是否显示AppBar和其他UI组件
  Timer? _uiHideTimer; // UI自动隐藏计时器

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? 0;
    _pageController = PageController(initialPage: _currentIndex);
    
    // 启用沉浸式全屏模式
    _enableImmersiveMode();
    
    // 计划UI自动隐藏（3秒后）
    _scheduleUIHide();

    // 如果有多个文件，3秒后淡出页码指示器
    if (widget.fileList != null && widget.fileList!.length > 1) {
      _scheduleIndicatorFadeOut();
    }
  }

  /// 计划页码指示器淡出动画
  /// 3秒后开始淡出，300毫秒完成动画后隐藏组件
  void _scheduleIndicatorFadeOut() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _pageIndicatorOpacity = 0.0;
        });
        // 完全隐藏（为了性能）
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              _showPageIndicator = false;
            });
          }
        });
      }
    });
  }
  
  /// 启用沉浸式全屏模式
  void _enableImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersive,
      overlays: [],
    );
  }
  
  /// 禁用沉浸式模式，恢复系统UI
  void _disableImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  }
  
  /// 切换UI显示/隐藏
  void _toggleUIVisibility() {
    // 取消之前的计时器
    _uiHideTimer?.cancel();
    
    setState(() {
      _showUI = !_showUI;
    });
    
    // 显示UI时启动3秒自动隐藏计时器
    if (_showUI) {
      _scheduleUIHide();
    }
  }
  
  /// 计划UI自动隐藏
  void _scheduleUIHide() {
    _uiHideTimer?.cancel();
    _uiHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showUI = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _uiHideTimer?.cancel();
    _pageController.dispose();
    _disableImmersiveMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有文件列表或只有一个文件，使用单文件预览模式
    if (widget.fileList == null || widget.fileList!.length <= 1) {
      return _buildSingleFilePreview(context, widget.file);
    }

    // 多文件模式：使用 PageView 支持滑动切换
    return _buildPageViewPreview(context);
  }

  /// 构建支持滑动切换的预览页面
  Widget _buildPageViewPreview(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // 获取当前文件类型
    final currentFile = widget.fileList![_currentIndex];
    final isMediaFile = FileUtils.isImageFile(currentFile.name) ||
                        FileUtils.isVideoFile(currentFile.name) ||
                        FileUtils.isPdfFile(currentFile.name);
    
    return Scaffold(
      backgroundColor: isMediaFile 
          ? Colors.black // 图片/视频/PDF固定黑色
          : (isDark ? Colors.black : theme.colorScheme.surface), // 其他文档跟随主题
      extendBodyBehindAppBar: true, // 内容延伸到AppBar下方
      appBar: _showUI ? _buildFloatingAppBar(context) : null,
      body: Stack(
        children: [
          // PageView 支持滑动切换
          PageView.builder(
            controller: _pageController,
            physics: const BouncingScrollPhysics(), // iOS 风格边缘回弹效果
            itemCount: widget.fileList!.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
                _showPageIndicator = true;
                _pageIndicatorOpacity = 1.0;
              });

              // 重新计划淡出
              _scheduleIndicatorFadeOut();
            },
            itemBuilder: (context, index) {
              return _FilePreviewItem(
                file: widget.fileList![index],
                key: ValueKey(widget.fileList![index].path),
                onTap: _toggleUIVisibility, // 传递点击回调
              );
            },
          ),

          // 页码指示器 - 改进的视觉效果
          if (_showUI && _showPageIndicator && widget.fileList!.length > 1)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _pageIndicatorOpacity,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          FileUtils.isImageFile(
                                  widget.fileList![_currentIndex].name)
                              ? Icons.image
                              : Icons.videocam,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_currentIndex + 1} / ${widget.fileList!.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建单文件预览页面（保持原有逻辑）
  Widget _buildSingleFilePreview(BuildContext context, FileItem file) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // 判断是否为媒体文件（图片/视频/PDF）
    final isMediaFile = FileUtils.isImageFile(file.name) ||
                        FileUtils.isVideoFile(file.name) ||
                        FileUtils.isPdfFile(file.name);
    
    return Scaffold(
      backgroundColor: isMediaFile 
          ? Colors.black // 图片/视频/PDF固定黑色
          : (isDark ? Colors.black : theme.colorScheme.surface), // 其他文档跟随主题
      extendBodyBehindAppBar: true, // 内容延伸到AppBar下方
      appBar: _showUI ? _buildFloatingAppBar(context) : null,
      body: _FilePreviewItem(
        file: file,
        onTap: _toggleUIVisibility, // 传递点击回调
      ),
    );
  }
  
  /// 构建浮动半透明AppBar
  PreferredSizeWidget _buildFloatingAppBar(BuildContext context) {
    final currentFile = widget.fileList != null && widget.fileList!.isNotEmpty
        ? widget.fileList![_currentIndex]
        : widget.file;
    
    return AppBar(
      backgroundColor: Colors.black.withValues(alpha: 0.6), // 半透明黑色背景（60%不透明度）
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            currentFile.name,
            style: const TextStyle(fontSize: 16, color: Colors.white),
          ),
          Text(
            _getFileTypeDisplayForFile(currentFile),
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: () => _showFileInfoForFile(context, currentFile),
          tooltip: '文件信息',
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  /// 获取指定文件的类型显示
  String _getFileTypeDisplayForFile(FileItem file) {
    if (FileUtils.isImageFile(file.name)) return '图片';
    if (FileUtils.isVideoFile(file.name)) return '视频';
    if (FileUtils.isAudioFile(file.name)) return '音频';
    if (FileUtils.isPdfFile(file.name)) return 'PDF文档';
    if (FileUtils.isDocumentFile(file.name)) return '文档';
    if (FileUtils.isTextFile(file.name)) return '文本';
    return '未知类型';
  }

  /// 显示指定文件的信息
  void _showFileInfoForFile(BuildContext context, FileItem file) async {
    // 对于音视频文件，显示详细信息
    if (FileUtils.isVideoFile(file.name) || FileUtils.isAudioFile(file.name)) {
      _showDetailedMediaInfoForFile(context, file);
      return;
    }

    // 普通文件显示基本信息
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('文件信息'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInfoRow('文件名', file.name),
            _buildInfoRow('路径', file.path),
            _buildInfoRow(
                '大小', FileSizeFormatter.formatBytesWithSpace(file.size)),
            _buildInfoRow('修改时间', _formatDateTime(file.modified)),
            _buildInfoRow('类型', _getFileTypeDisplayForFile(file)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 显示指定文件的详细媒体信息
  void _showDetailedMediaInfoForFile(
      BuildContext context, FileItem file) async {
    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在加载详细信息...'),
              ],
            ),
          ),
        ),
      ),
    );

    final navigator = Navigator.of(context);

    try {
      final extractor = MediaInfoExtractor();
      final info = FileUtils.isVideoFile(file.name)
          ? await extractor.extractVideoInfo(file.path)
          : await extractor.extractAudioInfo(file.path);

      if (!mounted) return;
      navigator.pop(); // 关闭加载对话框

      // 显示详细信息
      showDialog(
        context: this.context,
        builder: (context) => Dialog(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
            child: Column(
              children: [
                AppBar(
                  title: const Text('详细信息'),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                Expanded(
                  child: DetailedMediaInfoView(
                    info: info,
                    isVideo: FileUtils.isVideoFile(file.name),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      navigator.pop(); // 关闭加载对话框
      
      // 保存context到局部变量避免异步警告
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载详细信息失败: $e')),
        );
      }
    }
  }
}

/// 单个文件预览项组件（用于 PageView）
class _FilePreviewItem extends StatefulWidget {
  final FileItem file;
  final VoidCallback? onTap; // 点击回调，用于切换UI

  const _FilePreviewItem({super.key, required this.file, this.onTap});

  @override
  State<_FilePreviewItem> createState() => __FilePreviewItemState();
}

class __FilePreviewItemState extends State<_FilePreviewItem>
    with AutomaticKeepAliveClientMixin {
  String? _fileContent;
  bool _isLoading = true;
  String? _error;
  PdfController? _pdfController;

  @override
  // 只为图片和文本文件保持状态，视频不保持（避免内存问题）
  bool get wantKeepAlive =>
      FileUtils.isImageFile(widget.file.name) ||
      FileUtils.isTextFile(widget.file.name) ||
      FileUtils.isPdfFile(widget.file.name);

  @override
  void initState() {
    super.initState();
    _loadFileContent();
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _loadFileContent() async {
    try {
      logger.d('Loading file content for: ${widget.file.path}');

      // 图片、视频、音频不需要预加载
      if (FileUtils.isImageFile(widget.file.name) ||
          FileUtils.isVideoFile(widget.file.name) ||
          FileUtils.isAudioFile(widget.file.name)) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // PDF 文件
      if (FileUtils.isPdfFile(widget.file.name)) {
        await _loadPdfDocument();
        return;
      }

      // 文档文件
      if (FileUtils.isDocumentFile(widget.file.name)) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 文本文件 - 支持多种编码格式
      if (FileUtils.isTextFile(widget.file.name)) {
        final file = File(widget.file.path);
        final bytes = await file.readAsBytes();
        String? content;
        bool decoded = false;
        
        // 检测BOM（字节顺序标记）并使用相应编码
        if (bytes.length >= 2) {
          // UTF-16 LE BOM: FF FE (Windows记事本常用)
          if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
            try {
              content = String.fromCharCodes(
                Uint16List.view(Uint8List.fromList(bytes.sublist(2)).buffer)
              );
              decoded = true;
            } catch (e) {
              logger.w('UTF-16 LE decode failed: $e');
            }
          }
          // UTF-16 BE BOM: FE FF
          else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
            try {
              final data = bytes.sublist(2);
              final swapped = <int>[];
              for (int i = 0; i < data.length - 1; i += 2) {
                swapped.add(data[i + 1]);
                swapped.add(data[i]);
              }
              content = String.fromCharCodes(
                Uint16List.view(Uint8List.fromList(swapped).buffer)
              );
              decoded = true;
            } catch (e) {
              logger.w('UTF-16 BE decode failed: $e');
            }
          }
          // UTF-8 BOM: EF BB BF
          else if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
            try {
              content = utf8.decode(bytes.sublist(3));
              decoded = true;
            } catch (e) {
              logger.w('UTF-8 with BOM decode failed: $e');
            }
          }
        }
        
        // UTF-8 (无BOM)
        if (!decoded) {
          try {
            content = utf8.decode(bytes, allowMalformed: false);
            decoded = true;
          } on FormatException catch (_) {
            // UTF-8失败，继续尝试其他编码
          }
        }
        
        // GBK (简体中文Windows常用编码)
        if (!decoded) {
          try {
            content = await CharsetConverter.decode("GBK", bytes);
            if (content.isNotEmpty) {
              decoded = true;
            }
          } catch (e) {
            logger.w('GBK decode failed: $e');
          }
        }
        
        // GB2312 (旧版中文编码)
        if (!decoded) {
          try {
            content = await CharsetConverter.decode("GB2312", bytes);
            if (content.isNotEmpty) {
              decoded = true;
            }
          } catch (e) {
            logger.w('GB2312 decode failed: $e');
          }
        }
        
        // UTF-8 宽松模式
        if (!decoded) {
          try {
            content = utf8.decode(bytes, allowMalformed: true);
            decoded = true;
          } catch (e) {
            logger.w('UTF-8 malformed decode failed: $e');
          }
        }
        
        // Latin1 兜底
        if (!decoded || content == null || content.isEmpty) {
          content = latin1.decode(bytes);
        }
        
        setState(() {
          _fileContent = content;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = '不支持预览此文件类型';
          _isLoading = false;
        });
      }
    } catch (e) {
      logger.e('Error loading file content: $e');
      setState(() {
        _error = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPdfDocument() async {
    try {
      final pdfDoc = await PdfDocument.openFile(widget.file.path);
      _pdfController = PdfController(document: Future.value(pdfDoc));
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      logger.e('Error loading PDF: $e');
      setState(() {
        _error = 'PDF加载失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用，因为使用了 AutomaticKeepAliveClientMixin

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return Container(
        color: isDark ? Colors.black : theme.colorScheme.surface,
        child: Center(
          child: CircularProgressIndicator(
            color: isDark ? Colors.white : theme.colorScheme.primary,
          ),
        ),
      );
    }

    if (_error != null) {
      return GestureDetector(
        onTapUp: (details) {
          widget.onTap?.call();
        },
        child: Container(
          color: isDark ? Colors.black : theme.colorScheme.surface,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(
                    color: isDark ? Colors.white : theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _error = null;
                    });
                    _loadFileContent();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 根据文件类型显示不同预览
    if (FileUtils.isImageFile(widget.file.name)) {
      return _buildImagePreview();
    } else if (FileUtils.isVideoFile(widget.file.name)) {
      return _buildVideoPreview();
    } else if (FileUtils.isAudioFile(widget.file.name)) {
      return _buildAudioPreview();
    } else if (FileUtils.isPdfFile(widget.file.name)) {
      return _buildPdfViewer();
    } else if (FileUtils.isDocumentFile(widget.file.name)) {
      return _buildDocumentInfo();
    } else {
      return _buildTextPreview();
    }
  }

  Widget _buildImagePreview() {
    return GestureDetector(
      onTap: widget.onTap, // 点击切换UI
      child: Container(
        color: Colors.black, // 图片预览固定黑色背景
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Image.file(
              File(widget.file.path),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.broken_image, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        '图片加载失败',
                        style: TextStyle(color: Colors.white),
                      ),
                      Text(
                        '$error',
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPreview() {
    return GestureDetector(
      onTap: widget.onTap, // 点击切换UI
      child: Container(
        color: Colors.black, // 视频预览固定黑色背景
        child: Center(
          child: VideoPlayerWidget(videoPath: widget.file.path),
        ),
      ),
    );
  }

  Widget _buildAudioPreview() {
    return GestureDetector(
      onTap: widget.onTap, // 点击切换UI
      child: Container(
        color: Colors.purple.shade900, // 音频播放器紫色背景
        child: Center(
          child: AudioPlayerWidget(
            audioPath: widget.file.path,
            fileName: widget.file.name,
          ),
        ),
      ),
    );
  }

  Widget _buildPdfViewer() {
    if (_pdfController == null) {
      return Container(
        color: Colors.black, // PDF预览固定黑色背景
        child: const Center(
          child: Text(
            'PDF加载失败',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap, // 点击切换UI
      child: Container(
        color: Colors.black, // PDF预览固定黑色背景
        child: PdfView(controller: _pdfController!),
      ),
    );
  }

  Widget _buildDocumentInfo() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: widget.onTap, // 点击切换UI
      child: Container(
        color: isDark ? Colors.black : theme.colorScheme.surface,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 文档大图标
                DocumentIconWidget(fileName: widget.file.name, size: 120),
                const SizedBox(height: 32),
                
                // 文件名
                Text(
                  widget.file.name,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                
                // 文件信息卡片
                Card(
                  color: isDark 
                      ? Colors.white.withValues(alpha: 0.1)
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildDocInfoRow('类型', _getFileExtension()),
                        const SizedBox(height: 8),
                        _buildDocInfoRow(
                          '大小',
                          FileSizeFormatter.formatBytesWithSpace(widget.file.size),
                        ),
                        const SizedBox(height: 8),
                        _buildDocInfoRow(
                          '修改时间',
                          _formatFileDateTime(widget.file.modified),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                
                // 操作按钮
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await OpenFile.open(widget.file.path);
                    if (result.type != ResultType.done) {
                      logger.w('Failed to open file: ${result.message}');
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('使用外部应用打开'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// 构建文档信息行
  Widget _buildDocInfoRow(String label, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.white70 : theme.colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : theme.colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
  
  /// 获取文件扩展名
  String _getFileExtension() {
    final name = widget.file.name;
    final lastDot = name.lastIndexOf('.');
    if (lastDot != -1 && lastDot < name.length - 1) {
      return name.substring(lastDot + 1).toUpperCase();
    }
    return '未知';
  }
  
  /// 格式化文件日期时间
  String _formatFileDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTextPreview() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return GestureDetector(
      onTapUp: (details) {
        widget.onTap?.call();
      },
      child: Container(
        color: isDark 
            ? const Color(0xFF1E1E1E) // 深色模式：VS Code深色主题色
            : theme.colorScheme.surface, // 浅色模式：系统surface颜色
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              _fileContent ?? '',
              style: TextStyle(
                // 移除 fontFamily 以使用系统默认字体，更好地支持中文
                color: isDark 
                    ? const Color(0xFFD4D4D4) // 深色模式：VS Code文字颜色
                    : theme.colorScheme.onSurface, // 浅色模式：系统文字颜色
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
