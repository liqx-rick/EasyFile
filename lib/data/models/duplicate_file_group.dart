import 'package:easyfile/data/models/file_item.dart';
import 'package:path/path.dart' as path;

/// 重复文件组
///
/// 表示一组内容完全相同的文件
class DuplicateFileGroup {
  /// 该组的唯一标识（使用完整哈希）
  final String groupId;

  /// 重复的文件列表（至少2个）
  final List<FileItem> files;

  /// 该组文件的大小（字节）
  final int fileSize;

  DuplicateFileGroup({
    required this.groupId,
    required List<FileItem> files,
    required this.fileSize,
  })  : files = _sortFilesByRecommendation(files),
        assert(files.length >= 2, 'Duplicate group must have at least 2 files');

  /// 对文件列表排序（推荐保留的排在第一位）
  static List<FileItem> _sortFilesByRecommendation(List<FileItem> files) {
    if (files.length < 2) return files;

    // 创建临时组用于计算推荐分数
    final tempGroup = DuplicateFileGroup._internal(
      groupId: 'temp',
      files: files,
      fileSize: files.first.size,
    );

    // 计算每个文件的分数（带详细日志）
    print('[DuplicateFileGroup] 🔍 开始计算${files.length}个文件的推荐分数:');
    final fileScores = <FileItem, int>{};
    for (final file in files) {
      fileScores[file] = tempGroup._calculateRecommendScore(file, debug: true);
    }

    // 按推荐分数从高到低排序
    final sortedFiles = List<FileItem>.from(files);
    sortedFiles.sort((a, b) {
      final scoreA = fileScores[a]!;
      final scoreB = fileScores[b]!;
      return scoreB.compareTo(scoreA); // 降序排列（分数高的在前）
    });

    // 输出排序结果
    print('[DuplicateFileGroup] ✅ 排序完成:');
    final displayCount = sortedFiles.length > 3 ? 3 : sortedFiles.length;
    for (var i = 0; i < displayCount; i++) {
      final file = sortedFiles[i];
      final score = fileScores[file]!;
      final label = i == 0 ? '✅推荐保留' : '❌建议删除';
      print('  [$i] $label ${file.name} (总分: $score)');
    }
    if (sortedFiles.length > 3) {
      print('  ... 还有${sortedFiles.length - 3}个文件');
    }
    print('');

    return sortedFiles;
  }

  /// 内部构造函数（用于排序时的临时对象）
  DuplicateFileGroup._internal({
    required this.groupId,
    required this.files,
    required this.fileSize,
  });

  /// 重复文件数量
  int get count => files.length;

  /// 可释放的空间（保留1个，删除其余）
  int get reclaimableSpace => fileSize * (count - 1);

  // ==================== 智能推荐算法配置 ====================

  /// 正向关键词（推荐保留）
  static const _positiveKeywords = [
    // 中文
    '最终版', '正式版', '完成版', '已修改', '已编辑', '已审核', '已批准',
    '定稿', '终版', '完稿', '修正', '更新',
    // 英文
    'final', 'complete', 'edited', 'approved', 'reviewed',
    'revised', 'updated', 'latest', 'new', 'corrected',
    // 版本标识
    'v2', 'v3', 'v4', 'v5',
  ];

  /// 负向关键词（不推荐保留）
  static const _negativeKeywords = [
    // 中文
    '副本', '复件', '临时', '待删除', '草稿', '旧版', '备份',
    '测试', '未完成', '待修改', '待审核', '拷贝',
    // 英文
    'copy', 'temp', 'temporary', 'draft', 'old', 'backup',
    'delete', 'remove', 'test', 'unfinished', 'wip', 'duplicate', 'tmp',
    // 系统生成标记
    '副本 2', '副本 3', 'copy (2)', 'copy (3)', '(1)', '(2)', '(3)', '(4)', '(5)',
    '(6)',
  ];

