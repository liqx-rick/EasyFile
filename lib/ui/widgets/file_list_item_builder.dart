import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:easyfile/core/config/app_config.dart';

/// 文件列表项构建器工具类
///
/// 提供通用的文件列表项UI构建方法，可在多个页面复用（如junk_files_page、trash_files_page）
///
/// 主要功能：
/// - [buildFileThumbnail]: 根据MIME类型自动构建文件缩略图或图标
///   * 图片文件：显示实际缩略图，支持预览点击
///   * 视频文件：生成缩略图并叠加播放按钮
///   * 其他文件：显示彩色图标，支持11+种文件类型（音频、PDF、Office文档等）
/// - [truncateFileName]: 截断长文件名，保留首尾
/// - [formatRelativeDate]: 格式化相对日期（今天、昨天、N天前等）
/// - [formatDetailDate]: 格式化详细日期时间（YYYY-MM-DD HH:mm）
///
/// 设计原则：
/// - 基于trash_files_page经过打磨的实现
/// - 统一的视觉风格和交互体验
/// - 完善的错误处理和边界情况处理
class FileListItemBuilder {
  /// 构建文件缩略图或图标
  ///
  /// 根据文件类型自动选择：
  /// - 图片：显示真实缩略图（可点击预览）
  /// - 视频：生成并显示视频缩略图+播放按钮
  /// - 其他：显示带颜色背景的类型图标
  static Widget buildFileThumbnail({
    required String filePath,
    required String mimeType,
    String? fileName,
    bool isDirectory = false,
    VoidCallback? onTap,
    double size = 48.0,
  }) {
    final lowerMimeType = mimeType.toLowerCase();

    // 图片文件：显示缩略图
    if (lowerMimeType.startsWith('image/')) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.grey[200],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              File(filePath),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.image, size: 24, color: Colors.grey);
              },
            ),
          ),
        ),
      );
    }

    // 视频文件：显示视频缩略图
    if (lowerMimeType.startsWith('video/')) {
      return GestureDetector(
        onTap: onTap,
        child: FutureBuilder<String?>(
          future: VideoThumbnail.thumbnailFile(
            video: filePath,
            imageFormat: ImageFormat.JPEG,
            maxWidth: (size * 2.5).toInt(),
            quality: 75,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done &&
                snapshot.data != null) {
              return Stack(
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.grey[200],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        File(snapshot.data!),
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: EdgeInsets.all(size * 0.08),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: size * 0.4,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            // 加载中或失败时显示默认图标
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.purple[100],
              ),
              child: Icon(Icons.videocam,
                  size: size * 0.5, color: Colors.purple[700]),
            );
          },
        ),
      );
    }

    // 其他文件：根据类型显示对应图标
    return _buildFileTypeIcon(
      mimeType: lowerMimeType,
      fileName: fileName ?? '',
      isDirectory: isDirectory,
      size: size,
    );
  }

  /// 根据文件类型构建图标
  static Widget _buildFileTypeIcon({
    required String mimeType,
    required String fileName,
    required bool isDirectory,
    required double size,
  }) {
    if (isDirectory) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: Colors.blue[50],
        ),
        child: Icon(Icons.folder, size: size * 0.58, color: Colors.blue[700]),
      );
    }

    final config = AppConfig.instance.fileTypes;

    IconData icon;
    Color bgColor;
    Color iconColor;

    // 音频文件
    if (mimeType.startsWith('audio/') || config.isAudioFile(fileName)) {
      icon = Icons.audiotrack;
      bgColor = Colors.pink[50]!;
      iconColor = Colors.pink[700]!;
    }
    // PDF文档
    else if (mimeType.contains('pdf') || config.isPdfFile(fileName)) {
      icon = Icons.picture_as_pdf;
      bgColor = Colors.red[50]!;
      iconColor = Colors.red[700]!;
    }
    // Word文档
    else if (mimeType.contains('word') || config.isWordDocument(fileName)) {
      icon = Icons.description;
      bgColor = Colors.blue[50]!;
      iconColor = Colors.blue[700]!;
    }
    // Excel表格和CSV
    else if (mimeType.contains('excel') ||
        mimeType.contains('spreadsheet') ||
        mimeType.contains('csv') ||
        config.isExcelDocument(fileName)) {
      icon = Icons.table_chart;
      bgColor = Colors.green[50]!;
      iconColor = Colors.green[700]!;
    }
    // PPT演示
    else if (mimeType.contains('powerpoint') ||
        config.isPowerPointDocument(fileName)) {
      icon = Icons.slideshow;
      bgColor = Colors.orange[50]!;
      iconColor = Colors.orange[700]!;
    }
    // 文本文件
    else if ((mimeType.contains('text/') && !mimeType.contains('csv')) ||
        config.isTextFile(fileName)) {
      icon = Icons.description;
      bgColor = Colors.grey[200]!;
      iconColor = Colors.grey[800]!;
    }
    // 压缩包
    else if (mimeType.contains('zip') ||
        mimeType.contains('rar') ||
        mimeType.contains('7z') ||
        mimeType.contains('tar') ||
        config.isArchiveFile(fileName)) {
      icon = Icons.folder_zip;
      bgColor = Colors.amber[50]!;
      iconColor = Colors.amber[900]!;
    }
    // APK文件
    else if (mimeType.contains('android.package') ||
        config.isApkFile(fileName)) {
      icon = Icons.android;
      bgColor = Colors.green[50]!;
      iconColor = Colors.green[700]!;
    }
    // 代码文件
    else if (config.isCodeFile(fileName)) {
      icon = Icons.code;
      bgColor = Colors.deepPurple[50]!;
      iconColor = Colors.deepPurple[700]!;
    }
    // 配置文件
    else if (config.isConfigFile(fileName)) {
      icon = Icons.settings_applications;
      bgColor = Colors.teal[50]!;
      iconColor = Colors.teal[700]!;
    }
    // 数据库文件
    else if (config.isDatabaseFile(fileName)) {
      icon = Icons.storage;
      bgColor = Colors.indigo[50]!;
      iconColor = Colors.indigo[700]!;
    }
    // 其他文件
    else {
      icon = Icons.insert_drive_file;
      bgColor = Colors.grey[100]!;
      iconColor = Colors.grey[600]!;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: bgColor,
      ),
      child: Icon(icon, size: size * 0.5, color: iconColor),
    );
  }

  /// 截断文件名（保留首尾，中间省略）
  static String truncateFileName(String fileName, {int maxLength = 35}) {
    if (fileName.length <= maxLength) {
      return fileName;
    }

    final halfLength = (maxLength - 3) ~/ 2;
    final start = fileName.substring(0, halfLength);
    final end = fileName.substring(fileName.length - halfLength);

    return '$start...$end';
  }

  /// 格式化相对日期
  static String formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays < 1) {
      return '今天';
    } else if (diff.inDays < 2) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    } else if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()} 周前';
    } else if (diff.inDays < 365) {
      return '${(diff.inDays / 30).floor()} 个月前';
    } else {
      return '${(diff.inDays / 365).floor()} 年前';
    }
  }

  /// 格式化详细日期时间
  static String formatDetailDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
