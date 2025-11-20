import 'package:easyfile/data/models/file_category.dart';

/// 综合扫描结果，包含快速访问和分类文件信息
class ComprehensiveScanResult {
  // ===== 快速访问相关 =====
  /// 发现的快速访问文件夹总数
  final int quickAccessFoldersFound;

  /// 系统文件夹数量
  final int systemFoldersCount;

  /// 应用根目录数量
  final int appRootFoldersCount;

  /// 应用子目录数量
  final int appSubFoldersCount;

  /// 用户自定义文件夹数量
  final int userCustomFoldersCount;

  /// 新增的文件夹数量
  final int newlyAdded;

  /// 已存在的文件夹数量
  final int alreadyExists;

  /// 恢复显示的文件夹数量
  final int unhidden;

  // ===== 分类文件相关 =====
  /// 按分类统计的文件数量
  final Map<FileCategory, int> categoryFileCounts;

  /// 扫描的文件总数
  final int totalFilesScanned;

  /// 扫描是否成功
  final bool success;

  /// 错误消息（如果有）
  final String? errorMessage;

  ComprehensiveScanResult({
    required this.quickAccessFoldersFound,
    required this.systemFoldersCount,
    required this.appRootFoldersCount,
    required this.appSubFoldersCount,
    required this.userCustomFoldersCount,
    required this.newlyAdded,
    required this.alreadyExists,
    required this.unhidden,
    required this.categoryFileCounts,
    required this.totalFilesScanned,
    this.success = true,
    this.errorMessage,
  });

  /// 创建一个空的扫描结果
  factory ComprehensiveScanResult.empty() {
    return ComprehensiveScanResult(
      quickAccessFoldersFound: 0,
      systemFoldersCount: 0,
      appRootFoldersCount: 0,
      appSubFoldersCount: 0,
      userCustomFoldersCount: 0,
      newlyAdded: 0,
      alreadyExists: 0,
      unhidden: 0,
      categoryFileCounts: {},
      totalFilesScanned: 0,
      success: false,
    );
  }

  /// 创建一个错误结果
  factory ComprehensiveScanResult.error(String message) {
    return ComprehensiveScanResult(
      quickAccessFoldersFound: 0,
      systemFoldersCount: 0,
      appRootFoldersCount: 0,
      appSubFoldersCount: 0,
      userCustomFoldersCount: 0,
      newlyAdded: 0,
      alreadyExists: 0,
      unhidden: 0,
      categoryFileCounts: {},
      totalFilesScanned: 0,
      success: false,
      errorMessage: message,
    );
  }

  /// 获取快速访问文件夹的总发现数（包含所有类型）
  int get totalQuickAccessFound =>
      systemFoldersCount +
      appRootFoldersCount +
      appSubFoldersCount +
      userCustomFoldersCount;

  /// 获取格式化的扫描摘要
  String getSummary() {
    final parts = <String>[];

    if (systemFoldersCount > 0) {
      parts.add('$systemFoldersCount 个系统目录');
    }
    if (appRootFoldersCount > 0) {
      parts.add('$appRootFoldersCount 个应用目录');
    }
    if (userCustomFoldersCount > 0) {
      parts.add('$userCustomFoldersCount 个用户目录');
    }

    if (parts.isEmpty) {
      return '发现 $quickAccessFoldersFound 个目录';
    }

    return '发现 ${parts.join('、')}';
  }

  /// 获取分类文件统计摘要
  String getFileCategorySummary() {
    if (totalFilesScanned == 0) {
      return '未扫描到文件';
    }

    final parts = <String>[];
    categoryFileCounts.forEach((category, count) {
      if (count > 0 && category != FileCategory.all) {
        parts.add('${category.displayName} $count');
      }
    });

    if (parts.isEmpty) {
      return '扫描了 $totalFilesScanned 个文件';
    }

    return parts.join('、');
  }

  @override
  String toString() {
    return 'ComprehensiveScanResult('
        'quickAccess: $quickAccessFoldersFound, '
        'files: $totalFilesScanned, '
        'categories: ${categoryFileCounts.length})';
  }
}
