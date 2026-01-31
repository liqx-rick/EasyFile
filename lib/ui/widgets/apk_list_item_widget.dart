import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/models/apk_info.dart';

/// APK列表项组件
///
/// 显示单个APK的详细信息和操作按钮
class ApkListItemWidget extends StatelessWidget {
  final ApkInfo apkInfo;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onStatusTap;
  final VoidCallback? onDelete;

  const ApkListItemWidget({
    super.key,
    required this.apkInfo,
    this.onTap,
    this.onLongPress,
    this.onStatusTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 应用图标
            _buildAppIcon(),
            const SizedBox(width: 12),
            // 应用信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 应用名称
                  Text(
                    apkInfo.appName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // 包名和版本
                  Text(
                    '${apkInfo.packageName} · v${apkInfo.versionName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // 文件大小、修改时间和状态按钮
                  Row(
                    children: [
                      Icon(Icons.storage, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        _formatFileSize(apkInfo.fileSize),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        _formatModifiedTime(apkInfo.modifiedTime),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const Spacer(),
                      // 状态按钮
                      _buildCompactStatusButton(theme),
                    ],
                  ),
                  if (apkInfo.isDebug) ...[
                    const SizedBox(height: 4),
                    // Debug标签
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'DEBUG',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'SDK ${apkInfo.minSdkVersion}-${apkInfo.targetSdkVersion}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
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
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            iconBytes,
            width: 48,
            height: 48,
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
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.android, size: 32, color: Colors.grey),
    );
  }

  /// 构建紧凑的状态按钮
  Widget _buildCompactStatusButton(ThemeData theme) {
    final statusColor = Color(
      int.parse(apkInfo.status.colorHex.substring(1), radix: 16) + 0xFF000000,
    );

    // 检查是否是易览文件自身的安装包且已安装
    final isSelfPackage = apkInfo.packageName == 'com.guangqi.easyfile';
    final isInstalled = apkInfo.status == ApkInstallStatus.installed ||
        apkInfo.status == ApkInstallStatus.upgradable ||
        apkInfo.status == ApkInstallStatus.signatureMismatch;
    final shouldDisable = isSelfPackage && isInstalled;

    return InkWell(
      onTap: shouldDisable ? null : onStatusTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: shouldDisable ? Colors.grey.withOpacity(0.12) : statusColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: shouldDisable ? Colors.grey.withOpacity(0.3) : statusColor.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Text(
          apkInfo.status.displayName,
          style: TextStyle(
            fontSize: 11,
            color: shouldDisable ? Colors.grey : statusColor,
            fontWeight: FontWeight.w600,
          ),
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

  /// 格式化修改时间
  String _formatModifiedTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years年前';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months月前';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }
}
