import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/new_file_item.dart';
import 'package:easyfile/data/sources/new_files_scanner.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/mixins/edit_mode_mixin.dart';
import 'package:easyfile/ui/mixins/pop_scope_handler_mixin.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/services/batch_operations_service.dart';
import 'package:easyfile/ui/services/single_file_operations_service.dart';
import 'package:easyfile/ui/widgets/audio_cover_widget.dart';
import 'package:easyfile/ui/widgets/document_icon_widget.dart';
import 'package:easyfile/ui/widgets/edit_mode_hint_bar.dart';
import 'package:easyfile/ui/widgets/edit_mode_widgets.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/ui/widgets/image_thumbnail.dart';
import 'package:easyfile/ui/widgets/real_video_thumbnail.dart';
import 'package:easyfile/ui/widgets/selection_bottom_bar.dart';
import 'package:easyfile/ui/widgets/single_file_operations_sheet.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:flutter/material.dart';

/// 新文件列表页面
///
/// 显示最近7天内新增的文件
class NewFilesPage extends StatefulWidget {
  /// 保留天数（默认7天）
  final int retentionDays;

  const NewFilesPage({
    super.key,
    this.retentionDays = 7,
  });

  @override
  State<NewFilesPage> createState() => _NewFilesPageState();
}

class _NewFilesPageState extends State<NewFilesPage> with EditModeMixin, PopScopeHandlerMixin {
  final _scanner = NewFilesScanner();
  List<NewFileItem> _files = [];
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;

  // 统计数据
  int _totalCount = 0;
  int _totalSize = 0;

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

