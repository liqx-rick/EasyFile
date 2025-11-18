import 'package:flutter/material.dart';
import 'package:easyfile/core/services/search_history_service.dart';
import 'package:easyfile/core/logger.dart';

/// 文件搜索栏组件（使用Stack浮动显示搜索历史）
///
/// 搜索历史面板使用Stack浮动在搜索栏下方，不会影响Column布局
class FileSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final bool autofocus;
  final Function(String) onSearch;
  final VoidCallback onClose;
  final Function(String)? onChanged;

  /// 是否显示搜索历史（默认true）
  final bool showHistory;

  const FileSearchBar({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText = '搜索文件...',
    this.autofocus = true,
    required this.onSearch,
    required this.onClose,
    this.onChanged,
    this.showHistory = true,
  });

  @override
  State<FileSearchBar> createState() => _FileSearchBarState();
}

class _FileSearchBarState extends State<FileSearchBar> {
  bool _hasText = false;
  List<String> _history = [];
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
    widget.focusNode?.addListener(_onFocusChanged);
    _loadHistory();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode?.removeListener(_onFocusChanged);
    _removeOverlay();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (!widget.showHistory) return;
    logger.d('FileSearchBar: Loading search history...');
    final history = await SearchHistoryService().getHistory();
    logger.d('FileSearchBar: Loaded ${history.length} history items');
    if (mounted) {
      setState(() {
        _history = history;
      });
    }
  }

  void _onFocusChanged() async {
    logger.d(
        'FileSearchBar: Focus changed - hasFocus: ${widget.focusNode?.hasFocus}');
    if (widget.focusNode?.hasFocus == true) {
      // 获得焦点时重新加载历史（确保显示最新的搜索记录）
      await _loadHistory();

      if (widget.controller.text.isEmpty && _history.isNotEmpty) {
        logger.d(
            'FileSearchBar: Showing history overlay with ${_history.length} items');
        _showHistoryOverlay();
      }
    } else {
      _removeOverlay();
    }
  }

  void _onTextChanged() {
    if (!mounted) return;
    final hasText = widget.controller.text.isNotEmpty;
    if (_hasText != hasText) {
      setState(() {
        _hasText = hasText;
      });

      // 输入内容时隐藏历史，清空时显示历史
      if (hasText) {
        _removeOverlay();
      } else if (widget.focusNode?.hasFocus == true && _history.isNotEmpty) {
        _showHistoryOverlay();
      }
    }
  }

  void _showHistoryOverlay() {
    if (_overlayEntry != null || !widget.showHistory || _history.isEmpty) {
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: MediaQuery.of(context).size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 50), // 搜索栏高度
          child: Material(
            elevation: 4,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.3,
              ),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题栏
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '最近搜索',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await SearchHistoryService().clearHistory();
                            await _loadHistory();
                            _removeOverlay();
                          },
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child:
                              const Text('清除', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  // 历史记录列表
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final keyword = _history[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.history, size: 18),
                          title: Text(
                            keyword,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            widget.controller.text = keyword;
                            _removeOverlay();
                            _onSubmit(keyword);
                          },
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 0),
                          minVerticalPadding: 4,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> _onSubmit(String value) async {
    if (value.trim().isNotEmpty) {
      logger.d('FileSearchBar: Submitting search: $value');
      await SearchHistoryService().addSearch(value);
      await _loadHistory();
      _removeOverlay();
      widget.onSearch(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
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
              onPressed:
                  _hasText ? () => widget.controller.clear() : widget.onClose,
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
          ),
          onSubmitted: _onSubmit,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
