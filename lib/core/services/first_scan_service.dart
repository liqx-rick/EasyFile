import 'package:shared_preferences/shared_preferences.dart';
import '../logger.dart';

/// 首次全量扫描服务
/// 
/// 管理首次深度扫描的状态持久化，确保应用首次启动时执行深度扫描，
/// 后续启动时跳过扫描。使用 SharedPreferences 存储扫描完成标记。
class FirstScanService {
  static const String _key = 'is_first_full_scan_completed';
  
  static final FirstScanService _instance = FirstScanService._internal();
  factory FirstScanService() => _instance;
  FirstScanService._internal();

  /// 检查是否需要执行首次全量扫描
  /// 
  /// Returns:
  ///   - `true`: 需要执行首次扫描（首次启动或状态已重置）
  ///   - `false`: 已完成过首次扫描
  Future<bool> needsFirstScan() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isCompleted = prefs.getBool(_key) ?? false;
      logger.i('FirstScanService: First scan completed = $isCompleted, needs scan = ${!isCompleted}');
      return !isCompleted;
    } catch (e) {
      logger.e('FirstScanService: Error checking first scan status: $e');
      return true; // 出错时默认需要扫描
    }
  }

  /// 标记首次全量扫描已完成
  Future<void> markScanCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
      logger.i('FirstScanService: First scan marked as completed');
    } catch (e) {
      logger.e('FirstScanService: Error marking scan completed: $e');
    }
  }

  /// 重置扫描状态（用于测试或重新初始化）
  Future<void> resetScanStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      logger.i('FirstScanService: First scan status reset');
    } catch (e) {
      logger.e('FirstScanService: Error resetting scan status: $e');
    }
  }
}
