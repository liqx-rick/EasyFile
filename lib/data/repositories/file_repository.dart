import 'package:easyfile/data/models/file_item.dart';

/// 文件操作的核心仓库接口
///
/// 定义了文件管理的基本操作，包括查询、搜索、删除、复制、移动和重命名。
/// 所有实现类必须遵循此接口契约。
///
/// 实现类：
/// - [LocalFileRepository]: 本地文件系统实现
///
/// 使用示例：
/// ```dart
/// final repository = locator<FileRepository>();
/// final files = await repository.getFiles('/storage/emulated/0');
/// ```
abstract class FileRepository {
  Future<List<FileItem>> getFiles(String path);
  Future<List<FileItem>> searchFiles(String path, String query);
  Future<bool> deleteFile(FileItem file);
  Future<FileItem?> copyFile(FileItem file, String destinationPath);
  Future<FileItem?> moveFile(FileItem file, String destinationPath);
  Future<FileItem?> renameFile(FileItem file, String newName);
}
