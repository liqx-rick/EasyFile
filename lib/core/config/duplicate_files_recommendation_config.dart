import 'dart:convert';

import 'package:easyfile/core/logger.dart';

import 'storage/config_storage.dart';

/// 重复文件推荐算法配置
///
/// 符合"强烈值得进Config"原则：
/// - 原则3: 推荐/排序/优先级规则
/// - 原则4: 风险开关（可禁用某些规则）
///
/// 职责：
/// 1. 管理推荐算法的配置参数（关键词、目录特征等）
/// 2. 支持远程配置下发和热更新
/// 3. 提供配置重置功能
class DuplicateFilesRecommendationConfig {
  final ConfigStorage _storage;
  static const String _keyPrefix = 'dup_rec_';

  DuplicateFilesRecommendationConfig(this._storage);

  // ==================== 系统原生目录（常量，不可修改） ====================

  /// 系统原生功能目录（优先级最高的子集）
  ///
  /// 这些是Android系统标准目录，由系统定义，不可修改：
  /// - /storage/emulated/0/DCIM - 相机照片
  /// - /storage/emulated/0/Sounds - 系统录音
  /// - /storage/emulated/0/Recordings - 系统录音
  /// - /storage/emulated/0/Music - 音乐库
  /// - /storage/emulated/0/Movies - 视频库
  /// - /storage/emulated/0/Pictures - 图片库
  /// - /storage/emulated/0/Documents - 文档库
  ///
  /// 这些目录中的文件推荐保留（+1500分），即使存在重复。
  static const List<String> systemNativeDirectories = [
    '/storage/emulated/0/dcim',
    '/storage/emulated/0/sounds',
    '/storage/emulated/0/recordings',
    '/storage/emulated/0/music',
    '/storage/emulated/0/movies',
    '/storage/emulated/0/pictures',
    '/storage/emulated/0/documents',
  ];

  /// 获取系统原生目录列表（实例方法，便于通过配置实例访问）
  List<String> getSystemNativeDirectories() => systemNativeDirectories;

  /// Download目录（临时下载目录，优先级低于用户自建目录）
  static const String _downloadDirectoryPath = '/storage/emulated/0/download/';

  /// 获取Download目录（实例getter，便于通过配置实例访问）
  String get downloadDirectory => _downloadDirectoryPath;

  // ==================== 可配置的应用特征 ====================

  /// 应用数据目录特征（可配置，支持远程下发）
  ///
  /// 包含应用包名和缓存目录标识。用户可通过管理员后台更新。
  ///
  /// 默认值包含主流应用，新应用流行后可动态更新。
  List<String> get appDataPatterns {
    final stored = _getStringList('app_data_patterns');
    if (stored.isNotEmpty) {
      return stored; // 使用自定义列表
    }
    // 返回内置默认值
    return _defaultAppDataPatterns;
  }

  /// 应用数据目录特征默认值
  static const List<String> _defaultAppDataPatterns = [
    // 腾讯系
    'com.tencent.mm',
    'com.tencent.mobileqq',
    'com.tencent.tmgp',
    // 字节系
    'com.ss.android',
    'com.douyin',
    'com.toutiao',
    // 阿里系
    'com.alibaba.android.rimet',
    'com.alipay.android.app',
    'com.taobao',
    // 百度系
    'com.baidu.netdisk',
    'com.baidu.searchbox',
    // 小红书
    'com.xingin.xhs',
    // 快手
    'com.kuaishou',
    // 高德
    'com.amap.android.ams',
    // 缓存目录标识
    '.cache',
    '.tmp',
    '.temp',
    'android/data',
    'android/obb',
  ];

  /// 应用子目录模式（可配置）
  ///
  /// 应用会在用户可见目录下创建子目录，这些子目录的优先级应低于用户自建目录。
  /// 当新应用流行时，可动态更新此列表。
  List<String> get appSubdirectoryPatterns {
    final stored = _getStringList('app_subdir_patterns');
    if (stored.isNotEmpty) {
      return stored;
    }
    return _defaultAppSubdirectoryPatterns;
  }

  /// 应用子目录模式默认值
  static const List<String> _defaultAppSubdirectoryPatterns = [
    // 社交应用
    '/weixin/',
    '/wechat/',
    '/tencent/',
    '/qq/',
    // 字节系
    '/douyin/',
    '/tiktok/',
    '/bytedance/',
    // 购物应用
    '/taobao/',
    '/alipay/',
    '/jd/',
    '/shopee/',
    '/lazada/',
    // 出行应用
    '/didi/',
    '/amap/',
    '/baidu/',
    // 内容平台
    '/bilibili/',
    '/kuaishou/',
    '/xiaohongshu/',
    '/redbook/',
    // 其他常见应用
    '/meituan/',
    '/netease/',
  ];

