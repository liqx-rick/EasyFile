import 'dart:io';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/presenter/file_presenter.dart';
import 'package:easyfile/services/background_audio_service.dart';
import 'package:easyfile/ui/pages/file_preview_page.dart';
import 'package:easyfile/utils/file_utils.dart';
import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:flutter/material.dart';

/// 后台文件恢复混入
///
/// 提供统一的后台恢复逻辑，用于从通知栏点击后恢复音频播放器
/// 主要用于音频播放的后台恢复功能
mixin BackgroundRestorationMixin<T extends StatefulWidget> on State<T> {
  /// 最近一次恢复的时间戳，用于防止重复触发
  DateTime? _lastRestorationTime;

  /// 检查并恢复上次查看的文件
  ///
  /// 当音频在后台播放时，从 BackgroundAudioService 读取当前播放的音频路径并打开预览页面
  /// 对于音频文件，会自动构建播放列表（同目录的所有音频文件）
  ///
  /// 防重复保护：如果在1秒内重复调用，会被忽略
  Future<void> checkAndRestoreFilePreview({
    required BuildContext context,
    required FileViewModel viewModel,
    required FilePresenter presenter,
  }) async {
    try {
      // 防重复保护：如果在1秒内重复调用，忽略本次调用
      final now = DateTime.now();
      if (_lastRestorationTime != null) {
        final timeSinceLastRestore = now.difference(_lastRestorationTime!);
        if (timeSinceLastRestore.inMilliseconds < 1000) {
          return;
        }
      }

      // 检查音频播放器状态：只有在真的有音频在后台播放时才恢复
      final audioService = BackgroundAudioService();
      if (audioService.player == null || !audioService.isPlaying) {
        return;
      }

      // 从 BackgroundAudioService 获取当前播放的音频路径
      final currentAudioPath = audioService.currentAudioPath;
      if (currentAudioPath == null || currentAudioPath.isEmpty) {
        logger.w('Audio is playing but no audio path found');
        return;
      }

      // 记录本次恢复时间（在检查通过后，实际执行前记录）
      _lastRestorationTime = now;

      final file = File(currentAudioPath);
      if (!file.existsSync()) {
        logger.w('Current audio file does not exist: $currentAudioPath');
        return;
      }

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
    int initialIndex =
        audioFiles.indexWhere((f) => f.path == currentFileItem.path);
    if (initialIndex == -1) initialIndex = 0;

    return (audioFiles, initialIndex);
  }
}
