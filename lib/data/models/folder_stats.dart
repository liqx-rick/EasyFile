import 'package:easyfile/data/models/file_category.dart';

/// 文件夹统计信息
///
/// 包含文件数量、大小、类型分布等统计数据
class FolderStats {
  /// 总文件数
  final int totalFiles;

  /// 总文件夹数
  final int totalFolders;

  /// 各文件类型的数量分布
  final Map<FileCategory, int> fileTypeCounts;

  /// 总大小（MB）
  final double totalSizeMB;

  /// 最后修改时间
  final DateTime lastModified;

  const FolderStats({
    required this.totalFiles,
    required this.totalFolders,
    required this.fileTypeCounts,
    required this.totalSizeMB,
    required this.lastModified,
  });

  /// 获取特定类型的文件数量
  int getFileCount(FileCategory type) => fileTypeCounts[type] ?? 0;

  /// 图片文件数
  int get imageCount => getFileCount(FileCategory.image);

  /// 视频文件数
  int get videoCount => getFileCount(FileCategory.video);

  /// 音频文件数
  int get audioCount => getFileCount(FileCategory.audio);

  /// 文档文件数
  int get documentCount => getFileCount(FileCategory.document);

  /// 压缩包文件数
  int get archiveCount => getFileCount(FileCategory.archive);

  /// 其他文件数
  int get otherCount => getFileCount(FileCategory.other);

  /// 主要文件类型（数量最多的类型）
  FileCategory? get primaryFileType {
    if (fileTypeCounts.isEmpty) return null;

    var maxCount = 0;
    FileCategory? primaryType;

    fileTypeCounts.forEach((type, count) {
      if (count > maxCount) {
        maxCount = count;
        primaryType = type;
      }
    });

    return primaryType;
  }

  /// 主要文件类型的占比
  double get primaryTypePercentage {
    if (totalFiles == 0 || primaryFileType == null) return 0.0;
    final count = getFileCount(primaryFileType!);
    return (count / totalFiles) * 100;
  }

  /// 是否主要包含图片
  bool get isPrimarilyImages => imageCount > 0 && imageCount > totalFiles * 0.7;

  /// 是否主要包含视频
  bool get isPrimarilyVideos => videoCount > 0 && videoCount > totalFiles * 0.7;

  /// 是否主要包含音频
  bool get isPrimarilyAudio => audioCount > 0 && audioCount > totalFiles * 0.7;

  /// 是否主要包含文档
  bool get isPrimarilyDocuments =>
      documentCount > 0 && documentCount > totalFiles * 0.7;

  /// 从 JSON 创建
  factory FolderStats.fromJson(Map<String, dynamic> json) {
    final typeCountsJson =
        json['fileTypeCounts'] as Map<String, dynamic>? ?? {};
    final fileTypeCounts = <FileCategory, int>{};

    typeCountsJson.forEach((key, value) {
      try {
        final type = FileCategory.values.firstWhere(
          (e) => e.toString() == key,
          orElse: () => FileCategory.other,
        );
        fileTypeCounts[type] = value as int;
      } catch (e) {
        // 忽略无效的类型
      }
    });

    return FolderStats(
      totalFiles: (json['totalFiles'] as int?) ?? 0,
      totalFolders: (json['totalFolders'] as int?) ?? 0,
      fileTypeCounts: fileTypeCounts,
      totalSizeMB: (json['totalSizeMB'] as num?)?.toDouble() ?? 0.0,
      lastModified: json['lastModified'] != null
          ? DateTime.parse(json['lastModified'] as String)
          : DateTime.now(),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    final typeCountsJson = <String, int>{};
    fileTypeCounts.forEach((type, count) {
      typeCountsJson[type.toString()] = count;
    });

    return {
      'totalFiles': totalFiles,
      'totalFolders': totalFolders,
      'fileTypeCounts': typeCountsJson,
      'totalSizeMB': totalSizeMB,
      'lastModified': lastModified.toIso8601String(),
    };
  }

  /// 创建空统计
  factory FolderStats.empty() {
    return FolderStats(
      totalFiles: 0,
      totalFolders: 0,
      fileTypeCounts: {},
      totalSizeMB: 0.0,
      lastModified: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'FolderStats(files: $totalFiles, folders: $totalFolders, '
        'size: ${totalSizeMB.toStringAsFixed(1)}MB)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FolderStats &&
        other.totalFiles == totalFiles &&
        other.totalFolders == totalFolders &&
        other.totalSizeMB == totalSizeMB;
  }

  @override
  int get hashCode =>
      totalFiles.hashCode ^ totalFolders.hashCode ^ totalSizeMB.hashCode;
}
