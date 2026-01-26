import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/apk_info.dart';

/// APK详情页面
///
/// 显示APK的完整信息和操作按钮
class ApkDetailPage extends StatelessWidget {
  final ApkInfo apkInfo;
  final VoidCallback? onInstall;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onDelete;

  const ApkDetailPage({
    super.key,
    required this.apkInfo,
    this.onInstall,
    this.onOpenSettings,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('APK详情'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 头部信息卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 左侧：应用图标
                  _buildAppIcon(),
                  const SizedBox(width: 16),
                  // 中间：应用名称
                  Expanded(
                    child: Text(
                      apkInfo.appName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 右侧：安装状态标签
                  _buildStatusBadge(theme),
                ],
              ),
            ),

            // 基本信息
            _buildSection(
              context,
              title: '基本信息',
              children: [
                _buildInfoRow(
                  context,
                  icon: Icons.label,
                  label: '应用名称',
                  value: apkInfo.appName,
                ),
                _buildInfoRow(
                  context,
                  icon: Icons.apps,
                  label: '包名',
                  value: apkInfo.packageName,
                  copyable: true,
                  maxLines: 10,
                ),
                _buildInfoRow(
                  context,
                  icon: Icons.info,
                  label: '版本',
                  value: '${apkInfo.versionName} (${apkInfo.versionCode})',
                ),
              ],
            ),

            // 文件信息
            _buildSection(
              context,
              title: '文件信息',
              children: [
                _buildInfoRow(
                  context,
                  icon: Icons.storage,
                  label: '文件大小',
                  value: _formatFileSize(apkInfo.fileSize),
                ),
                _buildInfoRow(
                  context,
                  icon: Icons.access_time,
                  label: '修改时间',
                  value: _formatDateTime(apkInfo.modifiedTime),
                ),
                _buildInfoRow(
                  context,
                  icon: Icons.folder,
                  label: '文件路径',
                  value: apkInfo.filePath,
                  copyable: true,
                  maxLines: 10,
                ),
              ],
            ),

            // SDK信息
            _buildSection(
              context,
              title: 'SDK信息',
              children: [
                _buildInfoRow(
                  context,
                  icon: Icons.phone_android,
                  label: '最小SDK版本',
                  value: 'API ${apkInfo.minSdkVersion} (Android ${_getAndroidVersion(apkInfo.minSdkVersion)})',
                ),
                _buildInfoRow(
                  context,
                  icon: Icons.phone_android,
                  label: '目标SDK版本',
                  value: 'API ${apkInfo.targetSdkVersion} (Android ${_getAndroidVersion(apkInfo.targetSdkVersion)})',
                ),
                _buildInfoRow(
                  context,
                  icon: Icons.bug_report,
                  label: '调试模式',
                  value: apkInfo.isDebug ? '是 (Debug包)' : '否 (Release包)',
                ),
              ],
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 构建应用图标
  Widget _buildAppIcon() {
    if (apkInfo.appIconBase64 != null && apkInfo.appIconBase64!.isNotEmpty) {
      try {
        final Uint8List iconBytes = base64Decode(apkInfo.appIconBase64!);
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(
            iconBytes,
            width: 96,
            height: 96,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultIcon();
            },
          ),
        );
      } catch (e) {
        return _buildDefaultIcon();
      }
    }
    return _buildDefaultIcon();
  }

  /// 构建默认图标
  Widget _buildDefaultIcon() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.android, size: 64, color: Colors.grey),
    );
  }

  /// 构建状态标签
  Widget _buildStatusBadge(ThemeData theme) {
    final statusColor = Color(
      int.parse(apkInfo.status.colorHex.substring(1), radix: 16) + 0xFF000000,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor, width: 2),
      ),
      child: Text(
        apkInfo.status.displayName,
        style: TextStyle(
          fontSize: 14,
          color: statusColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 构建信息区块
  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Column(children: children),
        ),
      ],
    );
  }

  /// 构建信息行
  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool copyable = false,
    int maxLines = 1,
  }) {
    return InkWell(
      onTap: copyable
          ? () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已复制: $value'),
                  duration: const Duration(seconds: 1),
                ),
              );
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.end,
                      maxLines: maxLines,
                    ),
                  ),
                  if (copyable) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.copy, size: 16, color: Colors.grey[600]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// 获取Android版本名称
  String _getAndroidVersion(int apiLevel) {
    if (apiLevel >= 34) return '14+';
    if (apiLevel >= 33) return '13';
    if (apiLevel >= 32) return '12L';
    if (apiLevel >= 31) return '12';
    if (apiLevel >= 30) return '11';
    if (apiLevel >= 29) return '10';
    if (apiLevel >= 28) return '9';
    if (apiLevel >= 27) return '8.1';
    if (apiLevel >= 26) return '8.0';
    if (apiLevel >= 25) return '7.1';
    if (apiLevel >= 24) return '7.0';
    if (apiLevel >= 23) return '6.0';
    if (apiLevel >= 22) return '5.1';
    if (apiLevel >= 21) return '5.0';
    return '$apiLevel';
  }
}
