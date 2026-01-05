import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/new_file_item.dart';
import 'package:easyfile/platform/new_files_native_channel.dart';

/// 取消令牌：用于取消正在进行的扫描
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() {
    _cancelled = true;
    logger.i('CancelToken: Scan cancellation requested');
  }
}

/// 新文件扫描器
/// 负责扫描指定目录下的新文件
/// 
/// 注意：不再保存配置，每次扫描时传入最新配置确保实时生效
class NewFilesScanner {
  CancelToken? _currentScanToken;

  NewFilesScanner();

  /// 取消当前正在进行的扫描
  void cancelCurrentScan() {
    if (_currentScanToken != null && !_currentScanToken!.isCancelled) {
      _currentScanToken!.cancel();
      logger.i('NewFilesScanner: Current scan cancelled by user action');
    }
  }

  /// 扫描新文件（性能优化版）
  /// 
  /// **策略**: 使用Android MediaStore原生扫描（快速，2-3秒）
  /// 
  /// **取消机制**: 支持Tab切换时中断扫描
  /// 
  /// **参数**:
  /// - [retentionDays] 保留天数，从FileScanConfig传入确保使用最新配置
  /// - [maxResults] 最大结果数，用于预留缓存空间
  /// 
  /// **返回**: 按创建时间倒序排列的文件列表（最多maxResults项）
  Future<List<NewFileItem>> scanNewFiles({
    required int retentionDays,
    int maxResults = 200,
  }) async {
    logger.i('NewFilesScanner: Starting native scan');
    
    // 取消之前的扫描
    if (_currentScanToken != null) {
      _currentScanToken!.cancel();
    }
    _currentScanToken = CancelToken();
    
    try {
      // 检查取消状态
      if (_currentScanToken!.isCancelled) {
        logger.i('NewFilesScanner: Scan cancelled before native scan');
        return [];
      }
      
      // 使用原生优化扫描
      final nativeResults = await NewFilesNativeChannel.scanRecentFiles(
        retentionDays,
      );
      
      // 检查取消状态
      if (_currentScanToken!.isCancelled) {
        logger.i('NewFilesScanner: Scan cancelled after native scan');
        return [];
      }
      
      // 限制数量
      final limitedResults = nativeResults.take(maxResults).toList();
      
      logger.i('NewFilesScanner: Native scan complete, found ${limitedResults.length} files');
      return limitedResults;
      
    } catch (e) {
      logger.e('NewFilesScanner: Native scan failed: $e');
      // 返回空列表，UI层会显示友好的错误提示
      return [];
    } finally {
      _currentScanToken = null;
    }
  }

  /// 智能缓存策略 - 根据场景决定是否重新扫描
  ///
  /// **⚠️ 核心性能逻辑 - 修改前请评估影响**
  /// **适用场景**：应用启动时快速显示 + 后台更新
  /// **维护者注意**：1小时阈值经过用户验证，修改需A/B测试
  ///
  /// **用户主动刷新**: 总是执行扫描（保证数据最新）
  /// **应用启动**: 检查缓存文件修改时间
  ///   - < 1小时: 使用缓存（返回null），后台静默刷新
  ///   - >= 1小时: 执行完整扫描
  ///
  /// **返回值**:
  /// - `null`: 使用缓存，Presenter层启动后台刷新
  /// - `List<NewFileItem>`: 新扫描结果，更新UI
  Future<List<NewFileItem>?> quickScanIfNeeded(
    List<NewFileItem> cachedItems, {
    required int retentionDays,
    int maxResults = 200,
    bool isUserRefresh = false, // 是否为用户主动刷新
  }) async {
    // 用户主动刷新：始终扫描（快速响应）
    if (isUserRefresh) {
      logger.i('User refresh triggered, starting quick scan...');
      return await scanNewFiles(
        retentionDays: retentionDays,
        maxResults: maxResults,
      );
    }

    // 应用启动加载：检查缓存文件年龄
    if (cachedItems.isNotEmpty) {
      try {
        // 获取缓存文件的修改时间
        final directory = await getApplicationDocumentsDirectory();
        final cacheFile = File('${directory.path}${Platform.pathSeparator}new_files_index.json');
        
        if (await cacheFile.exists()) {
          final stat = await cacheFile.stat();
          final age = DateTime.now().difference(stat.modified);

          // 1小时内使用缓存（立即显示）
          if (age < Duration(hours: 1)) {
            logger.d(
                'Using cached scan results (cache file age: ${age.inMinutes} minutes)');

            // 返回null表示使用缓存，后台刷新由Presenter层控制
            return null; // 使用缓存
          }

          // 超过1小时：执行完整扫描
          logger.i('Cache expired (${age.inHours} hours old), performing full scan');
        }
      } catch (e) {
        logger.e('Error checking cache file age: $e');
      }
    }

    // 首次扫描或缓存过期
    return await scanNewFiles(
      retentionDays: retentionDays,
      maxResults: maxResults,
    );
  }


}
