import 'dart:io';
import 'package:easyfile/core/config/file_types_config.dart';

/// APK识别问题诊断脚本
/// 
/// 用于诊断为什么特定APK文件无法被识别
void main() async {
  print('=== APK识别问题诊断 ===\n');
  
  // 要检查的APK文件路径
  final targetApkPath = '/storage/emulated/0/Download/WeiXin/app-release.apk';
  
  print('目标文件: $targetApkPath\n');
  
  // 1. 检查文件扩展名识别
  print('【1】扩展名检查');
  final fileTypesConfig = FileTypesConfig();
  final isApk = fileTypesConfig.isApkFile(targetApkPath);
  print('  - 文件路径: $targetApkPath');
  print('  - 是否识别为APK: $isApk');
  
  final ext = targetApkPath.toLowerCase().split('.').last;
  print('  - 提取的扩展名: $ext');
  print('  - APK扩展名列表: ${fileTypesConfig.apkExtensions}');
  print('  - 扩展名匹配: ${fileTypesConfig.apkExtensions.contains(ext)}\n');
  
  // 2. 检查文件是否存在
  print('【2】文件存在性检查');
  final file = File(targetApkPath);
  final exists = file.existsSync();
  print('  - 文件是否存在: $exists');
  
  if (exists) {
    final stat = file.statSync();
    print('  - 文件大小: ${stat.size} 字节 (${(stat.size / 1024 / 1024).toStringAsFixed(2)} MB)');
    print('  - 修改时间: ${stat.modified}');
    print('  - 文件类型: ${stat.type}');
    
    // 检查文件权限
    try {
      final canRead = file.existsSync();
      print('  - 可读性: $canRead');
    } catch (e) {
      print('  - 可读性检查失败: $e');
    }
  } else {
    print('  ⚠️ 文件不存在！请检查路径是否正确');
  }
  print('');
  
  // 3. 检查目录路径
  print('【3】目录路径检查');
  final parentDir = Directory('/storage/emulated/0/Download/WeiXin');
  final parentExists = parentDir.existsSync();
  print('  - 父目录: ${parentDir.path}');
  print('  - 父目录是否存在: $parentExists');
  
  if (parentExists) {
    print('  - 列出父目录中的APK文件:');
    try {
      final entities = parentDir.listSync();
      final apkFiles = entities
          .where((e) => e is File && e.path.toLowerCase().endsWith('.apk'))
          .toList();
      
      if (apkFiles.isEmpty) {
        print('    ⚠️ 未找到任何APK文件');
      } else {
        for (final apkFile in apkFiles) {
          final f = File(apkFile.path);
          final size = f.lengthSync();
          print('    - ${apkFile.path} (${(size / 1024 / 1024).toStringAsFixed(2)} MB)');
        }
      }
    } catch (e) {
      print('    ❌ 无法列出目录: $e');
    }
  }
  print('');
  
  // 4. 检查扫描路径配置
  print('【4】扫描路径配置检查');
  print('  检查该路径是否在常规扫描范围内...');
  
  // 模拟扫描路径检查
  final downloadPath = '/storage/emulated/0/Download';
  print('  - 标准Download路径: $downloadPath');
  print('  - 目标路径是否包含Download: ${targetApkPath.contains(downloadPath)}');
  
  final weixinPath = '/storage/emulated/0/Download/WeiXin';
  print('  - WeiXin子目录: $weixinPath');
  print('  - 扫描深度要求: Download目录扫描深度为3层');
  
  // 计算路径深度
  final relativePath = targetApkPath.replaceFirst(downloadPath, '');
  final depth = relativePath.split('/').where((s) => s.isNotEmpty).length;
  print('  - 当前文件相对深度: $depth');
  print('  - 是否在扫描深度范围内: ${depth <= 3}');
  print('');
  
  // 5. 检查APK解析能力
  print('【5】APK解析能力检查');
  if (exists) {
    print('  尝试模拟APK解析流程...');
    print('  注意: 需要在Android环境中运行才能真正解析APK');
    print('  建议检查点:');
    print('    1. APK文件是否损坏');
    print('    2. Android PackageManager是否能解析该APK');
    print('    3. 是否有文件权限问题');
  }
  print('');
  
  // 6. 常见问题排查
  print('【6】常见问题排查');
  print('  可能的原因:');
  print('  ❶ 文件路径不在扫描范围内');
  print('     - 检查路径是否在优先扫描路径列表中');
  print('     - Download/WeiXin应该是优先扫描路径');
  print('');
  print('  ❷ 扫描深度限制');
  print('     - Download目录扫描深度=3');
  print('     - 当前文件深度=$depth (应该≤3)');
  print('');
  print('  ❸ APK文件解析失败');
  print('     - APK文件可能损坏');
  print('     - PackageManager无法解析该APK');
  print('     - 检查Android端日志: adb logcat | grep ApkParserHelper');
  print('');
  print('  ❹ 缓存问题');
  print('     - APK列表可能使用了缓存');
  print('     - 尝试在APK管理页面下拉刷新');
  print('     - 或清除应用缓存后重新扫描');
  print('');
  print('  ❺ 文件权限问题');
  print('     - 检查应用是否有读取该文件的权限');
  print('     - Android 11+需要特殊权限访问某些目录');
  print('');
  
  // 7. 建议的解决方案
  print('【7】建议的解决方案');
  print('  ✓ 立即尝试:');
  print('    1. 在APK管理页面下拉刷新，强制重新扫描');
  print('    2. 检查应用的存储权限设置');
  print('    3. 将APK文件移到Download根目录再试');
  print('');
  print('  ✓ 开发者调试:');
  print('    1. 连接设备运行: adb logcat | grep "ApkParser\\|ApkManager"');
  print('    2. 检查是否有解析错误日志');
  print('    3. 使用 adb shell ls -la 检查文件权限');
  print('    4. 检查 ApkCacheService 缓存数据');
  print('');
  
  print('=== 诊断完成 ===');
}
