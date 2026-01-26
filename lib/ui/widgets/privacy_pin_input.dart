import 'package:flutter/material.dart';

/// PIN输入组件
///
/// 支持4-6位数字PIN输入，带视觉反馈
class PrivacyPinInput extends StatefulWidget {
  final Function(String pin) onCompleted;
  final String? errorMessage;
  final bool landscapeMode; // 是否为横屏模式
  final bool keyboardOnly; // 仅显示键盘（不显示PIN点和确认按钮）
  final bool portraitMode; // 是否为竖屏模式（使用大键盘）
  final String? externalPin; // 外部传入的PIN状态（用于横屏左右同步）
  final Function(String pin)? onPinChanged; // PIN变化回调（用于横屏左右同步）

  const PrivacyPinInput({
    super.key,
    required this.onCompleted,
    this.errorMessage,
    this.landscapeMode = false,
    this.keyboardOnly = false,
    this.portraitMode = false,
    this.externalPin,
    this.onPinChanged,
  });

  @override
  State<PrivacyPinInput> createState() => _PrivacyPinInputState();
}

class _PrivacyPinInputState extends State<PrivacyPinInput> {
  String _pin = '';
  final int _minLength = 4;
  final int _maxLength = 6;

  @override
  void initState() {
    super.initState();
    // 如果有外部PIN状态，使用外部状态
    if (widget.externalPin != null) {
      _pin = widget.externalPin!;
    }
  }

  @override
  void didUpdateWidget(PrivacyPinInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当外部PIN状态变化时，更新内部状态
    if (widget.externalPin != null && widget.externalPin != _pin) {
      setState(() {
        _pin = widget.externalPin!;
      });
    }
  }

  void _onNumberPressed(int number) {
    if (_pin.length < _maxLength) {
      final newPin = _pin + number.toString();
      setState(() {
        _pin = newPin;
      });
      // 通知外部PIN变化
      widget.onPinChanged?.call(newPin);
    }
  }

  void _onConfirmPressed() {
    if (_pin.length >= _minLength) {
      widget.onCompleted(_pin);
    }
  }

  void _onDeletePressed() {
    if (_pin.isNotEmpty) {
      final newPin = _pin.substring(0, _pin.length - 1);
      setState(() {
        _pin = newPin;
      });
      // 通知外部PIN变化
      widget.onPinChanged?.call(newPin);
    }
  }

  void _onClearPressed() {
    setState(() {
      _pin = '';
    });
    // 通知外部PIN变化
    widget.onPinChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 仅显示键盘（横屏右侧）
    if (widget.keyboardOnly) {
      return _buildKeyboard();
    }

    // 完整显示（包含PIN点、错误消息、确认按钮、键盘）
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // PIN点显示（从右向左填充）
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_maxLength, (index) {
            // 从右向左填充：当输入3位时，显示在最右边的3个点
            // index=0是最左边，index=5是最右边
            // 当输入1位时，只有index=5亮；输入3位时，index=3,4,5亮
            final isActive = index >= (_maxLength - _pin.length);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.3),
                border: Border.all(
                  color: isActive ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
            );
          }),
        ),

        const SizedBox(height: 16),

        const SizedBox(height: 24),

        // 错误消息
        if (widget.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              widget.errorMessage!,
              style: TextStyle(
                color: theme.colorScheme.error,
                fontSize: 14,
              ),
            ),
          ),

        // 确认按钮
        FilledButton(
          onPressed: _pin.length >= _minLength ? _onConfirmPressed : null,
          child: const Text('确认'),
        ),

        // 横屏模式下不显示键盘（键盘在右侧独立显示）
        if (!widget.landscapeMode) ...[
          const SizedBox(height: 24),
          _buildKeyboard(),
        ],
      ],
    );
  }

  /// 构建数字键盘
  Widget _buildKeyboard() {
    // 竖屏模式使用更大的键盘
    final keyboardWidth = widget.portraitMode ? 280.0 : 200.0;
    final buttonSpacing = widget.portraitMode ? 12.0 : 6.0;

    return SizedBox(
      width: keyboardWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行 1-3
          _buildNumberRow([1, 2, 3]),
          SizedBox(height: buttonSpacing),
          // 第二行 4-6
          _buildNumberRow([4, 5, 6]),
          SizedBox(height: buttonSpacing),
          // 第三行 7-9
          _buildNumberRow([7, 8, 9]),
          SizedBox(height: buttonSpacing),
          // 第四行 清除-0-删除
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(
                icon: Icons.clear,
                onPressed: _onClearPressed,
              ),
              _buildNumberButton(0),
              _buildActionButton(
                icon: Icons.backspace_outlined,
                onPressed: _onDeletePressed,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumberRow(List<int> numbers) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: numbers.map((n) => _buildNumberButton(n)).toList(),
    );
  }

  Widget _buildNumberButton(int number) {
    final theme = Theme.of(context);
    // 竖屏模式使用更大的按钮
    final buttonSize = widget.portraitMode ? 72.0 : 52.0;
    final fontSize = widget.portraitMode ? 28.0 : 22.0;

    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onNumberPressed(number),
          borderRadius: BorderRadius.circular(36),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Center(
              child: Text(
                number.toString(),
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    // 竖屏模式使用更大的按钮
    final buttonSize = widget.portraitMode ? 72.0 : 52.0;
    final iconSize = widget.portraitMode ? 28.0 : 22.0;

    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize),
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
