import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/folder_stats.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';

/// 别名推荐服务
///
/// 基于文件夹路径、内容类型、文件数量等提供智能别名推荐
class AliasRecommendationService {
  /// 为文件夹推荐别名
  ///
  /// [path] 文件夹路径
  /// [originalName] 原始文件夹名
  /// [stats] 文件夹统计信息（可选）
  /// [type] 文件夹类型（可选）
  String recommendAlias({
    required String path,
    required String originalName,
    FolderStats? stats,
    QuickAccessFolderType? type,
  }) {
    logger.d('Recommending alias for: $path (type: $type)');

    // 1. 特殊路径映射（最高优先级）
    final specialAlias = _getSpecialPathAlias(path);
    if (specialAlias != null) {
      logger.d('Using special path alias: $specialAlias');
      return specialAlias;
    }

    // 2. 如果是其他目录类型，尝试从路径推断（比如应用目录）
    if (type == QuickAccessFolderType.other) {
      final appAlias = _getAppFolderAlias(path, originalName);
      if (appAlias != null) {
        logger.d('Using app folder alias: $appAlias');
        return appAlias;
      }
    }

    // 3. 基于内容类型推荐
    if (stats != null) {
      final contentAlias = _getContentBasedAlias(originalName, stats);
      if (contentAlias != null) {
        logger.d('Using content-based alias: $contentAlias');
        return contentAlias;
      }
    }

    // 4. 基于文件数量推荐
    if (stats != null && stats.totalFiles > 100) {
      final sizeAlias = _getSizeBasedAlias(originalName, stats);
      logger.d('Using size-based alias: $sizeAlias');
      return sizeAlias;
    }

    // 5. 默认：美化原始名称
    final beautified = _beautifyName(originalName);
    logger.d('Using beautified name: $beautified');
    return beautified;
  }

  /// 批量推荐别名
  Map<String, String> batchRecommendAliases(
    List<Map<String, dynamic>> folders,
  ) {
    final results = <String, String>{};

    for (final folder in folders) {
      final path = folder['path'] as String;
      final originalName = folder['originalName'] as String;
      final stats = folder['stats'] as FolderStats?;
      final type = folder['type'] as QuickAccessFolderType?;

      final alias = recommendAlias(
        path: path,
        originalName: originalName,
        stats: stats,
        type: type,
      );

      results[path] = alias;
    }

    return results;
  }

  // ==================== 私有推荐方法 ====================

  /// 特殊路径映射
  String? _getSpecialPathAlias(String path) {
    // Android 常用路径
    final androidMappings = {
      '/storage/emulated/0/DCIM': '相机照片',
      '/storage/emulated/0/Pictures': '图片',
      '/storage/emulated/0/Screenshots': '截图',
      '/storage/emulated/0/Download': '下载',
      '/storage/emulated/0/Documents': '文档',
      '/storage/emulated/0/Music': '音乐',
      '/storage/emulated/0/Movies': '视频',
      '/storage/emulated/0/Podcasts': '播客',
      '/storage/emulated/0/Ringtones': '铃声',
      '/storage/emulated/0/Alarms': '闹钟铃声',
      '/storage/emulated/0/Notifications': '通知铃声',
      '/storage/emulated/0/bluetooth': '蓝牙接收',
      '/storage/emulated/0/Screenrecorder': '录屏',
    };

    // 先检查Android路径
    if (androidMappings.containsKey(path)) {
      return androidMappings[path];
    }

    // Windows 常用路径（简化处理）
    if (path.endsWith('\\Downloads') || path.endsWith('/Downloads')) {
      return '下载';
    }
    if (path.endsWith('\\Documents') || path.endsWith('/Documents')) {
      return '文档';
    }
    if (path.endsWith('\\Pictures') || path.endsWith('/Pictures')) {
      return '图片';
    }
    if (path.endsWith('\\Music') || path.endsWith('/Music')) {
      return '音乐';
    }
    if (path.endsWith('\\Videos') || path.endsWith('/Videos')) {
      return '视频';
    }
    if (path.endsWith('\\Desktop') || path.endsWith('/Desktop')) {
      return '桌面';
    }

    return null;
  }

