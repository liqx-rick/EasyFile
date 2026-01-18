// ignore_for_file: non_constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'dart:convert';

/// Minizip-ng FFI 绑定类
class MinizipFFI {
  late final ffi.DynamicLibrary _lib;
  late final _MinizipBindings _bindings;

  MinizipFFI() {
    _lib = _loadLibrary();
    _bindings = _MinizipBindings(_lib);
  }

  ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libminizip_wrapper.so');
    }
    throw UnsupportedError('Platform not supported: ${Platform.operatingSystem}');
  }

  /// 列出ZIP压缩包内容
  MinizipListResultNative listContents(String archivePath) {
    final pathPtr = archivePath.toNativeUtf8();
    final resultPtr = calloc<_MinizipListResult>();

    try {
      final status = _bindings.minizip_list_contents(
        pathPtr.cast(),
        resultPtr,
      );

      final entries = <MinizipEntryNative>[];
      if (status == 0 && resultPtr.ref.entry_count > 0) {
        final entriesPtr = resultPtr.ref.entries;
        for (int i = 0; i < resultPtr.ref.entry_count; i++) {
          final entry = entriesPtr.elementAt(i).ref;
          final name = _readCString(entry.name, 1024);
          final pathname = _readCString(entry.pathname, 2048);
          final rawPathname = _readRawBytes(entry.raw_pathname, 2048);
          
          entries.add(MinizipEntryNative(
            name: name,
            pathname: pathname,
            rawPathname: rawPathname,
            size: entry.size,
            compressedSize: entry.compressed_size,
            mtime: entry.mtime,
            isDirectory: entry.is_directory,
            crc32: entry.crc32,
          ));
        }
      }

      final errorMessage = _readCString(resultPtr.ref.error_message, 512);

      _bindings.minizip_free_list_result(resultPtr);

      return MinizipListResultNative(
        status: status,
        entries: entries,
        errorMessage: errorMessage,
      );
    } finally {
      calloc.free(resultPtr);
      calloc.free(pathPtr);
    }
  }

  /// 检查是否为有效的ZIP文件
  bool isZipFile(String archivePath) {
    final pathPtr = archivePath.toNativeUtf8();
    try {
      return _bindings.minizip_is_zip_file(pathPtr.cast());
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// 解压整个ZIP压缩包
  MinizipExtractResultNative extractArchive(
    String archivePath,
    String targetDir, {
    String? password,
  }) {
    final pathPtr = archivePath.toNativeUtf8();
    final targetPtr = targetDir.toNativeUtf8();
    final passwordPtr = password != null ? password.toNativeUtf8() : ffi.nullptr;
    final resultPtr = calloc<_MinizipExtractResult>();

    try {
      final status = _bindings.minizip_extract_archive(
        pathPtr.cast(),
        targetPtr.cast(),
        passwordPtr.cast(),
        resultPtr,
      );

      final errorMsg = _readErrorMessage(resultPtr.ref.error_message);

      return MinizipExtractResultNative(
        status: status,
        totalFiles: resultPtr.ref.total_files,
        extractedFiles: resultPtr.ref.extracted_files,
        errorMessage: errorMsg,
      );
    } finally {
      _bindings.minizip_free_extract_result(resultPtr);
      calloc.free(resultPtr);
      calloc.free(pathPtr);
      calloc.free(targetPtr);
      if (password != null) {
        calloc.free(passwordPtr);
      }
    }
  }

  /// 解压单个文件（用于预览）
  /// entryPathRaw: 原始GBK字节数组
  MinizipExtractFileResultNative extractSingleFile(
    String archivePath,
    List<int> entryPathRaw,
    String outputPath, {
    String? password,
  }) {
    final archivePtr = archivePath.toNativeUtf8();
    
    // 将原始字节数组转为C字符串
    final entryPtr = calloc<ffi.Uint8>(entryPathRaw.length + 1);
    for (int i = 0; i < entryPathRaw.length; i++) {
      entryPtr[i] = entryPathRaw[i];
    }
    entryPtr[entryPathRaw.length] = 0; // null terminator
    
    final outputPtr = outputPath.toNativeUtf8();
    final passwordPtr = password != null ? password.toNativeUtf8() : ffi.nullptr;
    final resultPtr = calloc<_MinizipExtractFileResult>();

    try {
      final status = _bindings.minizip_extract_single_file(
        archivePtr.cast(),
        entryPtr.cast(),
        outputPtr.cast(),
        passwordPtr.cast(),
        resultPtr,
      );

      final errorMsg = _readErrorMessage(resultPtr.ref.error_message);
      final outPath = _readErrorMessage(resultPtr.ref.output_path);

      return MinizipExtractFileResultNative(
        status: status,
        fileSize: resultPtr.ref.file_size,
        outputPath: outPath,
        errorMessage: errorMsg,
      );
    } finally {
      _bindings.minizip_free_extract_file_result(resultPtr);
      calloc.free(resultPtr);
      calloc.free(archivePtr);
      calloc.free(entryPtr);
      calloc.free(outputPtr);
      if (password != null) {
        calloc.free(passwordPtr);
      }
    }
  }

  String _readErrorMessage(ffi.Array<ffi.Uint8> array) {
    final list = <int>[];
    for (int i = 0; i < 512; i++) {
      final byte = array[i];
      if (byte == 0) break;
      list.add(byte);
    }
    if (list.isEmpty) return '';
    try {
      return utf8.decode(list);
    } catch (e) {
      return String.fromCharCodes(list);
    }
  }

  String _readCString(ffi.Array<ffi.Uint8> array, int maxLen) {
    final list = <int>[];
    for (int i = 0; i < maxLen; i++) {
      final byte = array[i];
      if (byte == 0) break;
      list.add(byte);
    }
    
    if (list.isEmpty) return '';
    
    // 尝试多种解码方式
    // 1. 先尝试UTF-8解码
    try {
      final utf8Result = utf8.decode(list, allowMalformed: false);
      // 如果解码成功且不包含替换字符，则认为是UTF-8
      if (!utf8Result.contains('�')) {
        return utf8Result;
      }
    } catch (e) {
      // UTF-8解码失败，继续尝试GBK
    }
    
    // 2. 尝试GBK解码（中文Windows常用）
    try {
      try {
        return gbk_bytes.decode(list);
      } catch (e) {
        // 可能末尾被截断，尝试去掉最后1-2个字节
        if (list.length > 2) {
          try {
            return gbk_bytes.decode(list.sublist(0, list.length - 1));
          } catch (_) {
            return gbk_bytes.decode(list.sublist(0, list.length - 2));
          }
        } else {
          rethrow;
        }
      }
    } catch (e) {
      // GBK解码失败，使用Latin1作为后备
      return latin1.decode(list);
    }
  }

  /// 读取原始字节数组（不解码）
  List<int> _readRawBytes(ffi.Array<ffi.Uint8> array, int maxLen) {
    final list = <int>[];
    for (int i = 0; i < maxLen; i++) {
      final byte = array[i];
      if (byte == 0) break;
      list.add(byte);
    }
    return list;
  }
}

// ==================== Native 结构体定义 ====================

final class _MinizipEntry extends ffi.Struct {
  @ffi.Array(1024)
  external ffi.Array<ffi.Uint8> name;
  
  @ffi.Array(2048)
  external ffi.Array<ffi.Uint8> pathname;
  
  @ffi.Array(2048)
  external ffi.Array<ffi.Uint8> raw_pathname;
  
  @ffi.Int64()
  external int size;
  
  @ffi.Int64()
  external int compressed_size;
  
  @ffi.Int64()
  external int mtime;
  
  @ffi.Bool()
  external bool is_directory;
  
  @ffi.Uint32()
  external int crc32;
}

final class _MinizipListResult extends ffi.Struct {
  @ffi.Int32()
  external int status;
  
  @ffi.Int64()
  external int entry_count;
  
  external ffi.Pointer<_MinizipEntry> entries;
  
  @ffi.Array(512)
  external ffi.Array<ffi.Uint8> error_message;
}

final class _MinizipExtractResult extends ffi.Struct {
  @ffi.Int32()
  external int status;
  
  @ffi.Int64()
  external int total_files;
  
  @ffi.Int64()
  external int extracted_files;
  
  @ffi.Array(512)
  external ffi.Array<ffi.Uint8> error_message;
}

final class _MinizipExtractFileResult extends ffi.Struct {
  @ffi.Int32()
  external int status;
  
  @ffi.Int64()
  external int file_size;
  
  @ffi.Array(2048)
  external ffi.Array<ffi.Uint8> output_path;
  
  @ffi.Array(512)
  external ffi.Array<ffi.Uint8> error_message;
}

// ==================== Native 函数绑定 ====================

class _MinizipBindings {
  final ffi.DynamicLibrary _lib;
  
  _MinizipBindings(this._lib);

  late final minizip_list_contents = _lib.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<_MinizipListResult>,
      ),
      int Function(
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<_MinizipListResult>,
      )>('minizip_list_contents');

  late final minizip_free_list_result = _lib.lookupFunction<
      ffi.Void Function(ffi.Pointer<_MinizipListResult>),
      void Function(ffi.Pointer<_MinizipListResult>)
  >('minizip_free_list_result');

  late final minizip_is_zip_file = _lib.lookupFunction<
      ffi.Bool Function(ffi.Pointer<ffi.Char>),
      bool Function(ffi.Pointer<ffi.Char>)
  >('minizip_is_zip_file');

  late final minizip_extract_archive = _lib.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<_MinizipExtractResult>,
      ),
      int Function(
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<_MinizipExtractResult>,
      )>('minizip_extract_archive');

  late final minizip_extract_single_file = _lib.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<_MinizipExtractFileResult>,
      ),
      int Function(
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<_MinizipExtractFileResult>,
      )>('minizip_extract_single_file');

  late final minizip_free_extract_result = _lib.lookupFunction<
      ffi.Void Function(ffi.Pointer<_MinizipExtractResult>),
      void Function(ffi.Pointer<_MinizipExtractResult>)
  >('minizip_free_extract_result');

  late final minizip_free_extract_file_result = _lib.lookupFunction<
      ffi.Void Function(ffi.Pointer<_MinizipExtractFileResult>),
      void Function(ffi.Pointer<_MinizipExtractFileResult>)
  >('minizip_free_extract_file_result');
}

