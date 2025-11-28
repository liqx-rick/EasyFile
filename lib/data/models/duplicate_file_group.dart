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
    required this.files,
    required this.fileSize,
  }) : assert(files.length >= 2, 'Duplicate group must have at least 2 files');
  
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
    '副本 2', '副本 3', 'copy (2)', 'copy (3)', '(1)', '(2)', '(3)', '(4)', '(5)', '(6)',
  ];
  
  /// 应用数据目录特征
  static const _appDataPatterns = [
    'com.tencent.mm',        // 微信
    'com.tencent.mobileqq',  // QQ
    'com.ss.android',        // 字节系
    'com.alibaba',           // 阿里系
    'com.baidu',             // 百度系
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
  
  /// 重要位置路径（用户常用目录）
  static const _importantLocations = [
    '/storage/emulated/0/dcim',        // 相机照片
    '/storage/emulated/0/pictures',    // 图片
    '/storage/emulated/0/documents',   // 文档
    '/storage/emulated/0/movies',      // 电影
    '/storage/emulated/0/music',       // 音乐
  ];
  
  // ==================== 评分系统 ====================
  
  /// 计算文件的推荐保留分数（分数越高越推荐保留）
  int _calculateRecommendScore(FileItem file) {
    int score = 0;
    final lowerPath = file.path.toLowerCase();
    final lowerName = file.name.toLowerCase();
    
    // 1. 用户重要位置 (+1000分，最高优先级)
    if (_isInImportantLocation(lowerPath)) {
      score += 1000;
    }
    
    // 2. 正向关键词 (+500分)
    if (_hasPositiveKeyword(lowerName)) {
      score += 500;
    }
    
    // 2.5 路径名正向关键词 (+300分)
    if (_hasPositivePathKeyword(lowerPath)) {
      score += 300;
    }
    
    // 3. 文件大小（相对分数，0-100分）
    final maxSize = files.map((f) => f.size).reduce((a, b) => a > b ? a : b);
    score += _getSizeScore(file.size, maxSize);
    
    // 4. 负面特征（扣分）
    if (_hasNegativeKeyword(lowerName)) {
      score -= 300;
    }
    if (_hasNegativePathKeyword(lowerPath)) {
      score -= 250;
    }
    if (_isInAppDataDirectory(lowerPath)) {
      score -= 400;
    }
    if (_isHashOrRandomName(file.name)) {
      score -= 200;
    }
    if (_isInHiddenDirectory(lowerPath)) {
      score -= 200;
    }
    if (_isPathTooDeep(lowerPath)) {
      score -= 150;
    }
    
    // 5. 修改时间（相对分数，0-100分）
    final latestTime = files.map((f) => f.modified).reduce((a, b) => 
      a.isAfter(b) ? a : b
    );
    score += _getTimeScore(file.modified, latestTime);
    
    return score;
  }
  
  /// 检查是否在重要位置
  bool _isInImportantLocation(String lowerPath) {
    return _importantLocations.any((loc) => lowerPath.startsWith(loc));
  }
  
  /// 检查是否包含正向关键词
  bool _hasPositiveKeyword(String lowerName) {
    return _positiveKeywords.any((keyword) => 
      lowerName.contains(keyword.toLowerCase())
    );
  }
  
  /// 检查是否包含负向关键词
  bool _hasNegativeKeyword(String lowerName) {
    return _negativeKeywords.any((keyword) => 
      lowerName.contains(keyword.toLowerCase())
    );
  }
  
  /// 检查路径是否包含正向关键词
  bool _hasPositivePathKeyword(String lowerPath) {
    return _positivePathKeywords.any((keyword) => 
      lowerPath.contains(keyword.toLowerCase())
    );
  }
  
  /// 检查路径是否包含负向关键词
  bool _hasNegativePathKeyword(String lowerPath) {
    return _negativePathKeywords.any((keyword) => 
      lowerPath.contains(keyword.toLowerCase())
    );
  }
  
  /// 检查是否在应用数据目录
  bool _isInAppDataDirectory(String lowerPath) {
    return _appDataPatterns.any((pattern) => 
      lowerPath.contains(pattern.toLowerCase())
    );
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
    if (RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$')
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
  FileItem get recommendedToKeep {
    return files.reduce((a, b) {
      final scoreA = _calculateRecommendScore(a);
      final scoreB = _calculateRecommendScore(b);
      return scoreA > scoreB ? a : b;
    });
  }
  
  /// 建议删除的文件列表
  List<FileItem> get recommendedToDelete {
    final keep = recommendedToKeep;
    return files.where((f) => f.path != keep.path).toList();
  }
  
  /// 转换为 Map（用于持久化）
  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'files': files.map((f) => {
        'name': f.name,
        'path': f.path,
        'size': f.size,
        'modified': f.modified.millisecondsSinceEpoch,
      }).toList(),
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