  /// 应用数据目录特征
  static const _appDataPatterns = [
    'com.tencent.mm', // 微信
    'com.tencent.mobileqq', // QQ
    'com.ss.android', // 字节系
    'com.alibaba', // 阿里系
    'com.baidu', // 百度系
    '.cache',
    '.tmp',
    '.temp',
    'android/data',
    'android/obb',
  ];

  /// 正向路径关键词（路径中出现这些目录名，推荐保留）
  static const _positivePathKeywords = [
    // 中文
    '工作文档', '重要文件', '个人资料', '项目', '作品', '我的照片',
    '相册', '收藏', '归档', '整理', '精选',
    // 英文
    'important', 'work', 'project', 'personal', 'portfolio',
    'archive', 'organized', 'collection', 'favorite', 'selected',
  ];

  /// 负向路径关键词（路径中出现这些目录名，不推荐保留）
  static const _negativePathKeywords = [
    // 中文
    '缓存', '临时', '垃圾', '回收站', '草稿箱', '待删除', '旧文件', '废弃',
    // 英文
    'cache', 'temp', 'temporary', 'trash', 'recycle', 'draft',
    'old', 'backup', 'clone', 'dump', 'junk',
  ];

  /// 系统原生功能目录（优先级最高的子集）
  static const _systemNativeDirectories = [
    '/storage/emulated/0/dcim', // 相机照片
    '/storage/emulated/0/sounds', // 系统录音
    '/storage/emulated/0/recordings', // 系统录音
    '/storage/emulated/0/music', // 音乐库
    '/storage/emulated/0/movies', // 视频库
    '/storage/emulated/0/pictures', // 图片库
    '/storage/emulated/0/documents', // 文档库
  ];

  // Download目录（临时下载目录，优先级低于用户自建目录）
  static const String _downloadDirectory = '/storage/emulated/0/download/';

  /// 应用子目录模式（在系统目录下的应用生成目录，优先级降低）
  static const _appSubdirectoryPatterns = [
    '/weixin/',
    '/wechat/',
    '/tencent/',
    '/qq/',
    '/douyin/',
    '/tiktok/',
    '/baidu/',
    '/taobao/',
    '/alipay/',
    '/jd/',
    '/meituan/',
    '/didi/',
    '/bilibili/',
    '/kuaishou/',
    '/xiaohongshu/',
  ];

  // ==================== 评分系统 ====================

