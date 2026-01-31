import 'dart:io';

/// 简单的APK扫描测试脚本
/// 
/// 不依赖Flutter，可以直接运行来测试文件扫描逻辑
void main() async {
  print('=== APK扫描问题诊断 ===\n');
  
  // 目标APK路径
  const targetPath = '/storage/emulated/0/Download/WeiXin/app-release.apk';
  print('🎯 目标文件: $targetPath\n');
  
  // 1. 检查文件扩展名
  print('【1】扩展名检查');
  final isApkExt = targetPath.toLowerCase().endsWith('.apk');
  print('  ✓ 扩展名是否为.apk: $isApkExt\n');
  
  // 2. 检查文件是否存在
  print('【2】文件存在性检查');
  final file = File(targetPath);
  if (file.existsSync()) {
    final stat = file.statSync();
    print('  ✓ 文件存在');
    print('  ✓ 大小: ${(stat.size / 1024 / 1024).toStringAsFixed(2)} MB');
    print('  ✓ 修改时间: ${stat.modified}');
  } else {
    print('  ✗ 文件不存在！');
    print('  提示: 请检查路径是否正确\n');
    
    // 尝试查找父目录
    final parentDir = Directory('/storage/emulated/0/Download/WeiXin');
    if (parentDir.existsSync()) {
      print('  父目录存在，列出所有APK文件:');
      final files = parentDir.listSync(recursive: false);
      final apks = files.where((e) => e.path.toLowerCase().endsWith('.apk'));
      if (apks.isEmpty) {
        print('    (未找到APK文件)');
      } else {
        for (final apk in apks) {
          print('    - ${apk.path}');
        }
      }
    } else {
      print('  父目录也不存在: ${parentDir.path}');
    }
  }
  print('');
  
  // 3. 检查扫描路径深度
  print('【3】扫描深度分析');
  const downloadRoot = '/storage/emulated/0/Download';
  if (targetPath.startsWith(downloadRoot)) {
    final relative = targetPath.substring(downloadRoot.length);
    final parts = relative.split('/').where((s) => s.isNotEmpty).toList();
    print('  ✓ 路径在Download目录下');
    print('  ✓ 相对路径: $relative');
    print('  ✓ 深度: ${parts.length} 层');
    print('  ✓ 层级结构: ${parts.join(' → ')}');
    print('  ✓ 扫描深度限制: 3层 (Download目录)');
    
    if (parts.length <= 3) {
      print('  ✓ 深度OK - 应该能被扫描到');
    } else {
      print('  ✗ 超过扫描深度！需要增加深度限制');
    }
  }
  print('');
  
  // 4. 测试目录扫描
  print('【4】实际扫描测试');
  final downloadDir = Directory(downloadRoot);
  if (downloadDir.existsSync()) {
    print('  开始扫描Download目录(深度≤3)...');
    
    final foundApks = <String>[];
    await _scanDirectory(
      downloadDir.path,
      foundApks,
      currentDepth: 0,
      maxDepth: 3,
    );
    
    print('  扫描结果: 找到 ${foundApks.length} 个APK文件');
    
    // 检查目标文件是否在扫描结果中
    final targetFound = foundApks.contains(targetPath);
    if (targetFound) {
      print('  ✓ 目标APK已找到！');
    } else {
      print('  ✗ 目标APK未找到！');
      print('  前10个找到的APK:');
      for (var i = 0; i < foundApks.length && i < 10; i++) {
        print('    ${i + 1}. ${foundApks[i]}');
      }
    }
  } else {
    print('  ✗ Download目录不存在');
  }
  print('');
  
  // 5. 总结
  print('【5】问题诊断总结');
  print('  如果上面显示"目标APK未找到"，可能的原因:');
  print('  ❶ 文件不存在或路径错误');
  print('  ❷ 文件权限问题，应用无法读取');
  print('  ❸ APK解析失败(需要在Android环境中检查)');
  print('  ❹ 缓存问题，使用了旧数据');
  print('');
  print('  建议操作:');
  print('  1️⃣ 在APK管理页面下拉刷新(强制重新扫描)');
  print('  2️⃣ 检查Android日志: adb logcat | grep ApkParser');
  print('  3️⃣ 验证文件: adb shell ls -la "$targetPath"');
  print('  4️⃣ 清除应用缓存后重试');
  print('');
  print('=== 诊断完成 ===');
}

/// 递归扫描目录查找APK文件
Future<void> _scanDirectory(
  String dirPath,
  List<String> apkFiles, {
  required int currentDepth,
  required int maxDepth,
}) async {
  if (currentDepth > maxDepth) {
    return;
  }

  try {
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      return;
    }

    final entities = await directory.list().toList();

    for (final entity in entities) {
      try {
        if (entity is File) {
          // 检查是否为APK文件
          if (entity.path.toLowerCase().endsWith('.apk')) {
            apkFiles.add(entity.path);
          }
        } else if (entity is Directory) {
          // 递归扫描子目录
          await _scanDirectory(
            entity.path,
            apkFiles,
            currentDepth: currentDepth + 1,
            maxDepth: maxDepth,
          );
        }
      } catch (e) {
        // 忽略单个文件/文件夹的访问错误
        continue;
      }
    }
  } catch (e) {
    // 忽略目录访问错误
  }
}
