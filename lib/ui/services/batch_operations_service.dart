import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/app_trash_manager.dart';
import 'package:easyfile/core/settings/app_trash_settings.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/models/favorite_file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/widgets/enhanced_delete_dialog.dart';
import 'package:easyfile/ui/widgets/folder_picker_dialog.dart';
import 'package:easyfile/utils/path_security.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
// import 'package:easyfile/utils/thumbnail_cache_manager.dart'; // 已禁用缓存删除

/// 批量操作服务
///
/// 提供文件/文件夹的批量操作功能，包括：
/// - 批量收藏/取消收藏
/// - 批量删除
/// - 批量移动
/// - 批量复制
/// - 批量重命名（单个）
/// - 批量分享
///
/// ## BuildContext生命周期管理
///
/// 为避免"Looking up a deactivated widget's ancestor is unsafe"异常，
/// 本服务采用以下安全策略：
///
/// 1. **不存储BuildContext**：所有需要context的方法都要求调用者传入
/// 2. **调用点检查**：调用者需在调用前检查`mounted`状态
/// 3. **方法内检查**：每次使用context前都通过`_isMounted(context)`检查
/// 4. **回调保护**：`onExitSelectionMode`等回调在调用前确保widget仍然挂载
///
/// ### 典型用法
/// ```dart
/// onToggleFavorite: () {
///   if (!mounted) return;  // 调用点检查
///   batchService.batchToggleFavorite(context, selectedItems);
/// },
/// ```
class BatchOperationsService {
  final FileViewModel viewModel;
  final FilePresenter presenter;
  final VoidCallback onRefresh;
  final VoidCallback onExitSelectionMode;

  BatchOperationsService({
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
  ///
  /// 根据当前选中文件的收藏状态，智能切换添加或取消收藏操作。
  ///
  /// **关键点**：
  /// - 如果全部已收藏 → 批量取消收藏
  /// - 如果有未收藏的 → 只添加未收藏的文件（跳过已收藏和文件夹）
  /// - 异步操作后必须检查`_isMounted(context)`，防止在widget销毁后使用context
  /// - 操作成功后退出选择模式（`onExitSelectionMode()`）
  ///
  /// @param context 用于显示SnackBar的BuildContext，必须从外部传入
  /// @param selectedItems 选中的文件/文件夹路径集合
  Future<void> batchToggleFavorite(
    BuildContext context,
    Set<String> selectedItems,
  ) async {
    if (selectedItems.isEmpty) return;

    // ⚠️ 在异步操作前获取ScaffoldMessenger，避免异步后widget已销毁
    final messenger = ScaffoldMessenger.of(context);

    final allFavorite = isAllSelectedFavorite(selectedItems);
    final action = allFavorite ? '取消收藏' : '添加到收藏';

    try {
      if (allFavorite) {
        // 全部已收藏，批量取消收藏
        final (successCount, failCount) =
            await presenter.batchRemoveFavoriteFiles(selectedItems.toList());

        // ⚠️ 异步操作后必须检查widget是否还存在
        if (!_isMounted(context)) return;

        final message = failCount > 0
            ? '$action完成：成功 $successCount 个，失败 $failCount 个'
            : '已$action $successCount 个文件';

        // ⚠️ 延迟退出选择模式和显示消息，确保PopupMenu完全关闭
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onExitSelectionMode();
          _showSnackBarDirect(messenger, message);
        });
      } else {
        // 有未收藏的，批量添加收藏
        // 智能过滤：只添加未收藏的文件，跳过已收藏的文件和所有文件夹
        final filesToAdd = <FileItem>[];
        for (final path in selectedItems) {
          // 跳过已收藏的文件
          if (viewModel.isFavoriteFile(path)) continue;

          // 跳过文件夹（收藏功能仅支持文件）
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
            filesToAdd.add(file);
          } catch (e) {
            logger.w('Failed to create FileItem for: $path, error: $e');
          }
        }

        // 如果过滤后没有可添加的文件，提示并退出
        if (filesToAdd.isEmpty) {
          if (_isMounted(context)) {
            // ⚠️ 延迟退出选择模式和显示消息，确保PopupMenu完全关闭
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onExitSelectionMode();
              _showSnackBarDirect(messenger, '没有可添加到收藏的文件');
            });
          }
          return;
        }

