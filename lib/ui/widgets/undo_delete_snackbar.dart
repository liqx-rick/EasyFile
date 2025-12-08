import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easyfile/data/models/pending_delete_operation.dart';

/// 带撤销功能的删除SnackBar
/// 
/// 显示倒计时，允许用户在指定时间内撤销删除操作
class UndoDeleteSnackBar {
  /// 显示撤销删除的SnackBar
  /// 
  /// [context] - BuildContext
  /// [operation] - 待删除操作
  /// [undoDuration] - 撤销时长（秒）
  /// [onUndo] - 撤销回调
  /// [onExecute] - 执行删除回调
  static void show({
    required BuildContext context,
    required PendingDeleteOperation operation,
    required int undoDuration,
    required VoidCallback onUndo,
    required VoidCallback onExecute,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    
    // 创建倒计时控制器
    final remainingSeconds = ValueNotifier<int>(undoDuration);
    Timer? countdownTimer;
    
    // 启动倒计时
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds.value > 0) {
        remainingSeconds.value--;
      } else {
        timer.cancel();
        // 倒计时结束，执行删除
        if (operation.canExecute()) {
          onExecute();
        }
      }
    });

    // 显示SnackBar
    final snackBar = SnackBar(
      duration: Duration(seconds: undoDuration),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.grey[850],
      content: ValueListenableBuilder<int>(
        valueListenable: remainingSeconds,
        builder: (context, seconds, child) {
          return Row(
            children: [
              const Icon(
                Icons.delete_outline,
                color: Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      operation.getDescription(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$seconds 秒后将移至回收站',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      action: SnackBarAction(
        label: '撤销',
        textColor: Colors.yellowAccent,
        onPressed: () {
          countdownTimer?.cancel();
          remainingSeconds.dispose();
          operation.cancel();
          onUndo();
        },
      ),
    );

    final snackBarController = messenger.showSnackBar(snackBar);

    // SnackBar关闭时清理资源
    snackBarController.closed.then((_) {
      countdownTimer?.cancel();
      remainingSeconds.dispose();
    });
  }

  /// 显示简单的成功提示（撤销后）
  static void showUndoSuccess(BuildContext context, int fileCount) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已取消删除 ${fileCount == 1 ? '1 个项目' : '$fileCount 个项目'}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 显示删除完成提示
  static void showDeleteSuccess(BuildContext context, int fileCount) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text('已移至回收站 ${fileCount == 1 ? '1 个项目' : '$fileCount 个项目'}'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 显示删除失败提示
  static void showDeleteError(
    BuildContext context,
    String message, {
    int? successCount,
    int? failCount,
  }) {
    final content = successCount != null && failCount != null
        ? '成功 $successCount 项，失败 $failCount 项'
        : message;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(content)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
