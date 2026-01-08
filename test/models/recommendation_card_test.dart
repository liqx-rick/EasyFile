import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/data/models/recommendation_card.dart';

void main() {
  group('RecommendationCard 模型测试', () {
    test('从配置创建卡片实例', () {
      const config = RecommendationConfig(
        type: RecommendationType.wechat,
        title: '微信',
        icon: Icons.chat,
        color: Color(0xFF07C160),
        minFileCount: 3,
      );

      final card = RecommendationCard.fromConfig(config, fileCount: 50);

      expect(card.type, RecommendationType.wechat);
      expect(card.title, '微信');
      expect(card.icon, Icons.chat);
      expect(card.color, const Color(0xFF07C160));
      expect(card.fileCount, 50);
      expect(card.appKey, 'wechat'); // 应用类卡片有 appKey
      expect(card.appIcon, null); // 默认无图标
    });

    test('从配置创建卡片实例（带应用图标）', () {
      const config = RecommendationConfig(
        type: RecommendationType.wechat,
        title: '微信',
        icon: Icons.chat,
        color: Color(0xFF07C160),
        minFileCount: 3,
      );

      final appIcon = Uint8List.fromList([1, 2, 3, 4]); // 模拟图标数据
      final card = RecommendationCard.fromConfig(
        config,
        fileCount: 50,
        appIcon: appIcon,
      );

      expect(card.type, RecommendationType.wechat);
      expect(card.fileCount, 50);
      expect(card.appIcon, isNotNull);
      expect(card.appIcon, appIcon);
    });

    test('直接创建卡片实例', () {
      const card = RecommendationCard(
        type: RecommendationType.memories,
        title: '时光记忆',
        icon: Icons.camera_alt,
        color: Color(0xFFFF9800),
        fileCount: 100,
      );

      expect(card.type, RecommendationType.memories);
      expect(card.title, '时光记忆');
      expect(card.fileCount, 100);
      expect(card.appKey, null); // 系统类卡片无 appKey
    });
  });

  group('RecommendationConfig 配置测试', () {
    test('应用类配置 - 微信', () {
      const config = RecommendationConfig(
        type: RecommendationType.wechat,
        title: '微信',
        icon: Icons.chat,
        color: Color(0xFF07C160),
        minFileCount: 3,
      );

      expect(config.isAppCard, true); // 是应用类卡片
      expect(config.appKey, 'wechat'); // 有对应的 appKey
      expect(config.minFileCount, 3);
    });

    test('应用类配置 - Telegram', () {
      const config = RecommendationConfig(
        type: RecommendationType.telegram,
        title: 'Telegram',
        icon: Icons.send,
        color: Color(0xFF0088CC),
        minFileCount: 3,
      );

      expect(config.isAppCard, true);
      expect(config.appKey, 'telegram');
    });

    test('系统类配置 - 时光记忆（托底卡片）', () {
      const config = RecommendationConfig(
        type: RecommendationType.memories,
        title: '时光记忆',
        icon: Icons.camera_alt,
        color: Color(0xFFFF9800),
        minFileCount: 0,
      );

      expect(config.isAppCard, false); // 不是应用类卡片
      expect(config.appKey, null); // 无 appKey
      expect(config.minFileCount, 0); // 托底卡片无要求
    });
  });

  group('默认推荐配置列表测试', () {
    test('配置列表包含9个卡片', () {
      expect(defaultRecommendationConfigs.length, 9);
    });

    test('配置列表按优先级排序', () {
      expect(defaultRecommendationConfigs[0].type, RecommendationType.wechat);
      expect(defaultRecommendationConfigs[1].type, RecommendationType.qq);
      expect(defaultRecommendationConfigs[2].type, RecommendationType.wps);
      expect(defaultRecommendationConfigs[3].type, RecommendationType.telegram);
      expect(defaultRecommendationConfigs[4].type, RecommendationType.dingtalk);
      expect(defaultRecommendationConfigs[5].type, RecommendationType.memories);
      expect(defaultRecommendationConfigs[6].type, RecommendationType.videos);
      expect(
          defaultRecommendationConfigs[7].type, RecommendationType.recordings);
      expect(
          defaultRecommendationConfigs[8].type, RecommendationType.largeFiles);
    });

    test('应用类配置都需要文件数量检测', () {
      final appConfigs =
          defaultRecommendationConfigs.where((c) => c.isAppCard).toList();

      expect(appConfigs.length, 5); // 微信、QQ、WPS、Telegram、钉钉
      expect(appConfigs.every((c) => c.appKey != null), true);
      expect(appConfigs.every((c) => c.minFileCount > 0), true);
    });

    test('托底卡片无应用检测要求', () {
      final fallbackConfigs =
          defaultRecommendationConfigs.where((c) => !c.isAppCard).toList();

      expect(fallbackConfigs.length, 4); // 时光记忆、生活剪影、声音记录、大文件
      expect(fallbackConfigs.every((c) => c.appKey == null), true);
      expect(fallbackConfigs.every((c) => c.minFileCount == 0), true);
    });

    test('每个配置都有必需字段', () {
      for (final config in defaultRecommendationConfigs) {
        expect(config.title.isNotEmpty, true, reason: '${config.type} 缺少标题');
        expect(config.icon, isNotNull, reason: '${config.type} 缺少图标');
        expect(config.color, isNotNull, reason: '${config.type} 缺少颜色');
      }
    });

    test('应用类型到 appKey 的映射正确', () {
      expect(recommendationTypeToAppKey[RecommendationType.wechat], 'wechat');
      expect(recommendationTypeToAppKey[RecommendationType.qq], 'qq');
      expect(
          recommendationTypeToAppKey[RecommendationType.telegram], 'telegram');
      expect(recommendationTypeToAppKey[RecommendationType.wps], 'wps');

      // 系统类型没有映射
      expect(
          recommendationTypeToAppKey.containsKey(RecommendationType.memories),
          false);
      expect(recommendationTypeToAppKey.containsKey(RecommendationType.videos),
          false);
    });
  });

  group('RecommendationType 枚举测试', () {
    test('枚举包含9个类型', () {
      expect(RecommendationType.values.length, 9);
    });

    test('枚举值正确', () {
      expect(RecommendationType.wechat, isNotNull);
      expect(RecommendationType.qq, isNotNull);
      expect(RecommendationType.wps, isNotNull);
      expect(RecommendationType.memories, isNotNull);
      expect(RecommendationType.videos, isNotNull);
      expect(RecommendationType.recordings, isNotNull);
      expect(RecommendationType.largeFiles, isNotNull);
    });
  });
}
