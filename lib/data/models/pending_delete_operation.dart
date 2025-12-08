import 'package:easyfile/data/models/file_item.dart';

/// 待删除操作（用于撤销功能）
/// 
/// 在用户删除文件后，有一个短暂的撤销时间窗口（默认3秒）
/// 期间文件路径保存在此类中，等待用户操作：
/// - 用户不操作 → 倒计时结束，执行真实删除（移至回收站）
/// - 用户点击撤销 → 取消操作，文件保持原位
class PendingDeleteOperation {
  /// 待删除的文件列表
  final List<FileItem> files;

  /// 操作创建时间
  final DateTime createdAt;

  /// 是否已取消
  bool isCancelled = false;

  /// 是否已执行
  bool isExecuted = false;

  PendingDeleteOperation({
    required this.files,
  }) : createdAt = DateTime.now();

  /// 获取文件路径列表（用于日志和UI显示）
  List<String> get filePaths => files.map((f) => f.path).toList();

  /// 获取待删除文件数量
  int get fileCount => files.length;

  /// 获取总大小（字节）
  int get totalSize => files.fold(0, (sum, file) => sum + (file.size ?? 0));

  /// 标记为已取消
  void cancel() {
    isCancelled = true;
  }

  /// 标记为已执行
  void markExecuted() {
    isExecuted = true;
  }

  /// 检查是否可以执行删除（未取消且未执行）
  bool canExecute() {
    return !isCancelled && !isExecuted;
  }

  /// 获取操作描述（用于UI显示）
  String getDescription() {
    if (files.length == 1) {
      return '删除 "${files.first.name}"';
    } else {
      return '删除 ${files.length} 个项目';
    }
  }

  @override
  String toString() {
    return 'PendingDeleteOperation('
        'files: ${files.length}, '
        'createdAt: $createdAt, '
        'cancelled: $isCancelled, '
        'executed: $isExecuted'
        ')';
  }
}
