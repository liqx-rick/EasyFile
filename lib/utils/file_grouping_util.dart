import 'package:easyfile/data/models/file_item.dart';

/// 文件分组工具类
///
/// 提供统一的文件分组逻辑，避免在各个页面重复实现
class FileGroupingUtil {
  FileGroupingUtil._();

  /// 按修改日期对文件进行分组
  ///
  /// 分组规则：
  /// - 今天：当天修改的文件
  /// - 昨天：昨天修改的文件
  /// - 本周：本周内修改的文件（不包括今天和昨天）
  /// - 本月：本月内修改的文件（不包括本周）
  /// - 更早：本月之前修改的文件
  ///
  /// [files] 要分组的文件列表
  /// [removeEmpty] 是否移除空分组，默认为 true
  /// 返回按日期分组的文件 Map，key 为分组名称，value 为文件列表
  static Map<String, List<FileItem>> groupByModifiedDate(
    List<FileItem> files, {
    bool removeEmpty = true,
  }) {
    return _groupByDate(
      files,
      dateExtractor: (file) => file.modified,
      removeEmpty: removeEmpty,
      includeMonth: true,
    );
  }

  /// 按访问日期对文件进行分组（用于最近访问文件）
  ///
  /// 分组规则：
  /// - 今天：今天访问的文件
  /// - 昨天：昨天访问的文件
  /// - 本周：本周内访问的文件（不包括今天和昨天）
  /// - 更早：本周之前访问的文件
  ///
  /// [files] 要分组的文件列表
  /// [removeEmpty] 是否移除空分组，默认为 true
  /// 返回按日期分组的文件 Map，key 为分组名称，value 为文件列表
  static Map<String, List<FileItem>> groupByAccessDate(
    List<FileItem> files, {
    bool removeEmpty = true,
  }) {
    return _groupByDate(
      files,
      dateExtractor: (file) => file.accessedAt ?? file.modified,
      removeEmpty: removeEmpty,
      includeMonth: false,
    );
  }

  /// 按加入收藏时间对文件进行分组（用于收藏文件列表）
  ///
  /// 分组规则：
  /// - 今天：今天加入收藏的文件
  /// - 昨天：昨天加入收藏的文件
  /// - 本周：本周内加入收藏的文件（不包括今天和昨天）
  /// - 本月：本月内加入收藏的文件（不包括本周）
  /// - 更早：本月之前加入收藏的文件
  ///
  /// [files] 要分组的文件列表
  /// [removeEmpty] 是否移除空分组，默认为 true
  /// 返回按日期分组的文件 Map，key 为分组名称，value 为文件列表
  static Map<String, List<FileItem>> groupByAddedDate(
    List<FileItem> files, {
    bool removeEmpty = true,
  }) {
    return _groupByDate(
      files,
      dateExtractor: (file) => file.addedTime ?? file.modified,
      removeEmpty: removeEmpty,
      includeMonth: true,
    );
  }

  /// 内部分组实现
  static Map<String, List<FileItem>> _groupByDate(
    List<FileItem> files, {
    required DateTime Function(FileItem) dateExtractor,
    required bool removeEmpty,
    required bool includeMonth,
  }) {
    final Map<String, List<FileItem>> groups = {
      '今天': [],
      '昨天': [],
      '本周': [],
      if (includeMonth) '本月': [],
      '更早': [],
    };

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeekStart = today.subtract(Duration(days: now.weekday - 1));
    final thisMonthStart = DateTime(now.year, now.month, 1);

    for (final file in files) {
      final date = dateExtractor(file);
      final fileDate = DateTime(date.year, date.month, date.day);

      if (fileDate.isAtSameMomentAs(today)) {
        groups['今天']!.add(file);
      } else if (fileDate.isAtSameMomentAs(yesterday)) {
        groups['昨天']!.add(file);
      } else if (fileDate.isAfter(thisWeekStart) ||
          fileDate.isAtSameMomentAs(thisWeekStart)) {
        groups['本周']!.add(file);
      } else if (includeMonth &&
          (fileDate.isAfter(thisMonthStart) ||
              fileDate.isAtSameMomentAs(thisMonthStart))) {
        groups['本月']!.add(file);
      } else {
        groups['更早']!.add(file);
      }
    }

    // 移除空分组
    if (removeEmpty) {
      groups.removeWhere((key, value) => value.isEmpty);
    }

    return groups;
  }

  /// 日期分组的标准顺序（包含本月）
  static const List<String> dateGroupKeys = [
    '今天',
    '昨天',
    '本周',
    '本月',
    '更早',
  ];

  /// 日期分组的标准顺序（不包含本月，用于最近访问）
  static const List<String> recentGroupKeys = [
    '今天',
    '昨天',
    '本周',
    '更早',
  ];
}
