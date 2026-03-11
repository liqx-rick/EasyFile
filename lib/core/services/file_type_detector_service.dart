import 'dart:io';
import 'dart:typed_data';

import 'package:easyfile/core/logger.dart';

/// 文件类型识别结果
class FileTypeResult {
  final String fileName;
  final String filePath;
  final int fileSize;
  final String extension;
  final String detectedType;
  final String mimeType;
  final bool isExtensionMatch; // 扩展名是否与真实类型匹配

  const FileTypeResult({
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.extension,
    required this.detectedType,
    required this.mimeType,
    required this.isExtensionMatch,
  });

  /// 格式化文件大小
  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(2)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 文件类型识别服务
///
/// 通过读取文件头（Magic Number）识别文件的真实类型
/// 支持常见的图片、文档、压缩包、音视频格式
class FileTypeDetectorService {
  // 文件头签名映射表
  static final Map<String, _FileSignature> _signatures = {
    // 图片格式
    'JPEG': _FileSignature([0xFF, 0xD8, 0xFF], 'JPEG Image', 'image/jpeg'),
    'PNG': _FileSignature([0x89, 0x50, 0x4E, 0x47], 'PNG Image', 'image/png'),
    'GIF87': _FileSignature([0x47, 0x49, 0x46, 0x38, 0x37, 0x61], 'GIF Image', 'image/gif'),
    'GIF89': _FileSignature([0x47, 0x49, 0x46, 0x38, 0x39, 0x61], 'GIF Image', 'image/gif'),
    'BMP': _FileSignature([0x42, 0x4D], 'BMP Image', 'image/bmp'),
    'WEBP': _FileSignature([0x52, 0x49, 0x46, 0x46], 'WebP Image', 'image/webp',
        offset: 0, extraCheck: [0x57, 0x45, 0x42, 0x50], extraOffset: 8),

    // 文档格式
    'PDF': _FileSignature([0x25, 0x50, 0x44, 0x46], 'PDF Document', 'application/pdf'),

    // 压缩包格式（注意：DOCX/XLSX 也是 ZIP 格式，需要特殊处理）
    'ZIP_BASED': _FileSignature([0x50, 0x4B, 0x03, 0x04], 'ZIP-based Archive', 'application/zip'),
    'ZIP_EMPTY': _FileSignature([0x50, 0x4B, 0x05, 0x06], 'ZIP Archive (Empty)', 'application/zip'),
    'ZIP_SPANNED': _FileSignature([0x50, 0x4B, 0x07, 0x08], 'ZIP Archive (Spanned)', 'application/zip'),
    'RAR': _FileSignature([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07], 'RAR Archive', 'application/x-rar-compressed'),
    '7Z': _FileSignature([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C], '7-Zip Archive', 'application/x-7z-compressed'),
    'GZIP': _FileSignature([0x1F, 0x8B], 'GZIP Archive', 'application/gzip'),

    // 视频格式
    'MP4': _FileSignature([0x00, 0x00, 0x00], 'MP4 Video', 'video/mp4',
        offset: 0, extraCheck: [0x66, 0x74, 0x79, 0x70], extraOffset: 4),
    'AVI': _FileSignature([0x52, 0x49, 0x46, 0x46], 'AVI Video', 'video/x-msvideo',
        offset: 0, extraCheck: [0x41, 0x56, 0x49, 0x20], extraOffset: 8),
    'MKV': _FileSignature([0x1A, 0x45, 0xDF, 0xA3], 'MKV Video', 'video/x-matroska'),

    // 音频格式
    'MP3': _FileSignature([0xFF, 0xFB], 'MP3 Audio', 'audio/mpeg'),
    'MP3_ID3': _FileSignature([0x49, 0x44, 0x33], 'MP3 Audio (ID3)', 'audio/mpeg'),
    'WAV': _FileSignature([0x52, 0x49, 0x46, 0x46], 'WAV Audio', 'audio/wav',
        offset: 0, extraCheck: [0x57, 0x41, 0x56, 0x45], extraOffset: 8),
    'OGG': _FileSignature([0x4F, 0x67, 0x67, 0x53], 'OGG Audio', 'audio/ogg'),
    'FLAC': _FileSignature([0x66, 0x4C, 0x61, 0x43], 'FLAC Audio', 'audio/flac'),

    // 其他
    'EXE': _FileSignature([0x4D, 0x5A], 'Windows Executable', 'application/x-msdownload'),
    'ELF': _FileSignature([0x7F, 0x45, 0x4C, 0x46], 'Linux Executable', 'application/x-executable'),
  };

