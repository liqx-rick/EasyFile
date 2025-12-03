/// 应用使用统计信息
class AppUsageStats {
  /// 包名
  final String packageName;

  /// 最后使用时间
  final DateTime? lastTimeUsed;

  /// 总使用时长（毫秒）
  final int totalTimeInForeground;

  /// 最近7天的启动次数
  final int launchCount;

  AppUsageStats({
    required this.packageName,
    this.lastTimeUsed,
    required this.totalTimeInForeground,
    required this.launchCount,
  });

  /// 从JSON创建
  factory AppUsageStats.fromJson(Map<String, dynamic> json) {
    final lastTimeUsedValue = json['lastTimeUsed'] as int?;
    return AppUsageStats(
      packageName: json['packageName'] as String,
      lastTimeUsed: (lastTimeUsedValue != null && lastTimeUsedValue > 0)
          ? DateTime.fromMillisecondsSinceEpoch(lastTimeUsedValue)
          : null,
      totalTimeInForeground: json['totalTimeInForeground'] as int? ?? 0,
      launchCount: json['launchCount'] as int? ?? 0,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'lastTimeUsed': lastTimeUsed?.millisecondsSinceEpoch,
      'totalTimeInForeground': totalTimeInForeground,
      'launchCount': launchCount,
    };
  }

  /// 是否为活跃应用（最近7天使用过）
  bool get isActive {
    if (lastTimeUsed == null) return false;
    final now = DateTime.now();
    final diff = now.difference(lastTimeUsed!);
    return diff.inDays <= 7;
  }

  /// 是否为僵尸应用（超过180天未使用，即6个月）
  bool get isZombie {
    if (lastTimeUsed == null) return true;
    final now = DateTime.now();
    final diff = now.difference(lastTimeUsed!);
    return diff.inDays > 180;
  }

  /// 获取使用频率分级
  /// - 常用: 最近7天使用过
  /// - 偶尔: 最近30天使用过
  /// - 很少: 最近90天使用过
  /// - 僵尸: 超过180天未使用（6个月）
  UsageFrequency get frequency {
    if (lastTimeUsed == null) return UsageFrequency.zombie;
    
    final now = DateTime.now();
    final daysSinceUsed = now.difference(lastTimeUsed!).inDays;
    
    if (daysSinceUsed <= 7) return UsageFrequency.frequent;
    if (daysSinceUsed <= 30) return UsageFrequency.occasional;
    if (daysSinceUsed <= 180) return UsageFrequency.rare; // 改为180天
    return UsageFrequency.zombie;
  }

  /// 获取友好的最后使用时间描述
  String get lastUsedDescription {
    if (lastTimeUsed == null) return '从未使用';
    
    final now = DateTime.now();
    final diff = now.difference(lastTimeUsed!);
    
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}周前';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月前';
    return '${(diff.inDays / 365).floor()}年前';
  }

  @override
  String toString() {
    return 'AppUsageStats(package: $packageName, lastUsed: $lastUsedDescription, launches: $launchCount)';
  }
}

/// 使用频率分级
enum UsageFrequency {
  frequent('常用', '最近7天'),
  occasional('偶尔', '最近30天'),
  rare('很少', '最近180天'), // 改为180天，与僵尸判断一致
  zombie('僵尸', '6个月以上未使用');

  final String label;
  final String description;

  const UsageFrequency(this.label, this.description);
}
