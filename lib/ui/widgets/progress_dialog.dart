import 'package:flutter/material.dart';
import 'package:easyfile/core/logger.dart';

class ProgressDialog extends StatelessWidget {
  final String title;
  final String message;
  final bool showProgress;

  const ProgressDialog({
    super.key,
    required this.title,
    required this.message,
    this.showProgress = true,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showProgress) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
          ],
          Text(message),
        ],
      ),
    );
  }

  static void show(
    BuildContext context, {
    required String title,
    required String message,
    bool showProgress = true,
  }) {
    logger.d('Showing progress dialog: $title - $message');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProgressDialog(
        title: title,
        message: message,
        showProgress: showProgress,
      ),
    );
  }

  static void hide(BuildContext context) {
    logger.d('Hiding progress dialog');
    Navigator.of(context).pop();
  }
}