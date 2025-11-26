import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:charset_converter/charset_converter.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/ui/widgets/video_player_widget.dart';
import 'package:easyfile/ui/widgets/audio_player_widget.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/ui/services/single_file_operations_service.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:open_file/open_file.dart';
import 'package:pdfx/pdfx.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;

class FilePreviewPage extends StatefulWidget {
  final FileItem file;
  final List<FileItem>? fileList; // 可选：用于滑动切换
  final int? initialIndex; // 可选：初始索引
  final FileViewModel? viewModel; // 可选：如果不提供，功能按钮将被隐藏
  final FilePresenter? presenter; // 可选：如果不提供，功能按钮将被隐藏

  const FilePreviewPage({
    super.key,
    required this.file,
    this.fileList,
    this.initialIndex,
    this.viewModel,
    this.presenter,
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

  // 文件操作服务
  SingleFileOperationsService? _operationsService;

  // 收藏状态（用于实时更新UI）
  late bool _isFavorite;

  // 文件是否被修改（重命名、移动、复制），用于返回时通知父页面刷新
  bool _fileModified = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? 0;
    _pageController = PageController(initialPage: _currentIndex);

    // 初始化收藏状态
    _isFavorite = false;

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

    return PopScope(
      canPop: !_fileModified,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fileModified) {
          Navigator.of(context).pop(true);
        }
      },
      child: Scaffold(
        backgroundColor: isMediaFile
            ? Colors.black // 图片/视频/PDF固定黑色
            : (isDark ? Colors.black : theme.colorScheme.surface), // 其他文档跟随主题
        extendBodyBehindAppBar: true, // 内容延伸到AppBar下方
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
                  onSetUIVisible: (show) {
                    _uiHideTimer?.cancel();
                    setState(() {
                      _showUI = show;
                    });
                    if (show) {
                      _scheduleUIHide();
                    }
                  },
                );
              },
            ),

            // 页码指示器 - 只对图片显示，视频和音频不显示
            if (_showUI &&
                _showPageIndicator &&
                widget.fileList!.length > 1 &&
                FileUtils.isImageFile(widget.fileList![_currentIndex].name))
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
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.image,
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

            // AppBar - 作为Stack中的浮动元素，不影响布局
            if (_showUI)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildFloatingAppBar(context),
              ),

            // 左箭头按钮 - 上一个文件（仅对音频文件显示）
            if (_showUI &&
                widget.fileList!.length > 1 &&
                _currentIndex > 0 &&
                FileUtils.isAudioFile(widget.fileList![_currentIndex].name))
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 12,
                          spreadRadius: 2,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                      iconSize: 32,
                      onPressed: () {
                        if (_currentIndex > 0) {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      tooltip: '上一个',
                    ),
                  ),
                ),
              ),

            // 右箭头按钮 - 下一个文件（仅对音频文件显示）
            if (_showUI &&
                widget.fileList!.length > 1 &&
                _currentIndex < widget.fileList!.length - 1 &&
                FileUtils.isAudioFile(widget.fileList![_currentIndex].name))
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 12,
                          spreadRadius: 2,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon:
                          const Icon(Icons.chevron_right, color: Colors.white),
                      iconSize: 32,
                      onPressed: () {
                        if (_currentIndex < widget.fileList!.length - 1) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      tooltip: '下一个',
                    ),
                  ),
                ),
              ),
          ],
        ),
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

    return PopScope(
      canPop: !_fileModified,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fileModified) {
          Navigator.of(context).pop(true);
        }
      },
      child: Scaffold(
        backgroundColor: isMediaFile
            ? Colors.black // 图片/视频/PDF固定黑色
            : (isDark ? Colors.black : theme.colorScheme.surface), // 其他文档跟随主题
        extendBodyBehindAppBar: true, // 内容延伸到AppBar下方
        appBar: _showUI ? _buildFloatingAppBar(context) : null,
        body: _FilePreviewItem(
          file: file,
          onTap: _toggleUIVisibility, // 传递点击回调
          onSetUIVisible: (show) {
            _uiHideTimer?.cancel();
            setState(() {
              _showUI = show;
            });
            if (show) {
              _scheduleUIHide();
            }
          },
        ),
      ),
    );
  }

  /// 构建浮动半透明AppBar
  PreferredSizeWidget _buildFloatingAppBar(BuildContext context) {
    final currentFile = widget.fileList != null && widget.fileList!.isNotEmpty
        ? widget.fileList![_currentIndex]
        : widget.file;

    // 尝试获取 ViewModel 和 Presenter（优先使用参数，否则尝试从 context 获取）
    FileViewModel? viewModel = widget.viewModel;
    FilePresenter? presenter = widget.presenter;

    // 如果参数未提供，尝试从 context 获取（如果可用）
    if (viewModel == null || presenter == null) {
      try {
        viewModel ??= context.watch<FileViewModel>();
        presenter ??= context.read<FilePresenter>();
      } catch (e) {
        // Provider 不可用，功能按钮将被隐藏
        logger.d(
            'Provider not available in FilePreviewPage, operation buttons will be hidden');
      }
    }

    // 初始化操作服务（仅当 viewModel 和 presenter 都可用时）
    // 每次 build 都重新创建，确保使用最新的有效 context
    if (viewModel != null && presenter != null) {
      _operationsService = SingleFileOperationsService(
        context: context,
        viewModel: viewModel,
        presenter: presenter,
        onRefresh: () {
          if (mounted) {
            setState(() {
              // 刷新收藏状态
              _isFavorite = viewModel!.isFavoriteFile(currentFile.path);
            });
          }
        },
        onFileDeleted: () {
          // 文件被删除，关闭预览页并通知列表刷新
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        },
      );

      // 更新收藏状态
      _isFavorite = viewModel.isFavoriteFile(currentFile.path);
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isMediaFile = FileUtils.isImageFile(currentFile.name) ||
        FileUtils.isVideoFile(currentFile.name) ||
        FileUtils.isPdfFile(currentFile.name);

    // If previewing media (black background) keep icons white for visibility.
    final iconColor =
        (isDark || isMediaFile) ? Colors.white : theme.colorScheme.onSurface;

    return AppBar(
      backgroundColor: Colors.black.withOpacity(0.6), // 半透明黑色背景（60%不透明度）
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            currentFile.name,
            style: const TextStyle(fontSize: 16, color: Colors.white),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            FileSizeFormatter.formatBytesWithSpace(currentFile.size),
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
      iconTheme: IconThemeData(color: iconColor),
      actions: [
        // 打印按钮（只对支持打印的文件显示，且服务可用时）
        if (!currentFile.isDirectory &&
            _operationsService != null &&
            _canPrint(currentFile))
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () => _printFile(currentFile),
            tooltip: '打印',
          ),
        // 分享按钮（只对文件显示，且服务可用时）
        if (!currentFile.isDirectory && _operationsService != null)
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _operationsService?.shareFile(currentFile),
            tooltip: '分享',
          ),
        // 收藏/取消收藏按钮（只对文件显示，且服务可用时）
        if (!currentFile.isDirectory && _operationsService != null)
          IconButton(
            icon: Icon(_isFavorite ? Icons.star : Icons.star_border),
            onPressed: () => _operationsService?.toggleFavorite(currentFile),
            tooltip: _isFavorite ? '取消收藏' : '添加到收藏',
          ),
        // 三点菜单（只在服务可用时显示）
        if (_operationsService != null)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: iconColor),
            tooltip: '更多操作',
            onSelected: (value) async {
              // 等待 PopupMenu 完全关闭后再处理操作
              // 避免与新对话框的显示产生冲突
              await Future.delayed(const Duration(milliseconds: 100));
              _handleMenuAction(value, currentFile);
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'details',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: theme.colorScheme.onSurface),
                      SizedBox(width: 16),
                      Text('文件详情',
                          style: TextStyle(color: theme.colorScheme.onSurface)),
                    ],
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: 'rename',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.edit,
                          size: 20, color: theme.colorScheme.onSurface),
                      SizedBox(width: 16),
                      Text('重命名',
                          style: TextStyle(color: theme.colorScheme.onSurface)),
                    ],
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: 'move',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.drive_file_move,
                          size: 20, color: theme.colorScheme.onSurface),
                      SizedBox(width: 16),
                      Text('移动',
                          style: TextStyle(color: theme.colorScheme.onSurface)),
                    ],
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: 'copy',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.content_copy,
                          size: 20, color: theme.colorScheme.onSurface),
                      SizedBox(width: 16),
                      Text('复制',
                          style: TextStyle(color: theme.colorScheme.onSurface)),
                    ],
                  ),
                ),
              ),
              PopupMenuDivider(height: 8),
              PopupMenuItem<String>(
                value: 'delete',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 16),
                      Text('删除', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// 处理菜单操作
  Future<void> _handleMenuAction(String action, FileItem file) async {
    // 确保在执行操作前重新获取有效的 context
    // 这样可以避免 PopupMenu 关闭时的 context 问题
    if (!mounted) return;

    bool operationSuccess = false;
    switch (action) {
      case 'details':
        await _operationsService?.showFileDetails(file);
        break;
      case 'rename':
        operationSuccess = await _operationsService?.renameFile(file) ?? false;
        // 重命名成功后，标记文件已修改，但继续停留在预览页
        if (operationSuccess) {
          setState(() {
            _fileModified = true;
          });
        }
        break;
      case 'move':
        operationSuccess = await _operationsService?.moveFile(file) ?? false;
        // 移动成功后，标记文件已修改
        if (operationSuccess) {
          setState(() {
            _fileModified = true;
          });
        }
        break;
      case 'copy':
        operationSuccess = await _operationsService?.copyFile(file) ?? false;
        // 复制成功后，标记文件已修改（目标位置有新文件）
        if (operationSuccess) {
          setState(() {
            _fileModified = true;
          });
        }
        break;
      case 'delete':
        // 删除操作会通过 onFileDeleted 回调处理页面关闭
        await _operationsService?.deleteFile(file);
        return;
    }
  }

  /// 判断文件是否支持打印
  bool _canPrint(FileItem file) {
    return FileUtils.isImageFile(file.name) ||
        FileUtils.isPdfFile(file.name) ||
        FileUtils.isTextFile(file.name);
  }

  /// 打印文件
  ///
  /// 根据文件类型调用对应的打印方法：
  /// - 图片：转换为 PDF 后打印
  /// - PDF：直接打印原始文件
  /// - 文本：格式化为 PDF 后打印
  Future<void> _printFile(FileItem file) async {
    try {
      if (FileUtils.isImageFile(file.name)) {
        await _printImage(file);
      } else if (FileUtils.isPdfFile(file.name)) {
        await _printPdf(file);
      } else if (FileUtils.isTextFile(file.name)) {
        await _printText(file);
      }
    } catch (e) {
      logger.e('Print failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打印失败: $e')),
        );
      }
    }
  }

  /// 打印图片
  ///
  /// 将图片文件转换为 PDF 格式后打印
  /// 图片会自动缩放以适配页面大小，居中显示
  Future<void> _printImage(FileItem file) async {
    try {
      final imageBytes = await File(file.path).readAsBytes();
      final image = pw.MemoryImage(imageBytes);

      await Printing.layoutPdf(
        name: file.name,
        onLayout: (pw_pdf.PdfPageFormat format) async {
          final pdf = pw.Document();
          pdf.addPage(
            pw.Page(
              pageFormat: format,
              build: (context) => pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
            ),
          );
          return pdf.save();
        },
      );
      logger.i('Image print initiated: ${file.name}');
    } catch (e) {
      logger.e('Failed to print image: $e');
      rethrow;
    }
  }

  /// 打印 PDF
  ///
  /// 直接使用原始 PDF 文件字节进行打印
  /// 保留 PDF 原始格式和布局
  Future<void> _printPdf(FileItem file) async {
    try {
      final pdfBytes = await File(file.path).readAsBytes();
      await Printing.layoutPdf(
        name: file.name,
        onLayout: (_) => Future.value(pdfBytes),
      );
      logger.i('PDF print initiated: ${file.name}');
    } catch (e) {
      logger.e('Failed to print PDF: $e');
      rethrow;
    }
  }

  /// 打印文本
  ///
  /// 将文本文件格式化为 PDF 后打印
  /// 功能特性：
  /// - 带文件名标题
  /// - 自动分页
  /// - 限制最大内容长度（50KB），避免生成过大的 PDF
  /// - 支持 UTF-8 编码，失败时回退到 Latin1
  Future<void> _printText(FileItem file) async {
    try {
      // 直接读取文件内容
      String content;
      try {
        // 尝试以 UTF-8 读取
        content = await File(file.path).readAsString();
      } catch (e) {
        // UTF-8 失败，使用 Latin1 作为后备
        final bytes = await File(file.path).readAsBytes();
        content = latin1.decode(bytes);
      }

      // 限制内容长度，避免生成过大的 PDF
      const maxLength = 50000; // 约 50KB 文本
      if (content.length > maxLength) {
        content = '${content.substring(0, maxLength)}\n\n... (内容过长，已截断) ...';
      }

      await Printing.layoutPdf(
        name: file.name,
        onLayout: (pw_pdf.PdfPageFormat format) async {
          final pdf = pw.Document();
          pdf.addPage(
            pw.MultiPage(
              pageFormat: format,
              build: (context) => [
                pw.Header(
                  level: 0,
                  child: pw.Text(
                    file.name,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  content,
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ],
            ),
          );
          return pdf.save();
        },
      );
      logger.i('Text print initiated: ${file.name}');
    } catch (e) {
      logger.e('Failed to print text: $e');
      rethrow;
    }
  }
}

/// 单个文件预览项组件（用于 PageView）
class _FilePreviewItem extends StatefulWidget {
  final FileItem file;
  final VoidCallback? onTap; // 点击回调，用于切换UI
  final Function(bool show)? onSetUIVisible; // 强制设置UI显示状态

  const _FilePreviewItem({
    super.key,
    required this.file,
    this.onTap,
    this.onSetUIVisible,
  });

  @override
  State<_FilePreviewItem> createState() => __FilePreviewItemState();
}

class __FilePreviewItemState extends State<_FilePreviewItem>
    with AutomaticKeepAliveClientMixin {
  String? _fileContent;
  bool _isLoading = true;
  String? _error;
  PdfController? _pdfController; // 仅在非 Windows 平台使用

  @override
  // 只为图片和文本文件保持状态，视频和音频不保持（避免内存问题）
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
    _pdfController?.dispose(); // 仅在非 Windows 平台初始化
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
                  Uint16List.view(Uint8List.fromList(bytes.sublist(2)).buffer));
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
                  Uint16List.view(Uint8List.fromList(swapped).buffer));
              decoded = true;
            } catch (e) {
              logger.w('UTF-16 BE decode failed: $e');
            }
          }
          // UTF-8 BOM: EF BB BF
          else if (bytes.length >= 3 &&
              bytes[0] == 0xEF &&
              bytes[1] == 0xBB &&
              bytes[2] == 0xBF) {
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
      // 检查文件是否存在
      final file = File(widget.file.path);
      if (!await file.exists()) {
        throw Exception('文件不存在: ${widget.file.path}');
      }

      // 检查文件是否可读
      try {
        await file.readAsBytes();
      } catch (e) {
        throw Exception('文件无法读取，可能没有权限: $e');
      }

      logger.d('Opening PDF file: ${widget.file.path}');

      // 使用 pdfx 加载 PDF
      // 注意：pdfx 在某些设备上可能因平台通道问题而失败
      // 失败时会通过 catch 块优雅降级，提示用户使用外部应用
      final document = PdfDocument.openFile(widget.file.path);
      setState(() {
        _pdfController = PdfController(document: document);
        _isLoading = false;
      });
      logger.i('PDF document opened successfully');
    } catch (e) {
      logger.e('Error loading PDF: $e');

      // 根据错误类型提供友好的错误信息
      String errorMessage;
      if (e.toString().contains('文件不存在')) {
        errorMessage = '文件不存在，可能已被删除';
      } else if (e.toString().contains('无法读取')) {
        errorMessage = '无法读取文件，请检查应用权限';
      } else if (e.toString().contains("Can't open file")) {
        errorMessage = 'PDF文件已损坏或格式不正确';
      } else if (e.toString().contains('channel-error') ||
          e.toString().contains('PlatformException')) {
        // pdfx 插件平台通道错误，通常是插件初始化失败
        errorMessage = 'PDF 预览功能暂不可用\n请使用其他应用打开';
      } else {
        errorMessage = 'PDF加载失败: ${e.toString()}';
      }

      setState(() {
        _error = errorMessage;
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
                // PDF 文件加载失败时，提供备选方案：使用系统默认应用打开
                // 这确保即使内置预览失败，用户仍然可以查看 PDF 文件
                if (FileUtils.isPdfFile(widget.file.name)) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await OpenFile.open(widget.file.path);
                      if (result.type != ResultType.done) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('打开失败: ${result.message}')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('使用其他应用打开'),
                  ),
                ],
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
                      const Icon(Icons.broken_image,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        '图片加载失败',
                        style: TextStyle(color: Colors.white),
                      ),
                      Text(
                        '$error',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70),
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
    // 视频播放器自己处理点击事件（用于显示/隐藏控制栏）
    // 同时传递onToggleUI回调，与顶部AppBar同步切换
    return Container(
      color: Colors.black, // 视频预览固定黑色背景
      child: Center(
        child: VideoPlayerWidget(
          videoPath: widget.file.path,
          onToggleUI: widget.onTap, // 传递UI切换回调
          onSetUIVisible: widget.onSetUIVisible, // 传递强制设置UI状态的回调
        ),
      ),
    );
  }

  Widget _buildAudioPreview() {
    return GestureDetector(
      onTap: widget.onTap, // 点击切换UI
      child: AudioPlayerWidget(
        audioPath: widget.file.path,
        fileName: widget.file.name,
      ),
    );
  }

  Widget _buildPdfViewer() {
    // 使用 pdfx 组件显示 PDF 文档
    // 注意：此方法只有在 PDF 成功加载后才会被调用
    if (_pdfController == null) {
      // 防御性检查：理论上不应该到达这里
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap, // 点击切换UI
      child: Container(
        color: Colors.black,
        child: PdfView(
          controller: _pdfController!,
          scrollDirection: Axis.vertical,
          onDocumentLoaded: (document) {
            logger.i('PDF document loaded: ${document.pagesCount} pages');
          },
          onPageChanged: (page) {
            logger.d('PDF page changed to: $page');
          },
        ),
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
                          FileSizeFormatter.formatBytesWithSpace(
                              widget.file.size),
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