  /// 计算文件的推荐保留分数（分数越高越推荐保留）
  ///
  /// 评分维度（优先级从高到低）：
  /// 1. 目录类型评分：
  ///    - 系统原生功能目录（DCIM/Sounds/Recordings等）：+1500
  ///    - 用户自建一级目录（如 /曲艺/）：+1000
  ///    - 用户自建二级目录（如 /曲艺/浅草课程/）：+800
  ///    - Download目录：+500
  ///    - 应用子目录（weixin/qq等）：-500
  /// 2. 文件名关键词：正向+500，负向-300
  /// 3. 路径关键词：正向+300，负向-250
  /// 4. 文件大小：相对分数0-100
  /// 5. 修改时间：相对分数0-100
  /// 6. 其他负面特征：应用数据目录-400，哈希命名-200，隐藏目录-200，路径过深-150
  int _calculateRecommendScore(FileItem file, {bool debug = false}) {
    int score = 0;
    final lowerPath = file.path.toLowerCase();
    final lowerName = file.name.toLowerCase();
    final scoreDetails = <String>[];

    // 1. 目录类型评分（层级检测，优先级：系统原生 > 用户自建 > Download）
    if (_isInSystemNativeDirectory(lowerPath)) {
      score += 1500;
      scoreDetails.add('系统目录+1500');
    } else {
      final userDirScore = _getUserCreatedDirectoryScore(lowerPath);
      if (userDirScore > 0) {
        score += userDirScore;
        scoreDetails.add('用户目录+$userDirScore');
      } else if (lowerPath.startsWith(_downloadDirectory)) {
        score += 500;
        scoreDetails.add('下载目录+500');
      }
    }

    // 应用子目录扣分（独立检测，可与系统/用户目录叠加）
    if (_isInAppSubdirectory(lowerPath)) {
      score -= 500;
      scoreDetails.add('应用目录-500');
    }

    // 2. 文件名正向关键词
    if (_hasPositiveKeyword(lowerName)) {
      score += 500;
      scoreDetails.add('正向关键词+500');
    }

    // 3. 路径名正向关键词
    if (_hasPositivePathKeyword(lowerPath)) {
      score += 300;
      scoreDetails.add('路径关键词+300');
    }

    // 4. 文件大小（相对分数）
    final maxSize = files.map((f) => f.size).reduce((a, b) => a > b ? a : b);
    final sizeScore = _getSizeScore(file.size, maxSize);
    score += sizeScore;
    scoreDetails.add('大小+$sizeScore');

    // 5. 负面特征扣分
    if (_hasNegativeKeyword(lowerName)) {
      score -= 300;
      scoreDetails.add('负向关键词-300');
    }
    if (_hasNegativePathKeyword(lowerPath)) {
      score -= 250;
      scoreDetails.add('负向路径-250');
    }
    if (_isInAppDataDirectory(lowerPath)) {
      score -= 400;
      scoreDetails.add('应用数据-400');
    }
    if (_isHashOrRandomName(file.name)) {
      score -= 200;
      scoreDetails.add('哈希命名-200');
    }
    if (_isInHiddenDirectory(lowerPath)) {
      score -= 200;
      scoreDetails.add('隐藏目录-200');
    }
    if (_isPathTooDeep(lowerPath)) {
      score -= 150;
      scoreDetails.add('路径过深-150');
    }

    // 6. 修改时间（相对分数）
    final latestTime =
        files.map((f) => f.modified).reduce((a, b) => a.isAfter(b) ? a : b);
    final timeScore = _getTimeScore(file.modified, latestTime);
    score += timeScore;
    scoreDetails.add('时间+$timeScore');

    if (debug) {
      print('    📊 ${file.name}: $score分 (${scoreDetails.join(", ")})');
    }

    return score;
  }

  /// 检查是否在系统原生功能目录（最高优先级）
  bool _isInSystemNativeDirectory(String lowerPath) {
    return _systemNativeDirectories.any((dir) => lowerPath.startsWith(dir));
  }

  /// 计算用户自建目录分数
  ///
  /// 检测逻辑：
  /// 1. 排除应用子目录（weixin/qq 等）
  /// 2. 必须在内部存储根目录下（/storage/emulated/0/）
  /// 3. 根据层级深度评分：
  ///    - 一级目录：+1000分（如 /storage/emulated/0/曲艺/）
  ///    - 二级目录：+800分（如 /storage/emulated/0/曲艺/浅草课程/）
  ///    - 三级及以上：0分（可能是临时文件）
  /// 4. 排除隐藏目录（以.开头）
  int _getUserCreatedDirectoryScore(String lowerPath) {
    // 必须不是应用子目录
    if (_isInAppSubdirectory(lowerPath)) {
      return 0;
    }

    // 提取根目录后的路径
    final storageRoot = '/storage/emulated/0/';
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
      // 根目录直接子目录：/storage/emulated/0/曲艺/xxx.mp3
      return 1000;
    } else if (segments.length == 2) {
      // 根目录二级子目录：/storage/emulated/0/曲艺/浅草课程/xxx.mp3
      return 800;
    }

