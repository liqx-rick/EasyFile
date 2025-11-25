import 'package:easyfile/data/models/file_item.dart';

abstract class FileRepository {
  Future<List<FileItem>> getFiles(String path);
  Future<List<FileItem>> searchFiles(String path, String query);
  Future<bool> deleteFile(FileItem file);
  Future<FileItem?> copyFile(FileItem file, String destinationPath);
  Future<FileItem?> moveFile(FileItem file, String destinationPath);
  Future<FileItem?> renameFile(FileItem file, String newName);
}
