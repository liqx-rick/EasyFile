import 'package:flutter/services.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/file_item.dart';

/// 应用文件扫描通道（用于测试不同方案）
class AppFileScannerChannel {
  static const _channel = MethodChannel('easyfile/app_file_scanner');
  static const _eventChannel = EventChannel('easyfile/app_events');
  static const _fileChangeEventChannel = EventChannel('easyfile/file_change_events');
  
  /// 应用事件流（安装/卸载）
  static Stream<Map<String, dynamic>>? _appEventStream;
  
  /// 文件变化事件流（MediaStore监听）
  static Stream<Map<String, dynamic>>? _fileChangeEventStream;

  /// 监听应用安装/卸载事件
  /// 
  /// 返回事件流，每个事件包含：
  /// - event: 'installed' | 'uninstalled'
  /// - packageName: 应用包名
  /// 
  /// 使用示例：
  /// ```dart
  /// AppFileScannerChannel.watchAppEvents().listen((event) {
  ///   final eventType = event['event']; // 'installed' 或 'uninstalled'
  ///   final packageName = event['packageName'];
  ///   print('应用事件: $eventType - $packageName');
  /// });
  /// ```
  static Stream<Map<String, dynamic>> watchAppEvents() {
    _appEventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _appEventStream!;
  }

  /// 监听文件变化事件（MediaStore监听）
  /// 
  /// 返回事件流，每个事件包含：
  /// - event: 'file_changed'
  /// - uri: MediaStore URI
  /// - timestamp: 变化时间戳
  /// 
  /// 使用示例：
  /// ```dart
  /// AppFileScannerChannel.watchFileChangeEvents().listen((event) {
  ///   final uri = event['uri']; // MediaStore URI
  ///   final timestamp = event['timestamp'];
  ///   print('文件变化: $uri at $timestamp');
  /// });
  /// ```
  static Stream<Map<String, dynamic>> watchFileChangeEvents() {
    _fileChangeEventStream ??= _fileChangeEventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _fileChangeEventStream!;
  }

  /// 使用 MediaStore OWNER_PACKAGE_NAME 扫描（方案2 - Android 11+）
  static Future<List<FileItem>> scanByOwnerPackage(String packageName) async {
    try {
      logger.i('调用 MediaStore OWNER_PACKAGE_NAME 扫描: $packageName');
      final startTime = DateTime.now();

      final List<dynamic> result = await _channel.invokeMethod(
        'scanByOwnerPackage',
        {'packageName': packageName},
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      logger.i('扫描完成: ${result.length} 个文件, 耗时: ${duration.inMilliseconds}ms');

      final files = <FileItem>[];
      
      for (final item in result) {
        final map = Map<String, dynamic>.from(item as Map);
        
        files.add(FileItem(
          name: map['name'] as String,
          path: map['path'] as String,
          size: (map['size'] as num).toInt(),
          modified: DateTime.fromMillisecondsSinceEpoch(
            (map['modified'] as num).toInt(),
          ),
          isDirectory: false,
        ));
      }
      
      return files;
    } catch (e) {
      logger.e('扫描失败: $e');
      rethrow;
    }
  }

  /// 检查是否支持 OWNER_PACKAGE_NAME（Android 11+）
  static Future<bool> isOwnerPackageSupported() async {
    try {
      final bool result = await _channel.invokeMethod('isOwnerPackageSupported');
      return result;
    } catch (e) {
      logger.e('检查支持失败: $e');
      return false;
    }
  }

  /// 获取已知应用的路径列表
  static Future<List<String>> getKnownAppPaths(String appKey) async {
    try {
      final List<dynamic> result = await _channel.invokeMethod(
        'getKnownAppPaths',
        {'appKey': appKey},
      );
      return result.cast<String>();
    } catch (e) {
      logger.e('获取路径失败: $e');
      return [];
    }
  }

  /// 通过文件名模式扫描（例如微信相机文件）
  static Future<List<FileItem>> scanByFileNamePattern(List<String> patterns) async {
    try {
      logger.i('调用文件名模式扫描: $patterns');
      final startTime = DateTime.now();

      final List<dynamic> result = await _channel.invokeMethod(
        'scanByFileNamePattern',
        {'patterns': patterns},
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      logger.i('文件名模式扫描完成: ${result.length} 个文件, 耗时: ${duration.inMilliseconds}ms');

      final files = <FileItem>[];
      
      for (final item in result) {
        final map = Map<String, dynamic>.from(item as Map);
        
        files.add(FileItem(
          name: map['name'] as String,
          path: map['path'] as String,
          size: (map['size'] as num).toInt(),
          modified: DateTime.fromMillisecondsSinceEpoch(
            (map['modified'] as num).toInt(),
          ),
          isDirectory: false,
        ));
      }
      
      return files;
    } catch (e) {
      logger.e('文件名模式扫描失败: $e');
      rethrow;
    }
  }

  /// 获取应用特定的文件名模式
  static Future<List<String>> getAppFileNamePatterns(String appKey) async {
    try {
      final List<dynamic> result = await _channel.invokeMethod(
        'getAppFileNamePatterns',
        {'appKey': appKey},
      );
      return result.cast<String>();
    } catch (e) {
      logger.e('获取文件名模式失败: $e');
      return [];
    }
  }

  /// 在指定基础路径下查找包含特定关键字的子文件夹
  static Future<List<String>> findFoldersContaining(
    List<String> basePaths,
    String keyword,
  ) async {
    try {
      final List<dynamic> result = await _channel.invokeMethod(
        'findFoldersContaining',
        {
          'basePaths': basePaths,
          'keyword': keyword,
        },
      );
      return result.cast<String>();
    } catch (e) {
      logger.e('查找文件夹失败: $e');
      return [];
    }
  }

  /// 检查指定应用是否已安装
  /// 
  /// [packageName] 应用包名，如 'com.tencent.mm'
  /// 返回 true 表示已安装
  static Future<bool> isAppInstalled(String packageName) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isAppInstalled',
        {'packageName': packageName},
      );
      return result ?? false;
    } catch (e) {
      logger.e('检测应用安装失败 ($packageName): $e');
      return false;
    }
  }

  /// 获取指定应用的图标
  /// 
  /// [packageName] 应用包名
  /// 返回图标的字节数据（Uint8List），如果应用未安装或获取失败则返回 null
  static Future<Uint8List?> getAppIcon(String packageName) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'getAppIcon',
        {'packageName': packageName},
      );
      return result;
    } catch (e) {
      logger.e('获取应用图标失败 ($packageName): $e');
      return null;
    }
  }
}
