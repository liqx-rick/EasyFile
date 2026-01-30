import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/initialization_stage.dart';

import 'initialization_config.dart';

/// 混合权重进度计算器
///
/// 设计理念：
/// - 根据InitializationConfig动态计算阶段权重
/// - 权重归一化确保总和始终为1.0
/// - 阶段进度限制在0.95以内，防止卡死
/// - 保证总进度必然达到100%
///
/// 使用示例：
/// ```dart
/// final calculator = RobustProgressCalculator(
///   config: InitializationConfig.quickStart(),
/// );
///
/// // 扫描图片时
/// final progress = calculator.calculateProgress(
///   phase: 'p1_images',
///   stageProgress: 0.5,  // 当前阶段50%
/// );
/// ```
class RobustProgressCalculator {
  /// 基础阶段权重（相对权重，用于计算比例）
  ///
  /// 这些是参考权重，实际权重会根据配置动态调整
  static const Map<String, double> _baseWeights = {
    // P0: 基础初始化
    'p0_init': 0.02,

    // P1.1: 分类文件扫描
    'p1_images': 0.12,
    'p1_video': 0.10,
    'p1_music': 0.10,
    'p1_documents': 0.12,
    'p1_downloads': 0.08,
    'p1_apk': 0.08,
    'p1_archive': 0.08,

    // P1.2: 推荐应用扫描
    'p1_apps': 0.20,

    // P2: 文件夹检测
    'p2_folders': 0.10,
  };

  /// 当前配置
  final InitializationConfig _config;

  /// 有效权重（根据配置动态计算并归一化）
  late final Map<String, double> _effectiveWeights;

  RobustProgressCalculator({InitializationConfig? config}) : _config = config ?? InitializationConfig.full() {
    _effectiveWeights = _calculateEffectiveWeights();
    logger.d('[ProgressCalc] Initialized with config: $_config');
    logger.d('[ProgressCalc] Effective weights: ${_formatWeights(_effectiveWeights)}');
  }

  /// 根据配置计算有效权重（归一化到1.0）
  Map<String, double> _calculateEffectiveWeights() {
    final weights = <String, double>{};

    // P0: 始终执行
    weights['p0_init'] = _baseWeights['p0_init']!;

    // P1.1: 根据配置决定是否包含分类扫描
    if (_config.enableP1CategoryScan) {
      weights['p1_images'] = _baseWeights['p1_images']!;
      weights['p1_video'] = _baseWeights['p1_video']!;
      weights['p1_music'] = _baseWeights['p1_music']!;
      weights['p1_documents'] = _baseWeights['p1_documents']!;
      weights['p1_downloads'] = _baseWeights['p1_downloads']!;
      weights['p1_apk'] = _baseWeights['p1_apk']!;
      weights['p1_archive'] = _baseWeights['p1_archive']!;
    }

    // P1.2: 根据配置决定是否包含应用扫描
    if (_config.enableP1AppScan) {
      weights['p1_apps'] = _baseWeights['p1_apps']!;
    }

    // P2: 始终执行
    weights['p2_folders'] = _baseWeights['p2_folders']!;

    // 归一化：确保总和为1.0
    return _normalizeWeights(weights);
  }

  /// 归一化权重（总和调整为1.0）
  Map<String, double> _normalizeWeights(Map<String, double> weights) {
    final sum = weights.values.fold<double>(0, (a, b) => a + b);
    if (sum == 0) {
      logger.e('[ProgressCalc] Sum of weights is 0!');
      return weights;
    }

    final normalized = weights.map((phase, weight) => MapEntry(phase, weight / sum));

    logger.d('[ProgressCalc] Normalization: sum=$sum');
    return normalized;
  }

  /// 格式化权重用于日志输出
  String _formatWeights(Map<String, double> weights) {
    final buffer = StringBuffer();
    weights.forEach((phase, weight) {
      buffer.write('$phase=${(weight * 100).toStringAsFixed(1)}% ');
    });
    return buffer.toString().trim();
  }

