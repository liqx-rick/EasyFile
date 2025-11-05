// EasyFile - 文件预览测试
// 这是一个Dart代码文件示例

import 'dart:io';

void main() {
  print('Hello, EasyFile!');
  
  // 测试文件操作
  final file = File('test.txt');
  
  if (file.existsSync()) {
    final content = file.readAsStringSync();
    print('文件内容: $content');
  } else {
    print('文件不存在');
  }
}

class FileManager {
  static const String appName = 'EasyFile';
  
  /// 获取文件信息
  static FileInfo getFileInfo(String path) {
    final file = File(path);
    final stat = file.statSync();
    
    return FileInfo(
      name: file.path.split('/').last,
      size: stat.size,
      modified: stat.modified,
    );
  }
}

class FileInfo {
  final String name;
  final int size;
  final DateTime modified;
  
  FileInfo({
    required this.name,
    required this.size,
    required this.modified,
  });
  
  @override
  String toString() {
    return 'FileInfo(name: $name, size: $size, modified: $modified)';
  }
}