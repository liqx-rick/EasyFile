import 'package:easyfile/core/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首次安装检测服务
///
/// 管理应用初始化完成状态标记
/// 用于区分首次安装、重新安装、正常打开三种场景
class FirstInstallService {
  static const String _keyInitializationComplete = 'is_initialization_complete';

  /// 检查应用是否已初始化完成
  ///
  /// 返回 true：已初始化完成（有初始化标记）
  /// 返回 false：未初始化（无标记，首次安装）
  Future<bool> isInitialized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final result = prefs.getBool(_keyInitializationComplete) ?? false;
      logger.i('[FirstInstallService] isInitialized: $result');
      return result;
    } catch (e) {
      logger.e('[FirstInstallService] Error checking initialization status: $e');
      // 如果出错，假设未初始化，重新开始
      return false;
    }
  }

  /// 标记应用已初始化完成
  ///
  /// 这应该在 P2 完成后调用，表示所有初始化工作都已完成
  Future<void> markInitialized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyInitializationComplete, true);
      logger.i('[FirstInstallService] Marked as initialized');
    } catch (e) {
      logger.e('[FirstInstallService] Error marking initialization: $e');
      rethrow;
    }
  }

  /// 清除初始化标记
  ///
  /// 用于测试或恢复初始状态
  @visibleForTesting
  Future<void> clearInitialization() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyInitializationComplete);
      logger.i('[FirstInstallService] Cleared initialization flag');
    } catch (e) {
      logger.e('[FirstInstallService] Error clearing initialization: $e');
      rethrow;
    }
  }
}
