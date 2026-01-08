import 'dart:convert';
import 'package:easyfile/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/core/models/duplicate_file_scan_config.dart';
import 'package:easyfile/core/services/duplicate_files_recommendation_engine.dart';
import 'package:easyfile/data/models/duplicate_file_group.dart';
import 'package:easyfile/data/models/file_item.dart';

/// 文件指纹（用于快速检测变化）
class FileFingerprint {
  final String path;
  final int size;
  final int modifiedMillis; // Unix timestamp in milliseconds

  FileFingerprint({
    required this.path,
    required this.size,
    required this.modifiedMillis,
  });

  /// 从FileItem创建
  factory FileFingerprint.fromFileItem(FileItem file) {
    return FileFingerprint(
      path: file.path,
      size: file.size,
      modifiedMillis: file.modified.millisecondsSinceEpoch,
    );
  }

  /// 检查文件是否变化
  bool hasChanged(FileFingerprint other) {
    return size != other.size || modifiedMillis != other.modifiedMillis;
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'size': size,
      'modifiedMillis': modifiedMillis,
    };
  }

  factory FileFingerprint.fromJson(Map<String, dynamic> json) {
    return FileFingerprint(
      path: json['path'] as String,
      size: json['size'] as int,
      modifiedMillis: json['modifiedMillis'] as int,
    );
  }
}

/// 文件变化类型
enum FileChangeType {
  added,
  modified,
  deleted,
}

/// 文件变化记录
class FileChange {
  final String path;
  final FileChangeType type;
  final FileFingerprint? newFingerprint;

  FileChange({
    required this.path,
    required this.type,
    this.newFingerprint,
  });

  factory FileChange.added(String path, FileFingerprint fingerprint) {
    return FileChange(
      path: path,
      type: FileChangeType.added,
      newFingerprint: fingerprint,
    );
  }

  factory FileChange.modified(String path, FileFingerprint fingerprint) {
    return FileChange(
      path: path,
      type: FileChangeType.modified,
      newFingerprint: fingerprint,
    );
  }

  factory FileChange.deleted(String path) {
    return FileChange(
      path: path,
      type: FileChangeType.deleted,
    );
  }

  bool get isAdded => type == FileChangeType.added;
  bool get isModified => type == FileChangeType.modified;
  bool get isDeleted => type == FileChangeType.deleted;
}

/// 扫描缓存数据
class DuplicateFileScanCache {
  final String cacheVersion = '1.0';
  final DateTime scanTime;
  final DuplicateFileScanConfig config;
  final List<DuplicateFileGroup> groups;
  final Map<String, FileFingerprint> fileIndex;

  DuplicateFileScanCache({
    required this.scanTime,
    required this.config,
    required this.groups,
    required this.fileIndex,
  });

  /// 检查缓存是否过期（默认7天）
  bool isExpired({Duration maxAge = const Duration(days: 7)}) {
    return DateTime.now().difference(scanTime) > maxAge;
  }

  Map<String, dynamic> toJson() {
    return {
      'cacheVersion': cacheVersion,
      'scanTime': scanTime.toIso8601String(),
      'config': config.toJson(),
      'groups': groups.map((g) => g.toJson()).toList(),
      'fileIndex': fileIndex.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  factory DuplicateFileScanCache.fromJson(Map<String, dynamic> json) {
    return DuplicateFileScanCache(
      scanTime: DateTime.parse(json['scanTime'] as String),
      config: DuplicateFileScanConfig.fromJson(
          json['config'] as Map<String, dynamic>),
      groups: (json['groups'] as List)
          .map((g) => DuplicateFileGroup.fromJson(g as Map<String, dynamic>))
          .toList(),
      fileIndex: (json['fileIndex'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
            key, FileFingerprint.fromJson(value as Map<String, dynamic>)),
      ),
    );
  }
}

/// 智能缓存服务
///
/// 提供智能缓存管理功能：
/// - 💾 持久化缓存：将扫描结果保存到本地
/// - 🔍 快速变化检测：只检查文件元数据，不读取内容
/// - ⚡ 增量更新：只重新扫描变化的文件
/// - 🎯 精准控制：确保检测准确性，避免漏检
class DuplicateFileSmartCache {
  static const String _cacheKeyPrefix = 'duplicate_scan_cache_';

  /// 获取最大缓存大小（从 AppConfig 获取）
  int get _maxCacheSize => AppConfig.instance.fileScan.smartCacheMaxSizeBytes;

  /// 保存缓存到本地
  Future<void> saveCache(DuplicateFileScanCache cache) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(cache.config);

      // 序列化为JSON
      final jsonStr = jsonEncode(cache.toJson());

      // 检查大小
      final sizeInBytes = jsonStr.length;
      if (sizeInBytes > _maxCacheSize) {
        logger.w(
            'Cache size too large (${sizeInBytes ~/ 1024 ~/ 1024}MB), skipping save');
        return;
      }

      // 保存
      await prefs.setString(cacheKey, jsonStr);
      logger.i(
          'Cache saved successfully (${sizeInBytes ~/ 1024}KB, ${cache.groups.length} groups)');
    } catch (e, stackTrace) {
      logger.e('Failed to save cache: $e\n$stackTrace');
    }
  }

