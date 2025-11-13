/// 搜索历史记录项
class SearchHistoryItem {
  /// 搜索关键词
  final String keyword;

  /// 搜索时间
  final DateTime searchedAt;

  /// 搜索次数（用于统计热门搜索）
  final int searchCount;

  /// 搜索结果数量（可选）
  final int? resultCount;

  const SearchHistoryItem({
    required this.keyword,
    required this.searchedAt,
    this.searchCount = 1,
    this.resultCount,
  });

  /// 从 JSON 创建
  factory SearchHistoryItem.fromJson(Map<String, dynamic> json) {
    return SearchHistoryItem(
      keyword: json['keyword'] as String,
      searchedAt: DateTime.parse(json['searchedAt'] as String),
      searchCount: (json['searchCount'] as int?) ?? 1,
      resultCount: json['resultCount'] as int?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'keyword': keyword,
      'searchedAt': searchedAt.toIso8601String(),
      'searchCount': searchCount,
      if (resultCount != null) 'resultCount': resultCount,
    };
  }

  /// 创建副本（用于更新搜索次数）
  SearchHistoryItem copyWith({
    String? keyword,
    DateTime? searchedAt,
    int? searchCount,
    int? resultCount,
  }) {
    return SearchHistoryItem(
      keyword: keyword ?? this.keyword,
      searchedAt: searchedAt ?? this.searchedAt,
      searchCount: searchCount ?? this.searchCount,
      resultCount: resultCount ?? this.resultCount,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SearchHistoryItem && other.keyword == keyword;
  }

  @override
  int get hashCode => keyword.hashCode;

  @override
  String toString() {
    return 'SearchHistoryItem(keyword: $keyword, searchedAt: $searchedAt, '
        'searchCount: $searchCount, resultCount: $resultCount)';
  }
}
