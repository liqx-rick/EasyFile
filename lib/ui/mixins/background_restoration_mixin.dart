import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/services/background_audio_service.dart';

/// 后台文件恢复混入
///
/// 提供统一的后台恢复逻辑，用于从通知栏点击后恢复上次查看的文件
/// 主要用于音频播放的后台恢复功能
mixin BackgroundRestorationMixin<T extends StatefulWidget> on State<T> {
  /// 检查并恢复上次查看的文件
  ///
  /// 从 SharedPreferences 读取 'last_viewed_file_path'，如果存在且音频正在后台播放则自动打开该文件
  /// 对于音频文件，会自动构建播放列表（同目录的所有音频文件）
  Future<void> checkAndRestoreFilePreview({
    required BuildContext context,
    required FileViewModel viewModel,
    required FilePresenter presenter,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastViewedPath = prefs.getString('last_viewed_file_path');

      if (lastViewedPath == null || lastViewedPath.isEmpty) {
        return;
      }

      logger.d('Found last viewed file: $lastViewedPath');

      // 检查音频播放器状态：只有在真的有音频在后台播放时才恢复
      final audioService = BackgroundAudioService();
      if (audioService.player == null || !audioService.isPlaying) {
        logger.d('Audio player not playing, clearing restoration flag');
        await prefs.remove('last_viewed_file_path');
        return;
      }

      logger.d('Audio is playing in background, restoring preview');

      final file = File(lastViewedPath);
      if (!file.existsSync()) {
        logger.w('Last viewed file does not exist: $lastViewedPath');
        await prefs.remove('last_viewed_file_path');
        return;
      }

      // 清除恢复标记
      await prefs.remove('last_viewed_file_path');

      final stat = file.statSync();
      final fileItem = FileItem(
        name: file.path.split(Platform.pathSeparator).last,
        path: file.path,
        size: stat.size,
        modified: file.lastModifiedSync(),
        isDirectory: false,
      );

      logger.i('Restoring file preview: ${fileItem.name}');

      if (!context.mounted) {
        logger.w('Context not mounted, cannot restore preview');
        return;
      }

      // 如果是音频文件，构建播放列表
      List<FileItem>? fileList;
      int? initialIndex;

      if (FileUtils.isAudioFile(fileItem.name)) {
        try {
          final result = await _buildAudioPlaylist(file, fileItem);
          fileList = result.$1;
          initialIndex = result.$2;
        } catch (e) {
          logger.e('Failed to build audio playlist: $e');
          // 出错时仍然可以打开单个文件
        }
      }

      // 打开预览页面
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FilePreviewPage(
              file: fileItem,
              fileList: fileList,
              initialIndex: initialIndex ?? 0,
              viewModel: viewModel,
              presenter: presenter,
            ),
          ),
        );
      }
    } catch (e) {
      logger.e('Error restoring file preview: $e');
    }
  }

  /// 构建音频播放列表
  ///
  /// 读取同目录下的所有音频文件，按文件名排序，返回列表和当前文件的索引
  Future<(List<FileItem>, int)> _buildAudioPlaylist(
    File currentFile,
    FileItem currentFileItem,
  ) async {
    final parentDir = currentFile.parent;
    final dirContents = parentDir.listSync();

    final audioFiles = <FileItem>[];
    for (final entity in dirContents) {
      if (entity is File && FileUtils.isAudioFile(entity.path)) {
        try {
          final stat = entity.statSync();
          audioFiles.add(FileItem(
            name: entity.path.split(Platform.pathSeparator).last,
            path: entity.path,
            size: stat.size,
            modified: stat.modified,
            isDirectory: false,
          ));
        } catch (e) {
          logger.w('Failed to read file info: ${entity.path}');
        }
      }
    }

    if (audioFiles.isEmpty) {
      return (<FileItem>[], 0);
    }

    // 按文件名排序
    audioFiles.sort((a, b) => a.name.compareTo(b.name));

    // 找到当前文件的索引
    int initialIndex = audioFiles.indexWhere((f) => f.path == currentFileItem.path);
    if (initialIndex == -1) initialIndex = 0;

    logger.d('Built audio playlist: ${audioFiles.length} items, index: $initialIndex');

    return (audioFiles, initialIndex);
  }
}