  /// 从本地加载缓存
  ///
  /// 简化策略：只查找完全匹配的缓存
  /// - 不跨模式复用
  /// - 不考虑minSize降级
  /// - 逻辑简单可靠
  Future<DuplicateFileScanCache?> loadCache(
      DuplicateFileScanConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(config);

      logger.i('🔍 Loading cache for: $cacheKey');
      logger.i('   配置: ${config.toString()}');

      final jsonStr = prefs.getString(cacheKey);
      if (jsonStr == null) {
        logger.d('❌ No cache found for key: $cacheKey');
        return null;
      }

      // 反序列化
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final cache = DuplicateFileScanCache.fromJson(json);

      logger.i('📦 Cache loaded:');
      logger.i('   缓存配置: ${cache.config.toString()}');
      logger.i('   组数: ${cache.groups.length}');

      // 检查配置是否完全匹配
      if (!cache.config.isEquivalent(config)) {
        logger.w('⚠️ Cache config mismatch!');
        logger.w('   请求的: ${config.toString()}');
        logger.w('   缓存的: ${cache.config.toString()}');
        return null;
      }

      // ✅ 缓存永久有效，依赖增量更新保证准确性
      logger.i(
          '✅ Exact cache match found (${cache.groups.length} groups, age: ${DateTime.now().difference(cache.scanTime).inHours}h)');
      return cache;
    } catch (e, stackTrace) {
      logger.e('Failed to load cache: $e\n$stackTrace');
      return null;
    }
  }

  /// 清除指定配置的缓存
  Future<void> clearCache(DuplicateFileScanConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(config);
      await prefs.remove(cacheKey);
      logger.i('Cache cleared for config');
    } catch (e) {
      logger.e('Failed to clear cache: $e');
    }
  }

  /// 清除所有缓存
  Future<void> clearAllCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_cacheKeyPrefix));

      for (final key in keys) {
        await prefs.remove(key);
      }

      logger.i('All caches cleared (${keys.length} items)');
    } catch (e) {
      logger.e('Failed to clear all caches: $e');
    }
  }

  /// 检测文件变化
  ///
  /// 只检查文件元数据（大小、修改时间），不读取文件内容
  /// 确保快速且精准
  Future<List<FileChange>> detectChanges(
    DuplicateFileScanCache cache,
    List<FileItem> currentFiles,
  ) async {
    final changes = <FileChange>[];

    // 构建当前文件索引
    final currentIndex = <String, FileFingerprint>{};
    for (final file in currentFiles) {
      currentIndex[file.path] = FileFingerprint.fromFileItem(file);
    }

    // 检查新增和修改的文件
    for (final entry in currentIndex.entries) {
      final path = entry.key;
      final currentFingerprint = entry.value;
      final cachedFingerprint = cache.fileIndex[path];

      if (cachedFingerprint == null) {
        // 新增文件
        changes.add(FileChange.added(path, currentFingerprint));
      } else if (cachedFingerprint.hasChanged(currentFingerprint)) {
        // 修改的文件
        changes.add(FileChange.modified(path, currentFingerprint));
      }
    }

    // 检查删除的文件
    for (final cachedPath in cache.fileIndex.keys) {
      if (!currentIndex.containsKey(cachedPath)) {
        changes.add(FileChange.deleted(cachedPath));
      }
    }

    logger.d('Detected ${changes.length} changes: '
        '${changes.where((c) => c.isAdded).length} added, '
        '${changes.where((c) => c.isModified).length} modified, '
        '${changes.where((c) => c.isDeleted).length} deleted');

    return changes;
  }

  /// 应用增量更新
  ///
  /// 从缓存开始，只处理变化的文件
  /// 确保更新后的结果与全量扫描一致
  List<DuplicateFileGroup> applyIncrementalUpdate(
    DuplicateFileScanCache cache,
    List<FileChange> changes,
    List<FileItem> changedFiles,
    List<DuplicateFileGroup> newGroupsFromChanges,
  ) {
    // 从缓存复制所有组
    final groups = cache.groups
        .map((g) => DuplicateFileGroup(
              groupId: g.groupId,
              files: List.from(g.files),
              fileSize: g.fileSize,
              recommendationEngine: DuplicateFilesRecommendationEngine(),
            ))
        .toList();

    // 移除被删除或修改的文件
    final removePaths = changes
        .where((c) => c.isDeleted || c.isModified)
        .map((c) => c.path)
        .toSet();

    for (final group in groups) {
      group.files.removeWhere((f) => removePaths.contains(f.path));
    }

    // 移除空组
    groups.removeWhere((g) => g.files.length < 2);

    // 合并新扫描的重复组
    for (final newGroup in newGroupsFromChanges) {
      // 检查是否有相同hash的组
      final existingGroup =
          groups.where((g) => g.groupId == newGroup.groupId).firstOrNull;

      if (existingGroup != null) {
        // 合并到现有组
        for (final file in newGroup.files) {
          if (!existingGroup.files.any((f) => f.path == file.path)) {
            existingGroup.files.add(file);
          }
        }
      } else {
        // 添加新组
        groups.add(newGroup);
      }
    }

    // 再次清理小于2个文件的组
    groups.removeWhere((g) => g.files.length < 2);

    logger
        .i('Incremental update applied: ${groups.length} groups after update');

    return groups;
  }

  /// 生成缓存键
  String _getCacheKey(DuplicateFileScanConfig config) {
    // 使用配置生成唯一键
    final key =
        '$_cacheKeyPrefix${config.scanMode.name}_${config.selectedType?.name ?? 'all'}_${config.minSizeInKB}';
    return key;
  }

  /// 获取所有缓存的大小
  Future<int> getTotalCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_cacheKeyPrefix));

      int totalSize = 0;
      for (final key in keys) {
        final value = prefs.getString(key);
        if (value != null) {
          totalSize += value.length;
        }
      }

      return totalSize;
    } catch (e) {
      logger.e('Failed to get cache size: $e');
      return 0;
    }
  }
}
