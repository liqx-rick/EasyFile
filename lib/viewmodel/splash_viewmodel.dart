import 'package:flutter/material.dart';

/// 启动页视图数据模型
class SplashViewModel extends ChangeNotifier {
  // 是否正在初始化
  bool _isInitializing = false;

  // 初始化消息
  String _initMessage = '';

  // logo透明度（用于淡入动画）
  double _logoOpacity = 0.0;

  // Getters
  bool get isInitializing => _isInitializing;
  String get initMessage => _initMessage;
  double get logoOpacity => _logoOpacity;

  /// 设置初始化状态
  void setInitializing(bool initializing) {
    if (_isInitializing != initializing) {
      _isInitializing = initializing;
      notifyListeners();
    }
  }

  /// 设置初始化消息
  void setInitMessage(String message) {
    if (_initMessage != message) {
      _initMessage = message;
      notifyListeners();
    }
  }

  /// 设置logo透明度
  void setLogoOpacity(double opacity) {
    if (_logoOpacity != opacity) {
      _logoOpacity = opacity;
      notifyListeners();
    }
  }

  /// 开始logo淡入动画
  void startLogoFadeIn() {
    setLogoOpacity(1.0);
  }

  /// 重置所有状态
  void reset() {
    _isInitializing = false;
    _initMessage = '';
    _logoOpacity = 0.0;
    notifyListeners();
  }
}
