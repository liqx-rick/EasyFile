import 'dart:io';

import 'package:flutter/material.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/widgets/enhanced_delete_dialog.dart';
import 'package:easyfile/ui/widgets/folder_picker_dialog.dart';
import 'package:easyfile/utils/path_security.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';

/// 单文件操作服务
///
/// 为文件预览页提供单个文件的操作功能，包括：
/// - 收藏/取消收藏
/// - 重命名
/// - 删除
/// - 移动
/// - 复制
/// - 分享
///
/// 复用 FilePresenter 的单文件操作方法和 BatchOperationsService 的 UI 逻辑
class SingleFileOperationsService {
  final BuildContext context;
  final FileViewModel viewModel;
  final FilePresenter presenter;
  final VoidCallback? onRefresh;
  final VoidCallback? onFileDeleted; // 文件被删除后的回调（通常需要关闭预览页）

  SingleFileOperationsService({
    required this.context,
    required this.viewModel,
    required this.presenter,
    this.onRefresh,
    this.onFileDeleted,
  });

  bool get _isMounted {
    try {
      return context.mounted;
    } catch (_) {
      return false;
    }
  }

  void _showSnackBar(String message, {Duration? duration}) {
    if (!_isMounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration ?? const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message, [Color? backgroundColor]) {
    if (!_isMounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor ?? Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 切换文件收藏状态
  Future<void> toggleFavorite(FileItem file) async {
    try {
      final wasOriginallyFavorite = viewModel.isFavoriteFile(file.path);

      // 调用 presenter 的单文件收藏方法
      // 返回值是新的收藏状态：true=已收藏，false=未收藏
      final newFavoriteState = await presenter.toggleFavoriteFile(file);

      if (!_isMounted) return;

      // 判断操作是否成功：状态发生了变化
      final operationSucceeded = (newFavoriteState != wasOriginallyFavorite);

      if (operationSucceeded) {
        _showSnackBar(newFavoriteState ? '已添加到收藏' : '已取消收藏');
        onRefresh?.call();
      } else {
        final action = wasOriginallyFavorite ? '取消收藏' : '添加到收藏';
        _showErrorSnackBar('$action失败');
      }
    } catch (e) {
      logger.e('Toggle favorite failed: $e');
      if (_isMounted) {
        _showErrorSnackBar('操作失败：$e');
      }
    }
  }

  /// 分享文件
  Future<void> shareFile(FileItem file) async {
    if (file.isDirectory) {
      _showErrorSnackBar('无法分享文件夹', Colors.orange);
      return;
    }

    try {
      final success = await presenter.batchShareFiles([file.path]);

      if (!_isMounted) return;

      if (!success) {
        _showErrorSnackBar('分享失败，请检查文件是否存在');
      }
    } catch (e) {
      logger.e('Share file failed: $e');
      if (_isMounted) {
        _showErrorSnackBar('分享失败：$e');
      }
    }
  }

  /// 重命名文件
  ///
  /// 返回 true 表示重命名成功，需要刷新父页面
  Future<bool> renameFile(FileItem file) async {
    // 🔒 安全检查
    final riskLevel = PathSecurity.getPathRiskLevel(file.path);
    if (riskLevel == PathRiskLevel.forbidden ||
        riskLevel == PathRiskLevel.danger) {
      _showErrorSnackBar(
        PathSecurity.getOperationDeniedMessage(file.path, '重命名'),
      );
      logger.w('Rename blocked: ${file.path} (Risk: ${riskLevel.name})');
      return false;
    }

    if (PathSecurity.isSystemFolderName(file.name)) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🔒 禁止重命名'),
          content: Text(
            '"${file.name}" 是系统重要文件夹！\n\n'
            '重命名此文件夹会导致系统功能异常。\n\n'
            '为保护您的设备，此操作已被阻止。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
      return false;
    }

    // 显示重命名对话框
    final controller = TextEditingController(text: file.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.isDirectory ? '重命名文件夹' : '重命名文件'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '新名称',
            hintText: '请输入新名称',
          ),
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
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (newName == null || newName.trim().isEmpty || !_isMounted) return false;
    if (newName == file.name) return false;

    // 显示进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在重命名...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final success = await presenter.renameFile(file, newName.trim());

      if (!_isMounted) return false;
      Navigator.of(context).pop(); // 关闭进度对话框

      if (success) {
        _showSnackBar('重命名成功');
        onRefresh?.call();
        return true; // 返回 true 表示需要刷新父页面
      } else {
        _showErrorSnackBar('重命名失败');
        return false;
      }
    } catch (e) {
      if (!_isMounted) return false;
      Navigator.of(context).pop();
      _showErrorSnackBar('重命名失败：$e');
      return false;
    }
  }

  /// 删除文件
  Future<void> deleteFile(FileItem file) async {
    // 🔒 安全检查
    final riskLevel = PathSecurity.getPathRiskLevel(file.path);
    if (riskLevel == PathRiskLevel.forbidden ||
        riskLevel == PathRiskLevel.danger) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🛑 禁止删除'),
          content: Text(
            '"${file.name}" 是受保护的系统目录！\n\n'
            '删除系统目录会导致系统功能损坏。\n\n'
            '为保护您的设备，此操作已被阻止。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
      logger.w('Delete blocked: ${file.path} (Risk: ${riskLevel.name})');
      return;
    }

    if (PathSecurity.isSystemFolderName(file.name)) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🔒 禁止删除'),
          content: Text(
            '"${file.name}" 是系统重要文件夹！\n\n'
            '删除此文件夹会导致系统功能异常。\n\n'
            '为保护您的设备，此操作已被阻止。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
      return;
    }

    // 使用增强的删除确认对话框
    final confirmed = await EnhancedDeleteDialog.showSingleDeleteConfirmation(
      context: context,
      path: file.path,
    );

    if (!confirmed || !_isMounted) return;

    // 显示进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在删除...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      // 🔒 记录操作日志
      PathSecurity.logOperation(
        operation: 'DELETE (Preview)',
        path: file.path,
        riskLevel: riskLevel,
        allowed: true,
      );

      final success = await presenter.deleteFile(file);

      if (!_isMounted) return;
      Navigator.of(context).pop(); // 关闭进度对话框

      if (success) {
        _showSnackBar('删除成功');
        // 文件删除成功，通知调用者（通常需要关闭预览页）
        onFileDeleted?.call();
      } else {
        _showErrorSnackBar('删除失败');
      }
    } catch (e) {
      if (!_isMounted) return;
      Navigator.of(context).pop();
      _showErrorSnackBar('删除失败：$e');
    }
  }

  /// 移动文件
  ///
  /// 返回 true 表示移动成功，需要刷新父页面
  Future<bool> moveFile(FileItem file) async {
    // 🔒 安全检查
    final riskLevel = PathSecurity.getPathRiskLevel(file.path);
    if (riskLevel == PathRiskLevel.forbidden ||
        riskLevel == PathRiskLevel.danger) {
      _showErrorSnackBar('无法移动 "${file.name}"：这是受保护的系统目录');
      logger.w('Move blocked: ${file.path} (Risk: ${riskLevel.name})');
      return false;
    }

    if (PathSecurity.isSystemFolderName(file.name)) {
      if (!_isMounted) return false;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🔒 禁止移动'),
          content: Text(
            '"${file.name}" 是系统重要文件夹！\n\n'
            '移动此文件夹会导致系统功能异常。\n\n'
            '为保护您的设备，此操作已被阻止。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
      return false;
    }

    // 获取当前文件所在目录
    final currentPath = Directory(file.path).parent.path;

    // 确保 widget 仍然挂载后再显示对话框
    if (!_isMounted) return false;

    // 显示文件夹选择对话框
    final destinationPath = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(
        currentPath: currentPath,
        sourceFileName: file.name,
        operationType: '移动',
      ),
    );

    if (destinationPath == null || !_isMounted) return false;

    // 检查是否移动到相同目录
    if (currentPath == destinationPath) {
      _showSnackBar('无法移动：目标位置与源位置相同', duration: const Duration(seconds: 2));
      return false;
    }

    // 🔒 验证目标路径安全性
    final targetRiskLevel = PathSecurity.getPathRiskLevel(destinationPath);
    if (targetRiskLevel == PathRiskLevel.forbidden ||
        targetRiskLevel == PathRiskLevel.danger) {
      _showErrorSnackBar('目标位置不安全，无法移动文件');
      logger.w('Move blocked: target path $destinationPath is protected');
      return false;
    }

    // 检查是否要移动到子目录（会造成循环）
    if (file.isDirectory) {
      if (destinationPath.startsWith(file.path + Platform.pathSeparator) ||
          destinationPath == file.path) {
        _showErrorSnackBar('不能将文件夹移动到自己的子目录中');
        return false;
      }
    }

    // 显示进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在移动...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      // 🔒 记录操作日志
      PathSecurity.logOperation(
        operation: 'MOVE (Preview)',
        path: '${file.path} -> $destinationPath',
        riskLevel: riskLevel,
        allowed: true,
      );

      final success = await presenter.moveFile(file, destinationPath);

      if (!_isMounted) return false;
      Navigator.of(context).pop(); // 关闭进度对话框

      if (success) {
        _showSnackBar('移动成功');
        onRefresh?.call();
        return true;
      } else {
        _showErrorSnackBar('移动失败');
        return false;
      }
    } catch (e) {
      if (!_isMounted) return false;
      Navigator.of(context).pop();
      _showErrorSnackBar('移动失败：$e');
      return false;
    }
  }