    _loadFiles();
  }

  @override
  void dispose() {
    locator<FileViewModel>().removeListener(_onViewModelChanged);
    _scanner.cancelCurrentScan();
    super.dispose();
  }

  /// ViewModel变化监听器
  void _onViewModelChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// 加载文件列表
  Future<void> _loadFiles() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final files = await _scanner.scanNewFiles(
        retentionDays: widget.retentionDays,
        maxResults: 500,
      );

      if (!mounted) return;

      // 过滤掉已删除或移动的文件
      final existingFiles = files.where((file) => file.toFileItem() != null).toList();

      // 计算统计数据（基于实际存在的文件）
      _totalCount = existingFiles.length;
      _totalSize = 0;

      for (final file in existingFiles) {
        final fileItem = file.toFileItem();
        if (fileItem != null) {
          _totalSize += fileItem.size;
        }
      }

      setState(() {
        _files = existingFiles;
        _isLoading = false;
      });

      logger.i('新文件加载完成: ${existingFiles.length}个文件 (扫描到${files.length}个), 共${FileSizeFormatter.formatBytes(_totalSize)}');
    } catch (e) {
      logger.e('加载新文件失败: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  /// 刷新文件列表
  Future<void> _refresh() async {
    await _loadFiles();
  }

  /// 打开文件预览
  void _openFile(NewFileItem item) {
    final fileItem = item.toFileItem();
    if (fileItem == null) {
      _showError('文件不存在或无法访问');
      return;
    }

    // 构建文件列表（只包含存在的文件）
    final fileList = _files
        .map((e) => e.toFileItem())
        .where((e) => e != null)
        .cast<FileItem>()
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FilePreviewPage(
          file: fileItem,
          fileList: fileList,
          initialIndex: fileList.indexWhere((f) => f.path == fileItem.path),
          viewModel: locator<FileViewModel>(),
          presenter: locator<FilePresenter>(),
        ),
      ),
    ).then((needsRefresh) {
      // 如果文件被修改（删除、移动等），刷新列表
      if (needsRefresh == true) {
        _refresh();
      }
    });
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

  /// 显示错误提示
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 获取所有文件路径（用于全选）
  List<String> _getAllFilePaths() {
    return _files
        .map((item) => item.toFileItem())
        .where((file) => file != null)
        .map((file) => file!.path)
        .toList();
  }

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
      onMove: () {
        if (!mounted) return;
        // 使用内部存储根目录作为当前路径（新文件来自不同目录）
        _batchService.batchMove(context, _selectionController.selected, '/storage/emulated/0');
      },
      onDelete: () {
        if (!mounted) return;
        _batchService.batchDelete(context, _selectionController.selected);
      },
      onShare: () {
        if (!mounted) return;
        _batchService.batchShare(context, _selectionController.selected);
      },
      onToggleFavorite: () {
        if (!mounted) return;
        _batchService.batchToggleFavorite(context, _selectionController.selected);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !isEditMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isEditMode) {
          exitEditMode();
        }
      },
      child: Scaffold(
        appBar: isEditMode
            ? AppBar(
                // 编辑模式
                leading: SelectAllButton(
                  selectedCount: _selectionController.count,
                  totalCount: _getAllFilePaths().length,
                  onPressed: () {
                    setState(() {
                      handleSelectAll(_getAllFilePaths());
                    });
                  },
                ),
                title: const Text('新文件'),
                centerTitle: true,
                actions: [
                  // 退出编辑按钮
                  IconButton(
                    icon: const Icon(Icons.close, size: 24, weight: 700),
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: exitEditMode,
                    tooltip: '退出编辑',
                  ),
                ],
              )
            : AppBar(
                // 普通模式
                title: const Text('新文件'),
                centerTitle: true,
                actions: [
                  // 加载中或空列表时隐藏编辑按钮
                  if (!_isLoading && _files.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: enterEditMode,
                      tooltip: '编辑',
                    ),
                ],
              ),
        body: Column(
          children: [
            // 编辑模式提示栏
            if (isEditMode) const EditModeHintBar(),
            // 主体内容
            Expanded(child: _buildBody(theme)),
          ],
        ),
        // 编辑模式：显示底部操作栏
        bottomNavigationBar: isEditMode ? _buildSelectionBottomBar() : null,
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_hasError) {
      return _buildErrorView(theme);
    }

    if (_files.isEmpty) {
      return _buildEmptyView(theme);
    }

    return Column(
      children: [
        // 统计卡片
        _buildStatisticsCard(theme),
        const Divider(height: 1),

        // 文件列表
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: _files.length,
              itemBuilder: (context, index) {
                return _buildFileItem(_files[index], theme);
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 构建统计卡片
  Widget _buildStatisticsCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.colorScheme.primaryContainer.withOpacity(0.3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            icon: Icons.folder,
            label: '文件数',
            value: '$_totalCount',
            theme: theme,
          ),
          _buildStatItem(
            icon: Icons.storage,
            label: '总大小',
            value: FileSizeFormatter.formatBytes(_totalSize),
            theme: theme,
          ),
          _buildStatItem(
            icon: Icons.calendar_today,
            label: '时间范围',
            value: '${widget.retentionDays}天',
            theme: theme,
          ),
        ],
      ),
    );
  }

  /// 构建统计项
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required ThemeData theme,
  }) {
    return Column(
      children: [
        Icon(icon, size: 24, color: theme.colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  /// 构建文件项
  Widget _buildFileItem(NewFileItem item, ThemeData theme) {
    final fileItem = item.toFileItem();

    if (fileItem == null) {
      // 文件不存在，显示灰色项
      return ListTile(
        leading: const Icon(Icons.error_outline, color: Colors.grey),
        title: Text(
          item.path.split('/').last,
          style: const TextStyle(
            color: Colors.grey,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        subtitle: const Text(
          '文件已被删除或移动',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final fileName = fileItem.name;
    final fileSize = FileSizeFormatter.formatBytes(fileItem.size);
    final createdDate = _formatDate(item.created);
    final isSelected = _selectionController.contains(fileItem.path);
    final colorScheme = theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      selected: isSelected,
      selectedTileColor: colorScheme.primaryContainer.withOpacity(0.3),
      // leading 显示文件缩略图
      leading: _buildThumbnail(fileItem, 48),
      title: Text(
        fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: item.displayName.isNotEmpty
          ? Text(
              '来源: ${item.displayName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            )
          : null,
      // trailing: 编辑模式显示大小+日期+复选框，普通模式只显示大小+日期
      trailing: isEditMode
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      fileSize,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      createdDate,
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
                      _selectionController.toggle(fileItem.path);
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
                  fileSize,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  createdDate,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
      // 编辑模式：点击切换选择；普通模式：点击打开预览
      onTap: isEditMode
          ? () {
              setState(() {
                _selectionController.toggle(fileItem.path);
              });
            }
          : () => _openFile(item),
      // 长按：编辑模式禁用；普通模式显示操作菜单
      onLongPress: isEditMode
          ? () {} // 编辑模式：禁用长按
          : () {
              // 长按：显示单文件操作面板
              _showSingleFileOperationsMenu(context, fileItem);
            },
    );
  }

  /// 获取文件图标
  IconData _getFileIcon(FileItem file) {
    final fileName = file.name.toLowerCase();
    final extension = fileName.contains('.') ? fileName.split('.').last : '';

    // 图片
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension)) {
      return Icons.image;
    }

    // 视频
    if (['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv'].contains(extension)) {
      return Icons.video_file;
    }

    // 音频
    if (['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg'].contains(extension)) {
      return Icons.audio_file;
    }

    // 文档
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'].contains(extension)) {
      return Icons.description;
    }

    // 压缩包
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(extension)) {
      return Icons.folder_zip;
    }

    // APK
    if (extension == 'apk') {
      return Icons.android;
    }

    // 默认
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
    } else if (file.name.toLowerCase().endsWith('.apk')) {
      // APK 安装包 - Android 绿色
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF3DDC84), // Android 绿色
              const Color(0xFF3DDC84).withValues(alpha: 0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(size * 0.15),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3DDC84).withValues(alpha: 0.2),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(
          Icons.android,
          color: Colors.white,
          size: size * 0.6,
        ),
      );
    } else if (file.name.toLowerCase().endsWith('.exe')) {
      // Windows 安装包 - Windows 蓝色
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0078D4), // Windows 蓝色
              const Color(0xFF0078D4).withValues(alpha: 0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(size * 0.15),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0078D4).withValues(alpha: 0.2),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(
          Icons.window,
          color: Colors.white,
          size: size * 0.6,
        ),
      );
    } else {
      // 其他文件类型显示灰色图标
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

  /// 构建空状态视图
  Widget _buildEmptyView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 80,
            color: Colors.green[400],
          ),
          const SizedBox(height: 16),
          Text(
            '暂无新增文件',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '最近${widget.retentionDays}天内没有新增文件',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建错误视图
  Widget _buildErrorView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            '加载失败',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? '未知错误',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
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
    );
  }
}
