import 'package:flutter/material.dart';

/// 大文件删除进度对话框
/// 
/// 当删除大文件（>10MB）时显示进度条和当前处理的文件名
class DeleteProgressDialog extends StatelessWidget {
  final String currentFileName;
  final int currentIndex;
  final int totalCount;
  final double? progress; // 0.0 ~ 1.0，null表示不确定进度

  const DeleteProgressDialog({
    super.key,
    required this.currentFileName,
    required this.currentIndex,
    required this.totalCount,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 防止用户按返回键关闭
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              const Text(
                '正在移至回收站',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              // 进度指示器
              if (progress != null)
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).primaryColor,
                  ),
                )
              else
                const LinearProgressIndicator(
                  backgroundColor: Colors.grey,
                ),

              const SizedBox(height: 16),

              // 当前文件名
              Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    size: 20,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      currentFileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 进度文本
              Text(
                totalCount > 1
                    ? '正在处理 $currentIndex / $totalCount'
                    : '正在处理...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示进度对话框
  static Future<void> show({
    required BuildContext context,
    required String currentFileName,
    required int currentIndex,
    required int totalCount,
    double? progress,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => DeleteProgressDialog(
        currentFileName: currentFileName,
        currentIndex: currentIndex,
        totalCount: totalCount,
        progress: progress,
      ),
    );
  }

  /// 更新进度对话框（通过状态管理）
  /// 
  /// 注意：此方法需要配合StatefulWidget使用
  /// 推荐使用ValueNotifier或Provider来更新进度
  static void update({
    required BuildContext context,
    required String currentFileName,
    required int currentIndex,
    required int totalCount,
    double? progress,
  }) {
    // 关闭旧对话框
    Navigator.of(context).pop();
    // 显示新对话框
    show(
      context: context,
      currentFileName: currentFileName,
      currentIndex: currentIndex,
      totalCount: totalCount,
      progress: progress,
    );
  }
}

/// 进度对话框控制器（使用ValueNotifier实现动态更新）
class DeleteProgressController extends ChangeNotifier {
  String _currentFileName = '';
  int _currentIndex = 0;
  int _totalCount = 0;
  double? _progress;

  String get currentFileName => _currentFileName;
  int get currentIndex => _currentIndex;
  int get totalCount => _totalCount;
  double? get progress => _progress;

  void updateProgress({
    String? currentFileName,
    int? currentIndex,
    int? totalCount,
    double? progress,
  }) {
    if (currentFileName != null) _currentFileName = currentFileName;
    if (currentIndex != null) _currentIndex = currentIndex;
    if (totalCount != null) _totalCount = totalCount;
    if (progress != null) _progress = progress;
    notifyListeners();
  }

  void reset() {
    _currentFileName = '';
    _currentIndex = 0;
    _totalCount = 0;
    _progress = null;
    notifyListeners();
  }
}

/// 使用ChangeNotifier的进度对话框（支持动态更新）
class AnimatedDeleteProgressDialog extends StatelessWidget {
  final DeleteProgressController controller;

  const AnimatedDeleteProgressDialog({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        return DeleteProgressDialog(
          currentFileName: controller.currentFileName,
          currentIndex: controller.currentIndex,
          totalCount: controller.totalCount,
          progress: controller.progress,
        );
      },
    );
  }

  /// 显示带动态更新的进度对话框
  static Future<void> show({
    required BuildContext context,
    required DeleteProgressController controller,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AnimatedDeleteProgressDialog(
        controller: controller,
      ),
    );
  }
}
