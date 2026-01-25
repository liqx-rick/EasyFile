import 'package:flutter/foundation.dart';
import 'package:easyfile/core/models/extraction_completion_info.dart';

/// 解压通知管理器
///
/// 管理解压完成通知的状态（单例模式）
class ExtractionNotificationManager extends ChangeNotifier {
  // 单例实例
  static final ExtractionNotificationManager _instance =
      ExtractionNotificationManager._internal();

  factory ExtractionNotificationManager() => _instance;

  ExtractionNotificationManager._internal();

  /// 已完成的解压任务列表
  final List<ExtractionCompletionInfo> _completions = [];

  /// 是否展开通知栏
  bool _isExpanded = false;

  /// 获取已完成任务列表
  List<ExtractionCompletionInfo> get completions =>
      List.unmodifiable(_completions);

  /// 获取展开状态
  bool get isExpanded => _isExpanded;

  /// 是否有未读通知
  bool get hasNotifications => _completions.isNotEmpty;

  /// 通知数量
  int get notificationCount => _completions.length;

  /// 添加完成通知
  void addCompletion(ExtractionCompletionInfo info) {
    _completions.insert(0, info); // 新任务插入到最前面
    _isExpanded = false; // 添加新通知时默认折叠，让用户看到提示
    notifyListeners();
  }

  /// 移除指定通知
  void removeCompletion(String id) {
    _completions.removeWhere((info) => info.id == id);
    notifyListeners();
  }

  /// 清除所有通知
  void clearAll() {
    _completions.clear();
    _isExpanded = false;
    notifyListeners();
  }

  /// 切换展开/折叠状态
  void toggleExpanded() {
    _isExpanded = !_isExpanded;
    notifyListeners();
  }

  /// 设置展开状态
  void setExpanded(bool expanded) {
    if (_isExpanded != expanded) {
      _isExpanded = expanded;
      notifyListeners();
    }
  }
}
