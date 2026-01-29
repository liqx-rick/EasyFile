import 'package:easyfile/analytics/analytics_helper.dart';
import 'package:easyfile/core/logger.dart';

/// 隐私空间可信会话管理器
///
/// 功能：
/// - 记录用户验证状态和时间
/// - 监听应用生命周期（前台/后台切换）
/// - 自动过期失效机制
/// - 提供会话验证接口
///
/// 设计原则："进门验证，进门后操作自由"
/// - 进入隐私空间：强制验证
/// - 移入文件到隐私空间：智能验证（优先使用会话）
/// - 隐私空间内操作（删除/移出）：无需验证
class PrivacySessionManager {
  static final PrivacySessionManager _instance = PrivacySessionManager._();
  factory PrivacySessionManager() => _instance;
  PrivacySessionManager._();

  DateTime? _lastVerifiedTime;
  bool _isInBackground = false;

  /// 会话有效期（默认5分钟）
  Duration sessionTimeout = const Duration(minutes: 5);

  /// 后台失效策略（默认启用：进入后台立即失效）
  bool invalidateOnBackground = true;

  /// 记录验证成功
  ///
  /// 在以下场景调用：
  /// - 成功进入隐私空间
  /// - 成功通过PIN验证移入文件
  void markVerified() {
    _lastVerifiedTime = DateTime.now();
    _isInBackground = false;
    logger.i('🔓 隐私会话已激活，有效期: ${sessionTimeout.inMinutes}分钟');
  }

  /// 检查会话是否有效
  ///
  /// 失效条件：
  /// 1. 从未验证过
  /// 2. 应用在后台且启用了后台失效策略
  /// 3. 超过会话超时时间
  bool isSessionValid() {
    if (_lastVerifiedTime == null) {
      logger.d('🔒 会话无效：未验证');
      return false;
    }

    if (_isInBackground && invalidateOnBackground) {
      logger.d('🔒 会话无效：应用在后台');
      return false;
    }

    final elapsed = DateTime.now().difference(_lastVerifiedTime!);
    final isValid = elapsed < sessionTimeout;

    if (!isValid) {
      logger.d('🔒 会话无效：已超时 ${elapsed.inMinutes}分钟');
    } else {
      final remaining = sessionTimeout - elapsed;
      logger.d('✅ 会话有效：剩余 ${remaining.inMinutes}分钟${remaining.inSeconds % 60}秒');
    }

    return isValid;
  }

  /// 获取会话剩余时间（秒）
  ///
  /// 返回 null 表示会话无效
  int? getRemainingSeconds() {
    if (!isSessionValid()) return null;

    final elapsed = DateTime.now().difference(_lastVerifiedTime!);
    final remaining = sessionTimeout - elapsed;
    return remaining.inSeconds;
  }

  /// 清除会话
  ///
  /// 在以下场景调用：
  /// - 用户手动退出隐私空间
  /// - 修改PIN码
  /// - 重置隐私空间
  void invalidate() {
    _lastVerifiedTime = null;
    logger.i('🔒 隐私会话已清除');

    // 埋点：隐私空间锁定
    AnalyticsHelper.logPrivacySpaceLock();
  }

  /// 应用进入后台
  ///
  /// 由应用生命周期监听器调用
  void onAppPaused() {
    _isInBackground = true;
    logger.i('📱 应用进入后台，会话标记为后台状态');

    if (invalidateOnBackground) {
      logger.i('🔒 后台失效策略已启用，会话已失效');
    }
  }

  /// 应用返回前台
  ///
  /// 由应用生命周期监听器调用
  void onAppResumed() {
    _isInBackground = false;
    logger.i('📱 应用返回前台');

    // 检查会话是否仍然有效
    if (_lastVerifiedTime != null) {
      if (isSessionValid()) {
        final remaining = getRemainingSeconds();
        logger.i('✅ 会话仍然有效，剩余 $remaining 秒');
      } else {
        logger.i('🔒 会话已失效');
        _lastVerifiedTime = null;
      }
    }
  }

  /// 延长会话（用户有活动时调用）
  ///
  /// 可选功能：每次用户操作时重置计时器
  /// 目前未启用，保持固定5分钟有效期
  void extendSession() {
    if (_lastVerifiedTime != null && isSessionValid()) {
      _lastVerifiedTime = DateTime.now();
      logger.d('⏱️ 会话已延长');
    }
  }

  /// 获取会话状态描述（用于调试或UI显示）
  String getStatusDescription() {
    if (_lastVerifiedTime == null) {
      return '未验证';
    }

    if (_isInBackground && invalidateOnBackground) {
      return '后台已锁定';
    }

    final remaining = getRemainingSeconds();
    if (remaining == null) {
      return '已过期';
    }

    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    return '有效（剩余 $minutes:${seconds.toString().padLeft(2, '0')}）';
  }
}
