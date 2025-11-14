import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/search_history_item.dart';

/// 搜索历史本地存储服务
class SearchHistoryLocalSource {
  static const String _fileName = 'search_history.json';
  static const int _maxHistoryCount = 50; // 最多保存50条历史记录

  /// 获取搜索历史文件路径
  Future<String> _getFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_fileName';
  }

  /// 获取所有搜索历史（按时间倒序）
  Future<List<SearchHistoryItem>> getAllHistory() async {
    try {
      final filePath = await _getFilePath();
      final file = File(filePath);

      if (!await file.exists()) {
        logger.d('Search history file does not exist');
        return [];
      }

      final content = await file.readAsString();
      final List<dynamic> jsonList = json.decode(content);

      final history = jsonList
          .map(
            (json) => SearchHistoryItem.fromJson(json as Map<String, dynamic>),
          )
          .toList();

      // 按搜索时间倒序排列
      history.sort((a, b) => b.searchedAt.compareTo(a.searchedAt));

      logger.i('Loaded ${history.length} search history items');
      return history;
    } catch (e) {
      logger.e('Error loading search history: $e');
      return [];
    }
  }

  /// 获取热门搜索（按搜索次数降序）
  Future<List<SearchHistoryItem>> getPopularSearches({int limit = 10}) async {
    try {
      final allHistory = await getAllHistory();

      // 按搜索次数降序排列
      allHistory.sort((a, b) => b.searchCount.compareTo(a.searchCount));

      return allHistory.take(limit).toList();
    } catch (e) {
      logger.e('Error getting popular searches: $e');
      return [];
    }
  }

  /// 添加或更新搜索记录
  Future<bool> addSearchRecord(String keyword, {int? resultCount}) async {
    if (keyword.trim().isEmpty) {
      logger.w('Cannot add empty search keyword');
      return false;
    }

    try {
      final history = await getAllHistory();

      // 查找是否已存在该关键词
      final existingIndex = history.indexWhere(
        (item) => item.keyword == keyword,
      );

      if (existingIndex >= 0) {
        // 更新现有记录：增加搜索次数，更新时间
        final existing = history[existingIndex];
        history[existingIndex] = existing.copyWith(
          searchedAt: DateTime.now(),
          searchCount: existing.searchCount + 1,
          resultCount: resultCount,
        );
        logger.d(
          'Updated search record for "$keyword", count: ${history[existingIndex].searchCount}',
        );
      } else {
        // 添加新记录
        final newItem = SearchHistoryItem(
          keyword: keyword,
          searchedAt: DateTime.now(),
          searchCount: 1,
          resultCount: resultCount,
        );
        history.insert(0, newItem);
        logger.d('Added new search record: "$keyword"');
      }

      // 限制历史记录数量
      if (history.length > _maxHistoryCount) {
        history.removeRange(_maxHistoryCount, history.length);
        logger.d('Trimmed search history to $_maxHistoryCount items');
      }

      await _saveHistory(history);
      return true;
    } catch (e) {
      logger.e('Error adding search record: $e');
      return false;
    }
  }

  /// 删除单条搜索记录
  Future<bool> deleteSearchRecord(String keyword) async {
    try {
      final history = await getAllHistory();
      final initialLength = history.length;

      history.removeWhere((item) => item.keyword == keyword);

      if (history.length < initialLength) {
        await _saveHistory(history);
        logger.i('Deleted search record: "$keyword"');
        return true;
      }

      return false;
    } catch (e) {
      logger.e('Error deleting search record: $e');
      return false;
    }
  }

  /// 清空所有搜索历史
  Future<bool> clearAllHistory() async {
    try {
      final filePath = await _getFilePath();
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        logger.i('Cleared all search history');
      }

      return true;
    } catch (e) {
      logger.e('Error clearing search history: $e');
      return false;
    }
  }

  /// 搜索建议（根据输入的关键词前缀匹配）
  Future<List<String>> getSuggestions(String prefix) async {
    if (prefix.trim().isEmpty) {
      return [];
    }

    try {
      final history = await getAllHistory();
      final lowerPrefix = prefix.toLowerCase();

      // 查找以该前缀开头的关键词
      final suggestions = history
          .where((item) => item.keyword.toLowerCase().startsWith(lowerPrefix))
          .map((item) => item.keyword)
          .take(5) // 最多返回5个建议
          .toList();

      logger.d('Found ${suggestions.length} suggestions for "$prefix"');
      return suggestions;
    } catch (e) {
      logger.e('Error getting search suggestions: $e');
      return [];
    }
  }

  /// 保存搜索历史到文件
  Future<void> _saveHistory(List<SearchHistoryItem> history) async {
    try {
      final filePath = await _getFilePath();
      final file = File(filePath);

      final jsonList = history.map((item) => item.toJson()).toList();
      final content = json.encode(jsonList);

      await file.writeAsString(content);
      logger.d('Saved ${history.length} search history items');
    } catch (e) {
      logger.e('Error saving search history: $e');
      rethrow;
    }
  }
}
