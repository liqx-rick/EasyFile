/// 应用初始化阶段模型
///
/// 用于在初始化过程中传递阶段信息和实时进度
class InitializationStage {
  /// 阶段标识符（用于内部逻辑判断）
  final String phase;

  /// 显示给用户的消息
  final String message;

  /// 详细信息（可选，显示实时进度）
  /// 例如："已找到 2,156 张照片"
  final String? detail;

  /// 当前已处理的数量（可选）
  final int? current;

  /// 总数量估计值（可选）
  final int? total;

  const InitializationStage({
    required this.phase,
    required this.message,
    this.detail,
    this.current,
    this.total,
  });

  @override
  String toString() {
    return 'InitializationStage(phase: $phase, message: $message, detail: $detail, current: $current, total: $total)';
  }
}
