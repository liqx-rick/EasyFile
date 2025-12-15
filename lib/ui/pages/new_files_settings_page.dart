import 'package:flutter/material.dart';
import 'dart:io';

import 'package:easyfile/data/models/new_files_settings.dart';

/// 新文件设置页面
class NewFilesSettingsPage extends StatefulWidget {
  const NewFilesSettingsPage({super.key});

  @override
  State<NewFilesSettingsPage> createState() => _NewFilesSettingsPageState();
}

class _NewFilesSettingsPageState extends State<NewFilesSettingsPage> {
  late NewFilesSettings _settings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await NewFilesSettings.load();
    setState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    try {
      await _settings.save();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    }
  }

  Future<void> _resetToDefaults() async {
    setState(() {
      _settings = NewFilesSettings();
    });
    await _saveSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已恢复默认设置'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认设置'),
        content: const Text('将所有设置恢复为默认值，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _resetToDefaults();
            },
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('新文件发现模块设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('新文件发现模块设置'),
        elevation: 0,
      ),
      body: ListView(
        children: [
          // 扫描路径管理区
          _buildSectionHeader('扫描路径', Icons.folder_open, colorScheme),
          _buildCustomPathsList(),
          _buildAddPathButton(colorScheme),

          const Divider(height: 32),

          // 显示设置区
          _buildSectionHeader('显示设置', Icons.settings_display, colorScheme),
          _buildRetentionDaysSlider(colorScheme),
          _buildDisplayCountSlider(colorScheme),

          const Divider(height: 32),

          // 隐私控制区
          _buildSectionHeader('隐私控制', Icons.privacy_tip, colorScheme),
          _buildPrivacySwitch(
            title: '隐藏相机照片',
            subtitle: '隐藏 DCIM/Camera 文件夹中的照片',
            icon: Icons.camera_alt,
            value: _settings.hideCameraPhotos,
            onChanged: (value) async {
              setState(() {
                _settings.hideCameraPhotos = value;
              });
              await _saveSettings();
            },
          ),
          _buildPrivacySwitch(
            title: '隐藏截图',
            subtitle: '隐藏 Pictures/Screenshots 文件夹中的截图',
            icon: Icons.screenshot,
            value: _settings.hideScreenshots,
            onChanged: (value) async {
              setState(() {
                _settings.hideScreenshots = value;
              });
              await _saveSettings();
            },
          ),

          const SizedBox(height: 32),

          // 操作按钮区
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _showResetDialog,
              icon: const Icon(Icons.restore),
              label: const Text('恢复默认'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
      String title, IconData icon, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacySwitch({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Future<void> Function(bool) onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildRetentionDaysSlider(ColorScheme colorScheme) {
    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.calendar_today, color: colorScheme.primary),
          title: const Text('保留天数'),
          subtitle: Text(
            '扫描过去 ${_settings.retentionDays} 天内的文件',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Text(
            '${_settings.retentionDays} 天',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '7天',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Slider(
                  value: _settings.retentionDays.toDouble(),
                  min: 7,
                  max: 14,
                  divisions: 1,
                  label: '${_settings.retentionDays}天',
                  onChanged: (value) {
                    setState(() {
                      _settings.retentionDays = value.toInt();
                    });
                  },
                  onChangeEnd: (value) async {
                    await _saveSettings();
                  },
                ),
              ),
              Text(
                '14天',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDisplayCountSlider(ColorScheme colorScheme) {
    // 确保滑块值必须是20/50/100之一
    int displayValue = _settings.displayCount;
    if (displayValue != 20 && displayValue != 50 && displayValue != 100) {
      displayValue = 50; // 默认值50
    }

    // 映射：20->0, 50->1, 100->2
    double sliderValue = displayValue == 20 ? 0 : (displayValue == 50 ? 1 : 2);

    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.format_list_numbered, color: colorScheme.primary),
          title: const Text('显示数量'),
          subtitle: Text(
            '列表中最多显示 $displayValue 个文件',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Text(
            '$displayValue 个',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '20',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Slider(
                  value: sliderValue,
                  min: 0,
                  max: 2,
                  divisions: 2,
                  label: '$displayValue个',
                  onChanged: (value) {
                    // 映射回实际值：0->20, 1->50, 2->100
                    int actualValue = value == 0 ? 20 : (value == 1 ? 50 : 100);
                    setState(() {
                      _settings.displayCount = actualValue;
                    });
                  },
                  onChangeEnd: (value) async {
                    await _saveSettings();
                  },
                ),
              ),
              Text(
                '100',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomPathsList() {
    if (_settings.customScanPaths.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          '暂无自定义扫描路径',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      children: _settings.customScanPaths.map((path) {
        return ListTile(
          leading: const Icon(Icons.folder, size: 20),
          title: Text(
            path.split('/').last,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            path,
            style: const TextStyle(fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _removeCustomPath(path),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAddPathButton(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: OutlinedButton.icon(
        onPressed: _showAddPathDialog,
        icon: const Icon(Icons.add),
        label: const Text('添加扫描路径'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
    );
  }

  Future<void> _removeCustomPath(String path) async {
    setState(() {
      _settings.customScanPaths = List.from(_settings.customScanPaths)
        ..remove(path);
    });
    await _saveSettings();
  }

  void _showAddPathDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddPathBottomSheet(
        onPathSelected: (path) async {
          setState(() {
            if (!_settings.customScanPaths.contains(path)) {
              _settings.customScanPaths = List.from(_settings.customScanPaths)
                ..add(path);
            }
          });
          await _saveSettings();
        },
      ),
    );
  }
}

/// 添加路径底部弹窗
class _AddPathBottomSheet extends StatefulWidget {
  final Function(String) onPathSelected;

  const _AddPathBottomSheet({required this.onPathSelected});

  @override
  State<_AddPathBottomSheet> createState() => _AddPathBottomSheetState();
}

class _AddPathBottomSheetState extends State<_AddPathBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _recommendedPaths = [];
  List<String> _filteredPaths = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadRecommendedPaths();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecommendedPaths() async {
    // 获取常见目录
    final commonPaths = [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Documents',
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Movies',
      '/storage/emulated/0/Podcasts',
      '/storage/emulated/0/Audiobooks',
      '/storage/emulated/0/Alarms',
      '/storage/emulated/0/Notifications',
      '/storage/emulated/0/Ringtones',
      '/storage/emulated/0/bluetooth',
      '/storage/emulated/0/Android/media',
    ];

    // 过滤存在的路径
    final existingPaths = <String>[];
    for (final path in commonPaths) {
      if (Directory(path).existsSync()) {
        existingPaths.add(path);
      }
    }

    setState(() {
      _recommendedPaths = existingPaths;
      _filteredPaths = existingPaths;
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
      if (query.isEmpty) {
        _filteredPaths = _recommendedPaths;
      } else {
        _filteredPaths = _recommendedPaths
            .where((path) => path.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  '添加扫描路径',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // 搜索框
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索文件夹名称...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // 推荐列表
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: _filteredPaths.length,
              itemBuilder: (context, index) {
                final path = _filteredPaths[index];
                final folderName = path.split('/').last;

                return ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(folderName),
                  subtitle: Text(
                    path,
                    style: const TextStyle(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: () {
                    widget.onPathSelected(path);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),

          // 手动输入提示
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(
                top: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '提示：如需添加其他路径，请使用文件管理器查找并记录路径后手动输入',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
