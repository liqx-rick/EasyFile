import 'package:flutter/material.dart';
import 'package:easyfile/data/models/extraction_record.dart';
import 'package:easyfile/core/services/extraction_record_service.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/di/locator.dart';
import 'package:provider/provider.dart';
import 'package:easyfile/ui/pages/extracted_files_browser_page.dart';

/// 解压记录页面
class ExtractionRecordsPage extends StatefulWidget {
  const ExtractionRecordsPage({super.key});

  @override
  State<ExtractionRecordsPage> createState() => _ExtractionRecordsPageState();
}

class _ExtractionRecordsPageState extends State<ExtractionRecordsPage> {
  final ExtractionRecordService _service = ExtractionRecordService();
  List<ExtractionRecord> _records = [];
  Map<String, bool> _folderExistsMap = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);

    final records = await _service.getAllRecords();
    
    // 批量检查文件夹是否存在
    final paths = records.map((r) => r.targetPath).toList();
    final existsMap = await _service.batchCheckFoldersExist(paths);

    if (mounted) {
      setState(() {
        _records = records;
        _folderExistsMap = existsMap;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteRecord(ExtractionRecord record) async {
    await _service.deleteRecord(record.id);
    await _loadRecords();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除记录')),
      );
    }
  }

  Future<void> _deleteAllRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空所有记录'),
        content: const Text('确定要清空所有解压记录吗？\n（不会删除解压后的文件）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.deleteAllRecords();
      await _loadRecords();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清空所有记录')),
        );
      }
    }
  }

  Future<void> _viewFiles(ExtractionRecord record) async {
    final presenter = locator<FilePresenter>();
    final viewModel = context.read<FileViewModel>();

    // 导航到解压文件浏览页面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExtractedFilesBrowserPage(
          archiveName: record.archiveName,
          extractedPath: record.targetPath,
          presenter: presenter,
          viewModel: viewModel,
        ),
      ),
    );
  }

  String _formatPathDisplay(String path) {
    if (path == '/storage/emulated/0') {
      return '内部存储';
    }
    if (path.startsWith('/storage/emulated/0/')) {
      final relativePath = path.substring('/storage/emulated/0/'.length);
      return '内部存储$relativePath';
    }
    return path;
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('解压记录 (${_records.length})'),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空所有记录',
              onPressed: _deleteAllRecords,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? _buildEmptyState(theme)
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _records.length,
                  separatorBuilder: (context, index) => const Divider(height: 32),
                  itemBuilder: (context, index) {
                    final record = _records[index];
                    final folderExists = _folderExistsMap[record.targetPath] ?? false;
                    return _buildRecordItem(
                      record,
                      folderExists,
                      theme,
                      colorScheme,
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无解压记录',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '解压压缩包后会显示在这里',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordItem(
    ExtractionRecord record,
    bool folderExists,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isDeleted = !folderExists;
    final textColor = isDeleted
        ? colorScheme.onSurfaceVariant.withOpacity(0.5)
        : colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 压缩包名称
        Row(
          children: [
            Icon(
              Icons.folder_zip,
              color: isDeleted ? Colors.grey[400] : Colors.amber[700],
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                record.archiveName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // 解压文件夹信息
        Row(
          children: [
            const SizedBox(width: 28),
            Icon(
              Icons.folder,
              color: isDeleted ? Colors.grey[400] : colorScheme.primary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Text(
                    record.folderName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${record.fileCount}个文件)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (isDeleted) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.warning_amber,
                      size: 16,
                      color: Colors.orange[700],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '已删除',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange[700],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 位置和时间
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(
            _formatPathDisplay(record.targetPath),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(
            _formatDateTime(record.extractedAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 操作按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (folderExists)
              TextButton.icon(
                onPressed: () => _viewFiles(record),
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('查看文件'),
              ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => _deleteRecord(record),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除'),
            ),
          ],
        ),
      ],
    );
  }
}
