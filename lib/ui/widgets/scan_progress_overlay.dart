import 'package:flutter/material.dart';

/// 文件扫描进度Overlay组件
/// 在主页上方显示半透明的扫描进度提示
class ScanProgressOverlay extends StatelessWidget {
  final bool isScanning;
  final String? currentPath;
  final bool isFirstScan;

  const ScanProgressOverlay({
    super.key,
    required this.isScanning,
    this.currentPath,
    this.isFirstScan = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isScanning) {
      return const SizedBox.shrink();
    }

    // 根据扫描类型显示不同的文案
    final String message = isFirstScan ? '正在为第一次访问执行深度扫描，请稍等...' : '正在扫描文件...';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // 扫描动画图标
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // 扫描信息
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 扫描完成提示
class ScanCompleteSnackBar {
  static void show(BuildContext context, int totalCount, Duration duration) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '扫描完成，共发现 $totalCount 个文件',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        backgroundColor: Colors.green,
      ),
    );
  }
}
