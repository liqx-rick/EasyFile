import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/privacy_service.dart';
import 'package:easyfile/ui/widgets/privacy_pin_input.dart';
import 'package:flutter/material.dart';

/// 快速PIN验证对话框
///
/// 用于在文件操作中快速验证PIN，不进入完整的隐私空间
class PrivacyQuickAuthDialog extends StatefulWidget {
  const PrivacyQuickAuthDialog({super.key});

  @override
  State<PrivacyQuickAuthDialog> createState() => _PrivacyQuickAuthDialogState();
}

class _PrivacyQuickAuthDialogState extends State<PrivacyQuickAuthDialog> {
  final _privacyService = PrivacyService();
  String? _errorMessage;
  bool _isProcessing = false;
  int _failedAttempts = 0;

  Future<void> _onPinCompleted(String pin) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final success = await _privacyService.verifyPin(pin);

      if (success && mounted) {
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
          const Text('验证PIN'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '请输入PIN码以继续',
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
              const CircularProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
