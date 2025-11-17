/// 收藏文件项数据模型
///
/// 用于存储用户收藏的文件信息
class FavoriteFileItem {
  /// 文件路径（唯一标识）
  final String filePath;

  /// 收藏时间
  final DateTime addedTime;

  /// 最后访问时间
  final DateTime? lastAccessTime;

  /// 访问次数
  final int accessCount;

  /// 用户备注（可选）
  final String? userNote;

  /// 标签列表（可选，未来扩展）
  final List<String>? tags;

  FavoriteFileItem({
    required this.filePath,
    required this.addedTime,
    this.lastAccessTime,
    this.accessCount = 0,
    this.userNote,
    this.tags,
  });

  /// 从 JSON 创建
  factory FavoriteFileItem.fromJson(Map<String, dynamic> json) {
    return FavoriteFileItem(
      filePath: json['filePath'] as String,
      addedTime: DateTime.parse(json['addedTime'] as String),
      lastAccessTime: json['lastAccessTime'] != null
          ? DateTime.parse(json['lastAccessTime'] as String)
          : null,
      accessCount: json['accessCount'] as int? ?? 0,
      userNote: json['userNote'] as String?,
      tags:
          json['tags'] != null ? List<String>.from(json['tags'] as List) : null,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'addedTime': addedTime.toIso8601String(),
      'lastAccessTime': lastAccessTime?.toIso8601String(),
      'accessCount': accessCount,
      'userNote': userNote,
      'tags': tags,
    };
  }

  /// 创建副本并更新部分字段
  FavoriteFileItem copyWith({
    String? filePath,
    DateTime? addedTime,
    DateTime? lastAccessTime,
    int? accessCount,
    String? userNote,
    List<String>? tags,
  }) {
    return FavoriteFileItem(
      filePath: filePath ?? this.filePath,
      addedTime: addedTime ?? this.addedTime,
      lastAccessTime: lastAccessTime ?? this.lastAccessTime,
      accessCount: accessCount ?? this.accessCount,
      userNote: userNote ?? this.userNote,
      tags: tags ?? this.tags,
    );
  }

  /// 更新访问信息
  FavoriteFileItem updateAccess() {
    return copyWith(
      lastAccessTime: DateTime.now(),
      accessCount: accessCount + 1,
    );
  }

  @override
  String toString() {
    return 'FavoriteFileItem(filePath: $filePath, addedTime: $addedTime, accessCount: $accessCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FavoriteFileItem && other.filePath == filePath;
  }

  @override
  int get hashCode => filePath.hashCode;
}
