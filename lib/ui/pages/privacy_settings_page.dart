import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/services/privacy_service.dart';
import 'package:easyfile/ui/pages/privacy_reset_pin_page.dart';
import 'package:flutter/material.dart';

/// 隐私空间设置页面
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  final _privacyService = PrivacyService();

  bool _biometricEnabled = false;
  bool _canUseBiometric = false;
  String _biometricType = '生物识别';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final canUse = await _privacyService.canUseBiometric();
      final isEnabled = await _privacyService.isBiometricEnabled();
      final type = await _privacyService.getBiometricTypeString();

      if (mounted) {
        setState(() {
          _canUseBiometric = canUse;
          _biometricEnabled = isEnabled;
          _biometricType = type;
          _isLoading = false;
        });
      }
    } catch (e) {
      logger.e('加载设置失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (!_canUseBiometric) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此设备不支持生物识别')),
      );
      return;
    }

    if (value) {
      // 启用生物识别前先验证一次
      try {
        final success = await _privacyService.authenticateWithBiometric();
        if (success && mounted) {
          await _privacyService.setBiometricEnabled(true);
          setState(() {
            _biometricEnabled = true;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ 生物识别已启用')),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$_biometricType验证失败')),
          );
        }
      } catch (e) {
        logger.e('启用生物识别失败: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('启用失败')),
          );
        }
      }
    } else {
      // 禁用生物识别
      await _privacyService.setBiometricEnabled(false);
      setState(() {
        _biometricEnabled = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('生物识别已禁用')),
        );
      }
    }
  }

  Future<void> _changePin() async {
    // 先验证生物识别或当前PIN
    if (_biometricEnabled && _canUseBiometric) {
      final success = await _privacyService.authenticateWithBiometric();
      if (success && mounted) {
        _navigateToResetPin();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$_biometricType验证失败')),
        );
      }
    } else {
      _navigateToResetPin();
    }
  }

  void _navigateToResetPin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PrivacyResetPinPage()),
    ).then((result) {
      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ PIN码已修改')),
        );
      }
    });
  }

  Future<void> _resetPrivacySpace() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('重置隐私空间'),
          ],
        ),
        content: const Text(
          '⚠️ 此操作将：\n'
          '• 永久删除所有隐私文件\n'
          '• 清除PIN设置\n'
          '• 清除生物识别设置\n'
          '• 无法撤销\n\n'
          '确定要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _privacyService.resetPrivacySpace();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ 隐私空间已重置')),
          );
          // 返回到首页
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      } catch (e) {
        logger.e('重置失败: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('重置失败：$e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // 安全设置
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '安全设置',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),

                // 生物识别开关
                SwitchListTile(
                  secondary: Icon(
                    _biometricType == 'Face ID' ? Icons.face : Icons.fingerprint,
                  ),
                  title: const Text('生物识别'),
                  subtitle: Text(
                    _canUseBiometric ? '使用$_biometricType快速验证身份' : '此设备不支持生物识别',
                  ),
                  value: _biometricEnabled,
                  onChanged: _canUseBiometric ? _toggleBiometric : null,
                ),

                const Divider(),

                // 修改PIN
                ListTile(
                  leading: const Icon(Icons.lock_reset),
                  title: const Text('修改PIN码'),
                  subtitle: const Text('更改隐私空间的PIN码'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changePin,
                ),

                const Divider(),

                // 危险区域
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    '危险区域',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),

                // 重置隐私空间
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text(
                    '重置隐私空间',
                    style: TextStyle(color: Colors.red),
                  ),
                  subtitle: const Text('删除所有隐私文件并清除设置'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.red),
                  onTap: _resetPrivacySpace,
                ),

                const SizedBox(height: 24),

                // 提示信息
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '💡 建议启用生物识别，可在忘记PIN时快速重置。',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