  /// 识别文件类型
  ///
  /// [filePath] 文件路径
  /// 返回 FileTypeResult 或在出错时抛出异常
  Future<FileTypeResult> detectFileType(String filePath) async {
    try {
      logger.d('开始识别文件类型: $filePath');

      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在: $filePath');
      }

      // 获取文件信息
      final fileName = file.path.split(Platform.pathSeparator).last;
      final fileSize = await file.length();
      final extension = _getExtension(fileName);

      // 读取文件头（前 32 字节足够识别大多数格式）
      final bytes = await _readFileHeader(file, 32);

      // 识别文件类型
      final signature = _detectSignature(bytes);

      String detectedType = 'Unknown';
      String mimeType = 'application/octet-stream';
      bool isExtensionMatch = false;

      if (signature != null) {
        // 特殊处理：ZIP 格式文件（DOCX、XLSX、APK 等都是 ZIP 格式）
        if (signature.description == 'ZIP-based Archive') {
          // 根据扩展名判断具体类型
          if (extension == 'docx') {
            detectedType = 'DOCX Document';
            mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
            isExtensionMatch = true;
          } else if (extension == 'xlsx') {
            detectedType = 'XLSX Spreadsheet';
            mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
            isExtensionMatch = true;
          } else if (extension == 'apk') {
            detectedType = 'Android APK';
            mimeType = 'application/vnd.android.package-archive';
            isExtensionMatch = true;
          } else if (extension == 'jar') {
            detectedType = 'Java JAR';
            mimeType = 'application/java-archive';
            isExtensionMatch = true;
          } else if (extension == 'zip') {
            detectedType = 'ZIP Archive';
            mimeType = 'application/zip';
            isExtensionMatch = true;
          } else {
            // 扩展名不匹配，但可能是其他 ZIP 格式
            detectedType = 'ZIP Archive';
            mimeType = 'application/zip';
            isExtensionMatch = false;
          }
        } else {
          detectedType = signature.description;
          mimeType = signature.mimeType;
          isExtensionMatch = _checkExtensionMatch(extension, signature.description);
        }
      } else {
        // 如果无法识别，尝试根据扩展名推断
        final extensionInfo = _guessTypeByExtension(extension);
        if (extensionInfo != null) {
          detectedType = extensionInfo['type']!;
          mimeType = extensionInfo['mime']!;
          isExtensionMatch = true;
        }
      }

      logger.d('文件类型识别完成: $detectedType (MIME: $mimeType)');

      return FileTypeResult(
        fileName: fileName,
        filePath: filePath,
        fileSize: fileSize,
        extension: extension,
        detectedType: detectedType,
        mimeType: mimeType,
        isExtensionMatch: isExtensionMatch,
      );
    } catch (e, stackTrace) {
      logger.e('识别文件类型失败: $e\nStackTrace: $stackTrace');
      rethrow;
    }
  }

  /// 读取文件头
  Future<Uint8List> _readFileHeader(File file, int length) async {
    final randomAccessFile = await file.open();
    try {
      final fileLength = await randomAccessFile.length();
      final readLength = fileLength < length ? fileLength : length;
      final bytes = await randomAccessFile.read(readLength);
      return Uint8List.fromList(bytes);
    } finally {
      await randomAccessFile.close();
    }
  }

