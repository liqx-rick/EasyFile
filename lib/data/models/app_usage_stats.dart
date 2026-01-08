/// 应用使用统计信息
class AppUsageStats {
  /// 包名
  final String packageName;

  /// 最后使用时间（来自UsageStats，受系统限制，通常只有10天内的数据）
  final DateTime? lastTimeUsed;

  /// 最后更新时间（来自PackageInfo，永久保存，无时间限制）
  final DateTime? lastUpdateTime;

  /// 总使用时长（毫秒）
  final int totalTimeInForeground;

  /// 最近7天的启动次数
  final int launchCount;

  AppUsageStats({
    required this.packageName,
    this.lastTimeUsed,
    this.lastUpdateTime,
    required this.totalTimeInForeground,
    required this.launchCount,
  });

  /// 从JSON创建
  factory AppUsageStats.fromJson(Map<String, dynamic> json) {
    final lastTimeUsedValue = json['lastTimeUsed'] as int?;
    final lastUpdateTimeValue = json['lastUpdateTime'] as int?;
    return AppUsageStats(
      packageName: json['packageName'] as String,
      lastTimeUsed: (lastTimeUsedValue != null && lastTimeUsedValue > 0)
          ? DateTime.fromMillisecondsSinceEpoch(lastTimeUsedValue)
          : null,
      lastUpdateTime: (lastUpdateTimeValue != null && lastUpdateTimeValue > 0)
          ? DateTime.fromMillisecondsSinceEpoch(lastUpdateTimeValue)
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
      'lastUpdateTime': lastUpdateTime?.millisecondsSinceEpoch,
      'totalTimeInForeground': totalTimeInForeground,
      'launchCount': launchCount,
    };
  }

  /// 获取有效的最后使用/更新时间
  /// 优先使用lastTimeUsed（真实使用时间），如果没有则使用lastUpdateTime（更新时间）
  DateTime? get effectiveLastTime {
    return lastTimeUsed ?? lastUpdateTime;
  }

  /// 是否为活跃应用（最近7天使用过）
  bool get isActive {
    final time = effectiveLastTime;
    if (time == null) return false;
    final now = DateTime.now();
    final diff = now.difference(time);
    return diff.inDays <= 7;
  }

  /// 获取距今天数
  int? get daysSinceLastTime {
    final time = effectiveLastTime;
    if (time == null) return null;
    final now = DateTime.now();
    return now.difference(time).inDays;
  }

  /// 获取使用频率分级
  /// - 常用: 最近7天使用过
  /// - 偶尔: 最近30天使用过
  /// - 很少: 最近180天使用过
  /// - 极少: 超过180天未使用
  UsageFrequency get frequency {
    final time = effectiveLastTime;
    if (time == null) return UsageFrequency.veryRare;

    final now = DateTime.now();
    final daysSinceUsed = now.difference(time).inDays;

    if (daysSinceUsed <= 7) return UsageFrequency.frequent;
    if (daysSinceUsed <= 30) return UsageFrequency.occasional;
    if (daysSinceUsed <= 180) return UsageFrequency.rare;
    return UsageFrequency.veryRare;
  }

  /// 获取友好的最后使用时间描述
  String get lastUsedDescription {
    return getLastUsedDescription();
  }

  /// 获取友好的最后使用时间描述
  /// [deviceBaselineTime] 设备基准时间（用户最早安装应用的时间）
  ///
  /// 逻辑：
  /// - 优先使用baseline：早于baseline且超过1年显示"N+年前"
  /// - 托底方案（baseline不存在或不生效）：过滤距今超过10年的异常时间
  /// - 其他：显示实际时间
  String getLastUsedDescription({DateTime? deviceBaselineTime}) {
    final time = effectiveLastTime;
    if (time == null) return ''; // 从未使用，返回空字符串

    final now = DateTime.now();
    final diff = now.difference(time);

    // 优先：如果提供了设备基准时间，并且baseline合理（早于当前时间）
    if (deviceBaselineTime != null && deviceBaselineTime.isBefore(now)) {
      // 应用时间早于基准时间，使用友好显示
      if (time.isBefore(deviceBaselineTime)) {
        final baselineDiff = now.difference(deviceBaselineTime);
        final years = (baselineDiff.inDays / 365).floor();

        // 只有超过1年才显示"N+年前"，否则回退到正常时间显示
        if (years > 0) {
          return '$years+年前';
        }
        // years == 0 时继续往下执行，使用正常时间显示逻辑
      }
      // 应用时间晚于或等于基准时间，显示实际时间（继续往下执行）
    } else {
      // 托底方案：没有baseline或baseline不合理时，过滤距今超过10年的异常时间
      // 这些时间通常是系统应用的默认时间戳，不可靠
      if (diff.inDays > 365 * 10) {
        return ''; // 返回空字符串
      }
    }

    // 正常时间显示逻辑
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
  rare('很少', '最近180天'),
  veryRare('极少', '6个月以上未使用');

  final String label;
  final String description;

  const UsageFrequency(this.label, this.description);
}
