import 'package:easyfile/core/content/privacy_policy_content.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/ui/pages/privacy_policy_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 隐私政策弹窗
///
/// 根据友盟合规要求，必须在用户明确同意隐私政策后才能初始化SDK
/// 此弹窗在应用首次启动或隐私政策更新时显示
class PrivacyPolicyDialog extends StatelessWidget {
  final VoidCallback onAgree;
  final VoidCallback onDisagree;

  const PrivacyPolicyDialog({
    super.key,
    required this.onAgree,
    required this.onDisagree,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 防止用户通过返回键关闭弹窗
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Row(
                children: [
                  Icon(
                    Icons.privacy_tip_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '隐私政策与用户协议',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 内容
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '欢迎使用易览文件！',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 12),
                      _buildPrivacyContent(context),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 按钮
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: OutlinedButton(
                      onPressed: () {
                        logger.i('用户拒绝隐私政策');
                        onDisagree();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('不同意并退出'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 4,
                    child: FilledButton(
                      onPressed: () {
                        logger.i('用户同意隐私政策');
                        onAgree();
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('同意并继续'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyContent(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          height: 1.6,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
        );

    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );

    return RichText(
      text: TextSpan(
        style: textStyle,
        children: [
          TextSpan(text: PrivacyPolicyContent.dialogIntro),
          TextSpan(
            text: '《隐私政策》',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                logger.d('点击查看隐私政策');
                _showPrivacyPolicy(context);
              },
          ),
          const TextSpan(text: '和'),
          TextSpan(
            text: '《用户协议》',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                logger.d('点击查看用户协议');
                _showUserAgreement(context);
              },
          ),
          const TextSpan(text: '。\n\n'),
          TextSpan(text: PrivacyPolicyContent.dialogBody),
        ],
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
    );
  }

  void _showUserAgreement(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用户协议'),
        content: const SingleChildScrollView(
          child: Text(
            '欢迎使用易览文件管理应用！\n\n'
            '一、服务说明\n'
            '易览文件是一款本地文件管理工具，帮助用户管理设备上的文件。\n\n'
            '二、使用规范\n'
            '1. 您应遵守当地法律法规使用本应用\n'
            '2. 不得利用本应用从事违法活动\n'
            '3. 请勿删除重要系统文件\n\n'
            '三、免责声明\n'
            '1. 本应用仅提供工具，不对用户操作造成的数据丢失负责\n'
            '2. 建议在删除文件前做好备份\n'
            '3. 应用功能可能因设备差异存在兼容性问题\n\n'
            '四、知识产权\n'
            '1. 本应用的所有权利归开发者所有\n'
            '2. 未经许可不得反编译或修改应用\n\n'
            '五、协议修改\n'
            '我们保留修改本协议的权利，修改后将在应用内通知。\n\n'
            '六、联系我们\n'
            '如有任何问题，请通过应用内反馈功能联系我们。',
            style: TextStyle(height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
