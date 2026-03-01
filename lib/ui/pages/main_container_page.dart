import 'package:easyfile/core/logger.dart';
import 'package:easyfile/ui/pages/assistant_page.dart';
import 'package:easyfile/ui/pages/file_browser_page.dart';
import 'package:easyfile/ui/pages/tools_page.dart';
import 'package:easyfile/ui/widgets/swipe_guidance_overlay.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 三屏智能架构主容器
///
/// 包含三个页面：
/// - 0: AssistantPage（智能助手，负一屏）
/// - 1: FileBrowserPage（文件浏览器，主页）
/// - 2: ToolsPage（专业工具，正一屏）
class MainContainerPage extends StatefulWidget {
  const MainContainerPage({super.key});

  @override
  State<MainContainerPage> createState() => _MainContainerPageState();
}

class _MainContainerPageState extends State<MainContainerPage> {
  late PageController _pageController;
  int _currentPage = 1; // 默认停在主页（FileBrowserPage）
  bool _showGuidance = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
    _checkFirstRun();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 检查是否首次运行
  Future<void> _checkFirstRun() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shown = prefs.getBool('three_screen_guidance_shown') ?? false;

      if (!shown && mounted) {
        // 延迟显示引导，确保页面已完全加载
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          setState(() => _showGuidance = true);
        }
      }
    } catch (e) {
      logger.e('检查首次运行状态失败: $e');
    }
  }

  /// 页面切换回调
  void _onPageChanged(int index) {
    setState(() => _currentPage = index);

    // 记录页面切换事件
    final pageName = _getPageName(index);
    logger.i('切换到页面: $pageName');

    // TODO: 添加页面切换分析事件
    // AnalyticsHelper.logScreenSwitch(
    //   from: _getPageName(_currentPage),
    //   to: pageName,
    // );
  }

  /// 获取页面名称
  String _getPageName(int index) {
    switch (index) {
      case 0:
        return 'assistant';
      case 1:
        return 'home';
      case 2:
        return 'tools';
      default:
        return 'unknown';
    }
  }

  /// 关闭引导
  void _dismissGuidance() {
    setState(() => _showGuidance = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 三屏 PageView
          PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            children: const [
              AssistantPage(), // 负一屏：智能助手
              FileBrowserPage(), // 主页：文件浏览器
              ToolsPage(), // 正一屏：专业工具
            ],
          ),

          // 页面指示器
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: _buildPageIndicator(),
          ),

          // 首次引导
          if (_showGuidance)
            SwipeGuidanceOverlay(
              onDismiss: _dismissGuidance,
            ),
        ],
      ),
    );
  }

  /// 构建页面指示器
  Widget _buildPageIndicator() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (isDark ? Colors.black : Colors.white).withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _currentPage == index ? 24 : 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _currentPage == index
                    ? theme.colorScheme.primary
                    : (isDark ? Colors.white : Colors.black)
                        .withOpacity(0.3),
              ),
            );
          }),
        ),
      ),
    );
  }
}
