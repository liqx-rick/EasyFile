/// 压缩包条目信息
/// 
/// 用于表示压缩包内的文件或文件夹信息
class ArchiveEntryInfo {
  /// 条目名称（可能包含路径）
  final String name;

  /// 文件路径（相对于压缩包根目录）
  final String path;

  /// 原始路径字节（用于ZIP GBK编码文件提取）
  final List<int>? rawPathname;

  /// 文件大小（字节，未压缩大小）
  final int size;

  /// 压缩后大小（字节）
  final int compressedSize;

  /// 是否是目录
  final bool isDirectory;

  /// 修改时间
  final DateTime modificationDate;

  /// 压缩方法
  final int compressionMethod;

  /// CRC 校验值
  final int crc;

  const ArchiveEntryInfo({
    required this.name,
    required this.path,
    this.rawPathname,
    required this.size,
    required this.compressedSize,
    required this.isDirectory,
    required this.modificationDate,
    required this.compressionMethod,
    required this.crc,
  });

  /// 获取文件名（不含路径）
  String get fileName {
    final parts = path.split('/');
    return parts.last;
  }

  /// 获取父目录路径
  String? get parentPath {
    final parts = path.split('/');
    if (parts.length <= 1) return null;
    return parts.sublist(0, parts.length - 1).join('/');
  }

  /// 获取文件扩展名
  String get extension {
    if (isDirectory) return '';
    final name = fileName;
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1) return '';
    return name.substring(dotIndex + 1).toLowerCase();
  }

  /// 获取目录层级
  int get depth {
    return path.split('/').where((s) => s.isNotEmpty).length;
  }

  /// 获取压缩率（百分比）
  double get compressionRatio {
    if (size == 0) return 0;
    return ((size - compressedSize) / size * 100);
  }

  @override
  String toString() {
    return 'ArchiveEntryInfo(path: $path, size: $size, isDirectory: $isDirectory)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ArchiveEntryInfo && other.path == path;
  }

  @override
  int get hashCode => path.hashCode;
}

/// 解压结果
class ExtractResult {
  /// 是否成功
  final bool success;

  /// 解压到的目标路径
  final String targetPath;

  /// 总文件数
  final int totalFiles;

  /// 成功解压的文件数
  final int successFiles;

  /// 失败的文件列表
  final List<String> failedFiles;

  /// 错误消息（如果有）
  final String? errorMessage;

  const ExtractResult({
    required this.success,
    required this.targetPath,
    required this.totalFiles,
    required this.successFiles,
    this.failedFiles = const [],
    this.errorMessage,
  });

  /// 创建成功结果
  factory ExtractResult.success({
    required String targetPath,
    required int totalFiles,
    List<String> failedFiles = const [],
  }) {
    return ExtractResult(
      success: true,
      targetPath: targetPath,
      totalFiles: totalFiles,
      successFiles: totalFiles - failedFiles.length,
      failedFiles: failedFiles,
    );
  }

  /// 创建失败结果
  factory ExtractResult.failure({
    required String errorMessage,
    String? targetPath,
  }) {
    return ExtractResult(
      success: false,
      targetPath: targetPath ?? '',
      totalFiles: 0,
      successFiles: 0,
      errorMessage: errorMessage,
    );
  }

  /// 是否有部分文件失败
  bool get hasPartialFailure => failedFiles.isNotEmpty && successFiles > 0;

  @override
  String toString() {
    return 'ExtractResult(success: $success, successFiles: $successFiles/$totalFiles)';
  }
}
