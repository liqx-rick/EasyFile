import 'package:path/path.dart' as path;
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';

/// 重复文件推荐算法引擎
///
/// 职责：
/// 1. 根据推荐配置计算文件的保留分数
/// 2. 对重复文件进行智能排序
/// 3. 提供推荐信息和调试信息
///
/// 算法原理：
/// - 多维度评分系统（目录类型、关键词、大小、时间等）
/// - 按总分从高到低排序
/// - 分数最高的文件推荐保留
///
/// 注意：配置通过 AppConfig.instance.duplicateFilesRec 自动获取，
/// 遵循统一的配置管理模式
class DuplicateFilesRecommendationEngine {
  const DuplicateFilesRecommendationEngine();

  /// 获取推荐配置（从 AppConfig 单例获取）
  dynamic get _config => AppConfig.instance.duplicateFilesRec;

  /// 对文件列表进行排序（推荐保留的排在第一位）
  ///
  /// 参数：
  /// - files: 重复文件列表（至少2个）
  ///
  /// 返回：
  /// - 已排序的文件列表（推荐保留的在第一位）
  List<FileItem> sortFilesByRecommendation(List<FileItem> files) {
    if (files.length < 2) return files;

    // 计算每个文件的分数
    final fileScores = <FileItem, int>{};
    for (final file in files) {
      fileScores[file] = calculateRecommendScore(file, files);
    }

    // 按推荐分数从高到低排序
    final sortedFiles = List<FileItem>.from(files);
    sortedFiles.sort((a, b) {
      final scoreA = fileScores[a]!;
      final scoreB = fileScores[b]!;
      return scoreB.compareTo(scoreA); // 降序排列（分数高的在前）
    });

    return sortedFiles;
  }

