import 'package:easyfile/data/models/file_item.dart';

abstract class FileRepository {
  Future<List<FileItem>> getFiles(String path);
  Future<List<FileItem>> searchFiles(String path, String query);
  Future<bool> deleteFile(FileItem file);
  Future<bool> copyFile(FileItem file, String destinationPath);
  Future<bool> moveFile(FileItem file, String destinationPath);
  Future<bool> renameFile(FileItem file, String newName);
}
