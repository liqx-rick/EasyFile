import 'package:easyfile/data/models/new_files_settings.dart';

void main() async {
  // 加载当前设置
  final settings = await NewFilesSettings.load();
  
  print('当前设置:');
  print('  保留天数: ${settings.retentionDays}');
  print('  显示数量: ${settings.displayCount}');
  print('  隐藏相机照片: ${settings.hideCameraPhotos}');
  print('  隐藏截图: ${settings.hideScreenshots}');
  print('  自定义路径: ${settings.customScanPaths}');
}
