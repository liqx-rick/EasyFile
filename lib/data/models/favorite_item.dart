/// 收藏夹项目模型
///
/// 表示用户收藏的快速访问目录
class FavoriteItem {
  /// 收藏夹唯一标识符
  final String id;

  /// 收藏夹显示名称
  final String name;

  /// 收藏夹路径
  final String path;

  /// 收藏夹图标（可选，默认为文件夹图标）
  final String? iconName;

  /// 创建时间
  final DateTime createdAt;

  /// 最后访问时间
  final DateTime? lastAccessedAt;

  /// 是否置顶（Pin）
  final bool pinned;

  const FavoriteItem({
    required this.id,
    required this.name,
    required this.path,
    this.iconName,
    required this.createdAt,
    this.lastAccessedAt,
    this.pinned = false,
  });

  /// 从 JSON 创建 FavoriteItem
  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteItem(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      iconName: json['iconName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastAccessedAt: json['lastAccessedAt'] != null
          ? DateTime.parse(json['lastAccessedAt'] as String)
          : null,
      pinned: (json['pinned'] as bool?) ?? false,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'iconName': iconName,
      'createdAt': createdAt.toIso8601String(),
      'lastAccessedAt': lastAccessedAt?.toIso8601String(),
      'pinned': pinned,
    };
  }

  /// 复制并修改某些属性
  FavoriteItem copyWith({
    String? name,
    String? path,
    String? iconName,
    DateTime? lastAccessedAt,
    bool? pinned,
  }) {
    return FavoriteItem(
      id: id,
      name: name ?? this.name,
      path: path ?? this.path,
      iconName: iconName ?? this.iconName,
      createdAt: createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      pinned: pinned ?? this.pinned,
    );
  }

  @override
  String toString() {
    return 'FavoriteItem(id: $id, name: $name, path: $path, iconName: $iconName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FavoriteItem &&
        other.id == id &&
        other.name == name &&
        other.path == path &&
        other.iconName == iconName &&
        other.pinned == pinned;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        path.hashCode ^
        (iconName?.hashCode ?? 0) ^
        pinned.hashCode;
  }
}
