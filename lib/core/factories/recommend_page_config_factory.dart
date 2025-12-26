import 'package:flutter/material.dart';
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
        return RecommendPageConfig(
          type: card.type,
          title: card.title,
          subtitle: '来自该应用的文件',
          mode: RecommendMode.application,
          headerType: HeaderType.applicationSummary,
          listStyle: FileListStyle.auto, // 使用自动模式：图片/视频用网格，其他用列表
          themeColor: card.color,
          tabs: [
            TabConfig(
              title: '全部',
              fileTypes: null, // null 表示所有文件
              icon: Icons.folder_open,
            ),
            TabConfig(
              title: '图片',
              fileTypes: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
              icon: Icons.image,
            ),
            TabConfig(
              title: '视频',
              fileTypes: ['mp4', 'mov', 'avi', 'mkv'],
              icon: Icons.video_library,
            ),
            TabConfig(
              title: '文档',
              fileTypes: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'],
              icon: Icons.description,
            ),
            TabConfig(
              title: '音频',
              fileTypes: ['mp3', 'wav', 'aac', 'ogg', 'flac'],
              icon: Icons.music_note,
            ),
            TabConfig(
              title: '其他',
              fileTypes: const <String>[], // 明确的空数组：排除已知类型
              icon: Icons.insert_drive_file,
            ),
          ],
        );
      
      case RecommendationType.qq:
        return RecommendPageConfig(
          type: card.type,
          title: card.title,
          subtitle: '来自该应用的文件',
          mode: RecommendMode.application,
          headerType: HeaderType.applicationSummary,
          listStyle: FileListStyle.auto, // 使用自动模式
          themeColor: card.color,
          tabs: [
            TabConfig(
              title: '全部',
              fileTypes: null, // null 表示所有文件
              icon: Icons.folder_open,
            ),
            TabConfig(
              title: '图片',
              fileTypes: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
              icon: Icons.image,
            ),
            TabConfig(
              title: '视频',
              fileTypes: ['mp4', 'mov', 'avi', 'mkv'],
              icon: Icons.video_library,
            ),
            TabConfig(
              title: '文档',
              fileTypes: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'],
              icon: Icons.description,
            ),
            TabConfig(
              title: '音频',
              fileTypes: ['mp3', 'wav', 'aac', 'ogg', 'flac'],
              icon: Icons.music_note,
            ),
            TabConfig(
              title: '其他',
              fileTypes: const <String>[], // 明确的空数组：排除已知类型
              icon: Icons.insert_drive_file,
            ),
          ],
        );
      
      case RecommendationType.telegram:
        return RecommendPageConfig(
          type: card.type,
          title: card.title,
          subtitle: '来自该应用的文件',
          mode: RecommendMode.application,
          headerType: HeaderType.applicationSummary,
          listStyle: FileListStyle.auto, // 使用自动模式
          themeColor: card.color,
          tabs: [
            TabConfig(
              title: '全部',
              fileTypes: null, // null 表示所有文件
              icon: Icons.folder_open,
            ),
            TabConfig(
              title: '图片',
              fileTypes: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
              icon: Icons.image,
            ),
            TabConfig(
              title: '视频',
              fileTypes: ['mp4', 'mov', 'avi', 'mkv'],
              icon: Icons.video_library,
            ),
            TabConfig(
              title: '文档',
              fileTypes: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'],
              icon: Icons.description,
            ),
            TabConfig(
              title: '音频',
              fileTypes: ['mp3', 'wav', 'aac', 'ogg', 'flac'],
              icon: Icons.music_note,
            ),
            TabConfig(
              title: '其他',
              fileTypes: const <String>[], // 明确的空数组：排除已知类型
              icon: Icons.insert_drive_file,
            ),
          ],
        );
      
      case RecommendationType.dingtalk:
        return RecommendPageConfig(
          type: card.type,
          title: card.title,
          subtitle: '来自该应用的文件',
          mode: RecommendMode.application,
          headerType: HeaderType.applicationSummary,
          listStyle: FileListStyle.auto, // 使用自动模式
          themeColor: card.color,
          tabs: [
            TabConfig(
              title: '全部',
              fileTypes: null,
              icon: Icons.folder_open,
            ),
            TabConfig(
              title: '图片',
              fileTypes: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
              icon: Icons.image,
            ),
            TabConfig(
              title: '视频',
              fileTypes: ['mp4', 'mov', 'avi', 'mkv'],
              icon: Icons.video_library,
            ),
            TabConfig(
              title: '文档',
              fileTypes: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'],
              icon: Icons.description,
            ),
            TabConfig(
              title: '其他',
              fileTypes: const <String>[],
              icon: Icons.insert_drive_file,
            ),
          ],
        );
      
      case RecommendationType.wps:
        return RecommendPageConfig(
          type: card.type,
          title: card.title,
          subtitle: '来自该应用的文件',
          mode: RecommendMode.application,
          headerType: HeaderType.applicationSummary,
          listStyle: FileListStyle.auto, // 使用自动模式
          themeColor: card.color,
          tabs: [
            TabConfig(
              title: '全部',
              fileTypes: null, // null 表示所有文档
              icon: Icons.folder_open,
            ),
            TabConfig(
              title: 'Word',
              fileTypes: ['doc', 'docx'],
              icon: Icons.description,
            ),
            TabConfig(
              title: 'Excel',
              fileTypes: ['xls', 'xlsx'],
              icon: Icons.table_chart,
            ),
            TabConfig(
              title: 'PPT',
              fileTypes: ['ppt', 'pptx'],
              icon: Icons.slideshow,
            ),
            TabConfig(
              title: 'PDF',
              fileTypes: ['pdf'],
              icon: Icons.picture_as_pdf,
            ),
          ],
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
}
