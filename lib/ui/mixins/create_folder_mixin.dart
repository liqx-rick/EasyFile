import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:easyfile/core/logger.dart';

/// 新建文件夹功能 Mixin
///
/// 提供统一的新建文件夹对话框和创建逻辑
/// 使用此 Mixin 的页面需要：
/// - 实现 `getCurrentPath()` 方法返回当前路径
/// - 实现 `onFolderCreated()` 方法处理创建成功后的刷新逻辑
mixin CreateFolderMixin<T extends StatefulWidget> on State<T> {
  /// 获取当前路径（由子类实现）
  String getCurrentPath();

  /// 文件夹创建成功后的回调（由子类实现）
  Future<void> onFolderCreated();

  /// 验证文件夹名称
  String? _validateFolderName(String name, String currentPath) {
    if (name.trim().isEmpty) {
      return '文件夹名不能为空';
    }

    // 检查非法字符（操作系统级别的限制）
    final invalidChars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|'];
    for (final char in invalidChars) {
      if (name.contains(char)) {
        return '文件夹名不能包含以下字符：/ \\ : * ? " < > |';
      }
    }

    // 检查是否已存在同名文件夹
    final newPath = path.join(currentPath, name);
    final dir = Directory(newPath);
    if (dir.existsSync()) {
      return '该文件夹名称已存在';
    }

    return null;
  }

  /// 显示新建文件夹对话框
  Future<void> showCreateFolderDialog() async {
    final controller = TextEditingController();
    String? errorText;

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.create_new_folder, color: Colors.blue),
              SizedBox(width: 12),
              Text('创建新文件夹'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '文件夹名称',
                  hintText: '请输入文件夹名称',
                  errorText: errorText,
                  errorMaxLines: 3,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.folder),
                ),
                onChanged: (value) {
                  setDialogState(() {
                    errorText = _validateFolderName(value, getCurrentPath());
                  });
                },
                onSubmitted: (value) {
                  if (_validateFolderName(value, getCurrentPath()) == null &&
                      value.isNotEmpty) {
                    Navigator.of(context).pop(value.trim());
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: errorText == null && controller.text.isNotEmpty
                  ? () => Navigator.of(context).pop(controller.text.trim())
                  : null,
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );

    // 延迟 dispose，等待对话框关闭动画和键盘收起动画完成
    // 这避免了在对话框重建时使用已 dispose 的 controller
    await Future.delayed(const Duration(milliseconds: 300));
    controller.dispose();

    // 如果返回了文件夹名称，则创建文件夹
    if (result != null && result.isNotEmpty) {
      await createFolder(result);
    }
  }

  /// 创建文件夹
  Future<void> createFolder(String name) async {
    try {
      final currentPath = getCurrentPath();
      if (currentPath.isEmpty) {
        _showErrorDialog('无法创建文件夹', '当前路径无效', null);
        return;
      }

      // 创建完整路径
      final newPath = path.join(currentPath, name);
      final dir = Directory(newPath);

      // 创建文件夹
      await dir.create(recursive: true);
      logger.i('Folder created successfully: $newPath');

      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('文件夹 "$name" 创建成功'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // 刷新列表
      await onFolderCreated();
    } catch (e) {
      logger.e('Error creating folder: $e');
      if (mounted) {
        _showErrorDialog(
          '无法创建文件夹',
          _getErrorMessage(e),
          _getErrorSuggestion(e),
        );
      }
    }
  }

  /// 获取错误信息
  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('permission') || errorStr.contains('denied')) {
      return '没有在此位置创建文件夹的权限';
    } else if (errorStr.contains('exist')) {
      return '该文件夹已存在';
    } else if (errorStr.contains('space')) {
      return '存储空间不足';
    } else {
      return '发生未知错误：$error';
    }
  }

  /// 获取错误建议
  String? _getErrorSuggestion(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('permission') || errorStr.contains('denied')) {
      return '请选择其他位置或检查权限设置';
    } else if (errorStr.contains('exist')) {
      return '请使用其他名称或删除现有文件夹';
    } else if (errorStr.contains('space')) {
      return '请清理存储空间后重试';
    }
    return null;
  }

  /// 显示错误对话框
  void _showErrorDialog(String title, String message, String? suggestion) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.red, size: 48),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('错误原因：$message'),
            if (suggestion != null) ...[
              const SizedBox(height: 8),
              Text(
                '建议：$suggestion',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  /// 显示消息提示（保留兼容性）
  @Deprecated('Use _showErrorDialog instead')
  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
