import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/widgets/enhanced_delete_dialog.dart';
import 'package:easyfile/ui/widgets/folder_picker_dialog.dart';
import 'package:easyfile/ui/utils/file_details_helper.dart';
import 'package:easyfile/utils/path_security.dart';
import 'package:easyfile/utils/file_size_formatter.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/ui/dialogs/extract_archive_dialog.dart';
import 'package:easyfile/ui/pages/archive_viewer_page.dart';

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
  /// 打印文本文件时的最大内容长度（约 50KB），避免生成过大的 PDF
  static const int _maxPrintTextLength = 50000;

  final BuildContext context;
  final FileViewModel viewModel;
  final FilePresenter presenter;
  final VoidCallback? onRefresh;
  final VoidCallback? onFileDeleted; // 文件被删除后的回调（通常需要关闭预览页）
  final VoidCallback? onUIUpdate; // 轻量级UI更新回调（不重新加载数据，仅刷新UI）

  SingleFileOperationsService({
    required this.context,
    required this.viewModel,
    required this.presenter,
    this.onRefresh,
    this.onFileDeleted,
    this.onUIUpdate,
  });

  bool get _isMounted {
    try {
      return context.mounted;
    } catch (_) {
      return false;
    }
  }

  void _showSnackBar(String message,
      {Duration? duration, ScaffoldMessengerState? messenger}) {
    if (!_isMounted) return;
    final scaffoldMessenger = messenger ?? ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration ?? const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message,
      [Color? backgroundColor, ScaffoldMessengerState? messenger]) {
    if (!_isMounted) return;
    final scaffoldMessenger = messenger ?? ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor ?? Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 切换文件收藏状态
  Future<void> toggleFavorite(FileItem file) async {
    // Capture messenger before async operations
    final messenger = ScaffoldMessenger.of(context);

    try {
      final wasOriginallyFavorite = viewModel.isFavoriteFile(file.path);

      // 调用 presenter 的单文件收藏方法
      // 返回值是新的收藏状态：true=已收藏，false=未收藏
      final newFavoriteState = await presenter.toggleFavoriteFile(file);

      if (!_isMounted) return;

      // 判断操作是否成功：状态发生了变化
      final operationSucceeded = (newFavoriteState != wasOriginallyFavorite);

      if (operationSucceeded) {
        _showSnackBar(newFavoriteState ? '已添加到收藏' : '已取消收藏',
            messenger: messenger);
        // 收藏操作通过 viewModel.addFavoriteFile/removeFavoriteFile 自动触发 notifyListeners()
        // Consumer 会自动重建 UI，无需手动调用 onUIUpdate
      } else {
        final action = wasOriginallyFavorite ? '取消收藏' : '添加到收藏';
        _showErrorSnackBar('$action失败', null, messenger);
      }
    } catch (e) {
      logger.e('Toggle favorite failed: $e');
      if (_isMounted) {
        _showErrorSnackBar('操作失败：$e', null, messenger);
      }
    }
  }

  /// 分享文件
  Future<void> shareFile(FileItem file) async {
    // Capture messenger before any async operations
    final messenger = ScaffoldMessenger.of(context);

    if (file.isDirectory) {
      _showErrorSnackBar('无法分享文件夹', Colors.orange, messenger);
      return;
    }

    try {
      final success = await presenter.batchShareFiles([file.path]);

      if (!_isMounted) return;

      if (!success) {
        _showErrorSnackBar('分享失败，请检查文件是否存在', null, messenger);
      }
    } catch (e) {
      logger.e('Share file failed: $e');
      if (_isMounted) {
        _showErrorSnackBar('分享失败：$e', null, messenger);
      }
    }
  }

  /// 解压压缩包
  /// 
  /// 显示解压对话框，允许用户选择解压目录
  Future<void> extractArchive(FileItem file) async {
    final messenger = ScaffoldMessenger.of(context);

    // 检查是否是压缩包文件
    if (!FileUtils.isArchiveFile(file.name)) {
      _showErrorSnackBar('该文件不是压缩包', Colors.orange, messenger);
      return;
    }

    try {
      if (!_isMounted) return;

      // 显示解压对话框
      await showDialog(
        context: context,
        builder: (context) => ExtractArchiveDialog(archiveFile: file),
      );
    } catch (e) {
      logger.e('Extract archive failed: $e');
      if (_isMounted) {
        _showErrorSnackBar('解压失败：$e', null, messenger);
      }
    }
  }

  /// 查看压缩包内容
  /// 
  /// 显示压缩包内的文件列表，不实际解压
  Future<void> viewArchiveContents(FileItem file) async {
    final messenger = ScaffoldMessenger.of(context);

    // 检查是否是压缩包文件
    if (!FileUtils.isArchiveFile(file.name)) {
      _showErrorSnackBar('该文件不是压缩包', Colors.orange, messenger);
      return;
    }

    try {
      if (!_isMounted) return;

      // 导航到压缩包查看器页面
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ArchiveViewerPage(archiveFile: file),
        ),
      );
    } catch (e) {
      logger.e('View archive contents failed: $e');
      if (_isMounted) {
        _showErrorSnackBar('查看失败：$e', null, messenger);
      }
    }
  }

  /// 重命名文件
  ///
  /// 返回 true 表示重命名成功，需要刷新父页面
  Future<bool> renameFile(FileItem file) async {
    // Capture messenger and navigator before async operations
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // 🔒 安全检查
    final riskLevel = PathSecurity.getPathRiskLevel(file.path);
    if (riskLevel == PathRiskLevel.forbidden ||
        riskLevel == PathRiskLevel.danger) {
      _showErrorSnackBar(
        PathSecurity.getOperationDeniedMessage(file.path, '重命名'),
        null,
        messenger,
      );
      logger.w('Rename blocked: ${file.path} (Risk: ${riskLevel.name})');
      return false;
    }

    if (PathSecurity.isSystemFolderName(file.name)) {
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('🔒 禁止重命名'),
          content: Text(
            '"${file.name}" 是系统重要文件夹！\n\n'
            '重命名此文件夹会导致系统功能异常。\n\n'
            '为保护您的设备，此操作已被阻止。',
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
      return false;
    }

    // 显示重命名对话框
    final controller = TextEditingController(text: file.name);

    try {
      // 检测横屏模式
      final mediaQuery = MediaQuery.of(context);
      final isLandscape = mediaQuery.orientation == Orientation.landscape;

      // Check mounted before showing rename dialog
      if (!_isMounted) {
        controller.dispose();
        return false;
      }

      final newName = isLandscape
          ? await _showRenameBottomSheet(controller, file)
          : await _showRenameDialog(controller, file);

      if (newName == null || newName.trim().isEmpty || !_isMounted) {
        controller.dispose();
        return false;
      }
      if (newName == file.name) {
        controller.dispose();
        return false;
      }

      if (!_isMounted) {
        controller.dispose();
        return false;
      }

      if (!context.mounted) {
        controller.dispose();
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

        if (!_isMounted) {
          controller.dispose();
          return false;
        }
        navigator.pop(); // 关闭进度对话框

        if (success) {
          _showSnackBar('重命名成功', messenger: messenger);
          // 重命名成功后通过 viewModel.updateFileInList 自动触发 notifyListeners()
          // Consumer 会自动重建 UI，无需手动调用 onUIUpdate

          // 延迟释放 TextEditingController，等待对话框动画完成（对话框关闭动画约200-300ms）
          Future.delayed(const Duration(milliseconds: 350), () {
            controller.dispose();
          });

          return true; // 返回 true 表示操作成功
        } else {
          _showErrorSnackBar('重命名失败', null, messenger);
          Future.delayed(const Duration(milliseconds: 350), () {
            controller.dispose();
          });
          return false;
        }
      } catch (e) {
        if (!_isMounted) {
          controller.dispose();
          return false;
        }
        navigator.pop();
        Future.delayed(const Duration(milliseconds: 350), () {
          controller.dispose();
        });
        _showErrorSnackBar('重命名失败：$e', null, messenger);
        return false;
      }
    } catch (e) {
      // 如果在显示对话框时发生异常，确保dispose controller
      controller.dispose();
      _showErrorSnackBar('操作失败：$e', null, messenger);
      return false;
    }
  }

  /// 删除文件
  Future<void> deleteFile(FileItem file) async {
    // Capture messenger and navigator before async operations
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // 🔒 安全检查
    final riskLevel = PathSecurity.getPathRiskLevel(file.path);
    if (riskLevel == PathRiskLevel.forbidden ||
        riskLevel == PathRiskLevel.danger) {
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('🛑 禁止删除'),
          content: Text(
            '"${file.name}" 是受保护的系统目录！\n\n'
            '删除系统目录会导致系统功能损坏。\n\n'
            '为保护您的设备，此操作已被阻止。',
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(),
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
        builder: (dialogContext) => AlertDialog(
          title: const Text('🔒 禁止删除'),
          content: Text(
            '"${file.name}" 是系统重要文件夹！\n\n'
            '删除此文件夹会导致系统功能异常。\n\n'
            '为保护您的设备，此操作已被阻止。',
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
      return;
    }

    // Check mounted before showing delete confirmation dialog
    if (!_isMounted) return;

    // 使用增强的删除确认对话框
    final confirmed = await EnhancedDeleteDialog.showSingleDeleteConfirmation(
      context: context,
      path: file.path,
    );

    if (!confirmed || !_isMounted) return;

    if (!_isMounted) return;

    if (!context.mounted) return;

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
      navigator.pop(); // 关闭进度对话框

      if (success) {
        _showSnackBar('删除成功', messenger: messenger);
        // 文件删除成功，通知调用者（通常需要关闭预览页）
        onFileDeleted?.call();
      } else {
        _showErrorSnackBar('删除失败', null, messenger);
      }
    } catch (e) {
      if (!_isMounted) return;
      navigator.pop();
      _showErrorSnackBar('删除失败：$e', null, messenger);
    }
  }

  /// 移动文件
  ///
  /// 返回 true 表示移动成功，需要刷新父页面
  Future<bool> moveFile(FileItem file) async {
    // Capture messenger and navigator before async operations
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // 🔒 安全检查
    final riskLevel = PathSecurity.getPathRiskLevel(file.path);
    if (riskLevel == PathRiskLevel.forbidden ||
        riskLevel == PathRiskLevel.danger) {
      _showErrorSnackBar('无法移动 "${file.name}"：这是受保护的系统目录', null, messenger);
      logger.w('Move blocked: ${file.path} (Risk: ${riskLevel.name})');
      return false;
    }

    if (PathSecurity.isSystemFolderName(file.name)) {
      if (!_isMounted) return false;
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('🔒 禁止移动'),
          content: Text(
            '"${file.name}" 是系统重要文件夹！\n\n'
            '移动此文件夹会导致系统功能异常。\n\n'
            '为保护您的设备，此操作已被阻止。',
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(),
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
      _showSnackBar('无法移动：目标位置与源位置相同',
          duration: const Duration(seconds: 2), messenger: messenger);
      return false;
    }

    // 🔒 验证目标路径安全性
    final targetRiskLevel = PathSecurity.getPathRiskLevel(destinationPath);
    if (targetRiskLevel == PathRiskLevel.forbidden ||
        targetRiskLevel == PathRiskLevel.danger) {
      _showErrorSnackBar('目标位置不安全，无法移动文件', null, messenger);
      logger.w('Move blocked: target path $destinationPath is protected');
      return false;
    }

    // 检查是否要移动到子目录（会造成循环）
    if (file.isDirectory) {
      if (destinationPath.startsWith(file.path + Platform.pathSeparator) ||
          destinationPath == file.path) {
        _showErrorSnackBar('不能将文件夹移动到自己的子目录中', null, messenger);
        return false;
      }
    }

    if (!_isMounted) return false;

    if (!context.mounted) return false;

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
      navigator.pop(); // 关闭进度对话框

      if (success) {
        _showSnackBar('移动成功', messenger: messenger);
        // 移动成功后通过 viewModel.updateFileInList 自动触发 notifyListeners()
        // Consumer 会自动重建 UI，无需手动调用 onUIUpdate
        return true;
      } else {
        _showErrorSnackBar('移动失败', null, messenger);
        return false;
      }
    } catch (e) {
      if (!_isMounted) return false;
      navigator.pop();
      _showErrorSnackBar('移动失败：$e', null, messenger);
      return false;
    }
  }

  /// 复制文件
  ///
  /// 返回 true 表示复制成功，需要刷新父页面
  Future<bool> copyFile(FileItem file) async {
    // Capture messenger and navigator before async operations
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // 🔒 安全检查
    final riskLevel = PathSecurity.getPathRiskLevel(file.path);
    if (riskLevel == PathRiskLevel.forbidden ||
        riskLevel == PathRiskLevel.danger) {
      _showErrorSnackBar('无法复制 "${file.name}"：这是受保护的系统目录', null, messenger);
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
      _showErrorSnackBar('目标位置不安全，无法复制文件', null, messenger);
      logger.w('Copy blocked: target path $destinationPath is protected');
      return false;
    }

    if (!_isMounted) return false;

    if (!context.mounted) return false;

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
      navigator.pop(); // 关闭进度对话框

      if (success) {
        _showSnackBar('复制成功', messenger: messenger);
        // 复制成功后通过 viewModel.addFileToList 自动触发 notifyListeners()
        // Consumer 会自动重建 UI，无需手动调用 onUIUpdate
        return true;
      } else {
        _showErrorSnackBar('复制失败', null, messenger);
        return false;
      }
    } catch (e) {
      if (!_isMounted) return false;
      navigator.pop();
      _showErrorSnackBar('复制失败：$e', null, messenger);
      return false;
    }
  }

  /// 检查是否支持打印
  ///
  /// 支持打印的文件类型：
  /// - 图片文件（PNG、JPG等）
  /// - PDF文件
  /// - 文本文件（TXT等）
  bool canPrint(FileItem file) {
    if (file.isDirectory) return false;
    return FileUtils.isImageFile(file.name) ||
        FileUtils.isPdfFile(file.name) ||
        FileUtils.isTextFile(file.name);
  }

  /// 打印文件
  ///
  /// 根据文件类型调用对应的打印方法：
  /// - 图片：转换为 PDF 后打印
  /// - PDF：直接打印原始文件
  /// - 文本：格式化为 PDF 后打印
  Future<void> printFile(FileItem file) async {
    // Capture messenger before any async operations
    final messenger = ScaffoldMessenger.of(context);

    if (!canPrint(file)) {
      _showErrorSnackBar('该文件类型不支持打印', null, messenger);
      return;
    }

    try {
      if (FileUtils.isImageFile(file.name)) {
        await _printImage(file);
      } else if (FileUtils.isPdfFile(file.name)) {
        await _printPdf(file);
      } else if (FileUtils.isTextFile(file.name)) {
        await _printText(file);
      }
    } catch (e) {
      logger.e('Print failed: $e');
      if (_isMounted) {
        _showErrorSnackBar('打印失败: $e', null, messenger);
      }
    }
  }

  /// 打印图片
  ///
  /// 将图片文件转换为 PDF 格式后打印
  /// 图片会自动缩放以适配页面大小，居中显示
  Future<void> _printImage(FileItem file) async {
    try {
      final imageBytes = await File(file.path).readAsBytes();
      final image = pw.MemoryImage(imageBytes);

      await Printing.layoutPdf(
        name: file.name,
        onLayout: (pw_pdf.PdfPageFormat format) async {
          final pdf = pw.Document();
          pdf.addPage(
            pw.Page(
              pageFormat: format,
              build: (context) => pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
            ),
          );
          return pdf.save();
        },
      );
      logger.i('Image print initiated: ${file.name}');
    } catch (e) {
      logger.e('Failed to print image: $e');
      rethrow;
    }
  }

  /// 打印 PDF
  ///
  /// 直接使用原始 PDF 文件字节进行打印
  /// 保留 PDF 原始格式和布局
  Future<void> _printPdf(FileItem file) async {
    try {
      final pdfBytes = await File(file.path).readAsBytes();
      await Printing.layoutPdf(
        name: file.name,
        onLayout: (_) => Future.value(pdfBytes),
      );
      logger.i('PDF print initiated: ${file.name}');
    } catch (e) {
      logger.e('Failed to print PDF: $e');
      rethrow;
    }
  }

  /// 打印文本
  ///
  /// 将文本文件格式化为 PDF 后打印
  /// 功能特性：
  /// - 带文件名标题
  /// - 自动分页
  /// - 限制最大内容长度（50KB），避免生成过大的 PDF
  /// - 支持 UTF-8 编码，失败时回退到 Latin1
  Future<void> _printText(FileItem file) async {
    try {
      // 直接读取文件内容
      String content;
      try {
        // 尝试以 UTF-8 读取
        content = await File(file.path).readAsString();
      } catch (e) {
        // UTF-8 失败，使用 Latin1 作为后备
        final bytes = await File(file.path).readAsBytes();
        content = latin1.decode(bytes);
      }

      // 限制内容长度，避免生成过大的 PDF
      if (content.length > _maxPrintTextLength) {
        content =
            '${content.substring(0, _maxPrintTextLength)}\n\n... (内容过长，已截断) ...';
      }

      await Printing.layoutPdf(
        name: file.name,
        onLayout: (pw_pdf.PdfPageFormat format) async {
          final pdf = pw.Document();
          pdf.addPage(
            pw.MultiPage(
              pageFormat: format,
              build: (context) => [
                pw.Header(
                  level: 0,
                  child: pw.Text(
                    file.name,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  content,
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ],
            ),
          );
          return pdf.save();
        },
      );
      logger.i('Text print initiated: ${file.name}');
    } catch (e) {
      logger.e('Failed to print text: $e');
      rethrow;
    }
  }

  /// 显示文件详细信息
  ///
  /// [useBottomSheet] 是否使用底部面板
  /// - true: 使用 BottomSheet（适合从操作菜单进入，视觉连贯）
  /// - false: 使用 AlertDialog（适合预览页面直接查看，默认行为）
  Future<void> showFileDetails(FileItem file,
      {bool useBottomSheet = false}) async {
    if (useBottomSheet) {
      // 使用底部面板（从操作菜单进入时，视觉更连贯）
      FileDetailsHelper.showFileDetailsBottomSheet(context, file);
    } else {
      // 使用对话框（预览页面默认，保持现有行为）
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

  /// 显示重命名对话框（竖屏模式）
  Future<String?> _showRenameDialog(
    TextEditingController controller,
    FileItem file,
  ) {
    if (!_isMounted) return Future.value(null);
    return showDialog<String>(
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
  }

  /// 显示重命名底部表单（横屏模式）
  Future<String?> _showRenameBottomSheet(
    TextEditingController controller,
    FileItem file,
  ) {
    if (!_isMounted) return Future.value(null);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.isDirectory ? '重命名文件夹' : '重命名文件',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '新名称',
                    hintText: '请输入新名称',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      Navigator.pop(context, value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
