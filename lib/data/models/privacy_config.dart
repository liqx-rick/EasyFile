/// 隐私空间配置模型
class PrivacyConfig {
  /// 是否已初始化隐私空间
  final bool isInitialized;

  /// PIN的SHA-256哈希值（不存储明文）
  final String? pinHash;

  /// 是否启用生物识别
  final bool biometricEnabled;

  /// 最后访问时间
  final DateTime? lastAccessTime;

  const PrivacyConfig({
    this.isInitialized = false,
    this.pinHash,
    this.biometricEnabled = false,
    this.lastAccessTime,
  });

  /// 从 JSON 创建
  factory PrivacyConfig.fromJson(Map<String, dynamic> json) {
    return PrivacyConfig(
      isInitialized: json['isInitialized'] as bool? ?? false,
      pinHash: json['pinHash'] as String?,
      biometricEnabled: json['biometricEnabled'] as bool? ?? false,
      lastAccessTime: json['lastAccessTime'] != null ? DateTime.parse(json['lastAccessTime'] as String) : null,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'isInitialized': isInitialized,
      'pinHash': pinHash,
      'biometricEnabled': biometricEnabled,
      'lastAccessTime': lastAccessTime?.toIso8601String(),
    };
  }

  /// 复制并修改部分字段
  PrivacyConfig copyWith({
    bool? isInitialized,
    String? pinHash,
    bool? biometricEnabled,
    DateTime? lastAccessTime,
  }) {
    return PrivacyConfig(
      isInitialized: isInitialized ?? this.isInitialized,
      pinHash: pinHash ?? this.pinHash,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      lastAccessTime: lastAccessTime ?? this.lastAccessTime,
    );
  }
}
