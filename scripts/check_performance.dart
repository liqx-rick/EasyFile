#!/usr/bin/env dart

/// Flutter 性能检查工具
///
/// 检查项目中是否遵循了性能最佳实践：
/// 1. 列表是否使用懒加载
/// 2. 图片是否限制了缓存尺寸
/// 3. 视图切换是否正确管理资源
///
/// 运行方式：dart scripts/check_performance.dart

import 'dart:io';

void main() {
  print('🔍 开始性能检查...\n');

  int issueCount = 0;

  issueCount += checkListViews();
  issueCount += checkImages();
  issueCount += checkShrinkWrap();
  issueCount += checkImageCache();

  print('\n' + '=' * 60);
  if (issueCount == 0) {
    print('✅ 性能检查通过！未发现问题。');
  } else {
    print('⚠️  发现 $issueCount 个潜在问题，请检查上述警告。');
  }
  print('=' * 60);

  exit(issueCount > 0 ? 1 : 0);
}

/// 检查 ListView/GridView 是否使用懒加载
int checkListViews() {
  print('📋 检查列表视图...');
  int issues = 0;

  final files = findDartFiles('lib/ui');
  for (final file in files) {
    // 例外：设置页面和小数据量的静态列表
    if (file.contains('settings_page.dart') ||
        file.contains('quick_access_manage_page.dart')) {
      continue;
    }

    final content = File(file).readAsStringSync();
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 检查 ListView(children: ...)
      if (line.contains('ListView(') && !line.contains('ListView.builder')) {
        // 检查下几行是否有 children:
        final nextLines = lines.skip(i).take(5).join(' ');
        if (nextLines.contains('children:')) {
          print('  ⚠️  ${file}:${i + 1}');
          print('     建议使用 ListView.builder 而不是 ListView(children: ...)');
          issues++;
        }
      }

      // 检查 GridView(children: ...)
      if (line.contains('GridView(') && !line.contains('GridView.builder')) {
        final nextLines = lines.skip(i).take(5).join(' ');
        if (nextLines.contains('children:')) {
          print('  ⚠️  ${file}:${i + 1}');
          print('     建议使用 GridView.builder 而不是 GridView(children: ...)');
          issues++;
        }
      }
    }
  }

  if (issues == 0) {
    print('  ✅ 所有列表都使用了懒加载');
  }
  print('');
  return issues;
}

/// 检查图片是否限制了缓存尺寸
int checkImages() {
  print('🖼️  检查图片加载...');
  int issues = 0;

  final files = findDartFiles('lib/ui');
  for (final file in files) {
    final content = File(file).readAsStringSync();
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 检查 Image.file/Image.memory/Image.network
      if (line.contains(RegExp(r'Image\.(file|memory|network)\('))) {
        // 检查接下来的几行是否有 cacheWidth 或 cacheHeight
        final nextLines = lines.skip(i).take(15).join('\n');
        if (!nextLines.contains('cacheWidth') &&
            !nextLines.contains('cacheHeight') &&
            !nextLines.contains('// 预览') && // 预览页面例外
            !nextLines.contains('预览页面') && // 中文注释
            !nextLines.contains('Image.asset')) {
          // asset 例外
          print('  ⚠️  ${file}:${i + 1}');
          print('     建议为 Image 设置 cacheWidth 和 cacheHeight');
          issues++;
        }
      }
    }
  }

  if (issues == 0) {
    print('  ✅ 所有图片都限制了缓存尺寸');
  }
  print('');
  return issues;
}

/// 检查是否过度使用 shrinkWrap
int checkShrinkWrap() {
  print('📏 检查 shrinkWrap 使用...');
  int issues = 0;

  final files = findDartFiles('lib/ui');
  for (final file in files) {
    final content = File(file).readAsStringSync();
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.contains('shrinkWrap: true')) {
        // 检查是否有合理的注释说明（同一行或上一行）
        final prevLine = i > 0 ? lines[i - 1] : '';
        final hasComment = (prevLine.contains('//') || line.contains('//')) &&
            (prevLine.contains('必须') ||
                line.contains('必须') ||
                prevLine.contains('小数据量') ||
                line.contains('小数据量') ||
                prevLine.contains('Reorderable') ||
                line.contains('Reorderable'));

        if (!hasComment) {
          print('  ⚠️  ${file}:${i + 1}');
          print('     使用 shrinkWrap: true 可能影响性能，请确认是否必要');
          issues++;
        }
      }
    }
  }

  if (issues == 0) {
    print('  ✅ shrinkWrap 使用合理');
  }
  print('');
  return issues;
}

/// 检查是否配置了图片缓存
int checkImageCache() {
  print('💾 检查图片缓存配置...');
  int issues = 0;

  final mainFile = File('lib/main.dart');
  if (!mainFile.existsSync()) {
    print('  ❌ 找不到 lib/main.dart');
    return 1;
  }

  final content = mainFile.readAsStringSync();

  if (!content.contains('imageCache.maximumSize')) {
    print('  ⚠️  lib/main.dart');
    print('     建议在 main() 中配置 imageCache.maximumSize');
    issues++;
  }

  if (!content.contains('imageCache.maximumSizeBytes')) {
    print('  ⚠️  lib/main.dart');
    print('     建议在 main() 中配置 imageCache.maximumSizeBytes');
    issues++;
  }

  if (issues == 0) {
    print('  ✅ 图片缓存已正确配置');
  }
  print('');
  return issues;
}

/// 递归查找目录下的所有 .dart 文件
List<String> findDartFiles(String dir) {
  final files = <String>[];
  final directory = Directory(dir);

  if (!directory.existsSync()) {
    return files;
  }

  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(entity.path);
    }
  }

  return files;
}
