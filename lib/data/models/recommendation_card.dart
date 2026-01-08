import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 推荐卡片类型枚举
enum RecommendationType {
  // 应用类（需检测安装）- 直接映射到 AppScannerConfigs
  wechat, // 微信文件 -> appKey: 'wechat'
  qq, // QQ文件 -> appKey: 'qq'
  telegram, // Telegram文件 -> appKey: 'telegram'
  wps, // WPS文档 -> appKey: 'wps'
  dingtalk, // 钉钉 -> appKey: 'dingtalk'

  // 系统类（托底卡片）- 不需要应用检测
  memories, // 时光记忆（相机）
  videos, // 生活剪影（视频）
  recordings, // 声音记录（录音）
  largeFiles, // 大文件
}

/// 推荐类型到应用Key的映射
const Map<RecommendationType, String> recommendationTypeToAppKey = {
  RecommendationType.wechat: 'wechat',
  RecommendationType.qq: 'qq',
  RecommendationType.telegram: 'telegram',
  RecommendationType.wps: 'wps',
  RecommendationType.dingtalk: 'dingtalk',
};

/// 推荐卡片配置（简化版 - UI 配置）
///
/// 应用类卡片的扫描配置统一使用 AppScannerConfigs
/// 此配置仅定义 UI 相关属性（图标、颜色、标题等）
class RecommendationConfig {
  /// 卡片类型
  final RecommendationType type;

  /// 卡片标题
  final String title;

  /// 图标
  final IconData icon;

  /// 卡片颜色
  final Color color;

  /// 是否是应用类卡片（需要检测应用安装）
  bool get isAppCard => recommendationTypeToAppKey.containsKey(type);

  /// 获取对应的应用Key（应用类卡片）
  String? get appKey => recommendationTypeToAppKey[type];

  /// 最小文件数量（0表示无要求，托底卡片）
  final int minFileCount;

  const RecommendationConfig({
    required this.type,
    required this.title,
    required this.icon,
    required this.color,
    this.minFileCount = 0,
  });
}

/// 推荐卡片（运行时实例，包含检测结果）
class RecommendationCard {
  /// 卡片类型
  final RecommendationType type;

  /// 卡片标题
  final String title;

  /// 图标
  final IconData icon;

  /// 卡片颜色
  final Color color;

  /// 实际检测到的文件数量
  final int fileCount;

  /// 应用Key（应用类卡片）
  final String? appKey;

  /// 应用图标（应用类卡片，可选）
  final Uint8List? appIcon;

  /// 总空间占用（字节）
  final int? totalSize;

  /// 本周新增文件数量
  ///
  /// 注意：当前 UI 未使用此字段，保留供将来可能的趋势展示功能使用。
  /// 数据来源：MediaStore.DATE_MODIFIED 索引查询（最近7天）
  final int? weeklyGrowth;

  const RecommendationCard({
    required this.type,
    required this.title,
    required this.icon,
    required this.color,
    required this.fileCount,
    this.appKey,
    this.appIcon,
    this.totalSize,
    this.weeklyGrowth,
  });

  /// 从配置创建卡片实例
  factory RecommendationCard.fromConfig(
    RecommendationConfig config, {
    required int fileCount,
    Uint8List? appIcon,
    int? totalSize,
    int? weeklyGrowth,
  }) {
    return RecommendationCard(
      type: config.type,
      title: config.title,
      icon: config.icon,
      color: config.color,
      fileCount: fileCount,
      appKey: config.appKey,
      appIcon: appIcon,
      totalSize: totalSize,
      weeklyGrowth: weeklyGrowth,
    );
  }

  /// 序列化为JSON（用于持久化缓存）
  Map<String, dynamic> toJson() {
    return {
      'type': type.toString(),
      'title': title,
      'iconCodePoint': icon.codePoint,
      // 注意：不序列化color，反序列化时使用config中的预定义颜色
      'fileCount': fileCount,
      'appKey': appKey,
      'appIcon': appIcon?.toList(), // Uint8List转List<int>
      'totalSize': totalSize,
      'weeklyGrowth': weeklyGrowth,
    };
  }

  /// 从JSON反序列化
  factory RecommendationCard.fromJson(Map<String, dynamic> json) {
    final type = RecommendationType.values.firstWhere(
      (e) => e.toString() == json['type'],
    );

    // 从预定义配置中查找对应的icon和color（编译时常量）
    final config = defaultRecommendationConfigs.firstWhere(
      (c) => c.type == type,
      orElse: () => const RecommendationConfig(
        type: RecommendationType.largeFiles,
        title: '未知',
        icon: Icons.help_outline,
        color: Colors.grey,
      ),
    );

    return RecommendationCard(
      type: type,
      title: json['title'] as String,
      icon: config.icon, // 使用config中的const IconData
      color: config.color, // 使用config中的const Color
      fileCount: json['fileCount'] as int,
      appKey: json['appKey'] as String?,
      appIcon: json['appIcon'] != null
          ? Uint8List.fromList(List<int>.from(json['appIcon']))
          : null,
      totalSize: json['totalSize'] as int?,
      weeklyGrowth: json['weeklyGrowth'] as int?,
    );
  }
}

/// 默认推荐配置列表（按优先级排序）
///
/// 注意：应用类卡片的扫描配置统一使用 AppScannerConfigs
/// 此处仅定义 UI 配置和显示优先级
const List<RecommendationConfig> defaultRecommendationConfigs = [
  // ==========================================
  // 应用类（需检测安装+文件数量）
  // 扫描配置来自 AppScannerConfigs
  // ==========================================

  RecommendationConfig(
    type: RecommendationType.wechat,
    title: '微信',
    icon: Icons.chat,
    color: Color(0xFF07C160), // 微信绿
    minFileCount: 3,
  ),

  RecommendationConfig(
    type: RecommendationType.wps,
    title: 'WPS',
    icon: Icons.description,
    color: Color(0xFFD9534F), // WPS红
    minFileCount: 3,
  ),

  RecommendationConfig(
    type: RecommendationType.qq,
    title: 'QQ',
    icon: Icons.chat_bubble,
    color: Color(0xFF1296DB), // QQ蓝
    minFileCount: 3,
  ),

  RecommendationConfig(
    type: RecommendationType.telegram,
    title: 'Telegram',
    icon: Icons.send,
    color: Color(0xFF0088CC), // Telegram蓝
    minFileCount: 3,
  ),

  RecommendationConfig(
    type: RecommendationType.dingtalk,
    title: '钉钉',
    icon: Icons.work,
    color: Color(0xFF2A5CFF), // 钉钉蓝
    minFileCount: 3,
  ),

  // ==========================================
  // 系统类（托底卡片，无需应用检测）
  // 当应用类卡片不足4个时显示
  // ==========================================

  RecommendationConfig(
    type: RecommendationType.memories,
    title: '时光记忆',
    icon: Icons.camera_alt,
    color: Color(0xFFFF9800), // 橙色
    minFileCount: 0, // 托底卡片，无要求
  ),

  RecommendationConfig(
    type: RecommendationType.videos,
    title: '生活剪影',
    icon: Icons.video_library,
    color: Color(0xFF9C27B0), // 紫色
    minFileCount: 0,
  ),

  RecommendationConfig(
    type: RecommendationType.recordings,
    title: '声音记录',
    icon: Icons.mic,
    color: Color(0xFF009688), // 青色
    minFileCount: 0,
  ),

  RecommendationConfig(
    type: RecommendationType.largeFiles,
    title: '大文件',
    icon: Icons.insert_drive_file,
    color: Color(0xFF795548), // 棕色
    minFileCount: 0,
  ),
];
