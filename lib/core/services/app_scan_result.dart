import 'dart:typed_data';
import 'package:easyfile/data/models/file_item.dart';

/// 应用扫描结果
///
/// 封装应用检测和文件扫描的完整结果
class AppScanResult {
  /// 应用名称（中文）
  final String appName;

  /// 应用包名（如果已安装）
  final String? packageName;

  /// 是否已安装
  final bool isInstalled;

  /// 应用图标（可选）
  final Uint8List? appIcon;

  /// MediaStore 扫描的文件列表
  final List<FileItem> mediaStoreFiles;

  /// 路径扫描的文件列表
  final List<FileItem> pathScanFiles;

  /// 差异文件列表（路径扫描 - MediaStore）
  ///
  /// 这些文件只能通过路径扫描找到，MediaStore 未索引
  final List<FileItem> differenceFiles;

  /// 完整文件列表（去重后的所有文件）
  final List<FileItem> allFiles;

  /// MediaStore 扫描耗时
  final Duration mediaStoreDuration;

  /// 路径扫描耗时
  final Duration pathScanDuration;

  /// 总扫描耗时
  Duration get totalDuration => mediaStoreDuration + pathScanDuration;

  AppScanResult({
    required this.appName,
    this.packageName,
    required this.isInstalled,
    this.appIcon,
    this.mediaStoreFiles = const [],
    this.pathScanFiles = const [],
    this.differenceFiles = const [],
    this.allFiles = const [],
    this.mediaStoreDuration = Duration.zero,
    this.pathScanDuration = Duration.zero,
  });

  // ========================================
  // 统计信息
  // ========================================

  /// 总文件数
  int get totalCount => allFiles.length;

  /// MediaStore 文件数
  int get mediaStoreCount => mediaStoreFiles.length;

  /// 路径扫描文件数
  int get pathScanCount => pathScanFiles.length;

  /// 差异文件数
  int get differenceCount => differenceFiles.length;

  /// MediaStore 覆盖率（百分比）
  ///
  /// 计算 MediaStore 找到的文件占路径扫描文件的比例
  double get coverageRate {
    if (pathScanCount == 0) return 0.0;
    return (mediaStoreCount / pathScanCount) * 100;
  }

  /// 总文件大小（字节）
  int get totalSize {
    return allFiles.fold<int>(0, (sum, file) => sum + file.size);
  }

  /// 总文件大小（MB）
  double get totalSizeMB => totalSize / (1024 * 1024);

  /// MediaStore 扫描速度（文件/秒）
  double get mediaStoreScanSpeed {
    final seconds = mediaStoreDuration.inMilliseconds / 1000;
    if (seconds == 0) return 0.0;
    return mediaStoreCount / seconds;
  }

  /// 路径扫描速度（文件/秒）
  double get pathScanSpeed {
    final seconds = pathScanDuration.inMilliseconds / 1000;
    if (seconds == 0) return 0.0;
    return pathScanCount / seconds;
  }

  // ========================================
  // 工具方法
  // ========================================

  /// 创建未安装应用的结果
  factory AppScanResult.notInstalled(String appName) {
    return AppScanResult(
      appName: appName,
      isInstalled: false,
    );
  }

  /// 创建已取消扫描的结果
  factory AppScanResult.cancelled(String appName) {
    return AppScanResult(
      appName: appName,
      isInstalled: true,
      allFiles: const [],
      mediaStoreFiles: const [],
      pathScanFiles: const [],
    );
  }

  /// 复制并修改
  AppScanResult copyWith({
    String? appName,
    String? packageName,
    bool? isInstalled,
    Uint8List? appIcon,
    List<FileItem>? mediaStoreFiles,
    List<FileItem>? pathScanFiles,
    List<FileItem>? differenceFiles,
    List<FileItem>? allFiles,
    Duration? mediaStoreDuration,
    Duration? pathScanDuration,
  }) {
    return AppScanResult(
      appName: appName ?? this.appName,
      packageName: packageName ?? this.packageName,
      isInstalled: isInstalled ?? this.isInstalled,
      appIcon: appIcon ?? this.appIcon,
      mediaStoreFiles: mediaStoreFiles ?? this.mediaStoreFiles,
      pathScanFiles: pathScanFiles ?? this.pathScanFiles,
      differenceFiles: differenceFiles ?? this.differenceFiles,
      allFiles: allFiles ?? this.allFiles,
      mediaStoreDuration: mediaStoreDuration ?? this.mediaStoreDuration,
      pathScanDuration: pathScanDuration ?? this.pathScanDuration,
    );
  }

  /// 生成摘要信息
  String getSummary() {
    if (!isInstalled) {
      return '$appName: 未安装';
    }

    final lines = <String>[
      '应用: $appName ($packageName)',
      '总文件: $totalCount (${totalSizeMB.toStringAsFixed(2)} MB)',
      'MediaStore: $mediaStoreCount 文件 (${mediaStoreDuration.inMilliseconds}ms)',
      '路径扫描: $pathScanCount 文件 (${pathScanDuration.inMilliseconds}ms)',
      '差异文件: $differenceCount',
      '覆盖率: ${coverageRate.toStringAsFixed(1)}%',
    ];

    return lines.join('\n');
  }

  @override
  String toString() {
    return 'AppScanResult(appName: $appName, isInstalled: $isInstalled, '
        'totalFiles: $totalCount, mediaStore: $mediaStoreCount, '
        'pathScan: $pathScanCount, difference: $differenceCount)';
  }
}

/// 应用检测结果
///
/// 只包含应用安装检测信息，不包含文件扫描结果
class AppDetectionResult {
  /// 是否已安装
  final bool isInstalled;

  /// 应用包名（如果已安装）
  final String? packageName;

  /// 检测方式
  /// - 'configured_package': 通过配置的包名检测
  /// - 'label_matched': 通过应用名称匹配检测
  /// - 'none': 未检测到
  final String detectionMethod;

  /// 匹配到的应用名称（名称匹配时）
  final String? matchedLabel;

  AppDetectionResult({
    required this.isInstalled,
    this.packageName,
    this.detectionMethod = 'none',
    this.matchedLabel,
  });

  @override
  String toString() {
    if (!isInstalled) {
      return 'AppDetectionResult(isInstalled: false)';
    }
    return 'AppDetectionResult(isInstalled: true, packageName: $packageName, '
        'method: $detectionMethod)';
  }
}

/// 内部扫描结果（用于中间数据传递）
class ScanResult {
  final List<FileItem> files;
  final Duration duration;

  ScanResult({
    required this.files,
    required this.duration,
  });
}
