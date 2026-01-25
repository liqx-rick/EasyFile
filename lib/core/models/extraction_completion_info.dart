/// 解压完成信息
///
/// 用于在通知栏中显示已完成的解压任务
class ExtractionCompletionInfo {
  /// 唯一标识符
  final String id;

  /// 压缩包文件名
  final String archiveName;

  /// 压缩包完整路径
  final String archivePath;

  /// 解压目标路径
  final String extractPath;

  /// 解压文件数量
  final int fileCount;

  /// 完成时间
  final DateTime completedAt;

  /// 是否成功
  final bool isSuccess;

  /// 错误信息（如果失败）
  final String? errorMessage;

  ExtractionCompletionInfo({
    required this.id,
    required this.archiveName,
    required this.archivePath,
    required this.extractPath,
    required this.fileCount,
    required this.completedAt,
    this.isSuccess = true,
    this.errorMessage,
  });

  /// 生成唯一ID
  static String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}
