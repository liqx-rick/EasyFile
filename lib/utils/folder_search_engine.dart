import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:easyfile/core/logger.dart';

/// 文件夹匹配结果
class FolderMatch {
  final String name;
  final String path;
  final String matchType; // '应用名匹配' | '文件夹名匹配' | '路径匹配'
  final int score; // 匹配分数，用于排序

  FolderMatch({
    required this.name,
    required this.path,
    required this.matchType,
    required this.score,
  });
}

/// 文件夹搜索引擎
class FolderSearchEngine {
  // 预建索引：常见应用名 → 路径映射
  static final Map<String, List<String>> _appPathIndex = {
    '钉钉': ['/storage/emulated/0/DingTalk', '/storage/emulated/0/DingTalk/download'],
    'dingtalk': ['/storage/emulated/0/DingTalk'],
    '企业微信': ['/storage/emulated/0/tencent/WXWork'],
    '企微': ['/storage/emulated/0/tencent/WXWork'],
    'wework': ['/storage/emulated/0/tencent/WXWork'],
    'wxwork': ['/storage/emulated/0/tencent/WXWork'],
    '百度网盘': ['/storage/emulated/0/BaiduNetdisk'],
    '网盘': ['/storage/emulated/0/BaiduNetdisk'],
    'baidu': ['/storage/emulated/0/BaiduNetdisk'],
    '夸克': ['/storage/emulated/0/quark/Download', '/storage/emulated/0/quark'],
    'quark': ['/storage/emulated/0/quark'],
    'uc': ['/storage/emulated/0/UCDownloads'],
    'uc浏览器': ['/storage/emulated/0/UCDownloads'],
    '微信': ['/storage/emulated/0/tencent/MicroMsg/Download'],
    'wechat': ['/storage/emulated/0/tencent/MicroMsg'],
    'qq': ['/storage/emulated/0/tencent/QQfile_recv'],
    '相机': ['/storage/emulated/0/DCIM/Camera'],
    'camera': ['/storage/emulated/0/DCIM/Camera'],
    '截屏': ['/storage/emulated/0/Pictures/Screenshots'],
    'screenshot': ['/storage/emulated/0/Pictures/Screenshots'],
    '录音': ['/storage/emulated/0/Recordings'],
    'recording': ['/storage/emulated/0/Recordings'],
    '下载': ['/storage/emulated/0/Download'],
    'download': ['/storage/emulated/0/Download'],
    '文档': ['/storage/emulated/0/Documents'],
    'document': ['/storage/emulated/0/Documents'],
    '蓝牙': ['/storage/emulated/0/bluetooth'],
    'bluetooth': ['/storage/emulated/0/bluetooth'],
  };

  /// 搜索文件夹
  Future<List<FolderMatch>> search(String query) async {
    if (query.isEmpty) return [];

    logger.d('FolderSearchEngine: Searching for "$query"');
    final results = <FolderMatch>[];
    final lowerQuery = query.toLowerCase();

    // 1. 从索引中匹配
    _appPathIndex.forEach((key, paths) {
      if (key.toLowerCase().contains(lowerQuery)) {
        for (final folderPath in paths) {
          if (Directory(folderPath).existsSync()) {
            final score = _calculateScore(key, query);
            results.add(FolderMatch(
              name: path.basename(folderPath),
              path: folderPath,
              matchType: '应用名匹配',
              score: score + 100, // 应用名匹配优先级高
            ));
          }
        }
      }
    });

    // 2. 文件系统搜索（扫描常见根目录）
    final searchPaths = ['/storage/emulated/0'];
    for (final searchPath in searchPaths) {
      try {
        final matches = await _searchFileSystem(searchPath, lowerQuery, maxDepth: 2);
        results.addAll(matches);
      } catch (e) {
        logger.e('Error searching $searchPath: $e');
      }
    }

    // 3. 按分数排序并去重
    final uniqueResults = <String, FolderMatch>{};
    for (final result in results) {
      if (!uniqueResults.containsKey(result.path) ||
          uniqueResults[result.path]!.score < result.score) {
        uniqueResults[result.path] = result;
      }
    }

    final sortedResults = uniqueResults.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    logger.d('Found ${sortedResults.length} matches');
    return sortedResults.take(20).toList(); // 最多返回20个结果
  }

  /// 计算匹配分数
  int _calculateScore(String text, String query) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    // 完全匹配
    if (lowerText == lowerQuery) return 100;

    // 开头匹配
    if (lowerText.startsWith(lowerQuery)) return 80;

    // 包含匹配
    if (lowerText.contains(lowerQuery)) return 60;

    // 模糊匹配
    int fuzzyScore = 0;
    int queryIndex = 0;
    for (int i = 0; i < lowerText.length && queryIndex < lowerQuery.length; i++) {
      if (lowerText[i] == lowerQuery[queryIndex]) {
        fuzzyScore += 5;
        queryIndex++;
      }
    }

    return fuzzyScore;
  }

  /// 搜索文件系统
  Future<List<FolderMatch>> _searchFileSystem(
    String basePath,
    String query,
    {int maxDepth = 2}
  ) async {
    final results = <FolderMatch>[];

    if (maxDepth <= 0) return results;

    try {
      final dir = Directory(basePath);
      if (!dir.existsSync()) return results;

      final entities = dir.listSync(recursive: false);

      for (final entity in entities) {
        if (entity is Directory) {
          try {
            final folderName = path.basename(entity.path);

            // 跳过隐藏文件夹和系统文件夹
            if (folderName.startsWith('.') ||
                folderName == 'Android' ||
                folderName == 'data') {
              continue;
            }

            // 检查文件夹名是否匹配
            final lowerFolderName = folderName.toLowerCase();
            if (lowerFolderName.contains(query)) {
              final score = _calculateScore(folderName, query);
              results.add(FolderMatch(
                name: folderName,
                path: entity.path,
                matchType: '文件夹名匹配',
                score: score,
              ));
            }

            // 递归搜索子文件夹（深度限制）
            if (maxDepth > 1) {
              final subResults = await _searchFileSystem(
                entity.path,
                query,
                maxDepth: maxDepth - 1,
              );
              results.addAll(subResults);
            }
          } catch (e) {
            // 跳过无权限访问的文件夹
          }
        }
      }
    } catch (e) {
      logger.e('Error searching file system at $basePath: $e');
    }

    return results;
  }

  /// 获取常用路径列表（用于快速选择）
  static List<Map<String, String>> getCommonPaths() {
    return [
      {'name': '下载', 'path': '/storage/emulated/0/Download'},
      {'name': '微信下载', 'path': '/storage/emulated/0/tencent/MicroMsg/Download'},
      {'name': 'QQ文件', 'path': '/storage/emulated/0/tencent/QQfile_recv'},
      {'name': '钉钉', 'path': '/storage/emulated/0/DingTalk'},
      {'name': '企业微信', 'path': '/storage/emulated/0/tencent/WXWork'},
      {'name': '百度网盘', 'path': '/storage/emulated/0/BaiduNetdisk'},
      {'name': '夸克下载', 'path': '/storage/emulated/0/quark/Download'},
      {'name': 'UC下载', 'path': '/storage/emulated/0/UCDownloads'},
      {'name': '相机', 'path': '/storage/emulated/0/DCIM/Camera'},
      {'name': '截屏', 'path': '/storage/emulated/0/Pictures/Screenshots'},
      {'name': '录音', 'path': '/storage/emulated/0/Recordings'},
      {'name': '文档', 'path': '/storage/emulated/0/Documents'},
      {'name': '蓝牙', 'path': '/storage/emulated/0/bluetooth'},
    ];
  }
}
