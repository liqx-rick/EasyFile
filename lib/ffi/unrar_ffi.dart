// ignore_for_file: non_constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:convert';
import 'package:ffi/ffi.dart';

/// UnRAR FFI 绑定 - PoC版本
/// 
/// 这是一个概念验证实现，用于测试UnRAR集成的可行性
class UnrarFFI {
  late final ffi.DynamicLibrary _lib;
  late final UnrarBindings _bindings;

  UnrarFFI() {
    _lib = _loadLibrary();
    _bindings = UnrarBindings(_lib);
  }

  /// 加载动态库
  ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      // 与libarchive在同一个so中
      return ffi.DynamicLibrary.open('libarchive_wrapper.so');
    } else if (Platform.isWindows) {
      // Windows测试
      return ffi.DynamicLibrary.open('archive_wrapper.dll');
    } else {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }
  }

  /// 检查文件是否为RAR格式
  bool isRarFile(String filePath) {
    final pathPtr = filePath.toNativeUtf8();
    try {
      return _bindings.unrar_is_rar_file(pathPtr.cast());
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// 获取UnRAR版本（验证库已加载）
  String getVersion() {
    final versionPtr = _bindings.unrar_get_version();
    return versionPtr.cast<Utf8>().toDartString();
  }

  /// 列出RAR内容
  UnrarListResultNative listContents(String rarPath) {
    final pathPtr = rarPath.toNativeUtf8();
    final resultPtr = calloc<UnrarListResult>();

    try {
      final status = _bindings.unrar_list_contents(
        pathPtr.cast(),
        resultPtr,
      );

      final entries = <UnrarEntryNative>[];
      if (resultPtr.ref.entry_count > 0 && resultPtr.ref.entries != ffi.nullptr) {
        final entriesPtr = resultPtr.ref.entries;
        for (int i = 0; i < resultPtr.ref.entry_count; i++) {
          final entry = entriesPtr.elementAt(i).ref;
          entries.add(UnrarEntryNative(
            filename: _readCString(entry.filename, 2048),
            size: entry.size,
            packedSize: entry.packed_size,
            isDirectory: entry.is_directory,
          ));
        }
      }

      return UnrarListResultNative(
        status: status,
        entries: entries,
        errorMessage: _readCString(resultPtr.ref.error_message, 512),
      );
    } finally {
      _bindings.unrar_free_list_result(resultPtr);
      calloc.free(resultPtr);
      calloc.free(pathPtr);
    }
  }
  
  /// 解压RAR文件到指定目录
  UnrarExtractResultNative extract(
    String rarPath,
    String destPath, {
    String? password,
  }) {
    final rarPathPtr = rarPath.toNativeUtf8();
    final destPathPtr = destPath.toNativeUtf8();
    final passwordPtr = password != null ? password.toNativeUtf8() : ffi.nullptr;
    final resultPtr = calloc<UnrarExtractResult>();

    try {
      final status = _bindings.unrar_extract(
        rarPathPtr.cast(),
        destPathPtr.cast(),
        passwordPtr.cast(),
        resultPtr,
        ffi.nullptr, // 暂不使用进度回调
      );

      return UnrarExtractResultNative(
        status: status,
        extractedCount: resultPtr.ref.extracted_count,
        skippedCount: resultPtr.ref.skipped_count,
        failedCount: resultPtr.ref.failed_count,
        errorMessage: _readCString(resultPtr.ref.error_message, 512),
      );
    } finally {
      calloc.free(resultPtr);
      if (passwordPtr != ffi.nullptr) calloc.free(passwordPtr);
      calloc.free(destPathPtr);
      calloc.free(rarPathPtr);
    }
  }
  
  /// 解压单个文件
  bool extractFile(
    String rarPath,
    String filename,
    String destPath, {
    String? password,
  }) {
    final rarPathPtr = rarPath.toNativeUtf8();
    final filenamePtr = filename.toNativeUtf8();
    final destPathPtr = destPath.toNativeUtf8();
    final passwordPtr = password != null ? password.toNativeUtf8() : ffi.nullptr;

    try {
      final result = _bindings.unrar_extract_file(
        rarPathPtr.cast(),
        filenamePtr.cast(),
        destPathPtr.cast(),
        passwordPtr.cast(),
      );
      return result == 0;
    } finally {
      if (passwordPtr != ffi.nullptr) calloc.free(passwordPtr);
      calloc.free(destPathPtr);
      calloc.free(filenamePtr);
      calloc.free(rarPathPtr);
    }
  }

  /// 读取C字符串 (UTF-8编码)
  String _readCString(ffi.Array<ffi.Uint8> array, int maxLength) {
    final bytes = <int>[];
    for (int i = 0; i < maxLength; i++) {
      final byte = array[i];
      if (byte == 0) break;
      bytes.add(byte);
    }
    // 使用UTF-8解码器正确处理中文字符
    return utf8.decode(bytes, allowMalformed: true);
  }
}

// ==================== Native 数据模型 ====================

class UnrarEntryNative {
  final String filename;
  final int size;
  final int packedSize;
  final bool isDirectory;

  UnrarEntryNative({
    required this.filename,
    required this.size,
    required this.packedSize,
    required this.isDirectory,
  });

  @override
  String toString() {
    final type = isDirectory ? '[DIR]' : '[FILE]';
    final sizeStr = isDirectory ? '' : ' (${_formatSize(size)})';
    return '$type $filename$sizeStr';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class UnrarListResultNative {
  final int status;
  final List<UnrarEntryNative> entries;
  final String errorMessage;

  UnrarListResultNative({
    required this.status,
    required this.entries,
    required this.errorMessage,
  });

  bool get success => status == 0;
}

class UnrarExtractResultNative {
  final int status;
  final int extractedCount;
  final int skippedCount;
  final int failedCount;
  final String errorMessage;

  UnrarExtractResultNative({
    required this.status,
    required this.extractedCount,
    required this.skippedCount,
    required this.failedCount,
    required this.errorMessage,
  });

  bool get success => status == 0;
  int get totalProcessed => extractedCount + skippedCount + failedCount;
}

// ==================== FFI 结构定义 ====================

final class UnrarEntry extends ffi.Struct {
  @ffi.Array(2048)
  external ffi.Array<ffi.Uint8> filename;
  
  @ffi.Int64()
  external int size;
  
  @ffi.Int64()
  external int packed_size;
  
  @ffi.Bool()
  external bool is_directory;
}

final class UnrarListResult extends ffi.Struct {
  @ffi.Int32()
  external int status;
  
  @ffi.Int64()
  external int entry_count;
  
  external ffi.Pointer<UnrarEntry> entries;
  
  @ffi.Array(512)
  external ffi.Array<ffi.Uint8> error_message;
}

final class UnrarExtractResult extends ffi.Struct {
  @ffi.Int32()
  external int status;
  
  @ffi.Int64()
  external int extracted_count;
  
  @ffi.Int64()
  external int skipped_count;
  
  @ffi.Int64()
  external int failed_count;
  
  @ffi.Array(512)
  external ffi.Array<ffi.Uint8> error_message;
}

// ==================== FFI 绑定 ====================

class UnrarBindings {
  final ffi.DynamicLibrary _lib;

  UnrarBindings(this._lib);

  late final unrar_is_rar_file = _lib.lookupFunction<
      ffi.Bool Function(ffi.Pointer<ffi.Char>),
      bool Function(ffi.Pointer<ffi.Char>)>('unrar_is_rar_file');

  late final unrar_get_version = _lib.lookupFunction<
      ffi.Pointer<ffi.Char> Function(),
      ffi.Pointer<ffi.Char> Function()>('unrar_get_version');

  late final unrar_list_contents = _lib.lookupFunction<
      ffi.Int32 Function(
          ffi.Pointer<ffi.Char>, ffi.Pointer<UnrarListResult>),
      int Function(ffi.Pointer<ffi.Char>,
          ffi.Pointer<UnrarListResult>)>('unrar_list_contents');

  late final unrar_free_list_result = _lib.lookupFunction<
      ffi.Void Function(ffi.Pointer<UnrarListResult>),
      void Function(ffi.Pointer<UnrarListResult>)>('unrar_free_list_result');
  
  late final unrar_extract = _lib.lookupFunction<
      ffi.Int32 Function(
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<UnrarExtractResult>,
          ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>),
      int Function(
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<UnrarExtractResult>,
          ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>>)>('unrar_extract');
  
  late final unrar_extract_file = _lib.lookupFunction<
      ffi.Int32 Function(
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>),
      int Function(
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<ffi.Char>)>('unrar_extract_file');
}
