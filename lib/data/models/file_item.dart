import 'dart:io';

class FileItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;

  FileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

  factory FileItem.fromEntity(FileSystemEntity entity) {
    final stat = entity.statSync();
    
    // 正确提取文件/文件夹名称
    String name = '';
    final pathSegments = entity.uri.pathSegments;
    
    if (pathSegments.isNotEmpty) {
      // 如果最后一个段是空的（比如目录路径以/结尾），则取倒数第二个
      name = pathSegments.last.isEmpty && pathSegments.length > 1
          ? pathSegments[pathSegments.length - 2]
          : pathSegments.last;
    }
    
    // 如果还是空的，从路径中提取
    if (name.isEmpty) {
      final pathParts = entity.path.split(Platform.pathSeparator);
      name = pathParts.lastWhere((part) => part.isNotEmpty, orElse: () => 'Unknown');
    }
    
    return FileItem(
      name: name,
      path: entity.path,
      isDirectory: entity is Directory,
      size: stat.size,
      modified: stat.modified,
    );
  }
}
