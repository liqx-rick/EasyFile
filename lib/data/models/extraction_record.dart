/// 解压记录模型
class ExtractionRecord {
  final String id;
  final String archivePath;
  final String archiveName;
  final String? archiveMD5;
  final int archiveSize;
  final String targetPath;
  final String folderName;
  final int fileCount;
  final DateTime extractedAt;

  ExtractionRecord({
    required this.id,
    required this.archivePath,
    required this.archiveName,
    this.archiveMD5,
    required this.archiveSize,
    required this.targetPath,
    required this.folderName,
    required this.fileCount,
    required this.extractedAt,
  });

  /// 从数据库Map创建
  factory ExtractionRecord.fromMap(Map<String, dynamic> map) {
    return ExtractionRecord(
      id: map['id'] as String,
      archivePath: map['archive_path'] as String,
      archiveName: map['archive_name'] as String,
      archiveMD5: map['archive_md5'] as String?,
      archiveSize: map['archive_size'] as int,
      targetPath: map['target_path'] as String,
      folderName: map['folder_name'] as String,
      fileCount: map['file_count'] as int,
      extractedAt: DateTime.fromMillisecondsSinceEpoch(map['extracted_at'] as int),
    );
  }

  /// 转换为数据库Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'archive_path': archivePath,
      'archive_name': archiveName,
      'archive_md5': archiveMD5,
      'archive_size': archiveSize,
      'target_path': targetPath,
      'folder_name': folderName,
      'file_count': fileCount,
      'extracted_at': extractedAt.millisecondsSinceEpoch,
    };
  }

  /// 复制并修改
  ExtractionRecord copyWith({
    String? id,
    String? archivePath,
    String? archiveName,
    String? archiveMD5,
    int? archiveSize,
    String? targetPath,
    String? folderName,
    int? fileCount,
    DateTime? extractedAt,
  }) {
    return ExtractionRecord(
      id: id ?? this.id,
      archivePath: archivePath ?? this.archivePath,
      archiveName: archiveName ?? this.archiveName,
      archiveMD5: archiveMD5 ?? this.archiveMD5,
      archiveSize: archiveSize ?? this.archiveSize,
      targetPath: targetPath ?? this.targetPath,
      folderName: folderName ?? this.folderName,
      fileCount: fileCount ?? this.fileCount,
      extractedAt: extractedAt ?? this.extractedAt,
    );
  }
}
