import 'package:flutter/material.dart';
import '../../core/settings/app_trash_settings.dart';
import '../../core/di/locator.dart';

/// 回收站配置页面
class TrashConfigPage extends StatefulWidget {
  const TrashConfigPage({super.key});

  @override
  State<TrashConfigPage> createState() => _TrashConfigPageState();
}

class _TrashConfigPageState extends State<TrashConfigPage> {
  AppTrashSettings? _settings;
  bool _isLoading = true;

  late bool _isEnabled;
  late int _retentionDays;

  @override
  void initState() {
    super.initState();
    _initSettings();
  }

  Future<void> _initSettings() async {
    // 直接获取 AppTrashSettings（同步注册）
    _settings = locator<AppTrashSettings>();
    _loadSettings();
  }

  void _loadSettings() {
    if (_settings == null) return;
    setState(() {
      _isEnabled = _settings!.isEnabled;
      _retentionDays = _settings!.retentionDays;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _settings == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('回收站设置'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站设置'),
      ),
      body: ListView(
        children: [
          // 启用开关
          SwitchListTile(
            title: const Text('启用回收站'),
            subtitle: const Text('开启后，删除的文件会先移入回收站'),
            value: _isEnabled,
            onChanged: (value) async {
              setState(() => _isEnabled = value);
              await _settings!.setEnabled(value);
            },
          ),
          const Divider(),

          // 清理周期
          if (_isEnabled) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '自动清理周期',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            // 动态生成选项（从配置读取）
            ..._settings!.retentionOptions.map((days) {
              return _buildRetentionOption(days, '$days天');
            }),
            const Divider(),

            // 说明
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '删除的文件会保留指定天数后自动清理。您也可以随时手动清空回收站。',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRetentionOption(int days, String label) {
    // ignore: deprecated_member_use
    return RadioListTile<int>(
      title: Text(label),
      value: days,
      // ignore: deprecated_member_use
      groupValue: _retentionDays,
      // ignore: deprecated_member_use
      onChanged: (value) async {
        if (value != null) {
          setState(() => _retentionDays = value);
          await _settings!.setRetentionDays(value);
        }
      },
    );
  }
}
