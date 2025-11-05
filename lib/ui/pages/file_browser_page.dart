import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:easyfile/core/di/locator.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/data/sources/path_provider.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/ui/widgets/file_item_tile.dart';
import 'package:easyfile/ui/widgets/file_operation_sheet.dart';
import 'package:easyfile/ui/widgets/folder_picker_dialog.dart';
import 'package:easyfile/ui/widgets/progress_dialog.dart';
import 'package:easyfile/ui/widgets/rename_dialog.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';

class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({super.key});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  late FilePresenter presenter;
  late FileViewModel viewModel;
  bool _showSearchBar = false;

  @override
  void initState() {
    super.initState();
    logger.i('FileBrowserPage initState called');

    try {
      viewModel = locator<FileViewModel>();
      logger.d('ViewModel obtained: $viewModel');

      presenter = locator<FilePresenter>();
      logger.d('Presenter obtained: $presenter');

      _loadInitialDirectory();
    } catch (e) {
      logger.e('Error in initState: $e');
    }
  }

  Future<void> _loadInitialDirectory() async {
    try {
      // 直接使用一些简单的测试路径
      List<String> testPaths = [];

      if (Platform.isAndroid) {
        testPaths = [
          '/storage/emulated/0',
          '/sdcard',
          '/storage/emulated/0/Download',
          '/data/data/com.example.easyfile/files',
        ];
      } else {
        testPaths = [
          Directory.current.path,
          Platform.environment['HOME'] ??
              Platform.environment['USERPROFILE'] ??
              '/',
        ];
      }

      String? workingPath;
      for (final testPath in testPaths) {
        try {
          final dir = Directory(testPath);
          if (dir.existsSync()) {
            final files = dir.listSync();
            logger.d('Test path $testPath works, found ${files.length} items');
            workingPath = testPath;
            break;
          }
        } catch (e) {
          logger.w('Test path $testPath failed: $e');
        }
      }

      if (workingPath != null) {
        logger.i('Using working path: $workingPath');
        presenter.loadFiles(workingPath);
      } else {
        logger.w('No working path found, using fallback');
        final fallbackPath = Directory.current.path;
        presenter.loadFiles(fallbackPath);
      }
    } catch (e) {
      logger.e('Error in _loadInitialDirectory: $e');
      presenter.loadFiles('/');
    }
  }

  Future<void> _showPathSelector() async {
    try {
      final availablePaths = await PathProviderService.getAvailablePaths();
      if (!mounted) return;

      if (availablePaths.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有找到可用的目录')),
        );
        return;
      }

      final selectedPath = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('选择目录'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: availablePaths.length,
              itemBuilder: (context, index) {
                final path = availablePaths[index];
                final displayName = _getDisplayName(path);
                return ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(displayName),
                  subtitle: Text(path, style: const TextStyle(fontSize: 12)),
                  onTap: () => Navigator.of(context).pop(path),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      );

      if (selectedPath != null && mounted) {
        presenter.loadFiles(selectedPath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取目录列表失败: $e')),
        );
      }
    }
  }

  String _getDisplayName(String path) {
    if (path.contains('/storage/emulated/0')) {
      if (path == '/storage/emulated/0') return '内部存储';
      if (path.contains('/Download')) return '下载';
      if (path.contains('/Documents')) return '文档';
      if (path.contains('/Pictures')) return '图片';
      if (path.contains('/Android/data')) return '应用数据';
    }

    if (path.contains('Documents')) return '文档';
    if (path.contains('Desktop')) return '桌面';
    if (path.contains('Downloads')) return '下载';
    if (path.contains('Pictures')) return '图片';

    final segments = path.split(Platform.pathSeparator);
    return segments.last.isEmpty
        ? segments[segments.length - 2]
        : segments.last;
  }

  void _previewFile(FileItem file) {
    logger.d('Previewing file: ${file.path}');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FilePreviewPage(file: file),
      ),
    );
  }

  bool _canNavigateUp(String currentPath) {
    if (currentPath.isEmpty) return false;

    // 对于 Windows，检查是否在根目录（如 C:\）
    if (Platform.isWindows) {
      // 如果路径是类似 "C:\" 的格式，则不能再上级
      if (currentPath.length == 3 && currentPath.endsWith(':\\')) {
        return false;
      }
      // 如果路径是类似 "C:" 的格式，则不能再上级
      if (currentPath.length == 2 && currentPath.endsWith(':')) {
        return false;
      }
    } else {
      // 对于 Unix/Linux/macOS，检查是否在根目录
      if (currentPath == '/') {
        return false;
      }
    }

    return true;
  }

  /// 切换搜索栏的显示状态
  void _toggleSearch() {
    setState(() {
      _showSearchBar = !_showSearchBar;
    });
    if (!_showSearchBar && viewModel.isSearchMode) {
      presenter.clearSearch();
    }
  }

  /// 显示 SnackBar 消息
  ///
  /// [message] 要显示的消息文本
  /// [isSuccess] 是否为成功消息，成功消息使用绿色背景
  void _showSnackBar(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isSuccess ? Colors.green : null,
        ),
      );
    } catch (e) {
      logger.w('Failed to show SnackBar: $e. Message was: $message');
    }
  }

  void _showFileOperations(FileItem file) {
    logger.d('Showing file operations for: ${file.name}');
    showModalBottomSheet(
      context: context,
      builder: (context) => FileOperationSheet(
        file: file,
        onOperation: (operation) => _handleFileOperation(file, operation),
      ),
    );
  }

  Future<void> _handleFileOperation(
      FileItem file, FileOperation operation) async {
    logger.d('Handling file operation: $operation for ${file.name}');

    switch (operation) {
      case FileOperation.delete:
        await _deleteFile(file);
        break;
      case FileOperation.rename:
        await _renameFile(file);
        break;
      case FileOperation.copy:
        await _copyFile(file);
        break;
      case FileOperation.move:
        await _moveFile(file);
        break;
    }
  }

  /// 删除指定的文件或文件夹
  ///
  /// 显示确认对话框，如果用户确认，则执行删除操作并显示结果消息
  Future<void> _deleteFile(FileItem file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${file.name}" 吗？\n\n此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      logger.d('Starting delete operation for: ${file.name}');
      final success = await presenter.deleteFile(file);
      logger.d('Delete operation result: $success');

      // 等待文件列表刷新完成后显示结果消息
      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        final message = success ? '已删除 "${file.name}"' : '删除失败';
        logger.d('Showing delete SnackBar: $message');
        _showSnackBar(message, isSuccess: success);
      }
    }
  }

  /// 重命名指定的文件或文件夹
  ///
  /// 显示重命名对话框，如果用户提供新名称，则执行重命名操作并显示结果消息
  Future<void> _renameFile(FileItem file) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => RenameDialog(file: file),
    );

    if (newName != null && newName.isNotEmpty) {
      logger.d('Starting rename operation: ${file.name} -> $newName');
      final success = await presenter.renameFile(file, newName);
      logger.d('Rename operation result: $success');

      // 等待文件列表刷新完成后显示结果消息
      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        final message = success ? '已重命名为 "$newName"' : '重命名失败';
        logger.d('Showing rename SnackBar: $message');
        _showSnackBar(message, isSuccess: success);
      }
    }
  }

  /// 复制指定的文件或文件夹
  ///
  /// 显示文件夹选择对话框，选择目标文件夹后执行复制操作并显示结果消息
  Future<void> _copyFile(FileItem file) async {
    final destinationFolder = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(
        currentPath: viewModel.currentPath,
        title: '选择复制目标',
      ),
    );

    if (destinationFolder != null) {
      if (!mounted) return;
      ProgressDialog.show(
        context,
        title: '复制文件',
        message: '正在复制 "${file.name}"...',
      );

      logger.d('Starting copy operation: ${file.name} to $destinationFolder');
      final destinationPath =
          '$destinationFolder${Platform.pathSeparator}${file.name}';
      final success = await presenter.copyFile(file, destinationPath);
      logger.d('Copy operation result: $success');

      // 等待文件列表刷新完成后显示结果消息
      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        ProgressDialog.hide(context);
        final message = success ? '已复制 "${file.name}"' : '复制失败';
        logger.d('Showing copy SnackBar: $message');
        _showSnackBar(message, isSuccess: success);
      }
    }
  }

  /// 移动指定的文件或文件夹
  ///
  /// 显示文件夹选择对话框，选择目标文件夹后执行移动操作并显示结果消息
  Future<void> _moveFile(FileItem file) async {
    final destinationFolder = await showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(
        currentPath: viewModel.currentPath,
        title: '选择移动目标',
      ),
    );

    if (destinationFolder != null) {
      if (!mounted) return;
      ProgressDialog.show(
        context,
        title: '移动文件',
        message: '正在移动 "${file.name}"...',
      );

      logger.d('Starting move operation: ${file.name} to $destinationFolder');
      final destinationPath =
          '$destinationFolder${Platform.pathSeparator}${file.name}';
      final success = await presenter.moveFile(file, destinationPath);
      logger.d('Move operation result: $success');

      // 等待文件列表刷新完成后显示结果消息
      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        ProgressDialog.hide(context);
        final message = success ? '已移动 "${file.name}"' : '移动失败';
        logger.d('Showing move SnackBar: $message');
        _showSnackBar(message, isSuccess: success);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FileViewModel>.value(
      value: viewModel,
      child: Consumer<FileViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return Scaffold(
            appBar: AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    height: 36,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'EasyFile',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _toggleSearch,
                  tooltip: '搜索文件',
                ),
                IconButton(
                  icon: const Icon(Icons.folder_special),
                  onPressed: _showPathSelector,
                  tooltip: '选择目录',
                ),
              ],
              bottom: PreferredSize(
                //路径信息栏，返回当前目录，返回按钮和路径文字
                preferredSize: const Size.fromHeight(40),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                  child: Row(
                    children: [
                      if (_canNavigateUp(vm.currentPath)) ...[
                        IconButton(
                          icon: const Icon(Icons.navigate_before),
                          onPressed: () {
                            logger.d('Navigate up button pressed');
                            presenter.navigateUp();
                          },
                          tooltip: '返回上级目录',
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vm.currentPath.isEmpty ? '主目录' : '当前目录',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                            Text(
                              vm.currentPath.isEmpty
                                  ? '(正在加载...)'
                                  : vm.currentPath,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            body: Column(
              children: [
                // 搜索栏
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: _showSearchBar ? 60 : 0,
                  child: _showSearchBar
                      ? Container(
                          padding: const EdgeInsets.all(8),
                          color: Colors.blue[50],
                          child: TextField(
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: '搜索文件和文件夹...',
                              prefixIcon:
                                  const Icon(Icons.search, color: Colors.blue),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() {
                                    _showSearchBar = false;
                                  });
                                  if (viewModel.isSearchMode) {
                                    presenter.clearSearch();
                                  }
                                },
                              ),
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (query) {
                              if (query.isNotEmpty) {
                                presenter.searchFiles(query);
                              }
                            },
                            onChanged: (query) {
                              if (query.isEmpty && viewModel.isSearchMode) {
                                presenter.clearSearch();
                              }
                            },
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // 状态信息栏
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[100],
                  child: vm.isSearchMode
                      ? Row(
                          children: [
                            const Icon(Icons.search,
                                size: 16, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '搜索 "${vm.searchQuery}" - 找到 ${vm.files.length} 个结果',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.blue),
                              ),
                            ),
                            TextButton(
                              onPressed: () => presenter.clearSearch(),
                              child: const Text('清除搜索',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        )
                      : Text(
                          '找到 ${vm.files.length} 个项目 (${vm.files.where((f) => f.isDirectory).length} 个文件夹, ${vm.files.where((f) => !f.isDirectory).length} 个文件)',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                ),
                // 文件列表
                Expanded(
                  child: vm.files.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                vm.isSearchMode
                                    ? Icons.search_off
                                    : Icons.folder_open,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              Text(vm.isSearchMode ? '未找到匹配的文件' : '此文件夹为空'),
                              const SizedBox(height: 8),
                              Text(
                                vm.isSearchMode
                                    ? '搜索词: ${vm.searchQuery}'
                                    : '路径: ${vm.currentPath}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: vm.files.length,
                          itemBuilder: (_, i) => FileItemTile(
                            file: vm.files[i],
                            showFullPath: vm.isSearchMode,
                            onTap: () {
                              if (vm.files[i].isDirectory) {
                                if (vm.isSearchMode) {
                                  // 在搜索模式下，清除搜索并导航到该文件夹
                                  presenter.clearSearch();
                                  presenter.navigateToFolder(vm.files[i].path);
                                } else {
                                  presenter.navigateToFolder(vm.files[i].path);
                                }
                              } else {
                                // 预览文件
                                _previewFile(vm.files[i]);
                              }
                            },
                            onLongPress: () {
                              _showFileOperations(vm.files[i]);
                            },
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
