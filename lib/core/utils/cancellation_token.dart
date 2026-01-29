/// 取消令牌
///
/// 用于协作式取消长时间运行的操作
///
/// 使用示例：
/// ```dart
/// final token = CancellationToken();
///
/// Future<void> longRunningTask(CancellationToken token) async {
///   for (var i = 0; i < 1000; i++) {
///     if (token.isCancelled) {
///       throw CancelledException();
///     }
///     await doWork();
///   }
/// }
///
/// // 执行任务
/// final future = longRunningTask(token);
///
/// // 取消任务
/// token.cancel();
/// ```
class CancellationToken {
  bool _isCancelled = false;

  /// 是否已取消
  bool get isCancelled => _isCancelled;

  /// 取消操作
  void cancel() {
    _isCancelled = true;
  }

  /// 重置（用于复用）
  void reset() {
    _isCancelled = false;
  }

  /// 如果已取消则抛出异常
  void throwIfCancelled() {
    if (_isCancelled) {
      throw CancelledException();
    }
  }
}

/// 取消异常
class CancelledException implements Exception {
  final String message;

  CancelledException([this.message = '操作已取消']);

  @override
  String toString() => 'CancelledException: $message';
}