  /// 计算文件的推荐保留分数（分数越高越推荐保留）
  ///
  /// 评分维度（优先级从高到低）：
  /// 1. 目录类型评分：
  ///    - 系统原生功能目录（DCIM/Sounds等）：+1500
  ///    - 用户自建一级目录（如 /曲艺/）：+1000
  ///    - 用户自建二级目录（如 /曲艺/浅草课程/）：+800
  ///    - Download目录：+500
  ///    - 应用子目录（weixin/qq等）：-500
  /// 2. 文件名关键词：正向+500，负向-300
  /// 3. 路径关键词：正向+300，负向-250
  /// 4. 文件大小：相对分数0-100
  /// 5. 修改时间：相对分数0-100
  /// 6. 其他负面特征：应用数据目录-400，哈希命名-200，隐藏目录-200，路径过深-150
  int calculateRecommendScore(
    FileItem file,
    List<FileItem> allFiles, {
    bool debug = false,
  }) {
    int score = 0;
    final lowerPath = file.path.toLowerCase();
    final lowerName = file.name.toLowerCase();
    final scoreDetails = <String>[];

    // 1. 目录类型评分
    if (_isInSystemNativeDirectory(lowerPath)) {
      score += _config.systemNativeDirectoryScore as int;
      scoreDetails.add('系统目录+${_config.systemNativeDirectoryScore}');
    } else {
      final userDirScore = _getUserCreatedDirectoryScore(lowerPath);
      if (userDirScore > 0) {
        score += userDirScore;
        scoreDetails.add('用户目录+$userDirScore');
      } else if (lowerPath.startsWith(_config.downloadDirectory)) {
        score += _config.downloadDirectoryScore as int;
        scoreDetails.add('下载目录+${_config.downloadDirectoryScore}');
      }
    }

    // 应用子目录扣分
    if (_isInAppSubdirectory(lowerPath)) {
      score -= _config.appSubdirectoryPenalty as int;
      scoreDetails.add('应用目录-${_config.appSubdirectoryPenalty}');
    }

    // 2. 文件名正向关键词
    if (_hasPositiveKeyword(lowerName)) {
      score += _config.positiveKeywordScore as int;
      scoreDetails.add('正向关键词+${_config.positiveKeywordScore}');
    }

    // 3. 路径名正向关键词
    if (_hasPositivePathKeyword(lowerPath)) {
      score += _config.positivePathKeywordScore as int;
      scoreDetails.add('路径关键词+${_config.positivePathKeywordScore}');
    }

    // 4. 文件大小（相对分数）
    final maxSize = allFiles.map((f) => f.size).reduce((a, b) => a > b ? a : b);
    final sizeScore = _getSizeScore(file.size, maxSize);
    score += sizeScore;
    scoreDetails.add('大小+$sizeScore');

    // 5. 负面特征扣分
    if (_hasNegativeKeyword(lowerName)) {
      score -= _config.negativeKeywordPenalty as int;
      scoreDetails.add('负向关键词-${_config.negativeKeywordPenalty}');
    }
    if (_hasNegativePathKeyword(lowerPath)) {
      score -= _config.negativePathKeywordPenalty as int;
      scoreDetails.add('负向路径-${_config.negativePathKeywordPenalty}');
    }
    if (_isInAppDataDirectory(lowerPath)) {
      score -= _config.appDataDirectoryPenalty as int;
      scoreDetails.add('应用数据-${_config.appDataDirectoryPenalty}');
    }
    if (_isHashOrRandomName(file.name)) {
      score -= _config.hashNamePenalty as int;
      scoreDetails.add('哈希命名-${_config.hashNamePenalty}');
    }
    if (_isInHiddenDirectory(lowerPath)) {
      score -= _config.hiddenDirectoryPenalty as int;
      scoreDetails.add('隐藏目录-${_config.hiddenDirectoryPenalty}');
    }
    if (_isPathTooDeep(lowerPath)) {
      score -= _config.pathTooDeepPenalty as int;
      scoreDetails.add('路径过深-${_config.pathTooDeepPenalty}');
    }

    // 6. 修改时间（相对分数）
    final latestTime =
        allFiles.map((f) => f.modified).reduce((a, b) => a.isAfter(b) ? a : b);
    final timeScore = _getTimeScore(file.modified, latestTime);
    score += timeScore;
    scoreDetails.add('时间+$timeScore');

    if (debug) {
      logger
          .i('Score for ${file.name}: $score\n  ${scoreDetails.join('\n  ')}');
    }

    return score;
  }

  // ==================== 检测方法 ====================

  bool _isInSystemNativeDirectory(String lowerPath) {
    return _config
        .getSystemNativeDirectories()
        .any((dir) => lowerPath.startsWith(dir));
  }

  int _getUserCreatedDirectoryScore(String lowerPath) {
    // 必须不是应用子目录
    if (_isInAppSubdirectory(lowerPath)) {
      return 0;
    }

    // 提取根目录后的路径
    const storageRoot = '/storage/emulated/0/';
    if (!lowerPath.startsWith(storageRoot)) {
      return 0;
    }

    final relativePath = lowerPath.substring(storageRoot.length);
    final segments =
        relativePath.split('/').where((s) => s.isNotEmpty).toList();

    // 至少要有一级目录
    if (segments.isEmpty) {
      return 0;
    }

    // 排除以点开头的隐藏目录
    if (segments[0].startsWith('.')) {
      return 0;
    }

    // 根据层级深度评分
    if (segments.length == 1) {
      return _config.userCreatedFirstLevelScore as int;
    } else if (segments.length == 2) {
      return _config.userCreatedSecondLevelScore as int;
    }

    // 三级及以上不加分
    return 0;
  }

  bool _isInAppSubdirectory(String lowerPath) {
    return _config.appSubdirectoryPatterns
        .any((pattern) => lowerPath.contains(pattern));
  }

  bool _hasPositiveKeyword(String lowerName) {
    return _config.positiveKeywords
        .any((keyword) => lowerName.contains(keyword.toLowerCase()));
  }

