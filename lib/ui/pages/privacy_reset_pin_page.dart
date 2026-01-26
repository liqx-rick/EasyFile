import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/privacy_service.dart';
import 'package:easyfile/ui/widgets/privacy_pin_input.dart';
import 'package:flutter/material.dart';

/// PIN重置页面
///
/// 通过生物识别验证后，允许用户重置PIN
class PrivacyResetPinPage extends StatefulWidget {
  const PrivacyResetPinPage({super.key});

  @override
  State<PrivacyResetPinPage> createState() => _PrivacyResetPinPageState();
}

class _PrivacyResetPinPageState extends State<PrivacyResetPinPage> {
  final _privacyService = PrivacyService();

  String? _newPin;
  bool _isConfirming = false;
  String? _errorMessage;
  bool _isProcessing = false;
  String _currentPin = ''; // 当前输入的PIN（用于横屏左右同步）

  Future<void> _onPinCompleted(String pin) async {
    if (_isProcessing) return;

    if (!_isConfirming) {
      // 第一次输入
      setState(() {
        _newPin = pin;
        _isConfirming = true;
        _errorMessage = null;
        _currentPin = ''; // 清空当前PIN，准备确认输入
      });
    } else {
      // 确认输入
      if (pin == _newPin) {
        setState(() {
          _isProcessing = true;
          _errorMessage = null;
        });

        try {
          final success = await _privacyService.resetPin(pin);

          if (success && mounted) {
            Navigator.pop(context, true);
          } else if (mounted) {
            setState(() {
              _errorMessage = '重置失败，请重试';
              _isConfirming = false;
              _newPin = null;
              _isProcessing = false;
              _currentPin = ''; // 清空PIN状态
            });
          }
        } catch (e) {
          logger.e('重置PIN异常: $e');
          if (mounted) {
            setState(() {
              _errorMessage = '重置异常：$e';
              _isConfirming = false;
              _newPin = null;
              _isProcessing = false;
              _currentPin = ''; // 清空PIN状态
            });
          }
        }
      } else {
        setState(() {
          _errorMessage = '两次输入不一致，请重新输入';
          _isConfirming = false;
          _newPin = null;
          _currentPin = ''; // 清空PIN状态
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: const Text('重置PIN'),
        toolbarHeight: isLandscape ? 40 : 48,
      ),
      body: isLandscape ? _buildLandscapeLayout(theme) : _buildPortraitLayout(theme),
    );
  }

  /// 竖屏布局（原有布局）
  Widget _buildPortraitLayout(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 图标
            Icon(
              Icons.lock_reset,
              size: 80,
              color: theme.colorScheme.primary,
            ),

            const SizedBox(height: 24),

            // 标题
            Text(
              _isConfirming ? '确认新PIN' : '设置新PIN',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // 说明
            Text(
              _isConfirming ? '请再次输入新PIN码' : '请输入4-6位数字作为新PIN码',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 48),

            // PIN输入
            if (!_isProcessing)
              PrivacyPinInput(
                key: ValueKey(_isConfirming), // 切换状态时重建widget以清除输入
                onCompleted: _onPinCompleted,
                errorMessage: _errorMessage,
                portraitMode: true, // 竖屏使用大键盘
              )
            else
              const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }

  /// 横屏布局（左右分栏）
  Widget _buildLandscapeLayout(ThemeData theme) {
    return Row(
      children: [
        // 左侧：信息和确认按钮
        Expanded(
          flex: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 24,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 图标
                      Icon(
                        Icons.lock_reset,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),

                      const SizedBox(height: 12),

                      // 标题
                      Text(
                        _isConfirming ? '确认新PIN' : '设置新PIN',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 6),

                      // 说明
                      Text(
                        _isConfirming ? '请再次输入新PIN码' : '请输入4-6位数字作为新PIN码',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 16),

                      // PIN输入指示器（左侧）和确认按钮
                      if (!_isProcessing)
                        PrivacyPinInput(
                          key: ValueKey(_isConfirming),
                          onCompleted: _onPinCompleted,
                          errorMessage: _errorMessage,
                          landscapeMode: true, // 横屏模式
                          externalPin: _currentPin, // 使用共享PIN状态
                        )
                      else
                        const CircularProgressIndicator(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // 分隔线
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant,
        ),

        // 右侧：数字键盘
        Expanded(
          flex: 1,
          child: SingleChildScrollView(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: PrivacyPinInput(
                  key: ValueKey('keyboard_$_isConfirming'),
                  onCompleted: _onPinCompleted,
                  errorMessage: null, // 错误消息显示在左侧
                  landscapeMode: true,
                  keyboardOnly: true, // 仅显示键盘
                  externalPin: _currentPin, // 使用共享PIN状态
                  onPinChanged: (pin) {
                    // 右侧键盘输入时，更新共享PIN状态
                    setState(() {
                      _currentPin = pin;
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
