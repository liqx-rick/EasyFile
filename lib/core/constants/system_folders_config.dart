/// EasyFile 系统目录全局配置
///
/// 定义应用中统一使用的系统目录列表和相关工具方法
/// 这是快速访问管理的中心化配置，避免在多处重复定义系统目录
///
/// v2.0 简化方案：
/// - 预定义 7 个核心系统目录
/// - 扩展系统目录（用于安全检查）
/// - 统一管理显示名称（中文）
/// - 提供路径判断和转换工具方法
class SystemFoldersConfig {
  // ==================== 核心系统目录 ====================
  
  /// 预定义的系统目录列表（根路径）
  /// 
  /// 这些是 Android 系统或用户常用的标准目录，
  /// 修改此列表会影响整个应用的系统目录认知
  static const List<String> systemPaths = [
    '/storage/emulated/0/Download/',
    '/storage/emulated/0/Pictures/',
    '/storage/emulated/0/DCIM/',
    '/storage/emulated/0/Music/',
    '/storage/emulated/0/Movies/',
    '/storage/emulated/0/Documents/',
    '/storage/emulated/0/Sounds/',
  ];

  // ==================== 扩展系统目录 ====================
  
  /// 扩展系统目录列表（用于安全检查和路径过滤）
  /// 
  /// 这些目录虽然不在快速访问中展示，但在安全检查时需要警告用户
  /// 包括：备用下载目录、铃声目录、Android应用目录等
  static const List<String> extendedSystemPaths = [
    '/storage/emulated/0/Downloads/',     // 备用下载目录（部分设备使用）
    '/storage/emulated/0/Alarms/',        // 闹钟铃声
    '/storage/emulated/0/Notifications/', // 通知铃声
    '/storage/emulated/0/Ringtones/',     // 来电铃声
    '/storage/emulated/0/Podcasts/',      // 播客
    '/storage/emulated/0/Android/',       // Android 应用数据根目录
  ];

  /// 系统目录的显示名称（中文）
  /// 
  /// 用于 UI 展示，对应 systemPaths 中的路径
  static const Map<String, String> systemNames = {
    '/storage/emulated/0/Download/': '下载',
    '/storage/emulated/0/Pictures/': '图片',
    '/storage/emulated/0/DCIM/': '相机',
    '/storage/emulated/0/Music/': '音乐',
    '/storage/emulated/0/Movies/': '视频',
    '/storage/emulated/0/Documents/': '文档',
    '/storage/emulated/0/Sounds/': '声音',
  };

  // ==================== 工具方法 ====================
  
  /// 获取所有系统目录（核心 + 扩展）
  /// 
  /// 用于安全检查等需要完整系统目录列表的场景
  static List<String> getAllSystemPaths() {
    return [...systemPaths, ...extendedSystemPaths];
  }
  
  /// 获取所有系统目录名称（用于重命名检查）
  /// 
  /// 提取所有系统目录的文件夹名称，用于防止用户重命名系统目录
  /// 例如：['Download', 'Pictures', 'DCIM', ...]
  static List<String> getAllSystemFolderNames() {
    final allPaths = getAllSystemPaths();
    return allPaths.map((path) {
      // 移除前缀和尾部斜杠，提取目录名
      final withoutPrefix = path.replaceAll('/storage/emulated/0/', '');
      return withoutPrefix.replaceAll('/', '');
    }).toList();
  }

  /// 获取系统目录的显示名称
  /// 
  /// **参数**：
  /// - [path]: 目录路径
  /// 
  /// **返回**：该路径对应的中文名称，如果不在预定义列表中返回 '未知'
  /// 
  /// **示例**：
  /// ```dart
  /// var name = SystemFoldersConfig.getSystemName('/storage/emulated/0/Download/');
  /// // name = '下载'
  /// ```
  static String getSystemName(String path) {
    return systemNames[path] ?? '未知';
  }

  /// 检查路径是否为系统目录或其子目录
  /// 
  /// **参数**：
  /// - [path]: 要检查的目录路径
  /// 
  /// **返回**：如果是系统目录或系统目录的子目录，返回 true；否则返回 false
  /// 
  /// **说明**：
  /// - 完全匹配的根路径会返回 true
  /// - 位于系统目录下的任何子目录也会返回 true
  /// - 自动处理路径尾部斜杠差异，确保匹配准确性
  /// - 例如 `/storage/emulated/0/Download/WeChat/` 会返回 true
  /// 
  /// **示例**：
  /// ```dart
  /// SystemFoldersConfig.isSystemFolder('/storage/emulated/0/Download/')      // true
  /// SystemFoldersConfig.isSystemFolder('/storage/emulated/0/Download')       // true (无尾部斜杠也能匹配)
  /// SystemFoldersConfig.isSystemFolder('/storage/emulated/0/Download/WeChat/')  // true
  /// SystemFoldersConfig.isSystemFolder('/storage/emulated/0/MyCustom/')      // false
  /// ```
  static bool isSystemFolder(String path) {
    // 标准化路径：确保有尾部斜杠，以统一比较格式
    String normalizedPath = path.endsWith('/') ? path : '$path/';
    
    return systemPaths.any((sysPath) =>
        normalizedPath == sysPath || normalizedPath.startsWith(sysPath));
  }

  /// 获取路径的系统目录根路径
  /// 
  /// **参数**：
  /// - [path]: 要查询的目录路径
  /// 
  /// **返回**：如果该路径属于系统目录，返回对应的根路径；否则返回 null
  /// 
  /// **说明**：
  /// - 用于确定一个目录属于哪个系统目录
  /// - 例如 `/storage/emulated/0/Download/WeChat/` 会返回 `/storage/emulated/0/Download/`
  /// - 用于 UI 展开/折叠二级目录时的分组
  /// 
  /// **示例**：
  /// ```dart
  /// var root = SystemFoldersConfig.getSystemFolderRoot(
  ///   '/storage/emulated/0/Download/WeChat/'
  /// );
  /// // root = '/storage/emulated/0/Download/'
  /// 
  /// var none = SystemFoldersConfig.getSystemFolderRoot(
  ///   '/storage/emulated/0/MyCustom/'
  /// );
  /// // none = null
  /// ```
  static String? getSystemFolderRoot(String path) {
    try {
      return systemPaths.firstWhere(
        (sysPath) => path == sysPath || path.startsWith(sysPath),
      );
    } catch (e) {
      return null;
    }
  }
}
