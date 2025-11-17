import 'dart:io';

void main() {
  // 需要修复的文件列表
  final files = [
    'lib/ui/pages/category_file_page.dart',
    'lib/ui/pages/file_browser_page.dart',
    'lib/ui/pages/storage_page.dart',
    'lib/ui/widgets/audio_player_widget.dart',
    'lib/ui/widgets/category_nav_bar.dart',
    'lib/ui/widgets/document_icon_widget.dart',
    'lib/ui/widgets/favorites_section.dart',
    'lib/ui/widgets/file_category_tab_bar.dart',
    'lib/ui/widgets/file_search_bar.dart',
    'lib/ui/widgets/media_info_bar.dart',
    'lib/ui/widgets/migration_result_dialog.dart',
    'lib/ui/widgets/real_video_thumbnail.dart',
    'lib/ui/widgets/search_history_panel.dart',
  ];

  for (final filePath in files) {
    final file = File(filePath);
    if (!file.existsSync()) {
      print('⚠️  文件不存在: $filePath');
      continue;
    }

    final content = file.readAsStringSync();
    
    // 替换 .withOpacity(数字) 为 .withValues(alpha: 数字)
    final newContent = content.replaceAllMapped(
      RegExp(r'\.withOpacity\(([0-9.]+)\)'),
      (match) => '.withValues(alpha: ${match.group(1)})',
    );

    if (content != newContent) {
      file.writeAsStringSync(newContent);
      print('✅ 已修复: $filePath');
    } else {
      print('ℹ️  无需修复: $filePath');
    }
  }

  print('\n完成！');
}