  /// 应用文件夹别名
  String? _getAppFolderAlias(String path, String originalName) {
    // WhatsApp 特殊路径
    if (path.contains('WhatsApp')) {
      if (path.endsWith('/WhatsApp Images') ||
          path.contains('WhatsApp/Media/WhatsApp Images')) {
        return 'WhatsApp图片';
      }
      if (path.endsWith('/WhatsApp Video') ||
          path.contains('WhatsApp/Media/WhatsApp Video')) {
        return 'WhatsApp视频';
      }
      if (path.endsWith('/WhatsApp Audio') ||
          path.contains('WhatsApp/Media/WhatsApp Audio')) {
        return 'WhatsApp语音';
      }
      if (path.endsWith('/WhatsApp Documents') ||
          path.contains('WhatsApp/Media/WhatsApp Documents')) {
        return 'WhatsApp文档';
      }
      if (path.contains('/Sent')) {
        return 'WhatsApp已发送';
      }
    }

    // WeChat 特殊路径
    if (path.contains('MicroMsg') ||
        path.contains('WeChat') ||
        path.contains('weixin')) {
      if (path.contains('image') || path.contains('Image')) {
        return '微信图片';
      }
      if (path.contains('video') || path.contains('Video')) {
        return '微信视频';
      }
      if (path.contains('voice') || path.contains('Voice')) {
        return '微信语音';
      }
      if (path.contains('file') || path.contains('File')) {
        return '微信文件';
      }
      if (path.contains('download') || path.contains('Download')) {
        return '微信下载';
      }
    }

    // TikTok/抖音
    if (path.contains('TikTok') || path.contains('douyin')) {
      if (path.contains('video') || path.contains('Video')) {
        return '抖音视频';
      }
      if (path.contains('photo') || path.contains('Photo')) {
        return '抖音照片';
      }
    }

    // Instagram
    if (path.contains('Instagram')) {
      if (path.contains('Stories')) {
        return 'Instagram故事';
      }
      if (path.contains('Reels')) {
        return 'Instagram短视频';
      }
    }

    // Telegram
    if (path.contains('Telegram')) {
      if (path.contains('Images')) {
        return 'Telegram图片';
      }
      if (path.contains('Videos')) {
        return 'Telegram视频';
      }
      if (path.contains('Documents')) {
        return 'Telegram文件';
      }
      if (path.contains('Audio')) {
        return 'Telegram音频';
      }
    }

    // Camera/相机
    if (path.contains('Camera') || path.contains('camera')) {
      return '相机照片';
    }

    // Screenshots
    if (path.contains('Screenshot') || path.contains('screenshot')) {
      return '截图';
    }

    return null;
  }

  /// 基于内容类型的别名
  String? _getContentBasedAlias(String originalName, FolderStats stats) {
    if (stats.totalFiles == 0) return null;

    final primaryType = stats.primaryFileType;
    final percentage = stats.primaryTypePercentage;

    // 只有当某种类型占比超过70%时才推荐
    if (percentage < 70) return null;

    switch (primaryType) {
      case FileType.image:
        if (stats.imageCount > 50) {
          return '$originalName (${stats.imageCount}张图片)';
        }
        return '$originalName (图片)';

      case FileType.video:
        if (stats.videoCount > 20) {
          return '$originalName (${stats.videoCount}个视频)';
        }
        return '$originalName (视频)';

      case FileType.audio:
        if (stats.audioCount > 30) {
          return '$originalName (${stats.audioCount}首音乐)';
        }
        return '$originalName (音频)';

      case FileType.document:
        if (stats.documentCount > 20) {
          return '$originalName (${stats.documentCount}个文档)';
        }
        return '$originalName (文档)';

      case FileType.archive:
        return '$originalName (压缩包)';

      default:
        return null;
    }
  }

