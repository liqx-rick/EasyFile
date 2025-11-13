import 'package:easyfile/data/models/favorite_item.dart';
import 'package:easyfile/data/models/folder_stats.dart';

/// Sentinel value for copyWith to distinguish between null and undefined
const Object _undefined = Object();

/// 快速访问文件夹类型
enum QuickAccessFolderType {
  /// 系统预定义目录（Downloads, Documents等）
  system,
  
  /// 应用根目录（自动扫描）
  appRoot,
  
  /// 应用子目录（用户手动pin，归属到父应用）
  appSubfolder,
  
  /// 用户自建目录
  userCustom,
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

  /// 父应用名称（仅当type为appSubfolder时有值）
  final String? parentApp;

  /// 创建时间
  final DateTime createdAt;

  /// 最后访问时间
  final DateTime? lastAccessedAt;

  /// 访问次数
  final int accessCount;

  /// 是否固定在主页显示（已废弃，使用 homeDisplayOrder）
  @Deprecated('Use homeDisplayOrder instead')
  final bool pinned;

  /// 是否已加入快速访问（false=仅扫描出来但未加入）
  final bool isAddedToQuickAccess;

  /// 是否被用户忽略（不在列表中显示）
  final bool isHidden;

  /// 首页展示顺序（null=不在首页，0-5=在首页的位置）
  final int? homeDisplayOrder;

  /// 文件夹统计信息
  final FolderStats? stats;

  /// 图标名称（可选）
  final String? iconName;

  const QuickAccessFolder({
    required this.id,
    required this.path,
    required this.originalName,
    this.recommendedAlias,
    this.userAlias,
    required this.type,
    this.parentApp,
    required this.createdAt,
    this.lastAccessedAt,
    this.accessCount = 0,
    @Deprecated('Use homeDisplayOrder instead') this.pinned = false,
    this.isAddedToQuickAccess = true,
    this.isHidden = false,
    this.homeDisplayOrder,
    this.stats,
    this.iconName,
  });

  /// 显示名称（优先级：userAlias > recommendedAlias > originalName）
  String get displayName => userAlias ?? recommendedAlias ?? originalName;

  /// 获取分类显示文本
  String get categoryDisplay {
    switch (type) {
      case QuickAccessFolderType.system:
        return '系统目录';
      case QuickAccessFolderType.appRoot:
        return '应用目录';
      case QuickAccessFolderType.appSubfolder:
        return parentApp != null ? '应用目录 - $parentApp' : '应用目录';
      case QuickAccessFolderType.userCustom:
        return '我的文件夹';
    }
  }

  /// 是否是应用相关目录
  bool get isAppRelated =>
      type == QuickAccessFolderType.appRoot ||
      type == QuickAccessFolderType.appSubfolder;

  /// 是否在首页显示
  bool get isOnHomePage => homeDisplayOrder != null;

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
        orElse: () => QuickAccessFolderType.userCustom,
      ),
      parentApp: json['parentApp'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastAccessedAt: json['lastAccessedAt'] != null
          ? DateTime.parse(json['lastAccessedAt'] as String)
          : null,
      accessCount: (json['accessCount'] as int?) ?? 0,
      pinned: (json['pinned'] as bool?) ?? false, // 保留用于迁移
      isAddedToQuickAccess: (json['isAddedToQuickAccess'] as bool?) ?? 
          (json['pinned'] as bool?) ?? true, // 迁移：旧数据默认已加入
      isHidden: (json['isHidden'] as bool?) ?? false,
      homeDisplayOrder: json['homeDisplayOrder'] as int?,
      stats: json['stats'] != null
          ? FolderStats.fromJson(json['stats'] as Map<String, dynamic>)
          : null,
      iconName: json['iconName'] as String?,
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
      'parentApp': parentApp,
      'createdAt': createdAt.toIso8601String(),
      'lastAccessedAt': lastAccessedAt?.toIso8601String(),
      'accessCount': accessCount,
      'pinned': pinned, // 保留用于向后兼容
      'isAddedToQuickAccess': isAddedToQuickAccess,
      'isHidden': isHidden,
      'homeDisplayOrder': homeDisplayOrder,
      'stats': stats?.toJson(),
      'iconName': iconName,
    };
  }

  /// 从旧版 FavoriteItem 转换（用于数据迁移）
  factory QuickAccessFolder.fromFavoriteItem(FavoriteItem favorite) {
    return QuickAccessFolder(
      id: favorite.id,
      path: favorite.path,
      originalName: favorite.name,
      userAlias: favorite.name, // 保留用户原有的命名
      type: QuickAccessFolderType.system, // 旧数据默认为系统目录
      createdAt: favorite.createdAt,
      lastAccessedAt: favorite.lastAccessedAt,
      accessCount: 0,
      pinned: favorite.pinned, // 保留旧的 pinned 状态
      isAddedToQuickAccess: true, // 旧数据默认已加入快速访问
      isHidden: false,
      homeDisplayOrder: favorite.pinned ? 0 : null, // pinned=true 转为首页第一位
      iconName: favorite.iconName,
    );
  }

  /// 复制并修改某些属性
  QuickAccessFolder copyWith({
    String? id,
    String? path,
    String? originalName,
    String? recommendedAlias,
    String? userAlias,
    QuickAccessFolderType? type,
    String? parentApp,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
    int? accessCount,
    bool? pinned,
    bool? isAddedToQuickAccess,
    bool? isHidden,
    Object? homeDisplayOrder = _undefined,
    FolderStats? stats,
    String? iconName,
  }) {
    return QuickAccessFolder(
      id: id ?? this.id,
      path: path ?? this.path,
      originalName: originalName ?? this.originalName,
      recommendedAlias: recommendedAlias ?? this.recommendedAlias,
      userAlias: userAlias ?? this.userAlias,
      type: type ?? this.type,
      parentApp: parentApp ?? this.parentApp,
      createdAt: createdAt ?? this.createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      accessCount: accessCount ?? this.accessCount,
      pinned: pinned ?? this.pinned,
      isAddedToQuickAccess: isAddedToQuickAccess ?? this.isAddedToQuickAccess,
      isHidden: isHidden ?? this.isHidden,
      homeDisplayOrder: homeDisplayOrder == _undefined ? this.homeDisplayOrder : homeDisplayOrder as int?,
      stats: stats ?? this.stats,
      iconName: iconName ?? this.iconName,
    );
  }

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
