import 'dart:io';

import 'package:flutter/material.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/widgets/enhanced_delete_dialog.dart';
import 'package:easyfile/ui/widgets/folder_picker_dialog.dart';
import 'package:easyfile/utils/path_security.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';

/// 批量操作服务
///
/// 提供文件/文件夹的批量操作功能，包括：
/// - 批量收藏/取消收藏
/// - 批量删除
/// - 批量移动
/// - 批量复制
/// - 批量重命名（单个）
/// - 批量分享
class BatchOperationsService {
  final BuildContext context;
  final FileViewModel viewModel;
  final FilePresenter presenter;
  final VoidCallback onRefresh;
  final VoidCallback onExitSelectionMode;

  BatchOperationsService({
    required this.context,
    required this.viewModel,
    required this.presenter,
    required this.onRefresh,
    required this.onExitSelectionMode,
  });

  /// 检查选中的文件是否全部已收藏
  bool isAllSelectedFavorite(Set<String> selectedItems) {
    if (selectedItems.isEmpty) return false;
    return selectedItems.every((path) => viewModel.isFavoriteFile(path));
  }

  /// 批量添加/取消收藏
  Future<void> batchToggleFavorite(Set<String> selectedItems) async {
    if (selectedItems.isEmpty) return;

    final allFavorite = isAllSelectedFavorite(selectedItems);
    final action = allFavorite ? '取消收藏' : '添加到收藏';

    int successCount = 0;
    int failCount = 0;

    for (final path in selectedItems) {
      // 只处理文件，跳过文件夹
      final entity = FileSystemEntity.typeSync(path);
      if (entity != FileSystemEntityType.file) continue;

      try {
        final file = FileItem(
          name: path.split(Platform.pathSeparator).last,
          path: path,
          size: File(path).lengthSync(),
          modified: File(path).lastModifiedSync(),
          isDirectory: false,
        );

        if (allFavorite) {
          // 全部已收藏，则取消收藏
          await presenter.toggleFavoriteFile(file);
          successCount++;
        } else {
          // 有未收藏的，则添加收藏
          final isFav = viewModel.isFavoriteFile(path);
          if (!isFav) {
            await presenter.toggleFavoriteFile(file);
            successCount++;
          }
        }
      } catch (e) {
        logger.e('Failed to toggle favorite: $path, error: $e');
        failCount++;
      }
    }

    if (!_isMounted) return;

    final message = failCount > 0
        ? '$action完成：成功 $successCount 个，失败 $failCount 个'
        : '已$action $successCount 个文件';

    _showSnackBar(message);

    // 操作完成后退出选择模式
    onExitSelectionMode();
  }