  // ==================== 可配置的关键词 ====================

  /// 正向关键词（推荐保留）
  List<String> get positiveKeywords {
    final stored = _getStringList('positive_keywords');
    if (stored.isNotEmpty) return stored;
    return _defaultPositiveKeywords;
  }

  /// 正向关键词默认值
  static const List<String> _defaultPositiveKeywords = [
    // 中文
    '最终版',
    '正式版',
    '完成版',
    '已修改',
    '已编辑',
    '已审核',
    '已批准',
    '定稿',
    '终版',
    '完稿',
    '修正',
    '更新',
    '保留',
    '最终',
    // 英文
    'final',
    'complete',
    'edited',
    'approved',
    'reviewed',
    'revised',
    'updated',
    'latest',
    'new',
    'corrected',
    'keep',
    // 版本标识
    'v2',
    'v3',
    'v4',
    'v5',
  ];

  /// 负向关键词（不推荐保留）
  List<String> get negativeKeywords {
    final stored = _getStringList('negative_keywords');
    if (stored.isNotEmpty) return stored;
    return _defaultNegativeKeywords;
  }

  /// 负向关键词默认值
  static const List<String> _defaultNegativeKeywords = [
    // 中文
    '副本',
    '复件',
    '临时',
    '待删除',
    '草稿',
    '旧版',
    '备份',
    '测试',
    '未完成',
    '待修改',
    '待审核',
    '拷贝',
    // 英文
    'copy',
    'temp',
    'temporary',
    'draft',
    'old',
    'backup',
    'delete',
    'remove',
    'test',
    'unfinished',
    'wip',
    'duplicate',
    'tmp',
    // 系统生成标记
    '副本 2',
    '副本 3',
    'copy (2)',
    'copy (3)',
    '(1)',
    '(2)',
    '(3)',
    '(4)',
    '(5)',
    '(6)',
  ];

  /// 正向路径关键词（路径中出现这些目录名，推荐保留）
  List<String> get positivePathKeywords {
    final stored = _getStringList('positive_path_keywords');
    if (stored.isNotEmpty) return stored;
    return _defaultPositivePathKeywords;
  }

  /// 正向路径关键词默认值
  static const List<String> _defaultPositivePathKeywords = [
    // 中文
    '工作文档',
    '重要文件',
    '个人资料',
    '项目',
    '作品',
    '我的照片',
    '相册',
    '收藏',
    '归档',
    '整理',
    '精选',
    // 英文
    'important',
    'work',
    'project',
    'personal',
    'portfolio',
    'archive',
    'organized',
    'collection',
    'favorite',
    'selected',
  ];

  /// 负向路径关键词（路径中出现这些目录名，不推荐保留）
  List<String> get negativePathKeywords {
    final stored = _getStringList('negative_path_keywords');
    if (stored.isNotEmpty) return stored;
    return _defaultNegativePathKeywords;
  }

  /// 负向路径关键词默认值
  static const List<String> _defaultNegativePathKeywords = [
    // 中文
    '缓存',
    '临时',
    '垃圾',
    '回收站',
    '草稿箱',
    '待删除',
    '旧文件',
    '废弃',
    // 英文
    'cache',
    'temp',
    'temporary',
    'trash',
    'recycle',
    'draft',
    'old',
    'backup',
    'clone',
    'dump',
    'junk',
  ];

  // ==================== 评分规则配置 ====================

  /// 系统原生目录加分
  int get systemNativeDirectoryScore => 1500;

  /// 用户自建一级目录加分
  int get userCreatedFirstLevelScore => 1000;

  /// 用户自建二级目录加分
  int get userCreatedSecondLevelScore => 800;

  /// Download目录加分
  int get downloadDirectoryScore => 500;

  /// 应用子目录扣分
  int get appSubdirectoryPenalty => 500;

  /// 文件名正向关键词加分
  int get positiveKeywordScore => 500;

  /// 文件名负向关键词扣分
  int get negativeKeywordPenalty => 300;

  /// 路径正向关键词加分
  int get positivePathKeywordScore => 300;

  /// 路径负向关键词扣分
  int get negativePathKeywordPenalty => 250;

  /// 应用数据目录扣分
  int get appDataDirectoryPenalty => 400;

  /// 哈希命名扣分
  int get hashNamePenalty => 200;

  /// 隐藏目录扣分
  int get hiddenDirectoryPenalty => 200;

  /// 路径过深扣分
  int get pathTooDeepPenalty => 150;

  // ==================== 算法参数配置 ====================

