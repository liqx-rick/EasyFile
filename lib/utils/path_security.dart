import 'dart:io';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/constants/system_folders_config.dart';

/// 路径风险等级
enum PathRiskLevel {
  /// 安全 - 普通用户文件
  safe,

  /// 注意 - 系统重要目录（如DCIM、Documents等）
  warning,

  /// 危险 - 应用数据目录
  danger,

  /// 禁止 - 系统核心目录，绝不允许操作
  forbidden,
}

/// 路径安全工具类
///
/// 用于检查文件路径的安全性，防止误操作系统关键文件和目录
class PathSecurity {
  PathSecurity._(); // 私有构造函数，防止实例化

  /// EasyFile回收站目录
  static const String appTrashDir = '/data/data/com.guangqi.easyfile/.trash';

  /// 绝对禁止操作的路径（系统核心目录）
  static const List<String> _forbiddenPaths = [
    '/system',
    '/data/system',
    '/.android_secure',
    '/storage/emulated/0/Android/data/com.android',
    '/storage/emulated/0/Android/obb/com.android',
  ];

  /// 危险路径（应用数据目录）
  static const List<String> _dangerPaths = [
    '/storage/emulated/0/Android/data',
    '/storage/emulated/0/Android/obb',
    '/storage/emulated/0/Android/media',
  ];

  // ==================== 系统目录配置（使用 SystemFoldersConfig）====================
  // 注意：系统重要目录列表已迁移到 SystemFoldersConfig.getAllSystemPaths()
  // 系统目录名称列表已迁移到 SystemFoldersConfig.getAllSystemFolderNames()
  // 这样可以避免在多处维护相同的目录列表，确保单一数据源
  
  /// 额外的系统关键目录名称（不在 SystemFoldersConfig 中的特殊目录）
  static const List<String> _additionalSystemFolderNames = [
    'data',  // Android应用数据目录
    'obb',   // Android扩展文件目录
    'media', // Android媒体目录
  ];

  /// 检查路径是否安全可操作
  ///
  /// 返回 true 表示可以安全操作，false 表示不允许操作
  static bool isSafePath(String path) {
    final riskLevel = getPathRiskLevel(path);
    return riskLevel == PathRiskLevel.safe ||
        riskLevel == PathRiskLevel.warning;
  }

  /// 检查路径是否为系统关键路径
  ///
  /// 返回 true 表示这是系统关键目录，操作需要特别谨慎
  static bool isSystemCriticalPath(String path) {
    final riskLevel = getPathRiskLevel(path);
    return riskLevel == PathRiskLevel.warning ||
        riskLevel == PathRiskLevel.danger ||
        riskLevel == PathRiskLevel.forbidden;
  }

  /// 检查文件夹名称是否为系统关键文件夹
  ///
  /// 用于重命名操作的检查
  static bool isSystemFolderName(String folderName) {
    // 使用 SystemFoldersConfig 获取所有系统目录名称
    final systemFolderNames = SystemFoldersConfig.getAllSystemFolderNames();
    return systemFolderNames.contains(folderName) || 
           _additionalSystemFolderNames.contains(folderName);
  }

  /// 获取路径的风险等级
  static PathRiskLevel getPathRiskLevel(String path) {
    final normalizedPath = _normalizePath(path);

    // 检查是否为禁止操作的路径
    for (final forbidden in _forbiddenPaths) {
      final normalizedForbidden = _normalizePath(forbidden);
      if (normalizedPath == normalizedForbidden ||
          normalizedPath.startsWith('$normalizedForbidden/')) {
        return PathRiskLevel.forbidden;
      }
    }

    // 检查是否为危险路径（精确匹配或子路径）
    for (final danger in _dangerPaths) {
      final normalizedDanger = _normalizePath(danger);
      if (normalizedPath == normalizedDanger ||
          normalizedPath.startsWith('$normalizedDanger/')) {
        return PathRiskLevel.danger;
      }
    }

    // 检查是否为警告路径（使用 SystemFoldersConfig）
    final allSystemPaths = SystemFoldersConfig.getAllSystemPaths();
    for (final warning in allSystemPaths) {
      final normalizedWarning = _normalizePath(warning);
      if (normalizedPath == normalizedWarning) {
        return PathRiskLevel.warning;
      }
    }

    return PathRiskLevel.safe;
  }

