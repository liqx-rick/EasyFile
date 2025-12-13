import 'package:flutter/material.dart';
import 'package:easyfile/core/services/file_display_settings_service.dart';
import 'package:easyfile/core/services/page_settings_service.dart';
import 'package:easyfile/core/models/page_settings.dart';

/// 文件显示配置页面
class FileDisplaySettingsPage extends StatefulWidget {
  const FileDisplaySettingsPage({super.key});

  @override
  State<FileDisplaySettingsPage> createState() =>
      _FileDisplaySettingsPageState();
}

class _FileDisplaySettingsPageState extends State<FileDisplaySettingsPage> {
  final _displaySettings = FileDisplaySettingsService();
  final _settingsService = PageSettingsService();

  bool _gridShowFileInfo = true;
  bool _showHiddenFiles = false;
  bool _showSystemFiles = false;
  bool _showFullPath = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    final showInfo =
        _settingsService.getGridShowFileInfo(PageId.categoryImages);
    final showHidden = await _displaySettings.getShowHiddenFiles();
    final showSystem = await _displaySettings.getShowSystemFiles();
    final showFullPath = await _displaySettings.getShowFullPath();

    setState(() {
      _gridShowFileInfo = showInfo;
      _showHiddenFiles = showHidden;
      _showSystemFiles = showSystem;
      _showFullPath = showFullPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文件显示配置'),
        elevation: 0,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),

          // 网格模式文件信息显示
          SwitchListTile(
            secondary: Icon(Icons.info_outline, color: colorScheme.primary),
            title: const Text('网格模式显示文件信息'),
            subtitle: Text(
              _gridShowFileInfo ? '显示文件名和大小' : '简洁模式：图片/视频仅显示缩略图',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: _gridShowFileInfo,
            onChanged: (value) async {
              setState(() {
                _gridShowFileInfo = value;
              });
              await _settingsService.setGridShowFileInfo(value);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value ? '已开启文件信息显示' : '已切换到简洁模式（图片/视频）',
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
          ),

          const Divider(height: 1, indent: 56),

          // 显示文件路径
          SwitchListTile(
            secondary: Icon(Icons.route, color: colorScheme.primary),
            title: const Text('显示文件路径'),
            subtitle: Text(
              _showFullPath ? '分类列表模式下显示文件完整路径' : '分类列表模式下不显示路径',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: _showFullPath,
            onChanged: (value) async {
              setState(() {
                _showFullPath = value;
              });
              await _displaySettings.setShowFullPath(value);
            },
          ),

          const Divider(height: 1, indent: 56),

          // 显示隐藏文件
          SwitchListTile(
            secondary: Icon(
              _showHiddenFiles ? Icons.visibility : Icons.visibility_off,
              color: colorScheme.primary,
            ),
            title: const Text('显示隐藏文件'),
            subtitle: Text(
              _showHiddenFiles ? '当前显示以 . 开头的隐藏文件' : '当前隐藏以 . 开头的文件',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: _showHiddenFiles,
            onChanged: (value) async {
              setState(() {
                _showHiddenFiles = value;
              });
              await _displaySettings.setShowHiddenFiles(value);
            },
          ),

          const Divider(height: 1, indent: 56),

          // 显示系统文件
          SwitchListTile(
            secondary: Icon(
              _showSystemFiles ? Icons.folder_special : Icons.folder_off,
              color: colorScheme.primary,
            ),
            title: const Text('显示系统文件'),
            subtitle: Text(
              _showSystemFiles
                  ? '当前显示 Android、.thumbnails 等系统文件夹'
                  : '当前隐藏系统文件夹和文件',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: _showSystemFiles,
            onChanged: (value) async {
              setState(() {
                _showSystemFiles = value;
              });
              await _displaySettings.setShowSystemFiles(value);
            },
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
