/// 缓存配置
///
/// 管理应用的各类缓存策略和大小限制
class CacheConfig {
  // ==================== 压缩包预览缓存 ====================

  /// 压缩包预览缓存总大小限制（MB）
  final int archivePreviewCacheSizeMB = 500;

  /// 压缩包预览缓存过期时间（天）
  final int archivePreviewCacheExpireDays = 7;

  /// 单个文件最大预览大小（MB）
  final int archivePreviewMaxFileSizeMB = 200;

  // ==================== 未来扩展 ====================
  // 可在此添加其他缓存配置，如：
  // - 图片缩略图缓存
  // - 视频预览缓存
  // - 音频波形缓存等
}
