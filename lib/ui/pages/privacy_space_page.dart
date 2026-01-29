import 'package:easyfile/analytics/analytics_helper.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/services/privacy_service.dart';
import 'package:easyfile/data/models/file_category.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/services/file_type_analyzer.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/pages/privacy_settings_page.dart';
import 'package:easyfile/ui/widgets/file_category_tab_bar.dart';
import 'package:easyfile/ui/widgets/file_collection_view.dart';
import 'package:easyfile/ui/widgets/folder_picker_dialog.dart';
import 'package:easyfile/ui/widgets/unified_view_config.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 视图模式
enum PrivacyViewMode {
  list, // 列表视图
  grid, // 网格视图
}

/// 隐私空间主页
///
/// 显示隐私文件列表，支持打开、移出、删除操作
/// ⚠️ 注意：此页面不进行验证，必须通过 PrivacyAuthPage 验证后进入
class PrivacySpacePage extends StatefulWidget {
  const PrivacySpacePage({super.key});

  @override
  State<PrivacySpacePage> createState() => _PrivacySpacePageState();
}

class _PrivacySpacePageState extends State<PrivacySpacePage> {
  final _privacyService = PrivacyService();
  final _fileTypeAnalyzer = FileTypeAnalyzer();

  List<FileItem> _files = [];
  bool _isLoading = true;
  PrivacyViewMode _viewMode = PrivacyViewMode.list; // 默认列表视图

  // 文件分类相关
  FileCategory _selectedCategory = FileCategory.all;
  FileTypeStats? _fileStats;

  @override
  void initState() {
    super.initState();
    // 生物识别验证后可能锁定竖屏，再次确保恢复所有方向
    _ensureOrientationFreedom();
    _loadFiles();

    // 埋点：进入隐私空间
    AnalyticsHelper.logPrivacySpaceEnter('main_page');
  }

