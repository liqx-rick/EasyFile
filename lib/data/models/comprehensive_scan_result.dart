/// 扫描统计信息（仅用于日志输出）
///
/// 设计原则：
/// - UI层不依赖此类，通过 QuickAccessViewModel.folders 获取数据
/// - 仅用于 QuickAccessPresenter 内部统计和日志
/// - 保持轻量级，只包含实际使用的字段
///
/// 使用场景：
/// ```dart
/// final stats = await _scanComprehensively();
/// logger.i('扫描完成: $stats');
/// ```
class ScanStats {
  /// 发现的快速访问文件夹总数
  final int foldersFound;

  /// 新增的文件夹数量
  final int newlyAdded;

  /// 扫描的文件总数
  final int filesScanned;

  /// 扫描是否成功
  final bool success;

  /// 错误消息（如果有）
  final String? errorMessage;

  const ScanStats({
    required this.foldersFound,
    required this.newlyAdded,
    required this.filesScanned,
    this.success = true,
    this.errorMessage,
  });

  /// 创建一个空的扫描结果
  factory ScanStats.empty() {
    return const ScanStats(
      foldersFound: 0,
      newlyAdded: 0,
      filesScanned: 0,
      success: false,
    );
  }

  /// 创建一个错误结果
  factory ScanStats.error(String message) {
    return ScanStats(
      foldersFound: 0,
      newlyAdded: 0,
      filesScanned: 0,
      success: false,
      errorMessage: message,
    );
  }

  @override
  String toString() {
    if (!success) {
      return 'ScanStats(failed: $errorMessage)';
    }
    return 'ScanStats('
        '发现$foldersFound个文件夹, '
        '新增$newlyAdded个, '
        '扫描$filesScanned个文件'
        ')';
  }
}
