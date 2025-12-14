import 'package:easyfile/viewmodel/file_viewmodel.dart';
import 'package:easyfile/core/services/category_sort_service.dart';

/// 页面ID枚举
enum PageId {
  /// 主页-最近Tab
  homeRecent('home_recent'),

  /// 主页-收藏Tab
  homeFavorite('home_favorite'),

  /// 主页-新文件Tab
  homeNewFiles('home_new_files'),

  /// 主页-快速访问文件夹Tab
  homeBrowse('home_browse'),

  /// 存储页面
  storage('storage'),

  /// 图片分类
  categoryImages('category_images'),

  /// 文档分类
  categoryDocuments('category_documents'),

  /// 音乐分类
  categoryMusic('category_music'),

  /// 视频分类
  categoryVideo('category_video'),

  /// 下载分类
  categoryDownloads('category_downloads');

  final String key;
  const PageId(this.key);
}

/// 页面设置
class PageSettings {
  /// 视图模式
  final ViewMode? viewMode;

  /// 排序类型
  final SortType? sortType;

  /// 排序方向：true=升序，false=降序
  final bool? sortAscending;

  /// 是否启用分组
  final bool? groupEnabled;

  const PageSettings({
    this.viewMode,
    this.sortType,
    this.sortAscending,
    this.groupEnabled,
  });

  /// 创建副本
  PageSettings copyWith({
    ViewMode? viewMode,
    SortType? sortType,
    bool? sortAscending,
    bool? groupEnabled,
  }) {
    return PageSettings(
      viewMode: viewMode ?? this.viewMode,
      sortType: sortType ?? this.sortType,
      sortAscending: sortAscending ?? this.sortAscending,
      groupEnabled: groupEnabled ?? this.groupEnabled,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      if (viewMode != null) 'viewMode': viewMode!.name,
      if (sortType != null) 'sortType': sortType!.name,
      if (sortAscending != null) 'sortAscending': sortAscending,
      if (groupEnabled != null) 'groupEnabled': groupEnabled,
    };
  }

  /// 从JSON创建
  factory PageSettings.fromJson(Map<String, dynamic> json) {
    return PageSettings(
      viewMode: json['viewMode'] != null
          ? ViewMode.values.firstWhere((e) => e.name == json['viewMode'])
          : null,
      sortType: json['sortType'] != null
          ? SortType.values.firstWhere((e) => e.name == json['sortType'])
          : null,
      sortAscending: json['sortAscending'] as bool?,
      groupEnabled: json['groupEnabled'] as bool?,
    );
  }
}

/// 页面默认设置
class PageDefaultSettings {
  /// 各页面的默认设置
  static const Map<PageId, PageSettings> defaults = {
    // 主页-最近Tab: 列表/按访问时间/时间分组（固定）
    PageId.homeRecent: PageSettings(
      viewMode: ViewMode.list,
      sortType: SortType.modifiedTime,
      groupEnabled: true,
    ),

    // 主页-收藏Tab: 列表/按修改时间/不分组
    PageId.homeFavorite: PageSettings(
      viewMode: ViewMode.list,
      sortType: SortType.modifiedTime,
      groupEnabled: false,
    ),

    // 主页-快速访问Tab: 列表/按名称/不分组
    PageId.homeBrowse: PageSettings(
      viewMode: ViewMode.list,
      sortType: SortType.name,
      groupEnabled: false,
    ),

    // 存储页面: 列表/按名称/不分组
    PageId.storage: PageSettings(
      viewMode: ViewMode.list,
      sortType: SortType.name,
      groupEnabled: false,
    ),

    // 图片分类: 网格/按修改时间/时间分组
    PageId.categoryImages: PageSettings(
      viewMode: ViewMode.grid,
      sortType: SortType.modifiedTime,
      groupEnabled: true,
    ),

    // 文档分类: 列表/按修改时间/时间分组
    PageId.categoryDocuments: PageSettings(
      viewMode: ViewMode.list,
      sortType: SortType.modifiedTime,
      groupEnabled: true,
    ),

    // 音乐分类: 列表/按修改时间/时间分组
    PageId.categoryMusic: PageSettings(
      viewMode: ViewMode.list,
      sortType: SortType.modifiedTime,
      groupEnabled: true,
    ),

    // 视频分类: 网格/按修改时间/时间分组
    PageId.categoryVideo: PageSettings(
      viewMode: ViewMode.grid,
      sortType: SortType.modifiedTime,
      groupEnabled: true,
    ),

    // 下载分类: 列表/按修改时间/时间分组
    PageId.categoryDownloads: PageSettings(
      viewMode: ViewMode.list,
      sortType: SortType.modifiedTime,
      groupEnabled: true,
    ),
  };

  /// 获取页面的默认设置
  static PageSettings getDefaults(PageId pageId) {
    return defaults[pageId] ?? const PageSettings();
  }

  /// 获取页面描述（用于设置页面展示）
  static String getDescription(PageId pageId) {
    switch (pageId) {
      case PageId.homeRecent:
        return '最近访问';
      case PageId.homeFavorite:
        return '收藏文件';
      case PageId.homeNewFiles:
        return '新添加文件';
      case PageId.homeBrowse:
        return '快速访问';
      case PageId.storage:
        return '存储浏览';
      case PageId.categoryImages:
        return '图片分类';
      case PageId.categoryDocuments:
        return '文档分类';
      case PageId.categoryMusic:
        return '音乐分类';
      case PageId.categoryVideo:
        return '视频分类';
      case PageId.categoryDownloads:
        return '下载分类';
    }
  }

  /// 获取设置原因说明
  static String getReason(PageId pageId) {
    switch (pageId) {
      case PageId.homeRecent:
        return '时间就是核心维度';
      case PageId.homeFavorite:
        return '快速找到最近收藏的';
      case PageId.homeNewFiles:
        return '按时间分组，快速查看新文件';
      case PageId.homeBrowse:
        return '文件夹导航，层级清晰';
      case PageId.storage:
        return '文件夹导航，层级清晰';
      case PageId.categoryImages:
        return '照片瀑布流，按时间浏览';
      case PageId.categoryDocuments:
        return '快速找到最近的文档';
      case PageId.categoryMusic:
        return '通常按专辑/歌手，名称更合适';
      case PageId.categoryVideo:
        return '类似照片，适合网格浏览';
      case PageId.categoryDownloads:
        return '最近下载的最重要';
    }
  }
}