// ==================== Dart 数据类 ====================

/// ZIP条目信息
class MinizipEntryNative {
  final String name;
  final String pathname;
  final List<int> rawPathname; // 原始字节（GBK编码），用于提取
  final int size;
  final int compressedSize;
  final int mtime;
  final bool isDirectory;
  final int crc32;

  MinizipEntryNative({
    required this.name,
    required this.pathname,
    required this.rawPathname,
    required this.size,
    required this.compressedSize,
    required this.mtime,
    required this.isDirectory,
    required this.crc32,
  });

  @override
  String toString() {
    return 'MinizipEntry(name: $name, size: $size, dir: $isDirectory)';
  }
}

/// ZIP列表结果
class MinizipListResultNative {
  final int status;
  final List<MinizipEntryNative> entries;
  final String errorMessage;

  MinizipListResultNative({
    required this.status,
    required this.entries,
    required this.errorMessage,
  });

  bool get success => status == 0;

  @override
  String toString() {
    return 'MinizipListResult(status: $status, entries: ${entries.length}, error: "$errorMessage")';
  }
}

/// ZIP解压结果
class MinizipExtractResultNative {
  final int status;
  final int totalFiles;
  final int extractedFiles;
  final String errorMessage;

  MinizipExtractResultNative({
    required this.status,
    required this.totalFiles,
    required this.extractedFiles,
    required this.errorMessage,
  });

  bool get success => status == 0;

  @override
  String toString() {
    return 'MinizipExtractResult(status: $status, extracted: $extractedFiles/$totalFiles, error: "$errorMessage")';
  }
}

/// ZIP单文件解压结果
class MinizipExtractFileResultNative {
  final int status;
  final int fileSize;
  final String outputPath;
  final String errorMessage;

  MinizipExtractFileResultNative({
    required this.status,
    required this.fileSize,
    required this.outputPath,
    required this.errorMessage,
  });

  bool get success => status == 0;

  @override
  String toString() {
    return 'MinizipExtractFileResult(status: $status, size: $fileSize, path: $outputPath, error: "$errorMessage")';
  }
}