  /// 基于大小的别名
  String _getSizeBasedAlias(String originalName, FolderStats stats) {
    final fileCount = stats.totalFiles;
    final sizeMB = stats.totalSizeMB;

    // 文件数量较多
    if (fileCount > 1000) {
      return '$originalName (${(fileCount / 1000).toStringAsFixed(1)}k个文件)';
    } else if (fileCount > 500) {
      return '$originalName ($fileCount个文件)';
    }

    // 大小较大
    if (sizeMB > 1024) {
      final sizeGB = sizeMB / 1024;
      return '$originalName (${sizeGB.toStringAsFixed(1)}GB)';
    } else if (sizeMB > 100) {
      return '$originalName (${sizeMB.toStringAsFixed(0)}MB)';
    }

    return originalName;
  }

  /// 美化文件夹名称
  String _beautifyName(String name) {
    // 移除特殊字符和多余空格
    var beautified = name
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // 首字母大写
    if (beautified.isNotEmpty) {
      beautified = beautified[0].toUpperCase() + beautified.substring(1);
    }

    return beautified;
  }

  /// 获取推荐理由
  String getRecommendationReason({
    required String path,
    required String originalName,
    required String recommendedAlias,
    FolderStats? stats,
  }) {
    if (recommendedAlias == originalName) {
      return '保持原始名称';
    }

    // 特殊路径
    if (_getSpecialPathAlias(path) != null) {
      return '系统常用目录';
    }

    // 应用目录
    if (_getAppFolderAlias(path, originalName) != null) {
      return '应用专属目录';
    }

    // 内容类型
    if (stats != null && stats.primaryFileType != null) {
      final percentage = stats.primaryTypePercentage;
      if (percentage >= 70) {
        return '主要包含${_getFileTypeDisplayName(stats.primaryFileType!)} (${percentage.toStringAsFixed(0)}%)';
      }
    }

    // 文件数量
    if (stats != null && stats.totalFiles > 100) {
      return '包含大量文件 (${stats.totalFiles}个)';
    }

    return '优化显示名称';
  }

  /// 获取文件类型显示名称
  String _getFileTypeDisplayName(FileType type) {
    switch (type) {
      case FileType.image:
        return '图片';
      case FileType.video:
        return '视频';
      case FileType.audio:
        return '音频';
      case FileType.document:
        return '文档';
      case FileType.archive:
        return '压缩包';
      case FileType.other:
        return '其他文件';
    }
  }

  /// 验证别名是否合法
  bool isValidAlias(String alias) {
    if (alias.trim().isEmpty) return false;
    if (alias.length > 50) return false;

    // 不允许的字符
    final invalidChars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|'];
    for (final char in invalidChars) {
      if (alias.contains(char)) return false;
    }

    return true;
  }

  /// 清理别名（移除非法字符）
  String sanitizeAlias(String alias) {
    var sanitized = alias;

    // 替换非法字符
    final invalidChars = {
      '/': '-',
      '\\': '-',
      ':': '-',
      '*': '',
      '?': '',
      '"': '',
      '<': '',
      '>': '',
      '|': '-',
    };

    invalidChars.forEach((invalid, replacement) {
      sanitized = sanitized.replaceAll(invalid, replacement);
    });

    // 移除多余空格
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 限制长度
    if (sanitized.length > 50) {
      sanitized = sanitized.substring(0, 50);
    }

    return sanitized;
  }

  /// 生成别名变体（如果别名已存在）
  String generateAliasVariant(String baseAlias, int variant) {
    if (variant == 0) return baseAlias;
    return '$baseAlias ($variant)';
  }

  /// 比较两个别名的相似度（0-100）
  int calculateAliasSimilarity(String alias1, String alias2) {
    final lower1 = alias1.toLowerCase().trim();
    final lower2 = alias2.toLowerCase().trim();

    if (lower1 == lower2) return 100;
    if (lower1.contains(lower2) || lower2.contains(lower1)) return 80;

    // 简单的字符匹配度计算
    final set1 = lower1.split('').toSet();
    final set2 = lower2.split('').toSet();
    final intersection = set1.intersection(set2).length;
    final union = set1.union(set2).length;

    return ((intersection / union) * 100).round();
  }
}
