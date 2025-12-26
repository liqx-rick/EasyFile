import 'package:easyfile/data/models/recommendation_card.dart';
import 'package:easyfile/core/models/page_settings.dart';
import 'package:flutter/material.dart';

/// 推荐页面配置
/// 
/// 用于驱动 RecommendAggregatePage 的显示逻辑
/// 所有页面差异通过配置参数控制，页面本身不包含业务判断
class RecommendPageConfig {
  /// 推荐类型（决定数据源和查询参数）
  final RecommendationType type;
  
  /// 页面标题
  final String title;
  
  /// 副标题（可选）
  final String? subtitle;
  
  /// 推荐模式（决定是否显示 Tab）
  final RecommendMode mode;
  
  /// Header 类型（决定显示哪种 Header）
  final HeaderType headerType;
  
  /// 文件列表样式
  final FileListStyle listStyle;
  
  /// Tab 配置（仅 application 模式使用）
  final List<TabConfig>? tabs;
  
  /// 主题颜色
  final Color? themeColor;
  
  const RecommendPageConfig({
    required this.type,
    required this.title,
    this.subtitle,
    required this.mode,
    required this.headerType,
    this.listStyle = FileListStyle.list,
    this.tabs,
    this.themeColor,
  });
  
  /// 获取对应的 PageId（用于设置持久化）
  PageId get pageId {
    switch (mode) {
      case RecommendMode.application:
        return PageId.recommendApplication;
      case RecommendMode.content:
        return PageId.recommendContent;
      case RecommendMode.cleanupRecommend:
        return PageId.recommendCleanup;
    }
  }
}

/// 推荐模式
enum RecommendMode {
  /// 应用推荐模式（带 Tab，如微信、QQ）
  application,
  
  /// 内容推荐模式（无 Tab，如时光记忆、生活剪影）
  content,
  
  /// 清理推荐模式（无 Tab，如大文件）
  cleanupRecommend,
}

/// Header 类型
enum HeaderType {
  /// 无 Header
  none,
  
  /// 应用汇总 Header（显示应用信息、文件统计）
  applicationSummary,
  
  /// 情感化 Header（显示情感化文案，如"xx天前的美好瞬间"）
  emotion,
  
  /// 存储汇总 Header（显示存储占用信息）
  storageSummary,
}

/// 文件列表样式
enum FileListStyle {
  /// 列表样式（适合文件详情）
  list,
  
  /// 网格样式（适合图片预览）
  grid,
  
  /// 自动选择（根据Tab类型动态决定）
  auto,
}

/// Tab 配置（应用推荐模式使用）
class TabConfig {
  /// Tab 标题
  final String title;
  
  /// 文件类型过滤（如 ['jpg', 'png', 'gif']）
  /// - null: 表示所有文件（全部Tab）
  /// - 非空List: 过滤指定类型
  /// - 空List []: 表示其他类型（排除已知类型）
  final List<String>? fileTypes;
  
  /// Tab 图标（可选）
  final IconData? icon;
  
  const TabConfig({
    required this.title,
    required this.fileTypes,
    this.icon,
  });
}
