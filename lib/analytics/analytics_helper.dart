import 'package:easyfile/analytics/analytics_manager.dart';

/// 埋点辅助类 - 封装常用的埋点事件
class AnalyticsHelper {
  /// 扫描开始
  static Future<void> logScanStart(String scanType) async {
    await AnalyticsManager.log('scan_start', params: {'type': scanType});
  }

  /// 扫描完成
  static Future<void> logScanFinish({
    required String scanType,
    required int durationMs,
    required int itemCount,
    double? totalSizeMb,
  }) async {
    await AnalyticsManager.log('scan_finish', params: {
      'type': scanType,
      'duration_ms': durationMs,
      'item_count': itemCount,
      if (totalSizeMb != null) 'total_size_mb': totalSizeMb,
    });
  }

  /// 扫描取消
  static Future<void> logScanCancel(String scanType) async {
    await AnalyticsManager.log('scan_cancel', params: {'type': scanType});
  }

  /// 清理操作
  static Future<void> logCleanAction({
    required String cleanType,
    required int itemCount,
    required double sizeMb,
  }) async {
    await AnalyticsManager.log('clean_action', params: {
      'type': cleanType,
      'item_count': itemCount,
      'size_mb': sizeMb,
    });
  }

  /// 清理确认
  static Future<void> logCleanConfirm(String cleanType) async {
    await AnalyticsManager.log('clean_confirm', params: {'type': cleanType});
  }

  /// 清理成功
  static Future<void> logCleanSuccess(double freedMb) async {
    await AnalyticsManager.log('clean_success', params: {'freed_mb': freedMb});
  }

  /// 分类页面进入
  static Future<void> logCategoryEnter(String category) async {
    await AnalyticsManager.log('category_enter', params: {'category': category});
  }

  /// 文件浏览进入
  static Future<void> logFileBrowseEnter(String entryPoint) async {
    await AnalyticsManager.log('file_browse_enter', params: {'entry_point': entryPoint});
  }

  /// 文件操作
  static Future<void> logFileBrowseAction(String action) async {
    await AnalyticsManager.log('file_browse_action', params: {'action': action});
  }

  /// 隐私空间进入
  static Future<void> logPrivacySpaceEnter(String entryPoint) async {
    await AnalyticsManager.log('privacy_space_enter', params: {'entry_point': entryPoint});
  }

  /// 隐私空间认证
  static Future<void> logPrivacySpaceAuth(String authMethod, bool success) async {
    await AnalyticsManager.log('privacy_space_auth', params: {
      'auth_method': authMethod,
      'success': success,
    });
  }

  /// 隐私文件添加
  static Future<void> logPrivacyFileAdd(String fileType, int fileCount) async {
    await AnalyticsManager.log('privacy_file_add', params: {
      'file_type': fileType,
      'file_count': fileCount,
    });
  }

  /// 隐私文件移出
  static Future<void> logPrivacyFileRemove() async {
    await AnalyticsManager.log('privacy_file_remove');
  }

  /// 隐私空间锁定
  static Future<void> logPrivacySpaceLock() async {
    await AnalyticsManager.log('privacy_space_lock');
  }

  /// 压缩包管理进入
  static Future<void> logArchiveManagementEnter() async {
    await AnalyticsManager.log('archive_management_enter');
  }

  /// 压缩包扫描开始
  static Future<void> logArchiveScanStart() async {
    await AnalyticsManager.log('archive_scan_start');
  }

  /// 压缩包扫描完成
  static Future<void> logArchiveScanFinish({
    required int archiveCount,
    required double totalSizeMb,
    required int durationMs,
  }) async {
    await AnalyticsManager.log('archive_scan_finish', params: {
      'archive_count': archiveCount,
      'total_size_mb': totalSizeMb,
      'duration_ms': durationMs,
    });
  }

  /// 压缩包浏览
  static Future<void> logArchiveBrowse(String format) async {
    await AnalyticsManager.log('archive_browse', params: {'format': format});
  }

