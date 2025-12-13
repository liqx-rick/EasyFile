import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

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

  /// 显示新建文件夹对话框
  Future<void> showCreateFolderDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '文件夹名称',
            hintText: '请输入文件夹名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              Navigator.pop(context, value);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await createFolder(result);
    }
  }

  /// 创建文件夹
  Future<void> createFolder(String name) async {
    try {
      // 验证文件夹名称
      if (name.contains('/') || name.contains('\\')) {
        showMessage('文件夹名称不能包含 / 或 \\');
        return;
      }

      final currentPath = getCurrentPath();
      if (currentPath.isEmpty) {
        showMessage('当前路径无效');
        return;
      }

      // 创建完整路径
      final newPath = path.join(currentPath, name);
      final dir = Directory(newPath);

      // 检查文件夹是否已存在
      if (await dir.exists()) {
        showMessage('文件夹已存在');
        return;
      }

      // 创建文件夹
      await dir.create(recursive: true);
      showMessage('文件夹创建成功');

      // 刷新列表
      await onFolderCreated();
    } catch (e) {
      showMessage('创建文件夹失败: $e');
    }
  }

  /// 显示消息提示
  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
