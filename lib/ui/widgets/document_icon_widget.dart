import 'package:flutter/material.dart';
import '../../utils/file_utils.dart';

/// 文档图标组件 - 根据文档类型显示不同颜色的图标
class DocumentIconWidget extends StatelessWidget {
  final String fileName;
  final double size;

  const DocumentIconWidget({super.key, required this.fileName, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final iconData = _getDocumentIcon();
    final color = _getDocumentColor();
    final label = _getDocumentLabel();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(iconData, color: Colors.white, size: size * 0.45),
          if (label.isNotEmpty) ...[
            SizedBox(height: size * 0.05),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 获取文档图标
  IconData _getDocumentIcon() {
    if (FileUtils.isPdfFile(fileName)) {
      return Icons.picture_as_pdf;
    } else if (FileUtils.isWordFile(fileName)) {
      return Icons.description;
    } else if (FileUtils.isExcelFile(fileName)) {
      return Icons.table_chart;
    } else if (FileUtils.isPowerPointFile(fileName)) {
      return Icons.slideshow;
    } else if (FileUtils.isTextFile(fileName)) {
      return Icons.text_snippet;
    } else if (FileUtils.isArchiveFile(fileName)) {
      return Icons.folder_zip;
    } else {
      return Icons.insert_drive_file;
    }
  }

  /// 获取文档颜色
  Color _getDocumentColor() {
    if (FileUtils.isPdfFile(fileName)) {
      return const Color(0xFFE53935); // 红色 - PDF
    } else if (FileUtils.isWordFile(fileName)) {
      return const Color(0xFF1976D2); // 蓝色 - Word
    } else if (FileUtils.isExcelFile(fileName)) {
      return const Color(0xFF388E3C); // 绿色 - Excel
    } else if (FileUtils.isPowerPointFile(fileName)) {
      return const Color(0xFFFF6F00); // 橙色 - PowerPoint
    } else if (FileUtils.isTextFile(fileName)) {
      return const Color(0xFF757575); // 灰色 - 文本
    } else if (FileUtils.isArchiveFile(fileName)) {
      return const Color(0xFF6A1B9A); // 紫色 - 压缩包
    } else {
      return const Color(0xFF90A4AE); // 浅灰色 - 其他
    }
  }

  /// 获取文档标签
  String _getDocumentLabel() {
    final ext = fileName.toLowerCase().split('.').last;
    if (FileUtils.isPdfFile(fileName)) {
      return 'PDF';
    } else if (FileUtils.isWordFile(fileName)) {
      return ext.toUpperCase();
    } else if (FileUtils.isExcelFile(fileName)) {
      return ext.toUpperCase();
    } else if (FileUtils.isPowerPointFile(fileName)) {
      return ext.toUpperCase();
    } else if (FileUtils.isTextFile(fileName)) {
      return ext.toUpperCase();
    } else if (FileUtils.isArchiveFile(fileName)) {
      return ext.toUpperCase();
    } else {
      return '';
    }
  }
}

/// 文档图标组件 - 圆角版本（用于列表视图）
class DocumentIconWidgetRounded extends StatelessWidget {
  final String fileName;
  final double size;

  const DocumentIconWidgetRounded({
    super.key,
    required this.fileName,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final iconData = _getDocumentIcon();
    final color = _getDocumentColor();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(size * 0.15),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Icon(iconData, color: Colors.white, size: size * 0.6),
    );
  }

  /// 获取文档图标
  IconData _getDocumentIcon() {
    if (FileUtils.isPdfFile(fileName)) {
      return Icons.picture_as_pdf;
    } else if (FileUtils.isWordFile(fileName)) {
      return Icons.description;
    } else if (FileUtils.isExcelFile(fileName)) {
      return Icons.table_chart;
    } else if (FileUtils.isPowerPointFile(fileName)) {
      return Icons.slideshow;
    } else if (FileUtils.isTextFile(fileName)) {
      return Icons.text_snippet;
    } else if (FileUtils.isArchiveFile(fileName)) {
      return Icons.folder_zip;
    } else {
      return Icons.insert_drive_file;
    }
  }

  /// 获取文档颜色
  Color _getDocumentColor() {
    if (FileUtils.isPdfFile(fileName)) {
      return const Color(0xFFE53935); // 红色 - PDF
    } else if (FileUtils.isWordFile(fileName)) {
      return const Color(0xFF1976D2); // 蓝色 - Word
    } else if (FileUtils.isExcelFile(fileName)) {
      return const Color(0xFF388E3C); // 绿色 - Excel
    } else if (FileUtils.isPowerPointFile(fileName)) {
      return const Color(0xFFFF6F00); // 橙色 - PowerPoint
    } else if (FileUtils.isTextFile(fileName)) {
      return const Color(0xFF757575); // 灰色 - 文本
    } else if (FileUtils.isArchiveFile(fileName)) {
      return const Color(0xFF6A1B9A); // 紫色 - 压缩包
    } else {
      return const Color(0xFF90A4AE); // 浅灰色 - 其他
    }
  }
}
