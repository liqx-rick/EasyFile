/// APK安装包信息模型
class ApkInfo {
  /// APK文件路径
  final String filePath;

  /// 应用名称
  final String appName;

  /// 包名
  final String packageName;

  /// 版本名称
  final String versionName;

  /// 版本号
  final int versionCode;

  /// 应用图标（Base64编码）
  final String? appIconBase64;

  /// 最小SDK版本
  final int minSdkVersion;

  /// 目标SDK版本
  final int targetSdkVersion;

  /// 是否为Debug包
  final bool isDebug;

  /// APK文件大小（字节）
  final int fileSize;

  /// APK文件修改时间
  final DateTime modifiedTime;

  /// 安装状态
  ApkInstallStatus status;

  ApkInfo({
    required this.filePath,
    required this.appName,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    this.appIconBase64,
    required this.minSdkVersion,
    required this.targetSdkVersion,
    required this.isDebug,
    required this.fileSize,
    required this.modifiedTime,
    this.status = ApkInstallStatus.unknown,
  });

  /// 从JSON创建
  factory ApkInfo.fromJson(Map<String, dynamic> json) {
    return ApkInfo(
      filePath: json['filePath'] as String,
      appName: json['appName'] as String,
      packageName: json['packageName'] as String,
      versionName: json['versionName'] as String,
      versionCode: json['versionCode'] as int,
      appIconBase64: json['appIconBase64'] as String?,
      minSdkVersion: json['minSdkVersion'] as int,
      targetSdkVersion: json['targetSdkVersion'] as int,
      isDebug: json['isDebug'] as bool,
      fileSize: json['fileSize'] as int,
      modifiedTime: DateTime.fromMillisecondsSinceEpoch(
        json['modifiedTime'] as int,
      ),
      status: ApkInstallStatus.values.firstWhere(
        (e) => e.name == (json['status'] as String? ?? 'unknown'),
        orElse: () => ApkInstallStatus.unknown,
      ),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'appName': appName,
      'packageName': packageName,
      'versionName': versionName,
      'versionCode': versionCode,
      'appIconBase64': appIconBase64,
      'minSdkVersion': minSdkVersion,
      'targetSdkVersion': targetSdkVersion,
      'isDebug': isDebug,
      'fileSize': fileSize,
      'modifiedTime': modifiedTime.millisecondsSinceEpoch,
      'status': status.name,
    };
  }

  /// 复制并修改状态
  ApkInfo copyWith({ApkInstallStatus? status}) {
    return ApkInfo(
      filePath: filePath,
      appName: appName,
      packageName: packageName,
      versionName: versionName,
      versionCode: versionCode,
      appIconBase64: appIconBase64,
      minSdkVersion: minSdkVersion,
      targetSdkVersion: targetSdkVersion,
      isDebug: isDebug,
      fileSize: fileSize,
      modifiedTime: modifiedTime,
      status: status ?? this.status,
    );
  }
}

/// APK安装状态
enum ApkInstallStatus {
  /// 未知（未检查）
  unknown,

  /// 未安装
  notInstalled,

  /// 已安装（相同版本）
  installed,

  /// 可升级（APK版本更高）
  upgradable,

  /// 已安装但签名不匹配
  signatureMismatch,

  /// 解析失败
  parseFailed;

  /// 显示名称
  String get displayName {
    switch (this) {
      case ApkInstallStatus.unknown:
        return '未知';
      case ApkInstallStatus.notInstalled:
        return '未安装';
      case ApkInstallStatus.installed:
        return '已安装';
      case ApkInstallStatus.upgradable:
        return '可升级';
      case ApkInstallStatus.signatureMismatch:
        return '签名不匹配';
      case ApkInstallStatus.parseFailed:
        return '解析失败';
    }
  }

  /// 状态颜色（用于UI显示）
  String get colorHex {
    switch (this) {
      case ApkInstallStatus.unknown:
        return '#9E9E9E'; // 灰色
      case ApkInstallStatus.notInstalled:
        return '#2196F3'; // 蓝色
      case ApkInstallStatus.installed:
        return '#4CAF50'; // 绿色
      case ApkInstallStatus.upgradable:
        return '#FF9800'; // 橙色
      case ApkInstallStatus.signatureMismatch:
        return '#F44336'; // 红色
      case ApkInstallStatus.parseFailed:
        return '#9E9E9E'; // 灰色
    }
  }
}
