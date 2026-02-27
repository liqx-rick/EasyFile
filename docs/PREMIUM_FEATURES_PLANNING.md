# EasyFile 高级功能开放与会员预埋方案（v1.0 文档）

版本：v1.0（2026-02-14）
作者：产品/工程

## 目标
- 在 v1.0 中将若干“高级功能”标识并放入“功能设置”区块，所有用户在第一版中可免费使用。
- 在代码中预埋会员检查点与埋点，以便未来在 v2.0 引入会员体系时，能够平滑切换访问控制与付费提示。
- 保持对用户透明：界面以“⭐ 高级”标识功能，并在功能区放置说明，表明当前免费开放（或限时免费）。

## 核心原则
- 诚实透明：从一开始标识为“高级功能（免费开放）”，避免未来切换时的信任问题。
- 体验优先：v1.0 全部功能可用以培养用户习惯。
- 预埋接口：代码层提供 `PremiumFeatureManager`，第一版总是允许访问，未来切换时只需改其实现。
- 平滑过渡：未来若需收费，提前通知并提供试用/过渡机制。

## 受影响功能（示例）
- `推荐应用阈值`（主页推荐的文件数阈值） ⭐
- `重复文件扫描策略`（高级扫描最小文件大小、自定义范围） ⭐
- （可扩展）未来更多高级配置项

## UI 与文案方案
1. 在 `设置` 页面中将这些功能放入 `功能设置` 区块，功能项右侧显示 `⭐`（PremiumBadge）。
2. 在 `功能设置` 底部放置 `PremiumFeatureNotice`，文本示例：
   > ⭐ 标识的功能属于高级功能，提供更专业的文件管理能力。当前版本向所有用户免费开放，让您体验完整功能。
3. 单独子页面（如 `推荐应用阈值`、`重复文件扫描策略`）顶部亦展示 `⭐` 提示条。
4. 不在任何地方出现“会员”或“付费”字样于 v1.0 的主 UI（避免混淆），但保留代码注释和内部接口以便未来使用。

## 代码预埋（建议）
- 新增：`lib/core/services/premium_feature_manager.dart`（或相似位置）

示例（简化）：

```dart
class PremiumFeatureManager {
  static final PremiumFeatureManager _instance = PremiumFeatureManager._internal();
  factory PremiumFeatureManager() => _instance;
  PremiumFeatureManager._internal();

  static const String FEATURE_RECOMMENDATION_THRESHOLD = 'recommendation_threshold';
  static const String FEATURE_DUPLICATE_SCAN_ADVANCED = 'duplicate_scan_advanced';

  Future<bool> canUseFeature(String featureKey) async {
    // v1.0: 所有高级功能向所有用户开放
    return true;

    // v2.0: 替换为会员校验逻辑
    // final membershipService = locator<MembershipService>();
    // return await membershipService.hasAccess(featureKey);
  }

  bool isPremiumFeature(String featureKey) =>
      [FEATURE_RECOMMENDATION_THRESHOLD, FEATURE_DUPLICATE_SCAN_ADVANCED].contains(featureKey);

  Future<void> logFeatureUsage(String featureKey) async {
    // 记录使用，用于未来分析/计次/转化策略
    logger.i('Premium feature used: $featureKey');
  }
}
```

说明：第一版 `canUseFeature` 返回 `true`，未来只需改为依赖会员服务即可实现灰度/付费控制。

## 配置方案（app_config.yaml）
示例：

```yaml
feature:
  premium:
    enabled: true
    recommendation_threshold:
      min: 3
      max: 50
      default: 5
    duplicate_scan:
      min_size_presets: [100, 500, 1024, 10240] # KB
      default_min_size: 100
```

## 产品与文案策略
- 应用内文案：标注“⭐ 高级功能（当前免费开放）”。
- 发布说明：在 App Store / Play Store 描述中添加“高级功能当前版本免费开放”的短句。
- 后续收费策略须提前通知用户（建议至少提前 30 天）并提供早鸟或折扣。

## 迁移与未来收费方案要点
1. 预埋会员接口：`MembershipService`（返回是否为付费用户，可查询功能访问许可与剩余试用次数）。
2. 试用机制（可选）：为每个功能预设试用次数（例如 3 次），可在 `PremiumFeatureManager` 与远端/本地存储中管理计数。
3. 通知与补偿策略：若采收费策略，提前通知并给出补偿（例如免费延长、折扣或继续保留已创建的关键内容）。
4. 数据迁移：高级设置仍然保存在用户本地配置中（设置项与阈值），会员切换仅控制访问，不删除用户配置。

## 风险与缓解
- 风险：未来收费引发用户不满。缓解：透明公告、试用/早鸟、保留基础功能。
- 风险：功能未成熟导致投诉。缓解：添加体验期文案并持续修复问题。

## 实施计划（建议）
- Phase 1（1-2 天）
  - 新增 `PremiumFeatureManager` stub
  - 新增 `PremiumBadge` 与 `PremiumFeatureNotice` 组件
  - 更新 `settings_page.dart` 将项迁移到 `功能设置` 并加标识
- Phase 2（1 天）
  - 新建子页面 `DuplicateScanSettingsPage`，`RecommendationThresholdPage`
  - 持久化设置到现有配置存储
- Phase 3（0.5-1 天）
  - QA 与文案校对，更新 App Store 描述

## 审阅点（需要产品/PM 确认）
- 是否接受“高级功能标识 + 当前免费开放”的 UI 与文案？
- 是否需要试用次数机制在 v1.0 中同时上线？（建议先不启用）
- 是否需要把“会员”字样完全从用户可见界面中移除直到 v2.0？（建议：是）

---

> 下一步：如果您确认文档内容无误，我可以按计划在代码中添加 `PremiumFeatureManager`、`PremiumBadge`、并将 `settings_page.dart` 中相关条目迁移到 `功能设置`（并添加说明块）。

*文档已写入： `docs/PREMIUM_FEATURES_PLANNING.md`*
