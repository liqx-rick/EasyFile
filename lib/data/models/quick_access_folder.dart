import 'package:easyfile/core/constants/system_folders_config.dart';
import 'package:easyfile/data/models/folder_stats.dart';

/// 快速访问文件夹类型（v2.0 简化版）
enum QuickAccessFolderType {
  /// 系统预定义目录
  ///
  /// 包括：下载、图片、相机、音乐、视频、文档、声音等
  /// 这些目录由 [SystemFoldersConfig] 全局管理
  /// 支持二级目录展开
  system,

  /// 其他目录
  ///
  /// 包括：应用目录、用户自建目录等
  /// 这些目录只支持一级显示
  other,
}

/// 快速访问文件夹模型
///
/// 表示用户的快速访问目录，支持智能别名、分类管理等功能
class QuickAccessFolder {
  /// 唯一标识符
  final String id;

  /// 文件夹路径
  final String path;

  /// 原始文件夹名（不可更改）
  final String originalName;

  /// AI推荐的别名
  final String? recommendedAlias;

  /// 用户自定义别名（优先级最高）
  final String? userAlias;

  /// 文件夹类型
  final QuickAccessFolderType type;

  /// 创建时间
  final DateTime createdAt;

  /// 最后访问时间
  final DateTime? lastAccessedAt;

  /// 访问次数
  final int accessCount;

  /// 是否已加入快速访问（false=仅扫描出来但未加入）
  final bool isAddedToQuickAccess;

  /// 是否被用户忽略（不在列表中显示）
  final bool isHidden;

  /// 文件夹统计信息
  final FolderStats? stats;

  /// 图标名称（可选）
  final String? iconName;

  /// 父文件夹路径（用于子文件夹）
  ///
  /// 如果该文件夹是另一个文件夹的子文件夹，此字段存储父文件夹的路径。
  /// 仅当 [isSubfolder] 为 true 时此字段才有意义。
  final String? parentPath;

  const QuickAccessFolder({
    required this.id,
    required this.path,
    required this.originalName,
    this.recommendedAlias,
    this.userAlias,
    required this.type,
    required this.createdAt,
    this.lastAccessedAt,
    this.accessCount = 0,
    this.isAddedToQuickAccess = true,
    this.isHidden = false,
    this.stats,
    this.iconName,
    this.parentPath,
  });

  /// 显示名称（优先级：userAlias > recommendedAlias > originalName）
  String get displayName => userAlias ?? recommendedAlias ?? originalName;

  /// 是否是子文件夹
  ///
  /// 当此值为 true 时，表示该文件夹是另一个文件夹的子文件夹，
  /// 应该在 UI 中以缩进或嵌套方式展示在 [parentPath] 所指文件夹的下方。
  bool get isSubfolder => parentPath != null;

  /// 获取系统目录根路径（仅 system 类型有效）
  ///
  /// 如果该文件夹是系统目录或其子目录，返回对应的系统目录根路径
  /// 例如：`/storage/emulated/0/Download/WeChat/` 返回 `/storage/emulated/0/Download/`
  /// 其他类型返回 null
  String? get systemRoot {
    if (type != QuickAccessFolderType.system) return null;
    return SystemFoldersConfig.getSystemFolderRoot(path);
  }

  /// 获取相对于系统根的子路径（仅系统二级目录有效）
  ///
  /// 如果该目录是系统目录的子目录，返回相对于根目录的相对路径
  /// 例如：`/storage/emulated/0/Download/WeChat/` 返回 `WeChat/`
  /// 如果是根目录本身，返回 null
  String? get relativePathInSystem {
    if (type != QuickAccessFolderType.system) return null;
    final root = systemRoot;
    if (root == null) return null;

    if (path == root) return null; // 根目录本身
    return path.substring(root.length); // 子路径
  }

  /// 是否为系统目录的二级子目录
  ///
  /// 用于判断是否需要在 UI 中展开显示该目录
  bool get isSystemSubfolder {
    if (type != QuickAccessFolderType.system) return false;
    return systemRoot != null && path != systemRoot;
  }

  /// 获取分类显示文本
  String get categoryDisplay {
    switch (type) {
      case QuickAccessFolderType.system:
        return '系统目录';
      case QuickAccessFolderType.other:
        return '其他文件夹';
    }
  }

  /// 是否是系统目录
  bool get isSystem => type == QuickAccessFolderType.system;

  /// 从 JSON 创建
  factory QuickAccessFolder.fromJson(Map<String, dynamic> json) {
    return QuickAccessFolder(
      id: json['id'] as String,
      path: json['path'] as String,
      originalName: json['originalName'] as String,
      recommendedAlias: json['recommendedAlias'] as String?,
      userAlias: json['userAlias'] as String?,
      type: QuickAccessFolderType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => QuickAccessFolderType.other,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastAccessedAt: json['lastAccessedAt'] != null
          ? DateTime.parse(json['lastAccessedAt'] as String)
          : null,
      accessCount: (json['accessCount'] as int?) ?? 0,
      isAddedToQuickAccess: (json['isAddedToQuickAccess'] as bool?) ?? true,
      isHidden: (json['isHidden'] as bool?) ?? false,
      stats: json['stats'] != null
          ? FolderStats.fromJson(json['stats'] as Map<String, dynamic>)
          : null,
      iconName: json['iconName'] as String?,
      parentPath: json['parentPath'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'originalName': originalName,
      'recommendedAlias': recommendedAlias,
      'userAlias': userAlias,
      'type': type.toString(),
      'createdAt': createdAt.toIso8601String(),
      'lastAccessedAt': lastAccessedAt?.toIso8601String(),
      'accessCount': accessCount,
      'isAddedToQuickAccess': isAddedToQuickAccess,
      'isHidden': isHidden,
      'stats': stats?.toJson(),
      'iconName': iconName,
      'parentPath': parentPath,
    };
  }

  /// 复制并修改某些属性
  QuickAccessFolder copyWith({
    String? id,
    String? path,
    String? originalName,
    String? recommendedAlias,
    // 对于userAlias，允许显式设置为null来清空别名
    // 使用required参数或者在调用时明确指定
    String? userAlias = _undefined,
    QuickAccessFolderType? type,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
    int? accessCount,
    bool? isAddedToQuickAccess,
    bool? isHidden,
    FolderStats? stats,
    String? iconName,
    String? parentPath,
  }) {
    return QuickAccessFolder(
      id: id ?? this.id,
      path: path ?? this.path,
      originalName: originalName ?? this.originalName,
      recommendedAlias: recommendedAlias ?? this.recommendedAlias,
      // 如果userAlias被显式传入（包括null），使用新值；否则保持原值
      userAlias: userAlias == _undefined ? this.userAlias : userAlias,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      accessCount: accessCount ?? this.accessCount,
      isAddedToQuickAccess: isAddedToQuickAccess ?? this.isAddedToQuickAccess,
      isHidden: isHidden ?? this.isHidden,
      stats: stats ?? this.stats,
      iconName: iconName ?? this.iconName,
      parentPath: parentPath ?? this.parentPath,
    );
  }

  // Sentinel 值，用于区分"未指定"和"设为null"
  static const String _undefined = '__undefined__';

  @override
  String toString() {
    return 'QuickAccessFolder(id: $id, displayName: $displayName, path: $path, type: $type)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QuickAccessFolder &&
        other.id == id &&
        other.path == path &&
        other.type == type;
  }

  @override
  int get hashCode => id.hashCode ^ path.hashCode ^ type.hashCode;
}
