import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/privacy_service.dart';
import 'package:easyfile/ui/widgets/privacy_pin_input.dart';
import 'package:flutter/material.dart';

/// PIN设置页面（首次进入隐私空间）
class PrivacySetupPage extends StatefulWidget {
  const PrivacySetupPage({super.key});

  @override
  State<PrivacySetupPage> createState() => _PrivacySetupPageState();
}

class _PrivacySetupPageState extends State<PrivacySetupPage> {
  final _privacyService = PrivacyService();

  String? _firstPin;
  bool _isConfirming = false;
  bool _enableBiometric = false;
  bool _canUseBiometric = false;
  String? _errorMessage;
  bool _isProcessing = false;
  String _currentPin = ''; // 当前输入的PIN（用于横屏左右同步）

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final canUse = await _privacyService.canUseBiometric();
    if (mounted) {
      setState(() {
        _canUseBiometric = canUse;
      });
    }
  }

  Future<void> _onPinCompleted(String pin) async {
    if (_isProcessing) return;

    if (!_isConfirming) {
      // 第一次输入
      setState(() {
        _firstPin = pin;
        _isConfirming = true;
        _errorMessage = null;
        _currentPin = ''; // 清空当前PIN，准备确认输入
      });
    } else {
      // 确认输入
      if (pin == _firstPin) {
        setState(() {
          _isProcessing = true;
          _errorMessage = null;
        });

        try {
          final success = await _privacyService.initialize(
            pin,
            enableBiometric: _enableBiometric,
          );

          if (success && mounted) {
            // 初始化成功，激活会话（用户刚设置完PIN，应该直接进入）
            _privacyService.markSessionActive();
            logger.i('✅ 隐私空间初始化成功，会话已激活');

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ 隐私空间创建成功')),
            );
            Navigator.pop(context, true);
          } else if (mounted) {
            setState(() {
              _errorMessage = '初始化失败，请重试';
              _isConfirming = false;
              _firstPin = null;
              _isProcessing = false;
              _currentPin = ''; // 清空PIN状态
            });
          }
        } catch (e) {
          logger.e('初始化隐私空间异常: $e');
          if (mounted) {
            setState(() {
              _errorMessage = '初始化异常：$e';
              _isConfirming = false;
              _firstPin = null;
              _isProcessing = false;
              _currentPin = ''; // 清空PIN状态
            });
          }
        }
      } else {
        setState(() {
          _errorMessage = '两次输入不一致，请重新输入';
          _isConfirming = false;
          _firstPin = null;
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
        title: const Text('创建隐私空间'),
        toolbarHeight: isLandscape ? 40 : 48,
      ),
      body: isLandscape ? _buildLandscapeLayout(theme) : _buildPortraitLayout(theme),
    );
  }

  /// 竖屏布局（原有布局）
  Widget _buildPortraitLayout(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // 图标和标题（放在同一行）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 32,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                _isConfirming ? '确认PIN码' : '设置PIN码',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 说明
          Text(
            _isConfirming ? '请再次输入PIN码' : '请输入4-6位数字作为PIN码',
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          // 提示信息（仅首次设置时显示）
          if (!_isConfirming) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '请牢记您的PIN码。${_canUseBiometric ? "建议启用生物识别，" : ""}忘记PIN后只能清空隐私空间。',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange.shade700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          const SizedBox(height: 32),

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

          const SizedBox(height: 32),

          // 生物识别选项
          if (_canUseBiometric && !_isConfirming)
            Card(
              child: SwitchListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: const Text('启用生物识别', style: TextStyle(fontSize: 14)),
                subtitle: const Text('快速访问', style: TextStyle(fontSize: 12)),
                value: _enableBiometric,
                onChanged: (value) {
                  setState(() {
                    _enableBiometric = value;
                  });
                },
              ),
            ),
        ],
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
                        Icons.lock_outline,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),

                      const SizedBox(height: 12),

                      // 标题
                      Text(
                        _isConfirming ? '确认PIN码' : '设置PIN码',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 6),

                      // 说明
                      Text(
                        _isConfirming ? '请再次输入PIN码' : '请输入4-6位数字作为PIN码',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      // 提示信息（仅首次设置时显示）
                      if (!_isConfirming) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '请牢记您的PIN码。${_canUseBiometric ? "建议启用生物识别，" : ""}忘记PIN后只能清空隐私空间。',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange.shade700,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],

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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PrivacyPinInput(
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

                    // 生物识别选项（横屏时显示在右侧键盘下方）
                    if (_canUseBiometric && !_isConfirming) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(
                            Icons.fingerprint,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '启用生物识别',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Switch(
                            value: _enableBiometric,
                            onChanged: (value) {
                              setState(() {
                                _enableBiometric = value;
                              });
                            },
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