  /// 检测文件签名
  _FileSignature? _detectSignature(Uint8List bytes) {
    for (final signature in _signatures.values) {
      if (_matchSignature(bytes, signature)) {
        return signature;
      }
    }
    return null;
  }

  /// 匹配文件签名
  bool _matchSignature(Uint8List bytes, _FileSignature signature) {
    // 检查主签名
    if (bytes.length < signature.offset + signature.bytes.length) {
      return false;
    }

    for (int i = 0; i < signature.bytes.length; i++) {
      if (bytes[signature.offset + i] != signature.bytes[i]) {
        return false;
      }
    }

    // 检查额外签名（如果存在）
    if (signature.extraCheck != null && signature.extraOffset != null) {
      if (bytes.length < signature.extraOffset! + signature.extraCheck!.length) {
        return false;
      }
      for (int i = 0; i < signature.extraCheck!.length; i++) {
        if (bytes[signature.extraOffset! + i] != signature.extraCheck![i]) {
          return false;
        }
      }
    }

    return true;
  }

  /// 获取文件扩展名
  String _getExtension(String fileName) {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  /// 检查扩展名是否与检测到的类型匹配
  bool _checkExtensionMatch(String extension, String detectedType) {
    final ext = extension.toLowerCase();
    final type = detectedType.toLowerCase();

    if (type.contains('jpeg') || type.contains('jpg')) {
      return ext == 'jpg' || ext == 'jpeg';
    }
    if (type.contains('png')) return ext == 'png';
    if (type.contains('gif')) return ext == 'gif';
    if (type.contains('bmp')) return ext == 'bmp';
    if (type.contains('webp')) return ext == 'webp';
    if (type.contains('pdf')) return ext == 'pdf';
    if (type.contains('rar')) return ext == 'rar';
    if (type.contains('7z') || type.contains('7-zip')) return ext == '7z';
    if (type.contains('gzip')) return ext == 'gz' || ext == 'gzip';
    if (type.contains('mp4')) return ext == 'mp4';
    if (type.contains('avi')) return ext == 'avi';
    if (type.contains('mkv')) return ext == 'mkv';
    if (type.contains('mp3')) return ext == 'mp3';
    if (type.contains('wav')) return ext == 'wav';
    if (type.contains('ogg')) return ext == 'ogg';
    if (type.contains('flac')) return ext == 'flac';
    if (type.contains('exe') || type.contains('executable')) return ext == 'exe';
    if (type.contains('elf')) return ext == 'elf' || ext == '';

    return false;
  }

  /// 根据扩展名推断文件类型
  Map<String, String>? _guessTypeByExtension(String extension) {
    final ext = extension.toLowerCase();
    final guessMap = {
      'txt': {'type': 'Text File', 'mime': 'text/plain'},
      'html': {'type': 'HTML Document', 'mime': 'text/html'},
      'css': {'type': 'CSS Stylesheet', 'mime': 'text/css'},
      'js': {'type': 'JavaScript File', 'mime': 'text/javascript'},
      'json': {'type': 'JSON File', 'mime': 'application/json'},
      'xml': {'type': 'XML File', 'mime': 'application/xml'},
      'docx': {
        'type': 'DOCX Document',
        'mime': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      },
      'xlsx': {'type': 'XLSX Spreadsheet', 'mime': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'},
      'zip': {'type': 'ZIP Archive', 'mime': 'application/zip'},
      'apk': {'type': 'Android APK', 'mime': 'application/vnd.android.package-archive'},
      'jar': {'type': 'Java JAR', 'mime': 'application/java-archive'},
    };
    return guessMap[ext];
  }
}

/// 文件签名定义（内部类）
class _FileSignature {
  final List<int> bytes;
  final String description;
  final String mimeType;
  final int offset;
  final List<int>? extraCheck; // 额外检查的字节（用于更精确的识别）
  final int? extraOffset; // 额外检查的偏移量

  const _FileSignature(
    this.bytes,
    this.description,
    this.mimeType, {
    this.offset = 0,
    this.extraCheck,
    this.extraOffset,
  });
}
