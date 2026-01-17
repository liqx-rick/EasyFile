import 'package:flutter/material.dart';

/// 密码输入对话框
/// 
/// 用于输入加密压缩包的密码
class PasswordInputDialog extends StatefulWidget {
  final String? title;
  final String? message;
  final int? remainingAttempts;
  
  const PasswordInputDialog({
    super.key,
    this.title,
    this.message,
    this.remainingAttempts,
  });

  @override
  State<PasswordInputDialog> createState() => _PasswordInputDialogState();
}

class _PasswordInputDialogState extends State<PasswordInputDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscureText = true;
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lock, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(widget.title ?? '需要密码'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.message ?? '此压缩包已加密，请输入密码：',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: _obscureText,
            autofocus: true,
            enabled: !_isProcessing,
            decoration: InputDecoration(
              hintText: '输入密码',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureText ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscureText = !_obscureText;
                  });
                },
              ),
            ),
            onSubmitted: (_) => _handleSubmit(),
          ),
          if (widget.remainingAttempts != null) ...[
            const SizedBox(height: 8),
            Text(
              '剩余尝试次数: ${widget.remainingAttempts}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: widget.remainingAttempts! <= 1 
                    ? theme.colorScheme.error 
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isProcessing ? null : _handleSubmit,
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('确定'),
        ),
      ],
    );
  }

  void _handleSubmit() {
    final password = _controller.text.trim();
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('密码不能为空'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    setState(() {
      _isProcessing = true;
    });
    
    Navigator.of(context).pop(password);
  }
}
