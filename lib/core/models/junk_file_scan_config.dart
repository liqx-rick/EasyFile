/// 垃圾文件扫描配置
class JunkFileScanConfig {
  /// 扫描APK安装包
  final bool scanApk;

  /// 扫描临时文件
  final bool scanTempFiles;

  /// 扫描空文件夹
  final bool scanEmptyFolders;

  /// 仅扫描已安装的APK
  /// 
  /// 注意：当前版本由于技术限制（installed_apps包不支持从文件解析包名），
  /// 此选项暂时无法使用，默认为false（显示所有APK）
  final bool onlyInstalledApk;

  /// 临时文件最小天数（默认7天）
  final int minTempFileDays;

  /// 排除路径（小写）
  /// 
  /// 默认排除Android系统关键目录，防止误删系统文件
  final List<String> excludePaths;

  const JunkFileScanConfig({
    this.scanApk = true,
    this.scanTempFiles = true,
    this.scanEmptyFolders = true,
    this.onlyInstalledApk = false, // 默认显示所有APK（因为无法解析包名）
    this.minTempFileDays = 7,
    this.excludePaths = const [
      'Android/data',      // Android应用私有数据目录
      'Android/obb',       // Android应用扩展文件
      'Android/media',     // Android媒体文件目录
      '.thumbnails',       // 缩略图缓存
      'lost+found',        // Android系统恢复目录
    ],
  });

  /// 从JSON创建
  factory JunkFileScanConfig.fromJson(Map<String, dynamic> json) {
    return JunkFileScanConfig(
      scanApk: json['scanApk'] as bool? ?? true,
      scanTempFiles: json['scanTempFiles'] as bool? ?? true,
      scanEmptyFolders: json['scanEmptyFolders'] as bool? ?? true,
      onlyInstalledApk: json['onlyInstalledApk'] as bool? ?? false,
      minTempFileDays: json['minTempFileDays'] as int? ?? 7,
      excludePaths: (json['excludePaths'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'scanApk': scanApk,
      'scanTempFiles': scanTempFiles,
      'scanEmptyFolders': scanEmptyFolders,
      'onlyInstalledApk': onlyInstalledApk,
      'minTempFileDays': minTempFileDays,
      'excludePaths': excludePaths,
    };
  }

  /// 获取配置描述（用于缓存匹配）
  String get description {
    return 'APK:$scanApk(仅已装:$onlyInstalledApk)|临时:$scanTempFiles($minTempFileDays天+)|空文件夹:$scanEmptyFolders';
  }

  /// 复制并修改配置
  JunkFileScanConfig copyWith({
    bool? scanApk,
    bool? scanTempFiles,
    bool? scanEmptyFolders,
    bool? onlyInstalledApk,
    int? minTempFileDays,
    List<String>? excludePaths,
  }) {
    return JunkFileScanConfig(
      scanApk: scanApk ?? this.scanApk,
      scanTempFiles: scanTempFiles ?? this.scanTempFiles,
      scanEmptyFolders: scanEmptyFolders ?? this.scanEmptyFolders,
      onlyInstalledApk: onlyInstalledApk ?? this.onlyInstalledApk,
      minTempFileDays: minTempFileDays ?? this.minTempFileDays,
      excludePaths: excludePaths ?? this.excludePaths,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is JunkFileScanConfig && other.description == description;
  }

  @override
  int get hashCode => description.hashCode;

  @override
  String toString() => 'JunkFileScanConfig($description)';
}