  /// 时间评分衰减因子（每天扣除的分数）
  ///
  /// 默认值：5分/天
  /// - 意味着20天后时间因素完全不起作用（100分扣完）
  /// - 产品可根据用户反馈调整衰减速度
  /// - 较大值：更重视时间新鲜度
  /// - 较小值：降低时间因素的权重
  int get timeDecayScorePerDay => _getInt('time_decay_per_day', defaultValue: 5);

  /// 大小相似度阈值（字节）
  ///
  /// 默认值：1024字节（1KB）
  /// - 小于此差异认为文件大小相同，不参与评分
  /// - 避免微小差异影响推荐结果
  int get sizeSimilarityThreshold => _getInt('size_similarity_bytes', defaultValue: 1024);

  /// 时间相似度阈值（秒）
  ///
  /// 默认值：3600秒（1小时）
  /// - 小于此差异认为修改时间相同，不参与评分
  /// - 避免短时间内的多次修改影响推荐
  int get timeSimilarityThreshold => _getInt('time_similarity_seconds', defaultValue: 3600);

  /// 路径深度阈值（层数）
  ///
  /// 默认值：9层
  /// - 超过此深度认为路径过深，扣除 pathTooDeepPenalty 分数
  /// - 深层目录通常是系统或应用自动生成的
  int get pathDepthThreshold => _getInt('path_depth_threshold', defaultValue: 9);

  // ==================== 算法参数更新接口 ====================

  /// 更新时间衰减因子
  Future<void> setTimeDecayScorePerDay(int score) async {
    if (score < 1 || score > 20) {
      throw ArgumentError('Time decay score must be between 1 and 20');
    }
    await _setInt('time_decay_per_day', score);
    logger.i('Updated time decay score to $score per day');
  }

  /// 更新大小相似度阈值
  Future<void> setSizeSimilarityThreshold(int bytes) async {
    if (bytes < 0) {
      throw ArgumentError('Size similarity threshold must be non-negative');
    }
    await _setInt('size_similarity_bytes', bytes);
    logger.i('Updated size similarity threshold to $bytes bytes');
  }

  /// 更新时间相似度阈值
  Future<void> setTimeSimilarityThreshold(int seconds) async {
    if (seconds < 0) {
      throw ArgumentError('Time similarity threshold must be non-negative');
    }
    await _setInt('time_similarity_seconds', seconds);
    logger.i('Updated time similarity threshold to $seconds seconds');
  }

  /// 更新路径深度阈值
  Future<void> setPathDepthThreshold(int depth) async {
    if (depth < 1) {
      throw ArgumentError('Path depth threshold must be at least 1');
    }
    await _setInt('path_depth_threshold', depth);
    logger.i('Updated path depth threshold to $depth layers');
  }

  // ==================== 更新接口 ====================

  /// 更新应用数据目录特征（支持远程配置下发）
  Future<void> updateAppDataPatterns(List<String> patterns) async {
    await _setStringList('app_data_patterns', patterns);
    logger.i('Updated app data patterns: ${patterns.length} items');
  }

  /// 更新应用子目录模式
  Future<void> updateAppSubdirectoryPatterns(List<String> patterns) async {
    await _setStringList('app_subdir_patterns', patterns);
    logger.i('Updated app subdir patterns: ${patterns.length} items');
  }

  /// 更新正向关键词
  Future<void> updatePositiveKeywords(List<String> keywords) async {
    await _setStringList('positive_keywords', keywords);
    logger.i('Updated positive keywords: ${keywords.length} items');
  }

  /// 更新负向关键词
  Future<void> updateNegativeKeywords(List<String> keywords) async {
    await _setStringList('negative_keywords', keywords);
    logger.i('Updated negative keywords: ${keywords.length} items');
  }

  /// 重置为默认值
  Future<void> reset() async {
    final keys = _storage.getKeys().where((key) => key.startsWith(_keyPrefix)).toList();

    for (final key in keys) {
      await _storage.remove(key);
    }
    logger.i('Reset duplicate files recommendation config to defaults');
  }

  // ==================== 内部实现 ====================

  int _getInt(String key, {required int defaultValue}) {
    return _storage.getInt('$_keyPrefix$key') ?? defaultValue;
  }

  Future<void> _setInt(String key, int value) async {
    await _storage.setInt('$_keyPrefix$key', value);
  }

  List<String> _getStringList(String key) {
    final json = _storage.getString('$_keyPrefix$key');
    if (json == null) return [];
    try {
      return List<String>.from(jsonDecode(json) as List<dynamic>);
    } catch (e) {
      logger.w('Failed to parse $key: $e');
      return [];
    }
  }

  Future<void> _setStringList(String key, List<String> values) async {
    await _storage.setString('$_keyPrefix$key', jsonEncode(values));
  }
}
