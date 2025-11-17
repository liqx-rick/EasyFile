import 'package:shared_preferences/shared_preferences.dart';

/// 全局搜索历史服务
/// 管理所有页面共享的搜索历史记录
class SearchHistoryService {
  static final SearchHistoryService _instance =
      SearchHistoryService._internal();
  factory SearchHistoryService() => _instance;

  SearchHistoryService._internal();

  static const String _searchHistoryKey = 'global_search_history';
  static const int _maxHistoryCount = 20;

  List<String> _history = [];
  bool _initialized = false;

  /// 获取搜索历史
  Future<List<String>> getHistory() async {
    if (!_initialized) {
      await _loadHistory();
    }
    return List.unmodifiable(_history);
  }

  /// 添加搜索记录
  Future<void> addSearch(String keyword) async {
    if (keyword.trim().isEmpty) return;

    if (!_initialized) {
      await _loadHistory();
    }

    // 移除已存在的相同记录
    _history.remove(keyword);

    // 添加到列表开头
    _history.insert(0, keyword);

    // 限制历史记录数量
    if (_history.length > _maxHistoryCount) {
      _history = _history.sublist(0, _maxHistoryCount);
    }

    await _saveHistory();
  }

  /// 删除单条搜索记录
  Future<void> removeSearch(String keyword) async {
    if (!_initialized) {
      await _loadHistory();
    }

    _history.remove(keyword);
    await _saveHistory();
  }

  /// 清空搜索历史
  Future<void> clearHistory() async {
    _history.clear();
    await _saveHistory();
  }

  /// 从本地加载搜索历史
  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList(_searchHistoryKey);

      if (historyJson != null) {
        _history = historyJson;
      }

      _initialized = true;
    } catch (e) {
      _history = [];
      _initialized = true;
    }
  }

  /// 保存搜索历史到本地
  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_searchHistoryKey, _history);
    } catch (e) {
      // 忽略保存错误
    }
  }
}
