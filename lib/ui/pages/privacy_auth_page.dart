import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/privacy_service.dart';
import 'package:easyfile/ui/pages/privacy_reset_pin_page.dart';
import 'package:easyfile/ui/pages/privacy_space_page.dart';
import 'package:easyfile/ui/widgets/privacy_pin_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 身份验证页面
///
/// 用于在进入隐私空间前进行PIN或生物识别验证
class PrivacyAuthPage extends StatefulWidget {
  const PrivacyAuthPage({super.key});

  @override
  State<PrivacyAuthPage> createState() => _PrivacyAuthPageState();
}

class _PrivacyAuthPageState extends State<PrivacyAuthPage> {
  final _privacyService = PrivacyService();

  bool _canUseBiometric = false;
  bool _biometricEnabled = false;
  String _biometricType = '生物识别';
  String? _errorMessage;
  int _failedAttempts = 0;
  DateTime? _lockUntil;
  bool _isProcessing = false;
  String _currentPin = ''; // 当前输入的PIN（用于横屏左右同步）

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final canUse = await _privacyService.canUseBiometric();
    final isEnabled = await _privacyService.isBiometricEnabled();
    final type = await _privacyService.getBiometricTypeString();

    if (mounted) {
      setState(() {
        _canUseBiometric = canUse;
        _biometricEnabled = isEnabled;
        _biometricType = type;
      });

      // 如果启用了生物识别，自动弹出验证
      if (_biometricEnabled && _canUseBiometric) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _authenticateWithBiometric();
          }
        });
      }
    }
  }

  Future<void> _onPinCompleted(String pin) async {
    if (_isProcessing) return;

    // 检查是否被锁定
    if (_lockUntil != null && DateTime.now().isBefore(_lockUntil!)) {
      final remainingSeconds = _lockUntil!.difference(DateTime.now()).inSeconds;
      setState(() {
        _errorMessage = '输入错误次数过多，请等待$remainingSeconds秒';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final success = await _privacyService.verifyPin(pin);

      if (success && mounted) {
        // 验证成功，激活会话
        _privacyService.markSessionActive();

        // 进入隐私空间
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PrivacySpacePage()),
        );
      } else if (mounted) {
        // 验证失败
        setState(() {
          _failedAttempts++;
          _isProcessing = false;
          _currentPin = ''; // 清空PIN状态

          if (_failedAttempts >= 5) {
            // 锁定5分钟
            _lockUntil = DateTime.now().add(const Duration(minutes: 5));
            _errorMessage = 'PIN错误次数过多，已锁定5分钟';
          } else {
            _errorMessage = 'PIN错误，还可尝试${5 - _failedAttempts}次';
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

  Future<void> _authenticateWithBiometric() async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final success = await _privacyService.authenticateWithBiometric();

      // 生物识别对话框可能改变了系统方向，显式恢复
      logger.d('🔄 生物识别完成，恢复所有方向支持');
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      logger.d('✅ 方向设置已调用');

      if (success && mounted) {
        // 验证成功，激活会话
        _privacyService.markSessionActive();

        // 等待方向设置生效后再跳转（增加延迟到300ms）
        logger.d('⏳ 等待300ms让方向设置生效');
        await Future.delayed(const Duration(milliseconds: 300));
        logger.d('✅ 延迟完成，准备跳转');

        // 进入隐私空间
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const PrivacySpacePage()),
          );
        }
      } else if (mounted) {
        setState(() {
          _errorMessage = '$_biometricType验证失败';
        });
      }
    } catch (e) {
      logger.e('生物识别验证异常: $e');
      // 异常情况下也要恢复方向
      logger.d('🔄 异常情况，恢复所有方向支持');
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      if (mounted) {
        setState(() {
          _errorMessage = '验证异常，请使用PIN';
        });
      }
    }
  }

  Future<void> _onForgotPin() async {
    if (_biometricEnabled && _canUseBiometric) {
      // 尝试使用生物识别重置PIN
      final success = await _privacyService.authenticateWithBiometric();

      // 生物识别对话框可能改变了系统方向，显式恢复
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      if (success && mounted) {
        // 验证成功，进入重置PIN页面
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PrivacyResetPinPage()),
        );

        if (result == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ PIN重置成功，请使用新PIN登录')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$_biometricType验证失败')),
        );
      }
    } else {
      // 显示重置警告对话框
      _showResetDialog();
    }
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('重置隐私空间'),
          ],
        ),
        content: const Text(
          '由于您未启用生物识别，唯一的恢复方式是清空隐私空间。\n\n'
          '⚠️ 警告：此操作将：\n'
          '• 永久删除所有隐私文件\n'
          '• 清除PIN设置\n'
          '• 无法撤销\n\n'
          '确定要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final confirmed = await _showFinalConfirmation();
              if (confirmed && mounted) {
                await _resetPrivacySpace();
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空并重置'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showFinalConfirmation() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('最后确认'),
            content: const Text('您确定要删除所有隐私文件并重置吗？此操作不可恢复！'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('确认删除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _resetPrivacySpace() async {
    try {
      await _privacyService.resetPrivacySpace();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 隐私空间已重置')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      logger.e('重置隐私空间失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重置失败：$e')),
        );
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
        title: const Text('验证身份'),
        toolbarHeight: isLandscape ? 40 : 48,
        actions: [
          TextButton(
            onPressed: _onForgotPin,
            child: const Text('忘记PIN？'),
          ),
        ],
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
              Icons.lock,
              size: 80,
              color: theme.colorScheme.primary,
            ),

            const SizedBox(height: 24),

            // 标题
            const Text(
              '隐私空间',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // 说明
            Text(
              '请输入PIN码以继续',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 48),

            // PIN输入
            if (!_isProcessing)
              PrivacyPinInput(
                key: ValueKey(_failedAttempts), // 失败后重建组件清空输入
                onCompleted: _onPinCompleted,
                errorMessage: _errorMessage,
                portraitMode: true, // 竖屏使用大键盘
              )
            else
              const CircularProgressIndicator(),

            const SizedBox(height: 32),

            // 生物识别按钮
            if (_canUseBiometric && _biometricEnabled)
              OutlinedButton.icon(
                onPressed: _authenticateWithBiometric,
                icon: Icon(
                  _biometricType == 'Face ID' ? Icons.face : Icons.fingerprint,
                ),
                label: Text('使用$_biometricType'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
              ),
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
                        Icons.lock,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),

                      const SizedBox(height: 12),

                      // 标题
                      const Text(
                        '隐私空间',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 6),

                      // 说明
                      Text(
                        '请输入PIN码以继续',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 16),

                      // PIN输入指示器和确认按钮
                      if (!_isProcessing)
                        PrivacyPinInput(
                          key: ValueKey(_failedAttempts),
                          onCompleted: _onPinCompleted,
                          errorMessage: _errorMessage,
                          landscapeMode: true, // 横屏模式
                          externalPin: _currentPin, // 使用共享PIN状态
                        )
                      else
                        const CircularProgressIndicator(),

                      const SizedBox(height: 12),

                      // 生物识别按钮
                      if (_canUseBiometric && _biometricEnabled)
                        OutlinedButton.icon(
                          onPressed: _authenticateWithBiometric,
                          icon: Icon(
                            _biometricType == 'Face ID' ? Icons.face : Icons.fingerprint,
                            size: 18,
                          ),
                          label: Text('使用$_biometricType', style: const TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                          ),
                        ),
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
                  key: ValueKey('keyboard_$_failedAttempts'),
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
