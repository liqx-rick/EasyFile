import 'package:flutter/material.dart';

/// 文件列表骨架屏
///
/// 功能：在文件扫描时显示占位动画，提升感知性能
///
/// 使用示例：
/// ```dart
/// // 在 RecommendAggregatePage 的 build 方法中
/// if (_isLoading) {
///   return FileListSkeleton(
///     itemCount: _estimatedFileCount,
///     showTabs: widget.config.mode == RecommendMode.application,
///   );
/// }
/// ```
class FileListSkeleton extends StatefulWidget {
  /// 显示的骨架条目数量
  final int itemCount;

  /// 是否显示 Tab 栏骨架
  final bool showTabs;

  /// 是否显示搜索栏骨架
  final bool showSearchBar;

  const FileListSkeleton({
    super.key,
    this.itemCount = 20,
    this.showTabs = false,
    this.showSearchBar = true,
  });

  @override
  State<FileListSkeleton> createState() => _FileListSkeletonState();
}

class _FileListSkeletonState extends State<FileListSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildSkeletonBox(width: 100, height: 20),
        actions: [
          if (widget.showSearchBar)
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: _buildSkeletonCircle(size: 24),
            ),
        ],
      ),
      body: Column(
        children: [
          // Tab 栏骨架
          if (widget.showTabs) _buildTabsSkeleton(),

          // 文件列表骨架
          Expanded(
            child: ListView.builder(
              itemCount: widget.itemCount,
              itemBuilder: (context, index) => _buildFileItemSkeleton(),
            ),
          ),
        ],
      ),
    );
  }

  /// Tab 栏骨架
  Widget _buildTabsSkeleton() {
    return Container(
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(
          4,
          (index) => Padding(
            padding: EdgeInsets.only(right: 24),
            child: _buildSkeletonBox(width: 60, height: 24),
          ),
        ),
      ),
    );
  }

  /// 文件条目骨架
  Widget _buildFileItemSkeleton() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 图标/缩略图
          _buildSkeletonBox(width: 48, height: 48, borderRadius: 8),
          SizedBox(width: 12),

          // 文件信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 文件名
                _buildSkeletonBox(
                  width: double.infinity,
                  height: 16,
                  maxWidth: 200,
                ),
                SizedBox(height: 8),
                // 文件大小和日期
                _buildSkeletonBox(
                  width: 120,
                  height: 12,
                ),
              ],
            ),
          ),

          // 更多按钮
          _buildSkeletonCircle(size: 24),
        ],
      ),
    );
  }

  /// 骨架矩形框
  Widget _buildSkeletonBox({
    required double width,
    required double height,
    double? maxWidth,
    double borderRadius = 4,
  }) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          width: maxWidth != null ? width.clamp(0, maxWidth) : width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              colors: [
                Colors.grey[300]!,
                Colors.grey[200]!,
                Colors.grey[300]!,
              ],
              stops: [
                _shimmerController.value - 0.3,
                _shimmerController.value,
                _shimmerController.value + 0.3,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        );
      },
    );
  }

  /// 骨架圆形
  Widget _buildSkeletonCircle({required double size}) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                Colors.grey[300]!,
                Colors.grey[200]!,
                Colors.grey[300]!,
              ],
              stops: [
                _shimmerController.value - 0.3,
                _shimmerController.value,
                _shimmerController.value + 0.3,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 扫描进度指示器
///
/// 功能：显示扫描进度和当前文件数量
///
/// 使用示例：
/// ```dart
/// // 在骨架屏或加载状态下显示
/// ScanningProgress(
///   currentCount: _currentFileCount,
///   estimatedTotal: _estimatedFileCount,
/// )
/// ```
class ScanningProgress extends StatelessWidget {
  final int currentCount;
  final int? estimatedTotal;
  final String message;

  const ScanningProgress({
    super.key,
    required this.currentCount,
    this.estimatedTotal,
    this.message = '正在扫描文件...',
  });

  @override
  Widget build(BuildContext context) {
    final progress = estimatedTotal != null && estimatedTotal! > 0 ? currentCount / estimatedTotal! : null;

    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          if (progress != null) LinearProgressIndicator(value: progress) else LinearProgressIndicator(),

          SizedBox(height: 12),

          // 文字信息
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                estimatedTotal != null ? '$currentCount / $estimatedTotal' : '$currentCount',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
