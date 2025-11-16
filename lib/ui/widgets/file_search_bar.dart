import 'package:flutter/material.dart';
import 'package:easyfile/core/services/search_history_service.dart';

/// 文件搜索栏组件 - 简化版，不包含历史面板
class FileSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final bool autofocus;
  final Function(String) onSearch;
  final VoidCallback onClose;
  final Function(String)? onChanged;

  const FileSearchBar({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText = '搜索文件...',
    this.autofocus = true,
    required this.onSearch,
    required this.onClose,
    this.onChanged,
  });

  @override
  State<FileSearchBar> createState() => _FileSearchBarState();
}

class _FileSearchBarState extends State<FileSearchBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (!mounted) return;
    final hasText = widget.controller.text.isNotEmpty;
    if (_hasText != hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  Future<void> _onSubmit(String value) async {
    if (value.trim().isNotEmpty) {
      await SearchHistoryService().addSearch(value);
      widget.onSearch(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surfaceContainerHighest,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: const TextStyle(fontSize: 14),
          prefixIcon: Icon(
            Icons.search,
            color: theme.primaryColor,
            size: 20,
          ),
          suffixIcon: IconButton(
            icon: Icon(_hasText ? Icons.clear : Icons.close, size: 20),
            onPressed: _hasText 
                ? () => widget.controller.clear()
                : widget.onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: _hasText ? '清除' : '关闭',
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
        ),
        onSubmitted: _onSubmit,
        onChanged: widget.onChanged,
      ),
    );
  }
}
