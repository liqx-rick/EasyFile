import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/utils/time_formatter.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/ui/services/single_file_operations_service.dart';
import 'package:easyfile/ui/widgets/single_file_operations_sheet.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:provider/provider.dart';
import 'package:easyfile/core/platform/mediastore_scanner_channel.dart';

/// 压缩包管理页面
/// 
/// 扫描并展示设备上所有压缩包文件
/// 支持：
/// - 格式筛选（全部/ZIP/RAR/7Z/其他）
/// - 排序（名称/大小/时间）
/// - 查看内容、解压、删除等操作
class ArchiveManagementPage extends StatefulWidget {
  const ArchiveManagementPage({super.key});

  @override
  State<ArchiveManagementPage> createState() => _ArchiveManagementPageState();
}

class _ArchiveManagementPageState extends State<ArchiveManagementPage> {
  bool _isScanning = true;
  List<FileItem> _allArchives = [];
  List<FileItem> _filteredArchives = [];
  String _selectedFilter = 'all'; // all, zip, rar, 7z, other
  String _sortBy = 'name'; // name, size, time
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _scanArchives();
  }

  /// 扫描设备上的所有压缩包
  Future<void> _scanArchives() async {
    setState(() {
      _isScanning = true;
    });

    try {
      final archives = await _scanArchivesInBackground();
      if (mounted) {
        setState(() {
          _allArchives = archives;
          _applyFilterAndSort();
          _isScanning = false;
        });
      }
    } catch (e) {
      logger.e('扫描压缩包失败: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e')),
        );
      }
    }
  }

  /// 后台扫描压缩包（使用MediaStore）
  Future<List<FileItem>> _scanArchivesInBackground() async {
    logger.i('开始使用MediaStore扫描压缩包');
    
    try {
      // 使用MediaStore扫描压缩包（与分类页面逻辑一致）
      final archives = await MediaStoreScannerChannel.scan(MediaScanType.archive);
      
      logger.i('MediaStore扫描完成，找到 ${archives.length} 个压缩包');
      return archives;
    } catch (e) {
      logger.e('MediaStore扫描压缩包失败: $e');
      rethrow;
    }
  }

  /// 应用筛选和排序
  void _applyFilterAndSort() {
    // 1. 筛选
    if (_selectedFilter == 'all') {
      _filteredArchives = List.from(_allArchives);
    } else {
      _filteredArchives = _allArchives.where((file) {
        final ext = FileUtils.getExtension(file.name).toLowerCase();
        switch (_selectedFilter) {
          case 'zip':
            return ext == 'zip';
          case 'rar':
            return ext == 'rar';
          case '7z':
            return ext == '7z';
          case 'other':
            return !['zip', 'rar', '7z'].contains(ext);
          default:
            return true;
        }
      }).toList();
    }

    // 2. 排序
    _filteredArchives.sort((a, b) {
      int result;
      switch (_sortBy) {
        case 'name':
          result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case 'size':
          result = a.size.compareTo(b.size);
          break;
        case 'time':
          result = a.modified.compareTo(b.modified);
          break;
        default:
          result = 0;
      }
      return _sortAscending ? result : -result;
    });
  }

  /// 更改筛选器
  void _changeFilter(String filter) {
    setState(() {
      _selectedFilter = filter;
      _applyFilterAndSort();
    });
  }

  /// 更改排序方式
  void _changeSortBy(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = sortBy;
        _sortAscending = true;
      }
      _applyFilterAndSort();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('压缩包', style: TextStyle(fontSize: 18)),
            if (!_isScanning)
              Text(
                '${_filteredArchives.length} 个文件',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          // 排序菜单
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: '排序',
            onSelected: _changeSortBy,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'name',
                child: Row(
                  children: [
                    Icon(
                      _sortBy == 'name'
                          ? (_sortAscending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward)
                          : Icons.sort_by_alpha,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Text('按名称'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'size',
                child: Row(
                  children: [
                    Icon(
                      _sortBy == 'size'
                          ? (_sortAscending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward)
                          : Icons.data_usage,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Text('按大小'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'time',
                child: Row(
                  children: [
                    Icon(
                      _sortBy == 'time'
                          ? (_sortAscending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward)
                          : Icons.access_time,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Text('按时间'),
                  ],
                ),
              ),
            ],
          ),
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _isScanning ? null : _scanArchives,
          ),
        ],
      ),
      body: Column(
        children: [
          // 格式筛选器
          _buildFilterChips(theme),
          const Divider(height: 1),
          // 列表
          Expanded(
            child: _buildBody(theme),
          ),
        ],
      ),
    );
  }

  /// 构建格式筛选chips
  Widget _buildFilterChips(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('全部', 'all', theme),
            const SizedBox(width: 8),
            _buildFilterChip('ZIP', 'zip', theme),
            const SizedBox(width: 8),
            _buildFilterChip('RAR', 'rar', theme),
            const SizedBox(width: 8),
            _buildFilterChip('7Z', '7z', theme),
            const SizedBox(width: 8),
            _buildFilterChip('其他', 'other', theme),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, ThemeData theme) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _changeFilter(value),
      backgroundColor: theme.colorScheme.surface,
      selectedColor: theme.colorScheme.primaryContainer,
      checkmarkColor: theme.colorScheme.primary,
    );
  }

  /// 构建主体内容
  Widget _buildBody(ThemeData theme) {
    if (_isScanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '正在扫描压缩包...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_filteredArchives.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_zip_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedFilter == 'all' ? '未找到压缩包' : '未找到该格式的压缩包',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '支持 ZIP、RAR、7Z、TAR、GZ 等格式',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredArchives.length,
      itemBuilder: (context, index) {
        final archive = _filteredArchives[index];
        return _buildArchiveItem(archive, theme);
      },
    );
  }

  /// 构建压缩包列表项
  Widget _buildArchiveItem(FileItem archive, ThemeData theme) {
    final ext = FileUtils.getExtension(archive.name).toUpperCase();
    final parentDir = archive.path.substring(0, archive.path.lastIndexOf('/'));

    return ListTile(
      leading: Icon(
        Icons.folder_zip,
        size: 40,
        color: _getFormatColor(ext),
      ),
      title: Text(
        archive.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${FileSizeFormatter.formatBytes(archive.size)} • ${TimeFormatter.formatRelativeTime(archive.modified)}',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            parentDir,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: () => _showOperationsMenu(archive),
      ),
      onTap: () => _showOperationsMenu(archive),
    );
  }

  /// 获取格式对应的颜色
  Color _getFormatColor(String format) {
    switch (format.toLowerCase()) {
      case 'zip':
        return Colors.blue;
      case 'rar':
        return Colors.purple;
      case '7z':
        return Colors.green;
      case 'tar':
      case 'gz':
      case 'bz2':
      case 'xz':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// 显示操作菜单
  void _showOperationsMenu(FileItem archive) {
    final presenter = locator<FilePresenter>();
    final viewModel = context.read<FileViewModel>();

    final service = SingleFileOperationsService(
      context: context,
      viewModel: viewModel,
      presenter: presenter,
      onRefresh: _scanArchives, // 刷新列表
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SingleFileOperationsSheet(
        file: archive,
        service: service,
      ),
    );
  }
}