  /// 复制文件
  ///
  /// 返回 true 表示复制成功，需要刷新父页面
  Future<bool> copyFile(FileItem file) async {
    // 🔒 安全检查
    final riskLevel = PathSecurity.getPathRiskLevel(file.path);
    if (riskLevel == PathRiskLevel.forbidden ||
        riskLevel == PathRiskLevel.danger) {
      _showErrorSnackBar('无法复制 "${file.name}"：这是受保护的系统目录');
      logger.w('Copy blocked: ${file.path} (Risk: ${riskLevel.name})');
      return false;
    }

    // 获取当前文件所在目录
    final currentPath = Directory(file.path).parent.path;

    // 确保 widget 仍然挂载后再显示对话框
    if (!_isMounted) return false;

    // 显示文件夹选择对话框
    final destinationPath = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(
        currentPath: currentPath,
        sourceFileName: file.name,
        operationType: '复制',
      ),
    );

    if (destinationPath == null || !_isMounted) return false;

    // 🔒 验证目标路径安全性
    final targetRiskLevel = PathSecurity.getPathRiskLevel(destinationPath);
    if (targetRiskLevel == PathRiskLevel.forbidden ||
        targetRiskLevel == PathRiskLevel.danger) {
      _showErrorSnackBar('目标位置不安全，无法复制文件');
      logger.w('Copy blocked: target path $destinationPath is protected');
      return false;
    }

    // 显示进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在复制...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final success = await presenter.copyFile(file, destinationPath);

      if (!_isMounted) return false;
      Navigator.of(context).pop(); // 关闭进度对话框

      if (success) {
        _showSnackBar('复制成功');
        onRefresh?.call();
        return true;
      } else {
        _showErrorSnackBar('复制失败');
        return false;
      }
    } catch (e) {
      if (!_isMounted) return false;
      Navigator.of(context).pop();
      _showErrorSnackBar('复制失败：$e');
      return false;
    }
  }

  /// 显示文件详细信息
  Future<void> showFileDetails(FileItem file) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('文件详情'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('名称', file.name),
              const Divider(),
              _buildDetailRow(
                  '类型', file.isDirectory ? '文件夹' : _getFileType(file.name)),
              const Divider(),
              _buildDetailRow(
                  '大小', FileSizeFormatter.formatBytesWithSpace(file.size)),
              const Divider(),
              _buildDetailRow('路径', file.path),
              const Divider(),
              _buildDetailRow('修改时间', _formatDateTime(file.modified)),
            ],
          ),
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  String _getFileType(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.') + 1).toUpperCase()
        : '未知';
    return '$ext 文件';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}
