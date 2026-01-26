import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/privacy_service.dart';
import 'package:easyfile/ui/widgets/privacy_pin_input.dart';
import 'package:flutter/material.dart';

/// 隐私验证对话框（支持生物识别 + PIN）
///
/// 用于快速验证身份，优先尝试生物识别，失败后降级到PIN输入
class PrivacyAuthDialog extends StatefulWidget {
  const PrivacyAuthDialog({super.key});

  @override
  State<PrivacyAuthDialog> createState() => _PrivacyAuthDialogState();
}

class _PrivacyAuthDialogState extends State<PrivacyAuthDialog> {
  final _privacyService = PrivacyService();
  String? _errorMessage;
  bool _isProcessing = false;
  int _failedAttempts = 0;
  bool _canUseBiometric = false;
  bool _biometricEnabled = false;
  String _biometricType = '生物识别';
  bool _biometricChecked = false;

  @override
  void initState() {
    super.initState();
    _checkAndTryBiometric();
  }

  /// 检查生物识别并自动尝试
  Future<void> _checkAndTryBiometric() async {
    final canUse = await _privacyService.canUseBiometric();
    final isEnabled = await _privacyService.isBiometricEnabled();
    final type = await _privacyService.getBiometricTypeString();

    if (mounted) {
      setState(() {
        _canUseBiometric = canUse;
        _biometricEnabled = isEnabled;
        _biometricType = type;
        _biometricChecked = true;
      });

      // 如果启用了生物识别，自动弹出验证
      if (_biometricEnabled && _canUseBiometric) {
        // 延迟一下，让对话框完全显示
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _authenticateWithBiometric();
          }
        });
      }
    }
  }

  /// 使用生物识别验证
  Future<void> _authenticateWithBiometric() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final success = await _privacyService.authenticateWithBiometric();

      if (success && mounted) {
        logger.i('✅ 生物识别验证成功');
        Navigator.pop(context, true); // 验证成功，返回true
      } else if (mounted) {
        logger.w('❌ 生物识别验证失败或取消');
        setState(() {
          _isProcessing = false;
          _errorMessage = '生物识别失败，请输入PIN码';
        });
      }
    } catch (e) {
      logger.e('生物识别验证异常: $e');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = '生物识别异常，请输入PIN码';
        });
      }
    }
  }

  /// PIN验证完成
  Future<void> _onPinCompleted(String pin) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final success = await _privacyService.verifyPin(pin);

      if (success && mounted) {
        logger.i('✅ PIN验证成功');
        Navigator.pop(context, true); // 验证成功，返回true
      } else if (mounted) {
        setState(() {
          _failedAttempts++;
          _isProcessing = false;

          if (_failedAttempts >= 3) {
            _errorMessage = 'PIN错误次数过多';
            // 延迟关闭对话框
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                Navigator.pop(context, false);
              }
            });
          } else {
            _errorMessage = 'PIN错误，还可尝试${3 - _failedAttempts}次';
          }
        });
      }
    } catch (e) {
      logger.e('PIN验证异常: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '验证异常，请重试';
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lock, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('验证身份'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _biometricEnabled && _canUseBiometric ? '使用$_biometricType或输入PIN码' : '请输入PIN码以继续',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            if (!_isProcessing)
              PrivacyPinInput(
                key: ValueKey(_failedAttempts), // 失败后重建组件清空输入
                onCompleted: _onPinCompleted,
                errorMessage: _errorMessage,
              )
            else
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _biometricEnabled && _canUseBiometric ? '正在验证$_biometricType...' : '正在验证...',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        // 如果正在进行生物识别且支持，显示"使用PIN"按钮
        if (_isProcessing && _biometricEnabled && _canUseBiometric)
          TextButton(
            onPressed: () {
              setState(() {
                _isProcessing = false;
                _errorMessage = '已切换到PIN输入';
              });
            },
            child: const Text('使用PIN'),
          ),
        // 如果支持生物识别且不在验证中，显示生物识别按钮
        if (_biometricChecked && _biometricEnabled && _canUseBiometric && !_isProcessing)
          TextButton.icon(
            onPressed: _authenticateWithBiometric,
            icon: const Icon(Icons.fingerprint),
            label: Text(_biometricType),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