  /// 获取路径风险的描述信息
  static String getPathRiskDescription(
    String path, {
    required String operation,
  }) {
    final riskLevel = getPathRiskLevel(path);
    final pathName = path.split(Platform.pathSeparator).last;

    switch (riskLevel) {
      case PathRiskLevel.safe:
        return '确定要$operation "$pathName" 吗？';

      case PathRiskLevel.warning:
        return '⚠️ 警告\n\n'
            '"$pathName" 是系统重要目录！\n\n'
            '$operation此目录可能影响：\n'
            '• 系统功能正常使用\n'
            '• 其他应用访问文件\n'
            '• 媒体库的完整性\n\n'
            '确定要继续吗？';

      case PathRiskLevel.danger:
        return '🚨 高度危险\n\n'
            '"$pathName" 包含应用数据！\n\n'
            '$operation此目录将导致：\n'
            '• 应用无法正常运行\n'
            '• 应用数据永久丢失\n'
            '• 可能需要重新安装应用\n\n'
            '强烈建议不要执行此操作！\n\n'
            '如果确定要继续，请输入文件夹名称进行确认：';

      case PathRiskLevel.forbidden:
        return '🛑 禁止操作\n\n'
            '"$pathName" 是系统核心目录，禁止$operation！\n\n'
            '操作此目录可能导致：\n'
            '• 系统崩溃或无法启动\n'
            '• 设备变砖\n'
            '• 数据完全丢失\n\n'
            '为了您的设备安全，此操作已被阻止。';
    }
  }

  /// 获取操作被拒绝的提示信息
  static String getOperationDeniedMessage(String path, String operation) {
    final pathName = path.split(Platform.pathSeparator).last;
    return '操作已取消\n\n无法$operation "$pathName"，这是受保护的系统目录。';
  }

  /// 检查两个路径的操作是否安全（用于移动、复制等操作）
  static bool isSafeOperation(String sourcePath, String destinationPath) {
    return isSafePath(sourcePath) && isSafePath(destinationPath);
  }

  /// 记录安全操作日志
  static void logOperation({
    required String operation,
    required String path,
    required PathRiskLevel riskLevel,
    required bool allowed,
    String? reason,
  }) {
    final pathName = path.split(Platform.pathSeparator).last;
    final status = allowed ? '✓ ALLOWED' : '✗ BLOCKED';

    if (allowed) {
      logger.i('[$status] $operation: "$pathName" (Risk: ${riskLevel.name})');
    } else {
      logger.w(
        '[$status] $operation: "$pathName" (Risk: ${riskLevel.name})${reason != null ? ' - $reason' : ''}',
      );
    }

    // 对于被阻止的危险操作，记录完整路径用于审计
    if (!allowed &&
        (riskLevel == PathRiskLevel.danger ||
            riskLevel == PathRiskLevel.forbidden)) {
      logger.w('  Full path: $path');
    }
  }

  /// 标准化路径格式（用于比较）
  static String _normalizePath(String path) {
    // 移除末尾的斜杠
    String normalized = path.endsWith(Platform.pathSeparator)
        ? path.substring(0, path.length - 1)
        : path;

    // 统一使用正斜杠（跨平台兼容）
    normalized = normalized.replaceAll('\\', '/');

    return normalized;
  }

  /// 获取路径的显示名称（用于UI展示）
  static String getDisplayName(String path) {
    final parts = path.split(Platform.pathSeparator);
    return parts.isNotEmpty ? parts.last : path;
  }

  /// 检查是否为 Android 根存储目录
  static bool isStorageRoot(String path) {
    final normalized = _normalizePath(path);
    return normalized == '/storage/emulated/0' ||
        normalized == '/storage/emulated/0/';
  }

  // ==================== 路径过滤功能（Phase 1新增） ====================

  /// 检查路径是否为EasyFile回收站路径
  static bool isAppTrashPath(String path) {
    return path.startsWith(appTrashDir);
  }

  /// 检查路径是否为系统回收站路径
  static bool isSystemTrashPath(String path) {
    return path.contains('/.trashBin/') ||
        path.contains('/.recycle/') ||
        path.contains('/.Trash-') ||
        path.contains('/.trash/');
  }

  /// 检查路径是否应该被显示（全局过滤）
  ///
  /// 用于过滤不应该在文件列表、搜索结果中显示的路径
  /// 包括：
  /// 1. EasyFile回收站
  /// 2. 系统回收站
  /// 3. 禁止访问的系统路径
  ///
  /// 返回 true 表示应该显示，false 表示应该隐藏
  static bool shouldDisplayPath(String path) {
    // 1. 过滤EasyFile回收站
    if (isAppTrashPath(path)) {
      return false;
    }

    // 2. 过滤系统回收站
    if (isSystemTrashPath(path)) {
      return false;
    }

    // 3. 过滤禁止访问的路径
    final riskLevel = getPathRiskLevel(path);
    if (riskLevel == PathRiskLevel.forbidden) {
      return false;
    }

    return true;
  }

  /// 检查路径是否应该被扫描（用于文件扫描操作）
  ///
  /// 除了 shouldDisplayPath 的过滤条件外，还会过滤：
  /// 1. 隐藏目录（以.开头的目录）
  ///
  /// 返回 true 表示应该扫描，false 表示应该跳过
  static bool shouldScanPath(String path) {
    // 首先检查是否应该显示
    if (!shouldDisplayPath(path)) {
      return false;
    }

    // 检查是否为隐藏目录（以.开头）
    final pathParts = path.split(Platform.pathSeparator);
    for (final part in pathParts) {
      if (part.startsWith('.') && part.length > 1) {
        // 跳过隐藏目录，但不跳过 "." 和 ".."
        return false;
      }
    }

    return true;
  }
}
