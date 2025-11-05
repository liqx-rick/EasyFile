import 'package:flutter/material.dart';
import 'package:easyfile/data/models/file_item.dart';
import 'package:easyfile/core/logger.dart';

class RenameDialog extends StatefulWidget {
  final FileItem file;

  const RenameDialog({
    super.key,
    required this.file,
  });

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    logger.d('Initializing rename dialog for: ${widget.file.name}');
    _controller = TextEditingController(text: widget.file.name);
    
    // 如果是文件，选中文件名部分（不包括扩展名）
    if (!widget.file.isDirectory && widget.file.name.contains('.')) {
      final lastDotIndex = widget.file.name.lastIndexOf('.');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: lastDotIndex,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.file.isDirectory ? Icons.folder : Icons.insert_drive_file,
            color: widget.file.isDirectory ? Colors.amber : Colors.blue,
          ),
          const SizedBox(width: 8),
          const Text('重命名'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '原名称：${widget.file.name}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '新名称',
              border: const OutlineInputBorder(),
              errorText: _errorText,
            ),
            onChanged: (value) {
              setState(() {
                _errorText = _validateName(value);
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _errorText == null && _controller.text.isNotEmpty
              ? () {
                  final newName = _controller.text.trim();
                  logger.i('Rename dialog confirmed: ${widget.file.name} -> $newName');
                  Navigator.of(context).pop(newName);
                }
              : null,
          child: const Text('重命名'),
        ),
      ],
    );
  }

  String? _validateName(String name) {
    if (name.trim().isEmpty) {
      return '名称不能为空';
    }
    
    if (name.trim() == widget.file.name) {
      return '名称没有变化';
    }
    
    // 检查非法字符
    final invalidChars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|'];
    for (final char in invalidChars) {
      if (name.contains(char)) {
        return '名称不能包含字符: $char';
      }
    }
    
    return null;
  }
}