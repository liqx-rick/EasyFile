// ignore_for_file: non_constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

/// FFI 绑定类 - 负责加载和管理 Native 库
class ArchiveFFI {
  late final ffi.DynamicLibrary _lib;
  late final ArchiveNativeBindings _bindings;

  ArchiveFFI() {
    _lib = _loadLibrary();
    _bindings = ArchiveNativeBindings(_lib);
  }

  /// 加载动态库
  ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libarchive_wrapper.so');
    } else if (Platform.isIOS) {
      // 未来支持
      return ffi.DynamicLibrary.process();
    } else {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }
  }

  /// 解压压缩包（同步调用 - 应在 Isolate 中使用）
  ExtractResultNative extractArchive({
    required String archivePath,
    required String destPath,
    bool overwrite = true,
    bool preservePermissions = false,
    void Function(double progress, String filename)? onProgress,
  }) {
    final archivePathPtr = archivePath.toNativeUtf8();
    final destPathPtr = destPath.toNativeUtf8();
    final optionsPtr = calloc<ExtractOptions>();
    final resultPtr = calloc<ExtractResult>();

    try {
      optionsPtr.ref.archive_path = archivePathPtr.cast();
      optionsPtr.ref.dest_path = destPathPtr.cast();
      optionsPtr.ref.overwrite = overwrite;
      optionsPtr.ref.preserve_permissions = preservePermissions;
      optionsPtr.ref.on_progress = ffi.nullptr;
      optionsPtr.ref.user_data = ffi.nullptr;

      final handleId = _bindings.archive_extract_async(optionsPtr, resultPtr);

      return ExtractResultNative(
        status: resultPtr.ref.status,
        totalFiles: resultPtr.ref.total_files,
        extractedFiles: resultPtr.ref.extracted_files,
        totalBytes: resultPtr.ref.total_bytes,
        errorMessage: _readCString(resultPtr.ref.error_message, 512),
        handleId: handleId,
      );
    } finally {
      calloc.free(resultPtr);
      calloc.free(optionsPtr);
      calloc.free(destPathPtr);
      calloc.free(archivePathPtr);
    }
  }

  /// 取消解压
  bool cancelExtraction(int handleId) {
    return _bindings.archive_cancel(handleId);
  }

  /// 列出压缩包内容
  ListResultNative listContents(String archivePath) {
    final pathPtr = archivePath.toNativeUtf8();
    final resultPtr = calloc<ListResult>();

    try {
      final status = _bindings.archive_list_contents(
        pathPtr.cast(),
        resultPtr,
      );

      final entries = <ArchiveEntryNative>[];
      if (status == 0 && resultPtr.ref.entry_count > 0) {
        final entriesPtr = resultPtr.ref.entries;
        for (int i = 0; i < resultPtr.ref.entry_count; i++) {
          final entry = entriesPtr.elementAt(i).ref;
          
          entries.add(ArchiveEntryNative(
            name: _readCString(entry.name, 1024),
            pathname: _readCString(entry.pathname, 2048),
            size: entry.size,
            compressedSize: entry.compressed_size,
            mtime: entry.mtime,
            isDirectory: entry.is_directory,
            mode: entry.mode,
            crc32: entry.crc32,
          ));
        }
      }

      return ListResultNative(
        status: status,
        entries: entries,
        errorMessage: _readCString(resultPtr.ref.error_message, 512),
      );
    } finally {
      _bindings.archive_free_list_result(resultPtr);
      calloc.free(resultPtr);
      calloc.free(pathPtr);
    }
  }

  /// 验证压缩包
  bool validate(String archivePath) {
    final pathPtr = archivePath.toNativeUtf8();
    try {
      final result = _bindings.archive_validate(pathPtr.cast());
      return result == 0;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// 提取单个文件
  SingleFileExtractResultNative extractSingleFile({
    required String archivePath,
    required String entryPath,
    required String outputPath,
  }) {
    final archivePathPtr = archivePath.toNativeUtf8();
    final entryPathPtr = entryPath.toNativeUtf8();
    final outputPathPtr = outputPath.toNativeUtf8();
    final resultPtr = calloc<SingleFileExtractResult>();

    try {
      final status = _bindings.archive_extract_single_file(
        archivePathPtr.cast(),
        entryPathPtr.cast(),
        outputPathPtr.cast(),
        resultPtr,
      );

      return SingleFileExtractResultNative(
        status: status,
        success: resultPtr.ref.success,
        extractedSize: resultPtr.ref.extracted_size,
        errorMessage: _readCString(resultPtr.ref.error_message, 512),
      );
    } finally {
      calloc.free(resultPtr);
      calloc.free(outputPathPtr);
      calloc.free(entryPathPtr);
      calloc.free(archivePathPtr);
    }
  }

  /// 读取 C 字符串（从固定大小的 Array）
  /// 
  /// Native 层已经通过 libarchive 将文件名转换为 UTF-8 编码
  /// 这里只需要简单地从字节数组构造字符串即可
  String _readCString(ffi.Array<ffi.Uint8> cArray, int maxSize) {
    final bytes = <int>[];
    for (int i = 0; i < maxSize; i++) {
      if (cArray[i] == 0) break;
      bytes.add(cArray[i]);
    }
    
    if (bytes.isEmpty) return '';
    
    // Native 层已经通过 libarchive 的 hdrcharset 选项将文件名转换为 UTF-8
    // 直接从字节构造字符串即可
    return String.fromCharCodes(bytes);
  }
}

/// Native 类型定义

final class ExtractOptions extends ffi.Struct {
  external ffi.Pointer<ffi.Char> archive_path;
  external ffi.Pointer<ffi.Char> dest_path;
  @ffi.Bool()
  external bool overwrite;
  @ffi.Bool()
  external bool preserve_permissions;
  external ffi.Pointer<ffi.NativeFunction<ProgressCallbackNative>> on_progress;
  external ffi.Pointer<ffi.Void> user_data;
}

final class ExtractResult extends ffi.Struct {
  @ffi.Int32()
  external int status;
  @ffi.Int64()
  external int total_files;
  @ffi.Int64()
  external int extracted_files;
  @ffi.Int64()
  external int total_bytes;
  @ffi.Array(512)
  external ffi.Array<ffi.Uint8> error_message;
}

final class ArchiveEntry extends ffi.Struct {
  @ffi.Array(1024)
  external ffi.Array<ffi.Uint8> name;
  @ffi.Array(2048)
  external ffi.Array<ffi.Uint8> pathname;
  @ffi.Int64()
  external int size;
  @ffi.Int64()
  external int compressed_size;
  @ffi.Int64()
  external int mtime;
  @ffi.Bool()
  external bool is_directory;
  @ffi.Uint32()
  external int mode;
  @ffi.Uint32()
  external int crc32;
}

final class ListResult extends ffi.Struct {
  @ffi.Int32()
  external int status;
  @ffi.Int64()
  external int entry_count;
  external ffi.Pointer<ArchiveEntry> entries;
  @ffi.Array(512)
  external ffi.Array<ffi.Uint8> error_message;
}

final class SingleFileExtractResult extends ffi.Struct {
  @ffi.Bool()
  external bool success;
  @ffi.Int64()
  external int extracted_size;
  @ffi.Array(512)
  external ffi.Array<ffi.Uint8> error_message;
}

/// 进度回调类型
typedef ProgressCallbackNative = ffi.Void Function(
  ffi.Double progress,
  ffi.Pointer<ffi.Char> filename,
  ffi.Int64 current_size,
  ffi.Int64 total_size,
);

/// Native 函数绑定
class ArchiveNativeBindings {
  final ffi.DynamicLibrary _lib;

  ArchiveNativeBindings(this._lib);

  late final archive_extract_async = _lib.lookupFunction<
      ffi.Int64 Function(
        ffi.Pointer<ExtractOptions>,
        ffi.Pointer<ExtractResult>,
      ),
      int Function(
        ffi.Pointer<ExtractOptions>,
        ffi.Pointer<ExtractResult>,
      )>('archive_extract_async');

  late final archive_cancel = _lib.lookupFunction<
      ffi.Bool Function(ffi.Int64),
      bool Function(int)>('archive_cancel');

  late final archive_list_contents = _lib.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ListResult>,
      ),
      int Function(
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ListResult>,
      )>('archive_list_contents');

  late final archive_free_list_result = _lib.lookupFunction<
      ffi.Void Function(ffi.Pointer<ListResult>),
      void Function(ffi.Pointer<ListResult>)>('archive_free_list_result');

  late final archive_validate = _lib.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Char>),
      int Function(ffi.Pointer<ffi.Char>)>('archive_validate');

  late final archive_extract_single_file = _lib.lookupFunction<
      ffi.Int32 Function(
        ffi.Pointer<ffi.Char>, // archive_path
        ffi.Pointer<ffi.Char>, // entry_path
        ffi.Pointer<ffi.Char>, // output_path
        ffi.Pointer<SingleFileExtractResult>,
      ),
      int Function(
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<SingleFileExtractResult>,
      )>('archive_extract_single_file');
}