        final (successCount, failCount) =
            await presenter.batchAddFavoriteFiles(filesToAdd);

        // ⚠️ 异步操作后必须检查widget是否还存在
        if (!_isMounted(context)) return;

        final message = failCount > 0
            ? '$action完成：成功 $successCount 个，失败 $failCount 个'
            : '已$action $successCount 个文件';

        // ⚠️ 延迟退出选择模式和显示消息，确保PopupMenu完全关闭
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onExitSelectionMode();
          _showSnackBarDirect(messenger, message);
        });
      }
    } catch (e, stackTrace) {
      logger.e('Batch toggle favorite failed: $e\n$stackTrace');
      if (_isMounted(context)) {
        // ⚠️ 延迟退出选择模式和显示错误消息，确保PopupMenu完全关闭
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onExitSelectionMode();
          _showSnackBarDirect(messenger, '$action失败：$e');
        });
      }
    }
  }

  /// 批量删除
  ///
  /// 注意：context必须从调用处传入，并在调用前检查mounted状态
  Future<void> batchDelete(
    BuildContext context,
    Set<String> selectedItems,
  ) async {
    if (selectedItems.isEmpty) return;

    // 获取回收站服务（等待异步初始化完成）
    await locator.isReady<AppTrashSettings>();
    final trashSettings = locator<AppTrashSettings>();

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

    // 转换为FileItem列表
    final filesToDelete = <FileItem>[];
    for (final path in selectedItems) {
      final entity = FileSystemEntity.typeSync(path);
      if (entity == FileSystemEntityType.file) {
        final file = File(path);
        final stat = file.statSync();
        filesToDelete.add(FileItem(
          name: path.split(Platform.pathSeparator).last,
          path: path,
          isDirectory: false,
          size: stat.size,
          modified: stat.modified,
        ));
      } else if (entity == FileSystemEntityType.directory) {
        final dir = Directory(path);
        final stat = dir.statSync();
        filesToDelete.add(FileItem(
          name: path.split(Platform.pathSeparator).last,
          path: path,
          isDirectory: true,
          size: 0, // 文件夹大小在这里设为0
          modified: stat.modified,
        ));
      }
    }

    if (filesToDelete.isEmpty) return;

    // 统计文件和文件夹数量
    int fileCount = filesToDelete.where((f) => !f.isDirectory).length;
    int folderCount = filesToDelete.where((f) => f.isDirectory).length;

    // 使用增强的删除确认对话框
    final confirmed = await EnhancedDeleteDialog.showBatchDeleteConfirmation(
      context: context,
      paths: selectedItems.toList(),
      fileCount: fileCount,
      folderCount: folderCount,
    );

    if (!confirmed || !_isMounted(context)) return;

    // 检查是否启用回收站
    if (!trashSettings.isEnabled) {
      // 回收站已禁用，直接永久删除（旧逻辑）
      await _permanentDelete(context, filesToDelete);
      return;
    }

    // 启用回收站，后台移至回收站（用户无感知）
    await _moveToTrashWithProgress(context, filesToDelete);
  }
  /// 永久删除文件（回收站禁用时）
  Future<void> _permanentDelete(
    BuildContext context,
    List<FileItem> files,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

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
                  Text('正在永久删除...'),
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

      for (final file in files) {
        try {
          // 🔒 记录操作日志
          final riskLevel = PathSecurity.getPathRiskLevel(file.path);
          PathSecurity.logOperation(
            operation: 'PERMANENT DELETE',
            path: file.path,
            riskLevel: riskLevel,
            allowed: true,
          );

          if (file.isDirectory) {
            await Directory(file.path).delete(recursive: true);
          } else {
            await File(file.path).delete();
          }
          successCount++;
        } catch (e) {
          logger.e('Failed to delete: ${file.path}, error: $e');
          failCount++;
        }
      }

      if (!_isMounted(context)) return;
      navigator.pop(); // 关闭进度对话框

      // 立即从列表移除已删除的文件
      // final cacheManager = ThumbnailCacheManager(); // 已禁用缓存删除
      for (final file in files) {
        try {
          bool fileDeleted = false;
          if (file.isDirectory) {
            // 文件夹删除成功，从列表移除
            if (!await Directory(file.path).exists()) {
              viewModel.removeFileFromList(file.path);
              fileDeleted = true;
            }
          } else {
            // 文件删除成功，从列表移除
            if (!await File(file.path).exists()) {
              viewModel.removeFileFromList(file.path);
              fileDeleted = true;
            }
          }
          
          // 清理视频缩略图缓存（已禁用：保留缓存以优化删除后的重载性能）
          // if (fileDeleted && !file.isDirectory) {
          //   final fileName = file.name.toLowerCase();
          //   if (fileName.endsWith('.mp4') || fileName.endsWith('.avi') || 
          //       fileName.endsWith('.mkv') || fileName.endsWith('.mov') ||
          //       fileName.endsWith('.wmv') || fileName.endsWith('.flv') ||
          //       fileName.endsWith('.webm') || fileName.endsWith('.m4v')) {
          //     try {
          //       await cacheManager.deleteCached(file.path);
          //       logger.d('Deleted video thumbnail cache for: ${file.path}');
          //     } catch (e) {
          //       logger.w('Failed to delete thumbnail cache: $e');
          //     }
          //   }
          // }
          if (fileDeleted) {
            logger.d('Skipping thumbnail cache deletion (preserving for fast reload)');
          }
        } catch (e) {
          logger.w('Error checking file existence: ${file.path}, $e');
        }
      }

      // 刷新文件列表（可选，用于更新统计等）
      onRefresh();

      // 显示结果提示
      if (failCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('成功永久删除 $successCount 项'),
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
      if (!_isMounted(context)) return;
      navigator.pop(); // 关闭进度对话框
      messenger.showSnackBar(
        SnackBar(content: Text('删除失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 移至回收站（软删除模式）
  /// 
  /// 采用立即标记+后台移动的方式：
  /// 1. 立即在数据库中标记为已删除（毫秒级）
  /// 2. 立即刷新UI（文件瞬间消失）
  /// 3. 后台异步移动文件到回收站（用户无感知）
  Future<void> _moveToTrashWithProgress(
    BuildContext context,
    List<FileItem> files,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    
    // 等待回收站管理器初始化完成
    await locator.isReady<AppTrashManager>();
    final trashManager = locator<AppTrashManager>();

    try {
      // 立即标记删除（仅写数据库，速度极快）
      await trashManager.markFilesAsDeleted(files);
      
      if (!_isMounted(context)) return;

      // 立即从列表移除已删除的文件
      // final cacheManager = ThumbnailCacheManager(); // 已禁用缓存删除
      for (final file in files) {
        viewModel.removeFileFromList(file.path);
        
        // 清理视频缩略图缓存（已禁用：保留缓存以优化删除后的重载性能）
        // if (!file.isDirectory) {
        //   final fileName = file.name.toLowerCase();
        //   if (fileName.endsWith('.mp4') || fileName.endsWith('.avi') || 
        //       fileName.endsWith('.mkv') || fileName.endsWith('.mov') ||
        //       fileName.endsWith('.wmv') || fileName.endsWith('.flv') ||
        //       fileName.endsWith('.webm') || fileName.endsWith('.m4v')) {
        //     try {
        //       await cacheManager.deleteCached(file.path);
        //       logger.d('Deleted video thumbnail cache for: ${file.path}');
        //     } catch (e) {
        //       logger.w('Failed to delete thumbnail cache: $e');
        //     }
        //   }
        // }
        logger.d('Skipping thumbnail cache deletion (preserving for fast reload)');
      }

      // 注意：不调用 onRefresh，因为文件已通过 removeFileFromList 从列表移除
      // 如果调用 onRefresh 重新扫描目录，会把已标记删除但尚未物理移动的文件再次加载回来

      // 退出多选模式
      onExitSelectionMode();

      // 显示简单成功提示（不提"回收站"，避免用户担心）
      messenger.showSnackBar(
        SnackBar(
          content: Text('成功删除 ${files.length} 项'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // 后台队列会自动处理文件移动，用户无感知
    } catch (e) {
      if (!_isMounted(context)) return;
      
      // 退出多选模式（即使失败也退出）
      onExitSelectionMode();
      
      messenger.showSnackBar(
        SnackBar(
          content: Text('删除失败：$e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      logger.e('Failed to mark files as deleted: $e');
    }
  }

  /// 批量移动
  ///
  /// 注意：context必须从调用处传入，并在调用前检查mounted状态
  /// 
  /// [shouldRefresh] - 移动后是否需要刷新页面（浏览器页面需要，分类页面不需要）
  Future<void> batchMove(
    BuildContext context,
    Set<String> selectedItems,
    String currentPath, {
    bool shouldRefresh = true,
  }) async {
    if (selectedItems.isEmpty) return;

    // 🔒 安全检查：验证所有选中项是否允许移动
    for (final path in selectedItems) {
      final riskLevel = PathSecurity.getPathRiskLevel(path);

      if (riskLevel == PathRiskLevel.forbidden ||
          riskLevel == PathRiskLevel.danger) {
        final fileName = path.split(Platform.pathSeparator).last;
        _showErrorSnackBar(context, '无法移动 "$fileName"：这是受保护的系统目录');
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
      builder: (context) => FolderPickerDialog(
        currentPath: currentPath,
        sourceFileName: '${selectedItems.length} 个项目',
        operationType: '移动',
      ),
    );

    if (destinationPath == null || !_isMounted(context)) return;

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
      final movedFiles = <String, String>{}; // 记录成功移动的文件：oldPath -> newPath

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
          
          // 记录成功移动的文件
          movedFiles[path] = targetPath;
          successCount++;
        } catch (e) {
          logger.e('Failed to move: $path, error: $e');
          failCount++;
        }
      }

      if (!_isMounted(context)) return;
      navigator.pop();
      
      // 立即更新文件路径（对于分类页面等需要保留文件的场景）
      for (final entry in movedFiles.entries) {
        final oldPath = entry.key;
        final newPath = entry.value;
        
        try {
          // 获取移动后的文件信息
          final entity = FileSystemEntity.typeSync(newPath);
          if (entity == FileSystemEntityType.file) {
            final file = File(newPath);
            final stat = file.statSync();
            final movedFile = FileItem(
              name: path.basename(newPath),
              path: newPath,
              isDirectory: false,
              size: stat.size,
              modified: stat.modified,
            );
            viewModel.updateFileInList(oldPath, movedFile);
          } else if (entity == FileSystemEntityType.directory) {
            final dir = Directory(newPath);
            final stat = dir.statSync();
            final movedDir = FileItem(
              name: path.basename(newPath),
              path: newPath,
              isDirectory: true,
              size: 0,
              modified: stat.modified,
            );
            viewModel.updateFileInList(oldPath, movedDir);
          }
        } catch (e) {
          logger.w('Failed to update file path in list: $oldPath -> $newPath, $e');
        }
      }
      
      // 根据调用页面决定是否刷新
      // 浏览器页面需要刷新以重新加载目录
      // 分类页面不需要刷新，因为文件已通过 updateFileInList 更新
      if (shouldRefresh) {
        onRefresh();
      }
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
      if (!_isMounted(context)) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('移动失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 批量复制
  ///
  /// 注意：context必须从调用处传入，并在调用前检查mounted状态
  Future<void> batchCopy(
    BuildContext context,
    Set<String> selectedItems,
    String currentPath,
  ) async {
    if (selectedItems.isEmpty) return;

    // 🔒 安全检查：验证所有源文件是否允许复制
    for (final sourcePath in selectedItems) {
      final riskLevel = PathSecurity.getPathRiskLevel(sourcePath);
      if (riskLevel == PathRiskLevel.forbidden ||
          riskLevel == PathRiskLevel.danger) {
        final fileName = sourcePath.split(Platform.pathSeparator).last;
        _showErrorSnackBar(context, '无法复制 "$fileName"：这是受保护的系统目录');
        logger.w('Copy blocked by UI: $sourcePath (Risk: ${riskLevel.name})');
        return;
      }
    }

    // 显示文件夹选择对话框
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final destinationPath = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(
        currentPath: currentPath,
        sourceFileName: '${selectedItems.length} 个项目',
        operationType: '复制',
      ),
    );

    if (destinationPath == null || !_isMounted(context)) return;

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
                final suffix = counter > 1 ? counter.toString() : '';
                targetPath =
                    '$destinationPath${Platform.pathSeparator}$nameWithoutExt - 副本$suffix$ext';
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
            
            // 添加目录到 ViewModel（用于同步到其他页面）
            try {
              final dir = Directory(targetPath);
              final stat = dir.statSync();
              final copiedDir = FileItem(
                name: path.basename(targetPath),
                path: targetPath,
                isDirectory: true,
                size: 0,
                modified: stat.modified,
              );
              viewModel.addFileToList(copiedDir);
            } catch (e) {
              logger.w('Failed to add copied directory to ViewModel: $targetPath, $e');
            }
          } else if (entity == FileSystemEntityType.file) {
            await File(sourcePath).copy(targetPath);
            
            // 添加文件到 ViewModel（用于同步到其他页面）
            try {
              final file = File(targetPath);
              final stat = file.statSync();
              final copiedFile = FileItem(
                name: path.basename(targetPath),
                path: targetPath,
                isDirectory: false,
                size: stat.size,
                modified: stat.modified,
              );
              viewModel.addFileToList(copiedFile);
            } catch (e) {
              logger.w('Failed to add copied file to ViewModel: $targetPath, $e');
            }
          }

          successCount++;
        } catch (e) {
          final baseName = sourcePath.split(Platform.pathSeparator).last;
          failedItems.add(baseName);
          failCount++;
          logger.e('Failed to copy $sourcePath: $e');
        }
      }

      if (!_isMounted(context)) return;
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
      if (!_isMounted(context)) return;
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
  ///
  /// 注意：context必须从调用处传入，并在调用前检查mounted状态
  Future<void> batchRename(
    BuildContext context,
    Set<String> selectedItems,
  ) async {
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
      if (!_isMounted(context)) return;
      _showErrorSnackBar(
        context,
        PathSecurity.getOperationDeniedMessage(sourcePath, '重命名'),
      );
      logger.w('Rename blocked by UI: $sourcePath (Risk: ${riskLevel.name})');
      return;
    }

    // 检查是否为系统关键文件夹名称
    if (PathSecurity.isSystemFolderName(currentName)) {
      if (!_isMounted(context)) return;
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

    if (newName == null || newName.trim().isEmpty || !_isMounted(context)) {
      return;
    }
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
        if (!_isMounted(context)) return;
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
        if (!_isMounted(context)) return;
        Navigator.pop(context); // 关闭进度对话框
        _showErrorSnackBar(context, '重命名失败：目标路径不安全');
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

      // 如果文件被收藏，同步更新收藏记录中的路径
      if (entity == FileSystemEntityType.file && 
          viewModel.isFavoriteFile(sourcePath)) {
        logger.d('File is favorited, updating favorite path');

        try {
          // 获取原收藏信息
          final oldFavorite = viewModel.favoriteFiles.firstWhere(
            (f) => f.filePath == sourcePath,
          );

          // 更新数据源中的路径
          await presenter.favoriteFilesSource.updateFavoriteFilePath(
            sourcePath,
            targetPath,
          );

          // 同步更新 ViewModel 中的收藏状态
          viewModel.removeFavoriteFile(sourcePath);
          viewModel.addFavoriteFile(FavoriteFileItem(
            filePath: targetPath,
            addedTime: oldFavorite.addedTime,
            accessCount: oldFavorite.accessCount,
            lastAccessTime: oldFavorite.lastAccessTime,
          ));
        } catch (e) {
          logger.w('Failed to update favorite path after rename: $e');
        }
      }

      // 立即更新ViewModel中的文件信息（同步 _files, _allFiles, _newFiles）
      try {
        final renamedEntity = entity == FileSystemEntityType.directory
            ? Directory(targetPath)
            : File(targetPath);
        final stat = renamedEntity.statSync();
        final renamedFile = FileItem(
          name: newName.trim(),
          path: targetPath,
          isDirectory: entity == FileSystemEntityType.directory,
          size: entity == FileSystemEntityType.directory ? 0 : stat.size,
          modified: stat.modified,
        );
        viewModel.updateFileInList(sourcePath, renamedFile);
      } catch (e) {
        logger.w('Failed to update file in list after rename: $e');
      }

      if (!_isMounted(context)) return;
      navigator.pop();
      onRefresh();
      onExitSelectionMode();

      messenger.showSnackBar(
        const SnackBar(content: Text('重命名成功'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!_isMounted(context)) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('重命名失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 批量分享
  ///
  /// 注意：context必须从调用处传入，并在调用前检查mounted状态
  Future<void> batchShare(
    BuildContext context,
    Set<String> selectedItems,
  ) async {
    if (selectedItems.isEmpty) return;

    // 只分享文件，过滤掉文件夹
    final filePaths = selectedItems.where((path) {
      return FileSystemEntity.typeSync(path) == FileSystemEntityType.file;
    }).toList();

    if (filePaths.isEmpty) {
      _showErrorSnackBar(context, '请选择至少一个文件进行分享', Colors.orange);
      return;
    }

    try {
      // 检查是否包含非图片文件
      final hasNonImage = filePaths.any((path) {
        final extension = path.split('.').last.toLowerCase();
        return !['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif']
            .contains(extension);
      });

      // 如果选择了多个文件且包含非图片文件，显示提示
      if (filePaths.length > 1 && hasNonImage) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('批量分享提示'),
            content: const Text(
              '您选择了多个文件，其中包含非图片文件。\n\n'
              '⚠️ 请注意：部分应用（如微信、QQ等）对多文件分享有限制，可能只接受图片格式。\n\n'
              '建议：\n'
              '• 如需分享非图片文件，建议单独分享\n'
              '• 或选择支持多种文件类型的应用（如文件管理器、云盘等）',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('继续分享'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;
      }

      // Capture messenger before awaiting presenter
      final messenger = ScaffoldMessenger.of(context);

      // 使用presenter批量分享
      final success = await presenter.batchShareFiles(filePaths);

      if (!_isMounted(context)) return;
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
      if (!_isMounted(context)) return;
      _showErrorSnackBar(context, '分享失败：$e');
    }
  }

  // ========== 辅助方法 ==========

  /// 检查BuildContext是否仍然有效（widget是否还挂载）
  ///
  /// 这是防止"Looking up a deactivated widget's ancestor is unsafe"异常的核心方法。
  /// 在所有异步操作后、使用context之前，都必须调用此方法检查。
  ///
  /// **实现原理**：
  /// - 使用try-catch包裹`context.mounted`，防止访问已释放的context导致异常
  /// - 如果context已失效，访问`mounted`属性本身就会抛异常，catch后返回false
  ///
  /// @param context 需要检查的BuildContext
  /// @return true=widget仍然挂载，可以安全使用context；false=widget已销毁
  bool _isMounted(BuildContext context) {
    try {
      return context.mounted;
    } catch (_) {
      return false;
    }
  }

  /// 显示错误提示的SnackBar（红色背景）
  ///
  /// 自动检查context有效性，如果widget已销毁则静默忽略。
  ///
  /// @param context 用于显示SnackBar的BuildContext
  /// @param message 错误消息文本
  /// @param backgroundColor 背景颜色，默认红色
  void _showErrorSnackBar(BuildContext context, String message,
      [Color? backgroundColor]) {
    if (!_isMounted(context)) return;
    try {
      // 先获取messenger，避免在已销毁的widget树中查找
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor ?? Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      logger.w('Failed to show error snackbar: $e');
    }
  }

  /// 直接使用ScaffoldMessengerState显示SnackBar
  ///
  /// 用于异步操作后显示消息，避免访问已销毁的widget树。
  /// 应在异步操作前通过ScaffoldMessenger.of(context)获取messenger。
  ///
  /// @param messenger ScaffoldMessengerState实例
  /// @param message 要显示的消息文本
  /// @param duration 显示时长，默认2秒
  void _showSnackBarDirect(ScaffoldMessengerState messenger, String message,
      {Duration? duration}) {
    try {
      // 使用Future.microtask确保在当前帧完成后显示SnackBar
      // 避免在widget重建过程中访问BuildContext
      Future.microtask(() {
        try {
          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              duration: duration ?? const Duration(seconds: 2),
            ),
          );
        } catch (e) {
          logger.w('Failed to show snackbar in microtask: $e');
        }
      });
    } catch (e) {
      logger.w('Failed to schedule snackbar: $e');
    }
  }
}
