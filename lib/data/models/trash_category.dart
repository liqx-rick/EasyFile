import 'package:easyfile/data/models/trash_bin.dart';

/// 回收站分类聚合
class TrashCategory {
  /// 分类名称
  final String name;

  /// 分类类型
  final TrashCategoryType type;

  /// 包含的回收站列表
  final List<TrashBin> bins;

  /// 文件总数
  final int totalFiles;

  /// 总大小
  final int totalSize;

  TrashCategory({
    required this.name,
    required this.type,
    required this.bins,
    required this.totalFiles,
    required this.totalSize,
  });

  /// 获取所有回收站ID
  List<String> get binIds => bins.map((b) => b.id).toList();

  /// 获取回收站名称列表（用于显示）
  String get binNames {
    if (bins.isEmpty) return '';
    if (bins.length == 1) return bins[0].name;
    if (bins.length <= 3) {
      return bins.map((b) => b.name.replaceAll('回收站', '')).join(' + ');
    }
    return '${bins.take(2).map((b) => b.name.replaceAll('回收站', '')).join(' + ')} 等${bins.length}个';
  }
}

/// 回收站分类类型
enum TrashCategoryType {
  /// 相册回收站
  gallery,

  /// 系统回收站
  system,

  /// 应用数据回收站
  app,
}