  /// 确保屏幕方向自由
  Future<void> _ensureOrientationFreedom() async {
    logger.d('🔄 隐私空间: 确保恢复所有方向支持');
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    logger.d('✅ 隐私空间: 方向设置完成');
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final files = await _privacyService.getPrivateFiles();
      if (mounted) {
        // 计算文件类型统计
        final stats = _fileTypeAnalyzer.analyze(files);

        setState(() {
          _files = files;
          _fileStats = stats;
          _isLoading = false;
        });

        logger.d(
            '隐私空间文件统计: 总计=${stats.totalCount}, 图片=${stats.getCount(FileCategory.image)}, 视频=${stats.getCount(FileCategory.video)}, 音频=${stats.getCount(FileCategory.audio)}, 文档=${stats.getCount(FileCategory.document)}');
      }
    } catch (e) {
      logger.e('加载隐私文件失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败：$e')),
        );
      }
    }
  }

  /// 根据选中的分类过滤文件
  List<FileItem> _getFilteredFiles() {
    return _fileTypeAnalyzer.filterByCategory(_files, _selectedCategory);
  }

  /// 处理分类切换
  void _onCategoryChanged(FileCategory category) {
    setState(() {
      _selectedCategory = category;
      // 图片和视频默认使用网格视图，其他使用列表视图
      if (category == FileCategory.image || category == FileCategory.video) {
        _viewMode = PrivacyViewMode.grid;
      } else {
        _viewMode = PrivacyViewMode.list;
      }
    });
    logger.d('隐私空间切换分类: ${category.displayName}, 视图模式: $_viewMode');
  }

  Future<void> _openFile(FileItem file) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FilePreviewPage(file: file),
      ),
    );
  }

  Future<void> _moveOut(FileItem file) async {
    // 显示目录选择对话框
    final targetDir = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(
        title: '选择目标位置',
        currentPath: '/storage/emulated/0',
        sourceFileName: file.name,
        operationType: '移动',
      ),
    );

    if (targetDir == null || !mounted) return;

    final targetPath = '$targetDir/${file.name}';

    try {
      final success = await _privacyService.moveFromPrivate(file, targetPath);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 文件已移出隐私空间')),
        );
        _loadFiles();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 移出失败')),
        );
      }
    } catch (e) {
      logger.e('移出文件失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移出失败：$e')),
        );
      }
    }
  }

  Future<void> _deleteFile(FileItem file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要永久删除 "${file.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final success = await _privacyService.deletePrivateFile(file);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 文件已删除')),
        );
        _loadFiles();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 删除失败')),
        );
      }
    } catch (e) {
      logger.e('删除文件失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$e')),
        );
      }
    }
  }

  void _showFileOptions(FileItem file) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('打开'),
              onTap: () {
                Navigator.pop(context);
                _openFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move),
              title: const Text('移出隐私空间'),
              onTap: () {
                Navigator.pop(context);
                _moveOut(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteFile(file);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('如何使用隐私空间'),
          ],
        ),
        content: const Text(
          '添加文件：\n'
          '1. 在文件浏览器中长按文件\n'
          '2. 选择"移入隐私空间"\n'
          '3. 输入PIN码验证\n'
          '4. 文件即可移入隐私空间\n\n'
          '移出文件：\n'
          '• 长按隐私文件，选择"移出隐私空间"\n\n'
          '💡 提示：文件会从原位置移动，不会复制',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context); // 关闭对话框
              Navigator.pop(context); // 返回主页
            },
            child: const Text('去文件浏览器'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私空间'),
        actions: [
          // 有文件时显示帮助图标
          if (_files.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: '如何添加文件',
              onPressed: _showHelpDialog,
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PrivacySettingsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? _buildEmptyState(theme)
              : Column(
                  children: [
                    // 文件分类Tab栏（有多种文件类型时显示）
                    if (_fileStats != null && _fileStats!.hasMultipleTypes)
                      FileCategoryTabBar(
                        stats: _fileStats!,
                        selectedCategory: _selectedCategory,
                        onCategoryChanged: _onCategoryChanged,
                        showIcon: true, // 隐私空间显示图标
                        showCount: false, // 隐私空间不显示数字
                      ),
                    // 文件列表/网格
                    Expanded(
                      child: _viewMode == PrivacyViewMode.list ? _buildFileList() : _buildFileGrid(),
                    ),
                  ],
                ),
      // 仅在空状态时显示FAB
      floatingActionButton: _files.isEmpty && !_isLoading
          ? FloatingActionButton.extended(
              onPressed: _showHelpDialog,
              icon: const Icon(Icons.add),
              label: const Text('添加文件'),
            )
          : null,
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline,
                size: 60,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '隐私空间为空',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '这里将保护您的私密文件\n从文件浏览器添加文件到隐私空间',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            // 引导步骤
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '快速开始',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildStepItem(theme, '1', '打开文件浏览器'),
                  _buildStepItem(theme, '2', '长按要保护的文件'),
                  _buildStepItem(theme, '3', '选择"移入隐私空间"'),
                  _buildStepItem(theme, '4', '输入PIN码验证', isLast: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem(ThemeData theme, String number, String text, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    return _buildFileView(gridMode: false);
  }

  /// 构建网格视图
  Widget _buildFileGrid() {
    return _buildFileView(gridMode: true);
  }

  /// 统一构建文件视图（列表或网格）
  Widget _buildFileView({required bool gridMode}) {
    // 获取过滤后的文件列表
    final filteredFiles = _getFilteredFiles();

    // 获取简洁模式设置
    final showFileInfo = PageSettingsService().getGridShowFileInfo(PageId.categoryImages);
    logger.d('隐私空间${gridMode ? "网格" : "列表"}视图 - 简洁模式设置: showFileInfo=$showFileInfo, 过滤后文件数: ${filteredFiles.length}');

    // 为图片/视频配置简洁模式
    UnifiedViewConfig? Function(FileItem)? viewConfigBuilder;
    if (gridMode) {
      viewConfigBuilder = (file) {
        final isImage = FileUtils.isImageFile(file.name);
        final isVideo = FileUtils.isVideoFile(file.name);
        final shouldUseCompactMode = isImage || isVideo;

        if (shouldUseCompactMode) {
          return UnifiedViewConfig.fromContext(context, compactMode: !showFileInfo);
        }
        return null;
      };
    }

    return FileCollectionView(
      items: filteredFiles, // 使用过滤后的文件列表
      gridMode: gridMode,
      viewConfigBuilder: viewConfigBuilder,
      padding: gridMode ? const EdgeInsets.all(8) : const EdgeInsets.symmetric(vertical: 0),
      useUnifiedGridItem: true,
      onTap: (file) => _openFile(file),
      onLongPress: (file) => _showFileOptions(file),
    );
  }
}
