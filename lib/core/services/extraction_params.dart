/// 解压参数类（用于在 Isolate 之间传递）
class ExtractionParams {
  final String archivePath;
  final String targetDir;
  final String folderName;
  final bool autoRename;
  final String? password;
  final bool isRar;
  final bool isZip;

  ExtractionParams({
    required this.archivePath,
    required this.targetDir,
    required this.folderName,
    required this.autoRename,
    this.password,
    required this.isRar,
    required this.isZip,
  });

  Map<String, dynamic> toJson() => {
        'archivePath': archivePath,
        'targetDir': targetDir,
        'folderName': folderName,
        'autoRename': autoRename,
        'password': password,
        'isRar': isRar,
        'isZip': isZip,
      };

  factory ExtractionParams.fromJson(Map<String, dynamic> json) =>
      ExtractionParams(
        archivePath: json['archivePath'] as String,
        targetDir: json['targetDir'] as String,
        folderName: json['folderName'] as String,
        autoRename: json['autoRename'] as bool,
        password: json['password'] as String?,
        isRar: json['isRar'] as bool,
        isZip: json['isZip'] as bool,
      );
}

/// 解压结果类（用于从 Isolate 返回）
class ExtractionResultData {
  final bool success;
  final String? errorMessage;
  final String targetPath;
  final int? totalFiles;
  final int? extractedFiles;
  final int? handleId; // 解压句柄ID（用于停止操作，-1表示不支持）

  ExtractionResultData({
    required this.success,
    this.errorMessage,
    required this.targetPath,
    this.totalFiles,
    this.extractedFiles,
    this.handleId,
  });

  Map<String, dynamic> toJson() => {
        'success': success,
        'errorMessage': errorMessage,
        'targetPath': targetPath,
        'totalFiles': totalFiles,
        'extractedFiles': extractedFiles,
        'handleId': handleId,
      };

  factory ExtractionResultData.fromJson(Map<String, dynamic> json) =>
      ExtractionResultData(
        success: json['success'] as bool,
        errorMessage: json['errorMessage'] as String?,
        targetPath: json['targetPath'] as String,
        totalFiles: json['totalFiles'] as int?,
        extractedFiles: json['extractedFiles'] as int?,
        handleId: json['handleId'] as int?,
      );
}
