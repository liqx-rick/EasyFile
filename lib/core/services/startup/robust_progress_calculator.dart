import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/initialization_stage.dart';

/// 混合权重进度计算器
///
/// 设计理念：
/// - 使用固定阶段权重，不依赖文件数量估计
/// - 估计仅影响阶段内部的进度平滑度
/// - 阶段进度限制在0.95以内，防止卡死
/// - 保证总进度必然达到100%
///
/// 使用示例：
/// ```dart
/// final calculator = RobustProgressCalculator();
///
/// // 扫描图片时
/// final progress = calculator.calculateProgress(
///   phase: 'p1_images',
///   stageProgress: 0.5,  // 当前阶段50%
/// );
/// // progress = 0.02 + 0.12 * 0.5 = 0.08 (8%)
/// ```
class RobustProgressCalculator {
  /// 固定阶段权重（总和 = 1.0）
  ///
  /// P0 阶段（2%）：
  /// - p0_init: 基础资源加载
  ///
  /// P1 阶段（88%）：
  /// - p1_images: 图片扫描 (12%)
  /// - p1_video: 视频扫描 (10%)
  /// - p1_music: 音频扫描 (10%)
  /// - p1_documents: 文档扫描 (12%)
  /// - p1_downloads: 下载扫描 (8%)
  /// - p1_apk: APK扫描 (8%)
  /// - p1_archive: 压缩包扫描 (8%)
  /// - p1_apps: 推荐应用扫描 (20%)
  ///
  /// P2 阶段（10%）：
  /// - p2_folders: 快速访问文件夹检测
  static const Map<String, double> stageWeights = {
    // P0: 基础初始化
    'p0_init': 0.02,

    // P1.1: 分类文件扫描 (68%)
    'p1_images': 0.12,
    'p1_video': 0.10,
    'p1_music': 0.10,
    'p1_documents': 0.12,
    'p1_downloads': 0.08,
    'p1_apk': 0.08,
    'p1_archive': 0.08,

    // P1.2: 推荐应用扫描 (20%)
    'p1_apps': 0.20,

    // P2: 文件夹检测 (10%)
    'p2_folders': 0.10,
  };

  /// 计算当前总进度
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
    // 1. 计算已完成阶段的权重总和
    double completedWeight = 0.0;
    for (final phase in completedPhases) {
      final weight = stageWeights[phase];
      if (weight != null) {
        completedWeight += weight;
      } else {
        logger.w('Unknown completed phase: $phase');
      }
    }

    // 2. 获取当前阶段权重
    final currentWeight = stageWeights[currentPhase];
    if (currentWeight == null) {
      logger.e('Unknown current phase: $currentPhase');
      return completedWeight; // 返回已完成的进度
    }

    // 3. 限制阶段内进度最大为0.95，防止卡死
    final clampedStageProgress = stageProgress.clamp(0.0, 0.95);

    if (stageProgress > 0.95) {
      logger.d('Stage progress clamped: $stageProgress -> $clampedStageProgress (phase: $currentPhase)');
    }

    // 4. 计算总进度
    final totalProgress = completedWeight + (currentWeight * clampedStageProgress);

    logger.d('Progress: $currentPhase @ ${(stageProgress * 100).toStringAsFixed(1)}% '
        '→ Total: ${(totalProgress * 100).toStringAsFixed(1)}% '
        '(completed: ${(completedWeight * 100).toStringAsFixed(1)}%, '
        'current: ${(currentWeight * clampedStageProgress * 100).toStringAsFixed(1)}%)');

    return totalProgress;
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
