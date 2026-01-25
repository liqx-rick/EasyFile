/// 卡片尺寸计算工具类
/// 
/// 用于在CategoryNavBar和QuickAccessSection之间共享卡片尺寸计算逻辑
/// 避免通过setState传递尺寸导致的rebuild循环
class CardSizeCalculator {
  /// 根据屏幕宽度计算卡片高度
  /// 
  /// 与CategoryNavBar._buildCategoryGrid中的计算逻辑保持一致
  static double calculateCardHeight(double screenWidth) {
    const crossAxisCount = 5; // 固定5列
    const totalHorizontalPadding = 16; // 左右padding（Container的padding * 2）
    final availableWidth = screenWidth - totalHorizontalPadding;

    // 动态计算间距
    const minSpacing = 10.0;
    const maxSpacing = 50.0;
    final totalSpacingWidth = (crossAxisCount - 1) * minSpacing;
    final cardWidth = (availableWidth - totalSpacingWidth) / crossAxisCount;

    // 根据卡片大小调整间距
    final actualSpacing =
        cardWidth < 60 ? minSpacing : (cardWidth < 70 ? 11.0 : maxSpacing);

    final actualCardWidth =
        (availableWidth - (crossAxisCount - 1) * actualSpacing) /
            crossAxisCount;
    
    return actualCardWidth; // cardHeight = actualCardWidth
  }
}
