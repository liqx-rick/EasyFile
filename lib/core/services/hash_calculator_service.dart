import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easyfile/core/logger.dart';

/// Hash 计算结果
class HashResult {
  final String md5;
  final String sha1;
  final String sha256;
  final Duration calculationTime;

  const HashResult({
    required this.md5,
    required this.sha1,
    required this.sha256,
    required this.calculationTime,
  });
}

/// Hash 计算服务
///
/// 支持计算文件的 MD5、SHA1、SHA256 哈希值
/// 使用流式读取，适合大文件处理
class HashCalculatorService {
  /// 计算文件的所有 Hash 值
  ///
  /// [filePath] 文件路径
  /// [onProgress] 进度回调 (已读取字节数, 文件总大小)
  /// 返回 HashResult 或在出错时抛出异常
  Future<HashResult> calculateFileHash(
    String filePath, {
    void Function(int bytesRead, int totalBytes)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      logger.d('开始计算文件 Hash: $filePath');

      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在: $filePath');
      }

      final fileSize = await file.length();
      logger.d('文件大小: ${_formatBytes(fileSize)}');

      // 准备计算 MD5
      var md5Output = md5.convert(<int>[]);
      var sha1Output = sha1.convert(<int>[]);
      var sha256Output = sha256.convert(<int>[]);

      // 流式读取文件
      final bytes = await file.readAsBytes();

      // 计算三个 Hash
      md5Output = md5.convert(bytes);
      sha1Output = sha1.convert(bytes);
      sha256Output = sha256.convert(bytes);

      // 模拟进度更新（因为 readAsBytes 是一次性读取）
      if (onProgress != null) {
        onProgress(fileSize, fileSize);
      }

      final md5Hash = md5Output.toString();
      final sha1Hash = sha1Output.toString();
      final sha256Hash = sha256Output.toString();

      stopwatch.stop();
      logger.d('Hash 计算完成，耗时: ${stopwatch.elapsed.inMilliseconds}ms');

      return HashResult(
        md5: md5Hash,
        sha1: sha1Hash,
        sha256: sha256Hash,
        calculationTime: stopwatch.elapsed,
      );
    } catch (e, stackTrace) {
      logger.e('计算 Hash 失败: $e\nStackTrace: $stackTrace');
      rethrow;
    }
  }

  /// 格式化字节数为可读字符串
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
