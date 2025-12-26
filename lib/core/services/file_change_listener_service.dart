import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/platform/app_file_scanner_channel.dart';
import 'package:easyfile/core/services/app_statistics_cache.dart';
import 'package:easyfile/core/services/mediastore_cache_service.dart';

/// 文件变化监听服务
/// 
/// 监听 MediaStore 文件变化事件，自动清除相关缓存
/// - AppStatisticsCache（应用类推荐）
/// - MediaStoreCacheService（时光记忆、生活剪影、声音记录）
/// 
/// 使用示例：
/// ```dart
/// final listener = FileChangeListenerService(statisticsCache: cache);
/// await listener.startListening();
/// 
/// // 不需要时停止
/// listener.stopListening();
/// ```
class FileChangeListenerService {
  final AppStatisticsCache statisticsCache;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  DateTime? _lastEventTime;
  Timer? _debounceTimer;
  
  /// 防抖延迟（毫秒）- 避免频繁触发缓存清除
  final int debounceMillis;
  
  /// 缓存清除后的回调（用于UI刷新）
  final VoidCallback? onCacheCleared;
  
  FileChangeListenerService({
    required this.statisticsCache,
    this.debounceMillis = 2000, // 默认2秒防抖
    this.onCacheCleared,
  });

  /// 开始监听文件变化
  Future<void> startListening() async {
    if (_subscription != null) {
      logger.w('FileChangeListenerService: 已在监听中');
      return;
    }

    try {
      _subscription = AppFileScannerChannel.watchFileChangeEvents().listen(
        _handleFileChange,
        onError: (error) {
          logger.e('FileChangeListenerService: 监听错误 - $error');
        },
      );
      
      logger.i('✓ FileChangeListenerService: 文件变化监听已启动');
    } catch (e) {
      logger.e('FileChangeListenerService: 启动失败 - $e');
    }
  }

  /// 停止监听
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    logger.i('FileChangeListenerService: 文件变化监听已停止');
  }

  /// 处理文件变化事件
  void _handleFileChange(Map<String, dynamic> event) {
    final uri = event['uri'] as String?;
    final timestamp = event['timestamp'] as int?;
    
    if (uri == null) return;
    
    logger.d('文件变化: $uri');
    
    // 防抖处理：短时间内的多个事件只触发一次缓存清除
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: debounceMillis), () {
      _clearAllCache();
    });
    
    _lastEventTime = timestamp != null 
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : DateTime.now();
  }

  /// 清除所有缓存（应用统计 + MediaStore缓存）
  Future<void> _clearAllCache() async {
    try {
      // 1. 清除应用统计缓存（微信、QQ等应用类推荐）
      await statisticsCache.clearAll();
      
      // 2. 清除MediaStore缓存（时光记忆、生活剪影、声音记录）
      final mediaStoreCacheService = MediaStoreCacheService();
      await mediaStoreCacheService.clearAllCache();
      
      logger.i('✓ 文件变化 -> 已清除所有缓存（应用统计 + MediaStore）');
      
      // 触发回调通知UI刷新
      onCacheCleared?.call();
    } catch (e) {
      logger.e('清除缓存失败: $e');
    }
  }

  /// 获取最后一次事件时间
  DateTime? get lastEventTime => _lastEventTime;
  
  /// 是否正在监听
  bool get isListening => _subscription != null;

  /// 释放资源
  void dispose() {
    stopListening();
  }
}
