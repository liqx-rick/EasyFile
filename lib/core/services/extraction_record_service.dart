import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:easyfile/core/database/extraction_record_database.dart';
import 'package:easyfile/data/models/extraction_record.dart';
import 'package:easyfile/core/logger.dart';

/// 解压记录服务
///
/// 提供解压记录的增删查功能
class ExtractionRecordService {
  final ExtractionRecordDatabase _db = ExtractionRecordDatabase();
  final Uuid _uuid = const Uuid();

  /// 添加解压记录
  Future<void> addRecord({
    required String archivePath,
    required String targetPath,
    required int fileCount,
  }) async {
    try {
      final archiveFile = File(archivePath);
      final archiveName = archiveFile.uri.pathSegments.last;
      final archiveSize = await archiveFile.length();
      final folderName = targetPath.split(Platform.pathSeparator).last;

      // 计算MD5（可选，用于识别相同压缩包）
      String? archiveMD5;
      try {
        // 只对小于100MB的文件计算MD5，避免性能问题
        if (archiveSize < 100 * 1024 * 1024) {
          final bytes = await archiveFile.readAsBytes();
          archiveMD5 = md5.convert(bytes).toString();
        }
      } catch (e) {
        logger.w('Failed to calculate MD5 for $archivePath: $e');
      }

      final record = ExtractionRecord(
        id: _uuid.v4(),
        archivePath: archivePath,
        archiveName: archiveName,
        archiveMD5: archiveMD5,
        archiveSize: archiveSize,
        targetPath: targetPath,
        folderName: folderName,
        fileCount: fileCount,
        extractedAt: DateTime.now(),
      );

      await _db.insert(record);
      logger.i('Added extraction record: $archiveName -> $folderName');
    } catch (e) {
      logger.e('Failed to add extraction record: $e');
    }
  }

  /// 删除记录
  Future<void> deleteRecord(String id) async {
    try {
      await _db.delete(id);
    } catch (e) {
      logger.e('Failed to delete extraction record: $e');
    }
  }

  /// 清空所有记录
  Future<void> deleteAllRecords() async {
    try {
      await _db.deleteAll();
      logger.i('Cleared all extraction records');
    } catch (e) {
      logger.e('Failed to delete all extraction records: $e');
    }
  }

  /// 获取所有记录
  Future<List<ExtractionRecord>> getAllRecords() async {
    try {
      return await _db.getAll();
    } catch (e) {
      logger.e('Failed to get all extraction records: $e');
      return [];
    }
  }

  /// 根据压缩包路径查询记录
  Future<List<ExtractionRecord>> getRecordsByPath(String archivePath) async {
    try {
      return await _db.getByArchivePath(archivePath);
    } catch (e) {
      logger.e('Failed to get extraction records by path: $e');
      return [];
    }
  }

  /// 检查压缩包是否已解压过
  Future<bool> hasExtracted(String archivePath) async {
    try {
      final records = await _db.getByArchivePath(archivePath);
      return records.isNotEmpty;
    } catch (e) {
      logger.e('Failed to check extraction status: $e');
      return false;
    }
  }

  /// 批量查询压缩包是否已解压（用于列表显示角标）
  Future<Map<String, bool>> batchCheckExtracted(List<String> paths) async {
    try {
      final grouped = await _db.getBatchByPaths(paths);
      return Map.fromEntries(
        paths.map((path) => MapEntry(path, grouped.containsKey(path))),
      );
    } catch (e) {
      logger.e('Failed to batch check extraction status: $e');
      return {};
    }
  }

  /// 获取记录总数
  Future<int> getRecordCount() async {
    try {
      return await _db.getCount();
    } catch (e) {
      logger.e('Failed to get extraction record count: $e');
      return 0;
    }
  }

  /// 检查目标文件夹是否存在
  Future<bool> checkFolderExists(String targetPath) async {
    try {
      final dir = Directory(targetPath);
      return await dir.exists();
    } catch (e) {
      logger.w('Failed to check folder existence: $e');
      return false;
    }
  }

  /// 批量检查文件夹是否存在
  Future<Map<String, bool>> batchCheckFoldersExist(
    List<String> targetPaths,
  ) async {
    final results = <String, bool>{};
    for (final targetPath in targetPaths) {
      results[targetPath] = await checkFolderExists(targetPath);
    }
    return results;
  }
}