  bool _hasNegativeKeyword(String lowerName) {
    return _config.negativeKeywords
        .any((keyword) => lowerName.contains(keyword.toLowerCase()));
  }

  bool _hasPositivePathKeyword(String lowerPath) {
    return _config.positivePathKeywords
        .any((keyword) => lowerPath.contains(keyword.toLowerCase()));
  }

  bool _hasNegativePathKeyword(String lowerPath) {
    return _config.negativePathKeywords
        .any((keyword) => lowerPath.contains(keyword.toLowerCase()));
  }

  bool _isInAppDataDirectory(String lowerPath) {
    return _config.appDataPatterns
        .any((pattern) => lowerPath.contains(pattern.toLowerCase()));
  }

  bool _isHashOrRandomName(String fileName) {
    final nameWithoutExt = path.basenameWithoutExtension(fileName);
    final lower = nameWithoutExt.toLowerCase();

    // 规则1：纯数字（如：20231128_153045.jpg）
    if (RegExp(r'^[0-9_-]+$').hasMatch(lower)) {
      return true;
    }

    // 规则2：MD5/SHA格式（32或40个16进制字符）
    if (RegExp(r'^[a-f0-9]{32,40}$').hasMatch(lower)) {
      return true;
    }

    // 规则3：UUID格式
    if (RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')
        .hasMatch(lower)) {
      return true;
    }

    // 规则4：微信格式（mmexport + 时间戳）
    if (lower.startsWith('mmexport') || lower.startsWith('wx_camera')) {
      return true;
    }

    // 规则5：视频导出格式
    if (lower.startsWith('vid_') || lower.startsWith('img_')) {
      return true;
    }

    // 规则6：临时文件格式（包含.tmp字样的随机字符）
    if (lower.contains('.tmp') || lower.contains('temp')) {
      return true;
    }

    // 规则7：随机字符串（如 mmcokAag，包含大小写混合的无意义字符）
    if (nameWithoutExt.length >= 6 &&
        RegExp(r'^[a-zA-Z0-9]+$').hasMatch(nameWithoutExt) &&
        RegExp(r'[a-z]').hasMatch(nameWithoutExt) &&
        RegExp(r'[A-Z]').hasMatch(nameWithoutExt) &&
        !nameWithoutExt.contains('_') &&
        !nameWithoutExt.contains('-') &&
        !nameWithoutExt.contains(' ')) {
      return true;
    }

    return false;
  }

  bool _isInHiddenDirectory(String lowerPath) {
    final parts = lowerPath.split('/');
    return parts.any((part) => part.startsWith('.') && part.length > 1);
  }

  bool _isPathTooDeep(String filePath) {
    final parts = filePath.split('/');
    // Android内部存储基准是 /storage/emulated/0/（3层）
    // 使用配置的阈值，默认9层
    final threshold = (_config.pathDepthThreshold as int) + 3; // 加上基准3层
    return parts.length > threshold;
  }

  int _getSizeScore(int fileSize, int maxSize) {
    // 使用配置的大小相似度阈值，默认1KB
    final threshold = _config.sizeSimilarityThreshold as int;
    if ((maxSize - fileSize).abs() < threshold) {
      return 50;
    }

    // 按比例计算分数（0-100）
    if (maxSize == 0) return 50;
    return ((fileSize / maxSize) * 100).toInt();
  }

  int _getTimeScore(DateTime fileTime, DateTime latestTime) {
    final diffSeconds = latestTime.difference(fileTime).inSeconds.abs();

    // 使用配置的时间相似度阈值，默认1小时
    final timeSimilarityThreshold = _config.timeSimilarityThreshold as int;
    if (diffSeconds < timeSimilarityThreshold) {
      return 50;
    }

    // 使用配置的时间衰减因子，默认5分/天
    final decayPerDay = _config.timeDecayScorePerDay as int;
    final diffDays = diffSeconds ~/ 86400;
    final score = 100 - (diffDays * decayPerDay);
    return score.clamp(0, 100);
  }
}
