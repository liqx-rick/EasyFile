import 'package:easyfile/core/platform/device_info_channel.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 设备硬件信息页面
/// 显示运行软件的硬件环境统计
class DeviceInfoPage extends StatefulWidget {
  const DeviceInfoPage({super.key});

  @override
  State<DeviceInfoPage> createState() => _DeviceInfoPageState();
}

class _DeviceInfoPageState extends State<DeviceInfoPage> {
  SystemInfo? _systemInfo;
  PackageInfo? _packageInfo;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final systemInfo = await DeviceInfoChannel.getSystemInfo();
      final packageInfo = await PackageInfo.fromPlatform();

      setState(() {
        _systemInfo = systemInfo;
        _packageInfo = packageInfo;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = '获取设备信息失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('硬件环境信息'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDeviceInfo,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDeviceInfo,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _buildContent(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_systemInfo == null) return const SizedBox();

    final deviceInfo = _systemInfo!.deviceInfo;
    final platformInfo = _systemInfo!.platformInfo;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 应用信息卡片
        if (_packageInfo != null) ...[
          _buildSection(
            title: '应用信息',
            icon: Icons.apps,
            color: Colors.blue,
            children: [
              _buildInfoRow('应用名称', _packageInfo!.appName),
              _buildInfoRow('包名', _packageInfo!.packageName),
              _buildInfoRow('版本号', _packageInfo!.version),
              _buildInfoRow('构建号', _packageInfo!.buildNumber),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // 设备信息卡片
        _buildSection(
          title: '设备信息',
          icon: Icons.phone_android,
          color: Colors.green,
          children: [
            _buildInfoRow('制造商', deviceInfo.manufacturer),
            _buildInfoRow('型号', deviceInfo.model),
            _buildInfoRow('品牌', deviceInfo.brand),
            _buildInfoRow('设备代号', deviceInfo.device),
          ],
        ),
        const SizedBox(height: 16),

        // 系统信息卡片
        _buildSection(
          title: '系统信息',
          icon: Icons.settings_system_daydream,
          color: Colors.orange,
          children: [
            _buildInfoRow('操作系统', platformInfo['operatingSystem'] ?? 'Unknown'),
            _buildInfoRow('系统版本', platformInfo['operatingSystemVersion'] ?? 'Unknown'),
            _buildInfoRow('Android版本', 'API ${deviceInfo.sdkVersion}'),
            _buildInfoRow('语言区域', platformInfo['localeName'] ?? 'Unknown'),
          ],
        ),
        const SizedBox(height: 16),

        // 处理器信息卡片
        _buildSection(
          title: '处理器信息',
          icon: Icons.memory,
          color: Colors.purple,
          children: [
            _buildInfoRow('CPU架构', deviceInfo.cpuAbi),
            _buildInfoRow('CPU核心数', '${platformInfo['numberOfProcessors'] ?? 0}核'),
          ],
        ),
        const SizedBox(height: 16),

        // 内存信息卡片
        _buildSection(
          title: '内存信息',
          icon: Icons.storage,
          color: Colors.red,
          children: [
            _buildInfoRow('总内存', deviceInfo.formatMemory(deviceInfo.totalMemory)),
            _buildInfoRow('可用内存', deviceInfo.formatMemory(deviceInfo.availableMemory)),
            _buildProgressRow(
              '内存使用率',
              deviceInfo.memoryUsagePercent,
              Colors.red,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 存储信息卡片
        _buildSection(
          title: '存储信息',
          icon: Icons.sd_storage,
          color: Colors.teal,
          children: [
            _buildInfoRow('总存储', deviceInfo.formatMemory(deviceInfo.totalStorage)),
            _buildInfoRow('可用存储', deviceInfo.formatMemory(deviceInfo.availableStorage)),
            _buildProgressRow(
              '存储使用率',
              deviceInfo.storageUsagePercent,
              Colors.teal,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 屏幕信息卡片
        _buildSection(
          title: '屏幕信息',
          icon: Icons.screen_lock_portrait,
          color: Colors.indigo,
          children: [
            _buildInfoRow('分辨率', '${deviceInfo.screenWidth} x ${deviceInfo.screenHeight}'),
            _buildInfoRow('屏幕密度', '${deviceInfo.screenDensity} dpi'),
            _buildInfoRow(
              '屏幕等级',
              _getScreenDensityCategory(deviceInfo.screenDensity),
            ),
          ],
        ),

        const SizedBox(height: 32),

        // 导出按钮
        ElevatedButton.icon(
          onPressed: _exportInfo,
          icon: const Icon(Icons.upload_file),
          label: const Text('导出完整信息'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow(String label, double percent, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              Text(
                '${percent.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  String _getScreenDensityCategory(int dpi) {
    if (dpi >= 640) return 'XXXHDPI (超超高清)';
    if (dpi >= 480) return 'XXHDPI (超高清)';
    if (dpi >= 320) return 'XHDPI (高清)';
    if (dpi >= 240) return 'HDPI (中高清)';
    if (dpi >= 160) return 'MDPI (标清)';
    return 'LDPI (低清)';
  }

  void _exportInfo() {
    if (_systemInfo == null) return;

    final text = _systemInfo.toString();

    // 显示导出选项对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设备信息'),
        content: SingleChildScrollView(
          child: SelectableText(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