    // 三级及以上不加分（可能是临时文件）
    return 0;
  }

  /// 检查是否在应用子目录
  bool _isInAppSubdirectory(String lowerPath) {
    return _appSubdirectoryPatterns
        .any((pattern) => lowerPath.contains(pattern));
  }

  /// 检查是否包含正向关键词
  bool _hasPositiveKeyword(String lowerName) {
    return _positiveKeywords
        .any((keyword) => lowerName.contains(keyword.toLowerCase()));
  }

  /// 检查是否包含负向关键词
  bool _hasNegativeKeyword(String lowerName) {
    return _negativeKeywords
        .any((keyword) => lowerName.contains(keyword.toLowerCase()));
  }

  /// 检查路径是否包含正向关键词
  bool _hasPositivePathKeyword(String lowerPath) {
    return _positivePathKeywords
        .any((keyword) => lowerPath.contains(keyword.toLowerCase()));
  }

  /// 检查路径是否包含负向关键词
  bool _hasNegativePathKeyword(String lowerPath) {
    return _negativePathKeywords
        .any((keyword) => lowerPath.contains(keyword.toLowerCase()));
  }

  /// 检查是否在应用数据目录
  bool _isInAppDataDirectory(String lowerPath) {
    return _appDataPatterns
        .any((pattern) => lowerPath.contains(pattern.toLowerCase()));
  }

  /// 检查是否为哈希或随机文件名
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
    // 检测：长度>=6且大小写混合但没有空格或连字符
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

  /// 检查是否在隐藏目录
  bool _isInHiddenDirectory(String lowerPath) {
    final parts = lowerPath.split('/');
    return parts.any((part) => part.startsWith('.') && part.length > 1);
  }

  /// 检查路径是否过深
  bool _isPathTooDeep(String filePath) {
    final parts = filePath.split('/');
    // Android内部存储基准是 /storage/emulated/0/（3层）
    // 如果总深度 > 9 层（基准3层 + 用户6层），认为太深
    return parts.length > 9;
  }

  /// 计算文件大小分数（0-100）
  int _getSizeScore(int fileSize, int maxSize) {
    // 大小差异小于1KB，认为相同，返回中性分
    if ((maxSize - fileSize).abs() < 1024) {
      return 50;
    }

    // 按比例计算分数（0-100）
    if (maxSize == 0) return 50;
    return ((fileSize / maxSize) * 100).toInt();
  }

  /// 计算修改时间分数（0-100）
  int _getTimeScore(DateTime fileTime, DateTime latestTime) {
    final diffSeconds = latestTime.difference(fileTime).inSeconds.abs();

    // 时间差小于1小时，认为相同，返回中性分
    if (diffSeconds < 3600) {
      return 50;
    }

    // 最新的文件得100分，时间每相差1天扣5分，最低0分
    final diffDays = diffSeconds ~/ 86400;
    final score = 100 - (diffDays * 5);
    return score.clamp(0, 100);
  }

  /// 建议保留的文件（使用智能评分算法）
  ///
  /// 由于构造函数已经对 files 列表排序（推荐保留的在第一位），
  /// 直接返回第一个文件即可
  FileItem get recommendedToKeep {
    return files.first;
  }

  /// 建议删除的文件列表
  List<FileItem> get recommendedToDelete {
    return files.skip(1).toList();
  }

  /// 转换为 Map（用于持久化）
  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'files': files
          .map((f) => {
                'name': f.name,
                'path': f.path,
                'size': f.size,
                'modified': f.modified.millisecondsSinceEpoch,
              })
          .toList(),
      'fileSize': fileSize,
    };
  }

  /// 从 Map 创建
  factory DuplicateFileGroup.fromJson(Map<String, dynamic> json) {
    final filesList = (json['files'] as List<dynamic>).map((fileJson) {
      return FileItem(
        name: fileJson['name'] as String,
        path: fileJson['path'] as String,
        isDirectory: false,
        size: fileJson['size'] as int,
        modified: DateTime.fromMillisecondsSinceEpoch(
          fileJson['modified'] as int,
        ),
      );
    }).toList();

    return DuplicateFileGroup(
      groupId: json['groupId'] as String,
      files: filesList,
      fileSize: json['fileSize'] as int,
    );
  }
}
