import 'package:easyfile/core/models/large_file_scan_config.dart';

/// 重复文件扫描配置
class DuplicateFileScanConfig {
  /// 最小文件大小（KB），可配置，默认10KB
  final int minSizeInKB;

  /// 扫描模式
  final DuplicateScanMode scanMode;

  /// 文件类型（仅在分类检测模式下有效）
  final FileTypeFilter? selectedType;

  const DuplicateFileScanConfig({
    this.minSizeInKB = 10, // ✅ 默认最小扫描文件大小
    required this.scanMode,
    this.selectedType,
  }) : assert(
          scanMode == DuplicateScanMode.full || selectedType != null,
          'selectedType must be provided for category scan mode',
        );

  /// 完整检测配置
  const DuplicateFileScanConfig.fullScan({this.minSizeInKB = 10})
      : scanMode = DuplicateScanMode.full,
        selectedType = null;

  /// 分类检测配置
  const DuplicateFileScanConfig.categoryScan({
    required FileTypeFilter type,
    this.minSizeInKB = 10,
  })  : scanMode = DuplicateScanMode.category,
        selectedType = type;

  /// 获取要扫描的文件类型集合
  Set<FileTypeFilter> get fileTypes {
    if (scanMode == DuplicateScanMode.full) {
      // 完整检测：所有类型（包括 other）
      return {
        FileTypeFilter.video,
        FileTypeFilter.audio,
        FileTypeFilter.image,
        FileTypeFilter.document,
        FileTypeFilter.archive,
        FileTypeFilter.other, // ✅ 包含其他类型（CAD、设计文件、无扩展名等）
      };
    } else {
      // 分类检测：单一类型
      return {selectedType!};
    }
  }

  /// 描述文本（用于UI显示）
  String get description {
    if (scanMode == DuplicateScanMode.full) {
      return '> ${minSizeInKB}KB · 所有类型';
    } else {
      return '> ${minSizeInKB}KB · ${selectedType!.label}';
    }
  }

  /// 判断两个配置是否相同
  bool isEquivalent(DuplicateFileScanConfig other) {
    return minSizeInKB == other.minSizeInKB &&
        scanMode == other.scanMode &&
        selectedType == other.selectedType;
  }

  /// 转换为 Map（用于持久化）
  Map<String, dynamic> toJson() {
    return {
      'minSizeInKB': minSizeInKB,
      'scanMode': scanMode.name,
      'selectedType': selectedType?.name,
    };
  }

  /// 从 Map 创建
  factory DuplicateFileScanConfig.fromJson(Map<String, dynamic> json) {
    final scanModeStr = json['scanMode'] as String;
    final scanMode = DuplicateScanMode.values.firstWhere(
      (mode) => mode.name == scanModeStr,
    );

    FileTypeFilter? selectedType;
    if (json['selectedType'] != null) {
      final typeStr = json['selectedType'] as String;
      selectedType = FileTypeFilter.values.firstWhere(
        (type) => type.name == typeStr,
      );
    }

    return DuplicateFileScanConfig(
      minSizeInKB: json['minSizeInKB'] as int? ?? 100,
      scanMode: scanMode,
      selectedType: selectedType,
    );
  }

  @override
  String toString() {
    return 'DuplicateFileScanConfig(mode: ${scanMode.name}, '
        'type: ${selectedType?.name ?? "all"}, minSize: ${minSizeInKB}KB)';
  }
}

/// 扫描模式
enum DuplicateScanMode {
  full, // 完整检测
  category, // 分类检测
}
