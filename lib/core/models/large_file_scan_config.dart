/// 大文件扫描配置
class LargeFileScanConfig {
  /// 最小文件大小（MB）
  final int minSizeInMB;

  /// 文件类型过滤
  final Set<FileTypeFilter> fileTypes;

  /// 扫描范围
  final ScanScope scanScope;

  /// 最大结果数
  final int maxResults;

  const LargeFileScanConfig({
    this.minSizeInMB = 50,
    this.fileTypes = const {
      FileTypeFilter.video,
      FileTypeFilter.audio,
      FileTypeFilter.image,
      FileTypeFilter.document,
      FileTypeFilter.archive,
      FileTypeFilter.other,
    },
    this.scanScope = ScanScope.allStorage,
    this.maxResults = 100,
  });

  /// 复制并修改配置
  LargeFileScanConfig copyWith({
    int? minSizeInMB,
    Set<FileTypeFilter>? fileTypes,
    ScanScope? scanScope,
    int? maxResults,
  }) {
    return LargeFileScanConfig(
      minSizeInMB: minSizeInMB ?? this.minSizeInMB,
      fileTypes: fileTypes ?? this.fileTypes,
      scanScope: scanScope ?? this.scanScope,
      maxResults: maxResults ?? this.maxResults,
    );
  }

  /// 判断两个配置是否相同
  bool isEquivalent(LargeFileScanConfig other) {
    return minSizeInMB == other.minSizeInMB &&
        fileTypes.length == other.fileTypes.length &&
        fileTypes.every((type) => other.fileTypes.contains(type)) &&
        scanScope == other.scanScope &&
        maxResults == other.maxResults;
  }

  /// 转换为 Map（用于持久化）
  Map<String, dynamic> toJson() {
    return {
      'minSizeInMB': minSizeInMB,
      'fileTypes': fileTypes.map((e) => e.name).toList(),
      'scanScope': scanScope.name,
      'maxResults': maxResults,
    };
  }

  /// 从 Map 创建
  factory LargeFileScanConfig.fromJson(Map<String, dynamic> json) {
    return LargeFileScanConfig(
      minSizeInMB: json['minSizeInMB'] as int? ?? 50,
      fileTypes: (json['fileTypes'] as List<dynamic>?)
              ?.map((e) => FileTypeFilter.values
                  .firstWhere((type) => type.name == e))
              .toSet() ??
          const {
            FileTypeFilter.video,
            FileTypeFilter.audio,
            FileTypeFilter.image,
            FileTypeFilter.document,
            FileTypeFilter.archive,
            FileTypeFilter.other,
          },
      scanScope: ScanScope.values.firstWhere(
        (scope) => scope.name == json['scanScope'],
        orElse: () => ScanScope.allStorage,
      ),
      maxResults: json['maxResults'] as int? ?? 100,
    );
  }

  @override
  String toString() {
    return 'LargeFileScanConfig(minSize: ${minSizeInMB}MB, types: ${fileTypes.length}, scope: ${scanScope.name})';
  }
}

/// 文件类型过滤器
enum FileTypeFilter {
  video('视频'),
  audio('音频'),
  image('图片'),
  document('文档'),
  archive('压缩包'),
  other('其他');

  final String label;
  const FileTypeFilter(this.label);
}

/// 扫描范围
enum ScanScope {
  internalStorage('内部存储'),
  externalStorage('外部存储卡'),
  allStorage('所有存储');

  final String label;
  const ScanScope(this.label);
}