  /// 批量删除
  Future<void> batchDelete(Set<String> selectedItems) async {
    if (selectedItems.isEmpty) return;

    // 🔒 安全检查：验证所有选中项是否允许删除
    for (final path in selectedItems) {
      final riskLevel = PathSecurity.getPathRiskLevel(path);

      if (riskLevel == PathRiskLevel.forbidden ||
          riskLevel == PathRiskLevel.danger) {
        final fileName = path.split(Platform.pathSeparator).last;
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🛑 禁止删除'),
            content: Text(
              '选中的文件包含受保护的系统目录 "$fileName"！\n\n'
              '删除系统目录会导致：\n'
              '• 系统功能损坏\n'
              '• 应用无法运行\n'
              '• 数据永久丢失\n\n'
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
        logger.w('Delete blocked by UI: $path (Risk: ${riskLevel.name})');
        return;
      }

      // 检查是否为系统关键文件夹
      final fileName = path.split(Platform.pathSeparator).last;
      if (PathSecurity.isSystemFolderName(fileName)) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🔒 禁止删除'),
            content: Text(
              '"$fileName" 是系统重要文件夹！\n\n'
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
        logger.w('Delete blocked: "$fileName" is a system folder');
        return;
      }
    }

    // 统计文件和文件夹数量
    int fileCount = 0;
    int folderCount = 0;
    for (final path in selectedItems) {
      final entity = FileSystemEntity.typeSync(path);
      if (entity == FileSystemEntityType.directory) {
        folderCount++;
      } else if (entity == FileSystemEntityType.file) {
        fileCount++;
      }
    }

    // 使用增强的删除确认对话框
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final confirmed = await EnhancedDeleteDialog.showBatchDeleteConfirmation(
      context: context,
      paths: selectedItems.toList(),
      fileCount: fileCount,
      folderCount: folderCount,
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
      int successCount = 0;
      int failCount = 0;

      for (final path in selectedItems) {
        try {
          // 🔒 记录操作日志
          final riskLevel = PathSecurity.getPathRiskLevel(path);
          PathSecurity.logOperation(
            operation: 'DELETE (UI)',
            path: path,
            riskLevel: riskLevel,
            allowed: true,
          );

          final entity = FileSystemEntity.typeSync(path);
          if (entity == FileSystemEntityType.directory) {
            await Directory(path).delete(recursive: true);
          } else if (entity == FileSystemEntityType.file) {
            await File(path).delete();
          }
          successCount++;
        } catch (e) {
          logger.e('Failed to delete: $path, error: $e');
          failCount++;
        }
      }

      if (!_isMounted) return;
      navigator.pop(); // 关闭进度对话框

      // 刷新文件列表
      onRefresh();

      // 退出多选模式
      onExitSelectionMode();

      // 显示结果提示
      if (failCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功删除 $successCount 项'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功删除 $successCount 项，失败 $failCount 项'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!_isMounted) return;
      navigator.pop(); // 关闭进度对话框
      messenger.showSnackBar(
        SnackBar(content: Text('删除失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 批量移动
  Future<void> batchMove(Set<String> selectedItems, String currentPath) async {
    if (selectedItems.isEmpty) return;

    // 🔒 安全检查：验证所有选中项是否允许移动
    for (final path in selectedItems) {
      final riskLevel = PathSecurity.getPathRiskLevel(path);

      if (riskLevel == PathRiskLevel.forbidden ||
          riskLevel == PathRiskLevel.danger) {
        final fileName = path.split(Platform.pathSeparator).last;
        _showErrorSnackBar('无法移动 "$fileName"：这是受保护的系统目录');
        logger.w('Move blocked by UI: $path (Risk: ${riskLevel.name})');
        return;
      }

      // 检查是否为系统关键文件夹
      final fileName = path.split(Platform.pathSeparator).last;
      if (PathSecurity.isSystemFolderName(fileName)) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🔒 禁止移动'),
            content: Text(
              '"$fileName" 是系统重要文件夹！\n\n'
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
        logger.w('Move blocked: "$fileName" is a system folder');
        return;
      }
    }

    // 显示文件夹选择对话框
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final destinationPath = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(currentPath: currentPath),
    );

    if (destinationPath == null || !_isMounted) return;

    // 检查是否移动到相同目录
    for (final path in selectedItems) {
      final sourceDir = Directory(path).parent.path;
      if (sourceDir == destinationPath) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('无法移动：目标位置与源位置相同'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    // 🔒 验证目标路径安全性
    final targetRiskLevel = PathSecurity.getPathRiskLevel(destinationPath);
    if (targetRiskLevel == PathRiskLevel.forbidden ||
        targetRiskLevel == PathRiskLevel.danger) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('目标位置不安全，无法移动文件'),
          backgroundColor: Colors.red,
        ),
      );
      logger.w('Move blocked: target path $destinationPath is protected');
      return;
    }

    // 检查是否要移动到子目录（会造成循环）
    for (final path in selectedItems) {
      if (FileSystemEntity.typeSync(path) == FileSystemEntityType.directory) {
        if (destinationPath.startsWith(path + Platform.pathSeparator) ||
            destinationPath == path) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('不能将文件夹移动到自己的子目录中'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
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
      int successCount = 0;
      int failCount = 0;

      for (final path in selectedItems) {
        try {
          final entity = FileSystemEntity.typeSync(path);
          final baseName = path.split(Platform.pathSeparator).last;
          final targetPath =
              '$destinationPath${Platform.pathSeparator}$baseName';

          // 🔒 记录操作日志
          final riskLevel = PathSecurity.getPathRiskLevel(path);
          PathSecurity.logOperation(
            operation: 'MOVE (UI)',
            path: '$path -> $targetPath',
            riskLevel: riskLevel,
            allowed: true,
          );

          if (entity == FileSystemEntityType.directory) {
            await Directory(path).rename(targetPath);
          } else if (entity == FileSystemEntityType.file) {
            await File(path).rename(targetPath);
          }
          successCount++;
        } catch (e) {
          logger.e('Failed to move: $path, error: $e');
          failCount++;
        }
      }

      if (!_isMounted) return;
      navigator.pop();
      onRefresh();
      onExitSelectionMode();

      if (failCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功移动 $successCount 项'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功移动 $successCount 项，失败 $failCount 项'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!_isMounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('移动失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 批量复制
  Future<void> batchCopy(Set<String> selectedItems, String currentPath) async {
    if (selectedItems.isEmpty) return;

    // 🔒 安全检查：验证所有源文件是否允许复制
    for (final sourcePath in selectedItems) {
      final riskLevel = PathSecurity.getPathRiskLevel(sourcePath);
      if (riskLevel == PathRiskLevel.forbidden ||
          riskLevel == PathRiskLevel.danger) {
        final fileName = sourcePath.split(Platform.pathSeparator).last;
        _showErrorSnackBar('无法复制 "$fileName"：这是受保护的系统目录');
        logger.w('Copy blocked by UI: $sourcePath (Risk: ${riskLevel.name})');
        return;
      }
    }

    // 显示文件夹选择对话框
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final destinationPath = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(currentPath: currentPath),
    );

    if (destinationPath == null || !_isMounted) return;

    // 🔒 验证目标路径安全性
    final targetRiskLevel = PathSecurity.getPathRiskLevel(destinationPath);
    if (targetRiskLevel == PathRiskLevel.forbidden ||
        targetRiskLevel == PathRiskLevel.danger) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('目标位置不安全，无法复制文件'),
          backgroundColor: Colors.red,
        ),
      );
      logger.w('Copy blocked: target path $destinationPath is protected');
      return;
    }

    // 显示进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('正在复制 ${selectedItems.length} 项...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    int successCount = 0;
    int failCount = 0;
    final List<String> failedItems = [];

    try {
      for (final sourcePath in selectedItems) {
        try {
          final entity = FileSystemEntity.typeSync(sourcePath);
          final baseName = sourcePath.split(Platform.pathSeparator).last;
          var targetPath = '$destinationPath${Platform.pathSeparator}$baseName';

          // 如果目标路径已存在，自动重命名
          if (FileSystemEntity.typeSync(targetPath) !=
              FileSystemEntityType.notFound) {
            final sourceDir = Directory(sourcePath).parent.path;
            if (sourceDir == destinationPath) {
              // 复制到相同目录，自动重命名
              final ext = baseName.contains('.')
                  ? baseName.substring(baseName.lastIndexOf('.'))
                  : '';
              final nameWithoutExt = ext.isNotEmpty
                  ? baseName.substring(0, baseName.lastIndexOf('.'))
                  : baseName;
              var counter = 1;
              do {
                targetPath =
                    '$destinationPath${Platform.pathSeparator}${nameWithoutExt}_副本$counter$ext';
                counter++;
              } while (FileSystemEntity.typeSync(targetPath) !=
                  FileSystemEntityType.notFound);
            } else {
              // 不同目录且已存在，跳过
              failedItems.add(baseName);
              failCount++;
              logger.w('File already exists: $targetPath');
              continue;
            }
          }

          if (entity == FileSystemEntityType.directory) {
            // 递归复制文件夹
            await _copyDirectory(Directory(sourcePath), Directory(targetPath));
          } else if (entity == FileSystemEntityType.file) {
            await File(sourcePath).copy(targetPath);
          }

          successCount++;
        } catch (e) {
          final baseName = sourcePath.split(Platform.pathSeparator).last;
          failedItems.add(baseName);
          failCount++;
          logger.e('Failed to copy $sourcePath: $e');
        }
      }

      if (!_isMounted) return;
      navigator.pop();
      onRefresh();
      onExitSelectionMode();

      // 显示结果
      if (failCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功复制 $successCount 项'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '复制完成：成功 $successCount 项，失败 $failCount 项${failedItems.isNotEmpty ? "\n失败项: ${failedItems.take(3).join(", ")}${failedItems.length > 3 ? "..." : ""}" : ""}',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!_isMounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('复制失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 递归复制文件夹
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }

    await for (final entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDirectory = Directory(
          '${destination.path}${Platform.pathSeparator}${entity.path.split(Platform.pathSeparator).last}',
        );
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy(
          '${destination.path}${Platform.pathSeparator}${entity.path.split(Platform.pathSeparator).last}',
        );
      }
    }
  }

  /// 批量重命名（仅支持单个文件/文件夹）
  Future<void> batchRename(Set<String> selectedItems) async {
    if (selectedItems.length != 1) return;

    final sourcePath = selectedItems.first;
    final entity = FileSystemEntity.typeSync(sourcePath);
    final currentName = sourcePath.split(Platform.pathSeparator).last;
    final isDirectory = entity == FileSystemEntityType.directory;

    // 🔒 安全检查：验证是否允许重命名
    final riskLevel = PathSecurity.getPathRiskLevel(sourcePath);

    // 禁止重命名系统关键目录
    if (riskLevel == PathRiskLevel.forbidden ||
        riskLevel == PathRiskLevel.danger) {
      if (!_isMounted) return;
      _showErrorSnackBar(
        PathSecurity.getOperationDeniedMessage(sourcePath, '重命名'),
      );
      logger.w('Rename blocked by UI: $sourcePath (Risk: ${riskLevel.name})');
      return;
    }

    // 检查是否为系统关键文件夹名称
    if (PathSecurity.isSystemFolderName(currentName)) {
      if (!_isMounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🔒 禁止重命名'),
          content: Text(
            '"$currentName" 是系统重要文件夹！\n\n'
            '重命名此文件夹会导致：\n'
            '• 系统功能异常\n'
            '• 应用无法访问文件\n'
            '• 媒体库损坏\n\n'
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
      logger.w('Rename blocked: "$currentName" is a system folder');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // 显示重命名对话框
    final TextEditingController controller = TextEditingController(
      text: currentName,
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isDirectory ? '重命名文件夹' : '重命名文件'),
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

    if (newName == null || newName.trim().isEmpty || !_isMounted) return;
    if (newName == currentName) return;

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
      final parentPath = sourcePath.substring(
        0,
        sourcePath.lastIndexOf(Platform.pathSeparator),
      );
      final targetPath =
          '$parentPath${Platform.pathSeparator}${newName.trim()}';

      // 检查目标文件名是否已存在
      if (FileSystemEntity.typeSync(targetPath) !=
          FileSystemEntityType.notFound) {
        if (!_isMounted) return;
        navigator.pop(); // 关闭进度对话框
        messenger.showSnackBar(
          SnackBar(
            content: Text('重命名失败：名称"${newName.trim()}"已存在'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // 🔒 验证目标路径安全性
      final targetRiskLevel = PathSecurity.getPathRiskLevel(targetPath);
      if (targetRiskLevel == PathRiskLevel.forbidden ||
          targetRiskLevel == PathRiskLevel.danger) {
        if (!_isMounted) return;
        Navigator.pop(context); // 关闭进度对话框
        _showErrorSnackBar('重命名失败：目标路径不安全');
        logger.w('Rename blocked: target path $targetPath is protected');
        return;
      }

      // 🔒 记录操作日志
      PathSecurity.logOperation(
        operation: 'RENAME (UI)',
        path: '$sourcePath -> $targetPath',
        riskLevel: riskLevel,
        allowed: true,
      );

      if (entity == FileSystemEntityType.directory) {
        await Directory(sourcePath).rename(targetPath);
      } else if (entity == FileSystemEntityType.file) {
        await File(sourcePath).rename(targetPath);
      }

      if (!_isMounted) return;
      navigator.pop();
      onRefresh();
      onExitSelectionMode();

      messenger.showSnackBar(
        const SnackBar(content: Text('重命名成功'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!_isMounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('重命名失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 批量分享
  Future<void> batchShare(Set<String> selectedItems) async {
    if (selectedItems.isEmpty) return;

    // 只分享文件，过滤掉文件夹
    final filePaths = selectedItems.where((path) {
      return FileSystemEntity.typeSync(path) == FileSystemEntityType.file;
    }).toList();

    if (filePaths.isEmpty) {
      _showErrorSnackBar('请选择至少一个文件进行分享', Colors.orange);
      return;
    }

    try {
      // Capture messenger before awaiting presenter
      final messenger = ScaffoldMessenger.of(context);

      // 使用presenter批量分享
      final success = await presenter.batchShareFiles(filePaths);

      if (!_isMounted) return;
      if (success) {
        // 分享成功后退出多选模式
        onExitSelectionMode();
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('分享失败，请检查是否有有效的文件'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      logger.e('Failed to share files: $e');
      if (!_isMounted) return;
      _showErrorSnackBar('分享失败：$e');
    }
  }

  // ========== 辅助方法 ==========

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
}