  /// 压缩包解压
  static Future<void> logArchiveExtract(String format, double sizeMb, bool extractAll) async {
    await AnalyticsManager.log('archive_extract', params: {
      'format': format,
      'size_mb': sizeMb,
      'extract_all': extractAll,
    });
  }

  /// 压缩包密码检测
  static Future<void> logArchivePasswordCheck(bool hasPassword) async {
    await AnalyticsManager.log('archive_password_check', params: {
      'has_password': hasPassword,
    });
  }

  /// 快捷访问进入
  static Future<void> logQuickAccessEnter(String entryPoint) async {
    await AnalyticsManager.log('quick_access_enter', params: {'entry_point': entryPoint});
  }

  /// 快捷访问文件夹点击
  static Future<void> logQuickAccessFolderClick({
    required String folderType,
    required String folderName,
    required bool isPinned,
  }) async {
    await AnalyticsManager.log('quick_access_folder_click', params: {
      'folder_type': folderType,
      'folder_name': folderName,
      'is_pinned': isPinned,
    });
  }

  /// 快捷访问文件夹添加
  static Future<void> logQuickAccessFolderAdd(String folderType, String source) async {
    await AnalyticsManager.log('quick_access_folder_add', params: {
      'folder_type': folderType,
      'source': source,
    });
  }

  /// 快捷访问文件夹移除
  static Future<void> logQuickAccessFolderRemove(String folderType) async {
    await AnalyticsManager.log('quick_access_folder_remove', params: {'folder_type': folderType});
  }

  /// 回收站查看
  static Future<void> logTrashView() async {
    await AnalyticsManager.log('trash_view');
  }

  /// 回收站恢复
  static Future<void> logTrashRestore() async {
    await AnalyticsManager.log('trash_restore');
  }

  /// 回收站永久删除
  static Future<void> logTrashPermanentDelete(int itemCount) async {
    await AnalyticsManager.log('trash_permanent_delete', params: {'item_count': itemCount});
  }

  /// 应用管理进入
  static Future<void> logAppManagementEnter() async {
    await AnalyticsManager.log('app_management_enter');
  }

  /// 应用设置打开（用户可能卸载应用）
  static Future<void> logAppSettingsOpen(String packageName) async {
    await AnalyticsManager.log('app_settings_open', params: {'package_name': packageName});
  }

  /// 设置页面进入
  static Future<void> logSettingsEnter() async {
    await AnalyticsManager.log('settings_enter');
  }

  /// 设置修改
  static Future<void> logSettingsChange(String settingKey, dynamic newValue) async {
    await AnalyticsManager.log('settings_change', params: {
      'setting_key': settingKey,
      'new_value': newValue.toString(),
    });
  }

  /// 大文件扫描进入
  static Future<void> logLargeFilesEnter() async {
    await AnalyticsManager.log('large_files_enter');
  }

  /// 重复文件扫描进入
  static Future<void> logDuplicateFilesEnter() async {
    await AnalyticsManager.log('duplicate_files_enter');
  }

  /// 垃圾清理进入
  static Future<void> logJunkFilesEnter() async {
    await AnalyticsManager.log('junk_files_enter');
  }

  /// APK管理进入
  static Future<void> logApkManagementEnter() async {
    await AnalyticsManager.log('apk_management_enter');
  }

  /// 快捷访问重命名
  static Future<void> logQuickAccessRename(String folderType) async {
    await AnalyticsManager.log('quick_access_rename', params: {'folder_type': folderType});
  }

  /// 快捷访问卡片点击
  static Future<void> logQuickAccessCardClick(String cardType) async {
    await AnalyticsManager.log('quick_access_card_click', params: {'card_type': cardType});
  }

  /// 首页推荐内容查看
  static Future<void> logHomeRecommendView(String contentType, int itemCount) async {
    await AnalyticsManager.log('home_recommend_view', params: {
      'content_type': contentType,
      'item_count': itemCount,
    });
  }
}
