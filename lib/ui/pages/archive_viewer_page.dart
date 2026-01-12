import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/archive_entry_info.dart';
import 'package:easyfile/core/services/archive_service.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/utils/file_utils.dart';

/// 压缩包查看器页面
/// 
/// 显示压缩包内的文件和目录列表，不实际解压
class ArchiveViewerPage extends StatefulWidget {
  final FileItem archiveFile;

  const ArchiveViewerPage({
    super.key,
    required this.archiveFile,
  });

  @override
  State<ArchiveViewerPage> createState() => _ArchiveViewerPageState();
}

class _ArchiveViewerPageState extends State<ArchiveViewerPage> {
  final ArchiveService _archiveService = ArchiveService();
  List<ArchiveEntryInfo>? _entries;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadArchiveContents();
  }

  Future<void> _loadArchiveContents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final entries = await _archiveService.listArchiveContents(widget.archiveFile.path);
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '无法读取压缩包内容: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.archiveFile.name,
              style: const TextStyle(fontSize: 16),
            ),
            if (_entries != null)
              Text(
                '${_entries!.length} 个项目',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadArchiveContents,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_entries == null || _entries!.isEmpty) {
      return Center(
        child: Text(
          '压缩包为空',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return _buildEntriesList(theme);
  }

  Widget _buildEntriesList(ThemeData theme) {
    return ListView.builder(
      itemCount: _entries!.length,
      itemBuilder: (context, index) {
        final entry = _entries![index];
        return _buildEntryItem(entry, theme);
      },
    );
  }

  Widget _buildEntryItem(ArchiveEntryInfo entry, ThemeData theme) {
    return ListTile(
      leading: _buildEntryIcon(entry, theme),
      title: Text(
        entry.fileName.isEmpty ? entry.path : entry.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: _buildEntrySubtitle(entry, theme),
      trailing: entry.isDirectory
          ? null
          : Text(
              FileSizeFormatter.formatBytes(entry.size),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }

  Widget _buildEntryIcon(ArchiveEntryInfo entry, ThemeData theme) {
    if (entry.isDirectory) {
      return Icon(
        Icons.folder,
        color: theme.colorScheme.primary,
      );
    }

    // 使用 AppConfig 获取文件图标
    final iconData = _getFileIcon(entry.fileName);
    return Icon(
      iconData,
      color: theme.colorScheme.primary,
    );
  }

  IconData _getFileIcon(String fileName) {
    final config = AppConfig.instance.fileTypes;

    if (config.isImageFile(fileName)) {
      return Icons.image;
    } else if (config.isVideoFile(fileName)) {
      return Icons.movie;
    } else if (config.isAudioFile(fileName)) {
      return Icons.audiotrack;
    } else if (config.isPdfFile(fileName)) {
      return Icons.picture_as_pdf;
    } else if (config.isDocumentFile(fileName)) {
      final ext = FileUtils.getExtension(fileName);
      if (config.getWordExtensions().contains(ext)) {
        return Icons.article;
      } else if (config.getExcelExtensions().contains(ext)) {
        return Icons.table_chart;
      } else if (config.getTextExtensions().contains(ext)) {
        return Icons.description;
      }
      return Icons.description;
    } else if (config.isApkFile(fileName)) {
      return Icons.android;
    } else if (config.isArchiveFile(fileName)) {
      return Icons.folder_zip;
    }
    return Icons.insert_drive_file;
  }

  Widget? _buildEntrySubtitle(ArchiveEntryInfo entry, ThemeData theme) {
    if (entry.isDirectory) {
      return Text(
        entry.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    // 显示路径和压缩率
    final compressionRatio = entry.compressionRatio.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.path != entry.fileName)
          Text(
            entry.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        Text(
          '压缩率: $compressionRatio%',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
