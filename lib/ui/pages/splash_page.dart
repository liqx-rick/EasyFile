import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';

import '../../core/logger.dart';
import '../../presenter/splash_presenter.dart';
import '../../viewmodel/splash_viewmodel.dart';

/// 启动页界面
class SplashPage extends StatefulWidget {
  final VoidCallback? onComplete;

  const SplashPage({super.key, this.onComplete});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late SplashPresenter presenter;
  late AppLogger logger;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _hasInitialized = false; // 标记是否已经初始化过

  @override
  void initState() {
    super.initState();

    // 获取依赖
    logger = GetIt.instance<AppLogger>();

    // 初始化动画控制器
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    // 延迟一帧后开始初始化，确保页面已经构建完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasInitialized) {
        _startInitialization();
      }
    });
  }

  /// 开始初始化流程
  Future<void> _startInitialization() async {
    try {
      _hasInitialized = true; // 标记已开始初始化

      // 开始logo淡入动画
      _animationController.forward();

      // 获取ViewModel并创建Presenter
      final viewModel = Provider.of<SplashViewModel>(context, listen: false);
      presenter = SplashPresenter(
        viewModel: viewModel,
        logger: logger,
        onComplete: widget.onComplete, // 传递完成回调
      );

      // 开始应用初始化
      await presenter.initApp(context);
    } catch (e) {
      logger.e('SplashPage: Error during initialization: $e');
      // 即使出错也要继续，调用完成回调
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [theme.colorScheme.surface, theme.colorScheme.surface],
          ),
        ),
        child: Consumer<SplashViewModel>(
          builder: (context, viewModel, child) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Logo区域
                Expanded(
                  flex: 3,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _fadeAnimation,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _fadeAnimation.value,
                          child: _buildLogoSection(screenHeight),
                        );
                      },
                    ),
                  ),
                ),

                // 状态信息区域
                Expanded(flex: 1, child: _buildStatusSection(viewModel, theme)),

                // 底部版权信息
                Padding(
                  padding: const EdgeInsets.only(bottom: 32.0),
                  child: _buildFooterSection(theme),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 构建Logo区域
  Widget _buildLogoSection(double screenHeight) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo图标
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 120,
              height: 120,
              fit: BoxFit.cover,
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 应用名称
        Text(
          '易览文件',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).primaryColor,
            letterSpacing: 1.2,
          ),
        ),

        const SizedBox(height: 8),

        // 应用描述
        Text(
          '一款简洁高效的文件浏览器',
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  /// 构建状态信息区域
  Widget _buildStatusSection(SplashViewModel viewModel, ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 加载指示器
        if (viewModel.isInitializing)
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
            ),
          )
        else
          Icon(Icons.check_circle, size: 24, color: Colors.green),

        const SizedBox(height: 16),

        // 状态文本
        AnimatedOpacity(
          opacity: viewModel.initMessage.isNotEmpty ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Text(
            viewModel.initMessage,
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// 构建底部区域
  Widget _buildFooterSection(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Version 1.0.0',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Powered by EasyFile',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
