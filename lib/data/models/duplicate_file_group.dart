import 'package:easyfile/core/services/duplicate_files_recommendation_engine.dart';
import 'package:easyfile/data/models/file_item.dart';

/// 重复文件组
///
/// 表示一组内容完全相同的文件。
///
/// 职责：
/// - 存储重复文件组的基本信息
/// - 通过推荐引擎计算文件排序
/// - 提供推荐保留/删除的文件列表
///
/// 注意：该类是纯数据模型，所有推荐算法逻辑已外包到 DuplicateFilesRecommendationEngine
class DuplicateFileGroup {
  /// 该组的唯一标识（使用完整哈希）
  final String groupId;

  /// 重复的文件列表（至少2个，已按推荐度排序）
  final List<FileItem> files;

  /// 该组文件的大小（字节）
  final int fileSize;

  /// 推荐算法引擎（用于构造时排序文件）
  // ignore: unused_field
  final DuplicateFilesRecommendationEngine _recommendationEngine;

  DuplicateFileGroup({
    required this.groupId,
    required List<FileItem> files,
    required this.fileSize,
    required DuplicateFilesRecommendationEngine recommendationEngine,
  })  : _recommendationEngine = recommendationEngine,
        files = recommendationEngine.sortFilesByRecommendation(files),
        assert(files.length >= 2, 'Duplicate group must have at least 2 files');

  /// 重复文件数量
  int get count => files.length;

  /// 可释放的空间（保留1个，删除其余）
  int get reclaimableSpace => fileSize * (count - 1);

  /// 建议保留的文件（使用智能评分算法）
  ///
  /// 由于构造函数已经对 files 列表排序（推荐保留的在第一位），
  /// 直接返回第一个文件即可
  FileItem get recommendedToKeep {
    return files.first;
  }

  /// 建议删除的文件列表
  List<FileItem> get recommendedToDelete {
    return files.skip(1).toList();
  }

  /// 转换为 Map（用于持久化）
  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'files': files
          .map((f) => {
                'name': f.name,
                'path': f.path,
                'size': f.size,
                'modified': f.modified.millisecondsSinceEpoch,
              })
          .toList(),
      'fileSize': fileSize,
    };
  }

  /// 从 Map 创建
  factory DuplicateFileGroup.fromJson(Map<String, dynamic> json) {
    final filesList = (json['files'] as List<dynamic>).map((fileJson) {
      return FileItem(
        name: fileJson['name'] as String,
        path: fileJson['path'] as String,
        isDirectory: false,
        size: fileJson['size'] as int,
        modified: DateTime.fromMillisecondsSinceEpoch(
          fileJson['modified'] as int,
        ),
      );
    }).toList();

    return DuplicateFileGroup(
      groupId: json['groupId'] as String,
      files: filesList,
      fileSize: json['fileSize'] as int,
      recommendationEngine: DuplicateFilesRecommendationEngine(),
    );
  }
}
