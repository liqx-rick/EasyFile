import 'package:flutter/material.dart';

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
          // 显示设置区
          _buildSectionHeader('显示设置', Icons.settings_display, colorScheme),
          _buildRetentionDaysSlider(colorScheme),
          _buildDisplayCountSlider(colorScheme),

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

}
