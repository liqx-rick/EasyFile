import 'package:flutter/material.dart';
import 'package:easyfile/ui/pages/trash_page.dart';

/// 回收站功能卡片
///
/// 用于主页快速访问区域，提供回收站功能的快捷入口。
/// 点击后跳转到回收站页面，查看已删除文件、恢复或永久删除。
///
/// 特性：
/// - 支持单行/双行两种布局模式
/// - 所有尺寸（图标、文字、间距、padding）均根据可用高度动态计算
/// - 红色渐变背景 + 白色圆形图标 + 红色文字
class TrashCard extends StatelessWidget {
  /// 是否为紧凑模式（单行并排显示）
  final bool isCompactMode;

  /// 卡片可用高度，用于动态计算内部元素尺寸
  final double availableHeight;

  const TrashCard({
    super.key,
    required this.isCompactMode,
    required this.availableHeight,
  });

  @override
  Widget build(BuildContext context) {
    // 根据可用高度动态计算padding
    final cardPadding = (availableHeight * 0.04).clamp(3.0, 6.0);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const TrashPage(),
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.red.withValues(alpha: 0.6),
              Colors.red.withValues(alpha: 0.3),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.red.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    // 根据可用高度动态计算尺寸
    double iconSize;
    double fontSize;
    double spacing;
    bool useHorizontalLayout = false;

    if (isCompactMode) {
      // 单行模式：图标+文字竖排
      iconSize = (availableHeight * 0.30).clamp(14.0, 28.0);
      fontSize = (availableHeight * 0.15).clamp(10.0, 14.0);
      spacing = (availableHeight * 0.03).clamp(1.0, 4.0);
    } else {
      // 双行模式：图标+文字横排
      useHorizontalLayout = true;
      iconSize = (availableHeight * 0.45).clamp(16.0, 30.0);
      fontSize = (availableHeight * 0.25).clamp(11.0, 15.0);
      spacing = (availableHeight * 0.10).clamp(3.0, 10.0);
    }

    final iconWidget = Container(
      width: iconSize,
      height: iconSize,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.delete_outline,
        size: iconSize * 0.55,
        color: Colors.red[700],
      ),
    );

    final textWidget = Text(
      '回收站',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: Colors.red[700],
      ),
    );

    if (useHorizontalLayout) {
      // 双行模式：横向布局
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          iconWidget,
          SizedBox(width: spacing),
          textWidget,
        ],
      );
    } else {
      // 单行模式：纵向布局
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          iconWidget,
          SizedBox(height: spacing),
          textWidget,
        ],
      );
    }
  }
}
