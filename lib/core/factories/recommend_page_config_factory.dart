import 'package:flutter/material.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/models/recommend_page_config.dart';
import 'package:easyfile/data/models/recommendation_card.dart';

/// 推荐页面配置工厂
///
/// 职责：根据 RecommendationCard 生成对应的 RecommendPageConfig
class RecommendPageConfigFactory {
  /// 根据推荐卡片创建页面配置
  static RecommendPageConfig fromRecommendationCard(RecommendationCard card) {
    switch (card.type) {
      // ========== 应用类卡片 ==========

      case RecommendationType.wechat:
      case RecommendationType.qq:
      case RecommendationType.telegram:
      case RecommendationType.dingtalk:
        return _createStandardApplicationConfig(card);

      case RecommendationType.wps:
        return _createApplicationConfig(
          card: card,
          tabs: _createWpsApplicationTabs(),
        );

      // ========== 内容类卡片（系统托底） ==========

      case RecommendationType.memories:
        return RecommendPageConfig(
          type: card.type,
          title: card.title,
          subtitle: '来自系统相机的照片',
          mode: RecommendMode.content,
          headerType: HeaderType.emotion,
          listStyle: FileListStyle.grid, // 照片用网格
          themeColor: card.color,
        );

      case RecommendationType.videos:
        return RecommendPageConfig(
          type: card.type,
          title: card.title,
          subtitle: '来自系统相机的视频',
          mode: RecommendMode.content,
          headerType: HeaderType.emotion,
          listStyle: FileListStyle.grid, // 视频用网格
          themeColor: card.color,
        );

      case RecommendationType.recordings:
        return RecommendPageConfig(
          type: card.type,
          title: card.title,
          subtitle: '来自录音应用的音频',
          mode: RecommendMode.content,
          headerType: HeaderType.emotion,
          listStyle: FileListStyle.list, // 录音用列表
          themeColor: card.color,
        );

      // ========== 清理类卡片 ==========

      case RecommendationType.largeFiles:
        return RecommendPageConfig(
          type: card.type,
          title: card.title,
          subtitle: '占用空间较大的文件',
          mode: RecommendMode.cleanupRecommend,
          headerType: HeaderType.storageSummary,
          listStyle: FileListStyle.list,
          themeColor: card.color,
        );
    }
  }

  // ========== 私有辅助方法 ==========

  /// 创建标准应用配置（WeChat、QQ、Telegram 等）
  static RecommendPageConfig _createStandardApplicationConfig(
    RecommendationCard card,
  ) {
    return _createApplicationConfig(
      card: card,
      tabs: _createStandardApplicationTabs(),
    );
  }

  /// 创建通用应用配置
  static RecommendPageConfig _createApplicationConfig({
    required RecommendationCard card,
    required List<TabConfig> tabs,
  }) {
    return RecommendPageConfig(
      type: card.type,
      title: card.title,
      subtitle: '来自该应用的文件',
      mode: RecommendMode.application,
      headerType: HeaderType.applicationSummary,
      listStyle: FileListStyle.auto,
      themeColor: card.color,
      tabs: tabs,
    );
  }

  /// 创建标准应用的 Tab 列表
  static List<TabConfig> _createStandardApplicationTabs() {
    final config = AppConfig.instance.fileTypes;
    final imageTypes = config.imageExtensions.take(5).toList();
    final videoTypes = config.videoExtensions.take(4).toList();
    final audioTypes = config.audioExtensions.take(5).toList();
    final docTypes = config.officeDocumentExtensions;

    return [
      TabConfig(
        title: '全部',
        fileTypes: null,
        icon: Icons.folder_open,
      ),
      TabConfig(
        title: '图片',
        fileTypes: imageTypes,
        icon: Icons.image,
      ),
      TabConfig(
        title: '视频',
        fileTypes: videoTypes,
        icon: Icons.video_library,
      ),
      TabConfig(
        title: '文档',
        fileTypes: docTypes,
        icon: Icons.description,
      ),
      TabConfig(
        title: '音频',
        fileTypes: audioTypes,
        icon: Icons.music_note,
      ),
      TabConfig(
        title: '其他',
        fileTypes: const <String>[],
        icon: Icons.insert_drive_file,
      ),
    ];
  }

  /// 创建 WPS 应用的 Tab 列表
  static List<TabConfig> _createWpsApplicationTabs() {
    return [
      TabConfig(
        title: '全部',
        fileTypes: null,
        icon: Icons.folder_open,
      ),
      TabConfig(
        title: 'Word',
        fileTypes: const ['doc', 'docx'],
        icon: Icons.description,
      ),
      TabConfig(
        title: 'Excel',
        fileTypes: const ['xls', 'xlsx'],
        icon: Icons.table_chart,
      ),
      TabConfig(
        title: 'PPT',
        fileTypes: const ['ppt', 'pptx'],
        icon: Icons.slideshow,
      ),
      TabConfig(
        title: 'PDF',
        fileTypes: const ['pdf'],
        icon: Icons.picture_as_pdf,
      ),
    ];
  }
}
