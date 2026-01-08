import 'package:easyfile/core/constants/system_folders_config.dart';

/// 文件来源检测器
///
/// 根据文件路径智能识别文件来源，返回友好的显示文本
///
/// 识别策略（5层优先级）：
/// 1. 系统预定义目录根路径 - 直接映射系统目录名
/// 2. 系统预定义目录的二级子目录 - 映射应用/功能名称
/// 3. 扩展系统目录 - 映射扩展目录名
/// 4. 其他常见来源 - 路径特征和文件名前缀匹配
/// 5. 兜底策略 - 显示父目录名或"未知"
class FileSourceDetector {
  /// 检测文件来源 - 返回来源的显示文本
  ///
  /// **参数**：
  /// - [filePath]: 文件的完整路径
  ///
  /// **返回**：文件来源的中文显示名称
  ///
  /// **示例**：
  /// ```dart
  /// detectSource('/storage/emulated/0/Download/test.jpg')
  /// // 返回: '下载'
  ///
  /// detectSource('/storage/emulated/0/Download/WeiXin/photo.jpg')
  /// // 返回: '微信'
  ///
  /// detectSource('/storage/emulated/0/Pictures/Screenshots/screen.png')
  /// // 返回: '截屏'
  /// ```
  static String detectSource(String filePath) {
    if (filePath.isEmpty) return SystemFoldersConfig.unknownSource;

    final lowerPath = filePath.toLowerCase();

    // ========== 层级1 & 2：系统预定义目录 ==========
    final systemRoot = SystemFoldersConfig.getSystemFolderRoot(filePath);
    if (systemRoot != null) {
      // 提取系统目录后的相对路径
      String pathAfterRoot = filePath.substring(systemRoot.length);

      // 移除开头的斜杠
      if (pathAfterRoot.startsWith('/')) {
        pathAfterRoot = pathAfterRoot.substring(1);
      }

      // 检查是否在根目录（文件直接在系统目录下，无二级目录）
      if (pathAfterRoot.isEmpty || !pathAfterRoot.contains('/')) {
        return SystemFoldersConfig.getSystemName(systemRoot);
      }

      // 提取二级目录名
      final secondLevelDir = pathAfterRoot.split('/')[0];
      if (secondLevelDir.isNotEmpty) {
        return SystemFoldersConfig.getSubdirectoryName(secondLevelDir);
      }
    }

    // ========== 层级3：扩展系统目录 ==========
    for (final extPath in SystemFoldersConfig.extendedSystemPaths) {
      if (lowerPath.startsWith(extPath.toLowerCase())) {
        return SystemFoldersConfig.getExtendedSystemName(extPath);
      }
    }

    // ========== 层级4：其他常见来源 ==========

    // 4.1 路径特征匹配（深层应用目录）
    if (lowerPath.contains('/bluetooth')) {
      return SystemFoldersConfig.subdirectoryNames['bluetooth']!;
    }
    if (lowerPath.contains('/tencent/micromsg')) {
      return SystemFoldersConfig.subdirectoryNames['wechat']!;
    }
    if (lowerPath.contains('/tencent/qq')) {
      return SystemFoldersConfig.subdirectoryNames['qq']!;
    }
    if (lowerPath.contains('/baidunetdisk')) {
      return SystemFoldersConfig.subdirectoryNames['baidunetdisk']!;
    }
    if (lowerPath.contains('/quark')) {
      return SystemFoldersConfig.subdirectoryNames['quark']!;
    }
    if (lowerPath.contains('/dingtalk')) {
      return SystemFoldersConfig.subdirectoryNames['dingtalk']!;
    }
    if (lowerPath.contains('/wxwork') || lowerPath.contains('/wework')) {
      return SystemFoldersConfig.subdirectoryNames['wework']!;
    }

    // 4.2 文件名前缀匹配（特殊命名规则）
    final fileName = filePath.split('/').last.toLowerCase();
    if (fileName.startsWith('wx_') || fileName.startsWith('mmexport')) {
      return SystemFoldersConfig.subdirectoryNames['wechat']!;
    }
    if (fileName.startsWith('qq_')) {
      return SystemFoldersConfig.subdirectoryNames['qq']!;
    }

    // ========== 层级5：兜底策略 - 父目录名 ==========
    return _getParentDirName(filePath);
  }

  /// 获取父目录名作为兜底显示
  ///
  /// 提取文件路径中倒数第二段作为父目录名
  /// 尝试映射到友好名称，未匹配则返回原始目录名
  static String _getParentDirName(String filePath) {
    final parts = filePath.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      // 返回倒数第二段（父目录名）
      final parentDir = parts[parts.length - 2];
      // 尝试映射到友好名称
      return SystemFoldersConfig.getSubdirectoryName(parentDir);
    }
    return SystemFoldersConfig.unknownSource;
  }

  /// 获取路径的显示名称（取最后一段有意义的部分）
  ///
  /// @deprecated 此方法已废弃，建议使用 detectSource() 方法
  static String getPathDisplayName(String path) {
    final segments = path.split('/');
    return segments.lastWhere((s) => s.isNotEmpty, orElse: () => path);
  }
}
