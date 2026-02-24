import 'package:easyfile/core/content/privacy_policy_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 隐私政策同意状态管理服务
///
/// 负责管理用户是否已同意隐私政策的状态，
/// 符合友盟等第三方SDK的合规要求
class PrivacyConsentService {
  static const String _privacyConsentKey = 'privacy_policy_consent';
  static const String _privacyConsentVersionKey = 'privacy_policy_consent_version';

  // 当前隐私政策版本——由 PrivacyPolicyContent.version 统一维护，
  // 无需在此处单独修改。
  static String get _currentPrivacyVersion => PrivacyPolicyContent.version;

  /// 检查用户是否已同意隐私政策
  ///
  /// 返回 true 表示用户已同意当前版本的隐私政策
  /// 返回 false 表示用户尚未同意或隐私政策已更新
  static Future<bool> hasUserConsented() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasConsented = prefs.getBool(_privacyConsentKey) ?? false;
      final consentedVersion = prefs.getString(_privacyConsentVersionKey) ?? '';

      // 检查是否同意且版本匹配
      return hasConsented && consentedVersion == _currentPrivacyVersion;
    } catch (e) {
      // 出错默认返回未同意
      return false;
    }
  }

  /// 记录用户已同意隐私政策
  static Future<void> setUserConsented() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_privacyConsentKey, true);
      await prefs.setString(_privacyConsentVersionKey, _currentPrivacyVersion);
    } catch (e) {
      // 记录失败不影响主流程
    }
  }

  /// 清除用户同意状态（用于测试或用户撤销同意）
  static Future<void> clearConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_privacyConsentKey);
      await prefs.remove(_privacyConsentVersionKey);
    } catch (e) {
      // 清除失败不影响主流程
    }
  }
}