/// Dart 数据类 - 从 Native 结构转换

class ExtractResultNative {
  final int status;
  final int totalFiles;
  final int extractedFiles;
  final int totalBytes;
  final String errorMessage;
  final int handleId;

  ExtractResultNative({
    required this.status,
    required this.totalFiles,
    required this.extractedFiles,
    required this.totalBytes,
    required this.errorMessage,
    required this.handleId,
  });

  bool get success => status == 0;
}

class ArchiveEntryNative {
  final String name;
  final String pathname;
  final int size;
  final int compressedSize;
  final int mtime;
  final bool isDirectory;
  final int mode;
  final int crc32;

  ArchiveEntryNative({
    required this.name,
    required this.pathname,
    required this.size,
    required this.compressedSize,
    required this.mtime,
    required this.isDirectory,
    required this.mode,
    required this.crc32,
  });
}

class ListResultNative {
  final int status;
  final List<ArchiveEntryNative> entries;
  final String errorMessage;

  ListResultNative({
    required this.status,
    required this.entries,
    required this.errorMessage,
  });

  bool get success => status == 0;
}

class SingleFileExtractResultNative {
  final int status;
  final bool success;
  final int extractedSize;
  final String errorMessage;

  SingleFileExtractResultNative({
    required this.status,
    required this.success,
    required this.extractedSize,
    required this.errorMessage,
  });
}