  /// 计算当前总进度（使用动态权重）
  ///
  /// [completedPhases] 已完成的阶段列表
  /// [currentPhase] 当前正在执行的阶段
  /// [stageProgress] 当前阶段的内部进度 (0.0 - 1.0)
  ///
  /// 返回: 总进度 (0.0 - 1.0)
  double calculateProgress({
    List<String> completedPhases = const [],
    required String currentPhase,
    required double stageProgress,
  }) {
    // 1. 计算已完成阶段的权重总和（使用有效权重）
    double completedWeight = 0.0;
    for (final phase in completedPhases) {
      final weight = _effectiveWeights[phase];
      if (weight != null) {
        completedWeight += weight;
      } else {
        // 忽略未在有效权重中的阶段（可能被配置禁用）
        logger.d('[ProgressCalc] Phase not in effective weights (skipped): $phase');
      }
    }

    // 2. 获取当前阶段权重（使用有效权重）
    final currentWeight = _effectiveWeights[currentPhase];
    if (currentWeight == null) {
      logger.w('[ProgressCalc] Current phase not in effective weights: $currentPhase');
      return completedWeight.clamp(0.0, 1.0); // 返回已完成的进度
    }

    // 3. 限制阶段内进度最大为0.95，防止卡死
    final clampedStageProgress = stageProgress.clamp(0.0, 0.95);

    if (stageProgress > 0.95) {
      logger.d('[ProgressCalc] Stage progress clamped: $stageProgress -> $clampedStageProgress (phase: $currentPhase)');
    }

    // 4. 计算总进度
    final totalProgress = completedWeight + (currentWeight * clampedStageProgress);

    return totalProgress.clamp(0.0, 1.0);
  }

  /// 根据实际扫描文件数生成阶段信息
  ///
  /// [phase] 阶段标识
  /// [scannedCount] 已扫描文件数
  /// [estimatedTotal] 估计总文件数（可选，null表示未知）
  InitializationStage buildStage({
    required String phase,
    required int scannedCount,
    int? estimatedTotal,
  }) {
    String message;
    String? detail;

    switch (phase) {
      case 'p0_init':
        message = '⚡ 加载基础资源';
        detail = '快速访问、收藏夹';
        break;

      case 'p1_images':
        message = '📷 扫描图片';
        detail = scannedCount > 0 ? '已找到 ${_formatCount(scannedCount)} 张照片' : '正在搜索照片...';
        break;

      case 'p1_video':
        message = '🎬 扫描视频';
        detail = scannedCount > 0 ? '已找到 ${_formatCount(scannedCount)} 个视频' : '正在搜索视频...';
        break;

      case 'p1_music':
        message = '🎵 扫描音频';
        detail = scannedCount > 0 ? '已找到 ${_formatCount(scannedCount)} 首歌曲' : '正在搜索音乐...';
        break;

      case 'p1_documents':
        message = '📄 扫描文档';
        detail = scannedCount > 0 ? '已找到 ${_formatCount(scannedCount)} 份文档' : '正在搜索文档...';
        break;

      case 'p1_downloads':
        message = '📥 扫描下载';
        detail = scannedCount > 0 ? '已找到 ${_formatCount(scannedCount)} 个文件' : '正在检查下载文件...';
        break;

      case 'p1_apk':
        message = '� 扫描下载';
        detail = scannedCount > 0 ? '已找到 ${_formatCount(scannedCount)} 个安装包' : '正在检查下载文件...';
        break;

      case 'p1_archive':
        message = '📥 扫描下载';
        detail = scannedCount > 0 ? '已找到 ${_formatCount(scannedCount)} 个压缩包' : '正在检查下载文件...';
        break;

      case 'p1_apps':
        message = '📱 扫描推荐应用';
        detail = scannedCount > 0 ? '已检测 ${_formatCount(scannedCount)} 个应用' : '正在检测已安装应用...';
        break;

      case 'p2_folders':
        message = '📂 检测常用文件夹';
        detail = scannedCount > 0 ? '已发现 ${_formatCount(scannedCount)} 个文件夹' : '正在分析文件夹结构...';
        break;

      default:
        message = '正在初始化...';
        detail = null;
    }

    return InitializationStage(
      phase: phase,
      message: message,
      detail: detail,
      current: scannedCount,
      total: estimatedTotal,
    );
  }

  /// 格式化计数（添加千分位分隔符）
  String _formatCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 10000) {
      final thousands = count ~/ 1000;
      final hundreds = count % 1000;
      return '$thousands,${hundreds.toString().padLeft(3, '0')}';
    }
    // 超过1万，使用简化显示
    final wan = count / 10000;
    return '${wan.toStringAsFixed(1)}万';
  }
}
