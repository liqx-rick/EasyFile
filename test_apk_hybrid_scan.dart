#!/usr/bin/env dart
// 测试APK混合扫描功能
// 使用方法: dart test_apk_hybrid_scan.dart

void main() {
  print('='.repeat(60));
  print('APK混合扫描优化 - 测试脚本');
  print('='.repeat(60));
  
  print('\n📋 测试清单:\n');
  
  final testCases = [
    {
      'id': 1,
      'name': 'QQ下载的660权限APK',
      'file': '/storage/emulated/0/Download/QQ/app-release/app-release.apk',
      'permission': '-rw-rw---- (660)',
      'expect': '✅ MediaStore可以扫描到',
      'command': 'adb shell ls -l /storage/emulated/0/Download/QQ/app-release/',
    },
    {
      'id': 2,
      'name': '深层目录APK（3+层）',
      'file': '/storage/emulated/0/Download/QQ/app-release/app-release.apk',
      'depth': '深度2（Download → QQ → app-release → file）',
      'expect': '✅ 深度限制5层，可以扫描到',
    },
    {
      'id': 3,
      'name': 'MediaStore扫描性能',
      'expect': '✅ 应该在500ms内完成',
      'verify': '查看日志: [ApkManagerService] ✅ MediaStore扫描完成',
    },
    {
      'id': 4,
      'name': '混合扫描统计',
      'expect': '✅ 日志显示MediaStore和文件系统分别计数',
      'verify': '查看日志: MediaStore: X 个, 文件系统补充: Y 个',
    },
    {
      'id': 5,
      'name': '权限错误日志',
      'expect': '✅ 权限被拒的文件应该有警告日志',
      'verify': '查看日志: [ApkManagerService] ⚠️ 权限被拒',
    },
  ];
  
  for (var testCase in testCases) {
    print('测试 ${testCase['id']}: ${testCase['name']}');
    print('   文件: ${testCase['file'] ?? 'N/A'}');
    print('   预期: ${testCase['expect']}');
    if (testCase.containsKey('command')) {
      print('   验证命令: ${testCase['command']}');
    }
    if (testCase.containsKey('verify')) {
      print('   验证方法: ${testCase['verify']}');
    }
    print('');
  }
  
  print('\n' + '='.repeat(60));
  print('🚀 执行测试步骤:');
  print('='.repeat(60));
  print('');
  
  final steps = [
    '1. 启动应用: flutter run',
    '2. 打开终端监听日志: adb logcat | grep -i ApkManagerService',
    '3. 在应用中进入 [存储管理] → [安装包管理]',
    '4. 点击右上角刷新按钮 🔄',
    '5. 观察日志输出，验证以下内容:',
    '   - 📱 阶段1: MediaStore扫描...',
    '   - ✅ MediaStore扫描完成: X 个APK (Yms)',
    '   - 📁 阶段2: 文件系统扫描补充...',
    '   - ✅ 文件系统扫描完成: 补充 Z 个APK (Wms)',
    '   - ========== 扫描统计 ==========',
    '   - 总文件数: N 个APK',
    '6. 检查APK列表中是否有 app-release.apk',
    '7. 尝试点击该APK，查看详情',
  ];
  
  for (var step in steps) {
    print(step);
  }
  
  print('\n' + '='.repeat(60));
  print('📊 预期结果:');
  print('='.repeat(60));
  print('');
  print('✅ QQ下载的app-release.apk应该出现在列表中');
  print('✅ MediaStore扫描速度应该很快（<500ms）');
  print('✅ 总APK数量应该比之前多（20个 vs 15个）');
  print('✅ 日志显示详细的扫描统计信息');
  print('✅ 权限被拒的文件有明确的警告日志');
  print('');
  
  print('='.repeat(60));
  print('🔍 问题排查:');
  print('='.repeat(60));
  print('');
  print('如果仍然扫描不到:');
  print('1. 检查MediaStore是否正常工作:');
  print('   adb shell content query --uri content://media/external/file');
  print('');
  print('2. 检查文件是否被MediaStore索引:');
  print('   adb shell content query --uri content://media/external/file \\');
  print('     --where "_data LIKE \\'%app-release.apk%\\'"');
  print('');
  print('3. 手动触发MediaStore扫描:');
  print('   adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \\');
  print('     -d file:///storage/emulated/0/Download/QQ/app-release/app-release.apk');
  print('');
  print('4. 查看完整日志:');
  print('   adb logcat -v time > apk_scan_test.log');
  print('   (在另一个终端执行测试，然后分析日志文件)');
  print('');
  
  print('='.repeat(60));
  print('✅ 测试脚本准备完成！');
  print('='.repeat(60));
}

extension StringRepeat on String {
  String repeat(int count) => List.filled(count, this).join();
}
