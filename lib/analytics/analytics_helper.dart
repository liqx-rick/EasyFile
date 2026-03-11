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

  /// Hash 校验工具进入
  static Future<void> logHashCheckerEnter() async {
    await AnalyticsManager.log('hash_checker_enter');
  }

  /// Hash 计算完成
  static Future<void> logHashCalculateFinish({
    required int fileSizeBytes,
    required int durationMs,
  }) async {
    await AnalyticsManager.log('hash_calculate_finish', params: {
      'file_size_bytes': fileSizeBytes,
      'duration_ms': durationMs,
    });
  }

  /// Hash 值复制
  static Future<void> logHashCopy(String hashType) async {
    await AnalyticsManager.log('hash_copy', params: {'hash_type': hashType});
  }

  /// Hash 计算失败
  static Future<void> logHashCalculateFail({
    required String errorType,
    required int fileSizeBytes,
  }) async {
    await AnalyticsManager.log('hash_calculate_fail', params: {
      'error_type': errorType,
      'file_size_bytes': fileSizeBytes,
    });
  }

  /// 文件夹大小计算工具进入
  static Future<void> logFolderSizeCalculatorEnter() async {
    await AnalyticsManager.log('folder_size_calculator_enter');
  }

  /// 文件夹大小计算完成
  static Future<void> logFolderSizeCalculateFinish({
    required int folderSizeBytes,
    required int fileCount,
    required int durationMs,
  }) async {
    await AnalyticsManager.log('folder_size_calculate_finish', params: {
      'folder_size_bytes': folderSizeBytes,
      'file_count': fileCount,
      'duration_ms': durationMs,
    });
  }

  /// 文件夹选择失败
  static Future<void> logFolderSelectFail(String reason) async {
    await AnalyticsManager.log('folder_select_fail', params: {
      'reason': reason,
    });
  }

  /// 文件夹大小计算失败
  static Future<void> logFolderSizeCalculateFail({
    required String errorType,
    required int scannedFiles,
  }) async {
    await AnalyticsManager.log('folder_size_calculate_fail', params: {
      'error_type': errorType,
      'scanned_files': scannedFiles,
    });
  }

  /// 文件类型识别器进入
  static Future<void> logFileTypeDetectorEnter() async {
    await AnalyticsManager.log('file_type_detector_enter');
  }

  /// 文件类型识别完成
  static Future<void> logFileTypeDetectFinish({
    required int fileCount,
  }) async {
    await AnalyticsManager.log('file_type_detect_finish', params: {
      'file_count': fileCount,
    });
  }

  /// 文件类型不匹配检出
  static Future<void> logFileTypeMismatchDetected({
    required int mismatchCount,
    required int totalCount,
  }) async {
    await AnalyticsManager.log('file_type_mismatch_detected', params: {
      'mismatch_count': mismatchCount,
      'total_count': totalCount,
      'mismatch_rate': (mismatchCount / totalCount * 100).toStringAsFixed(2),
    });
  }

  /// 二维码工具进入
  static Future<void> logQrCodeToolEnter() async {
    await AnalyticsManager.log('qr_code_tool_enter');
  }

  /// 二维码 Tab 切换
  static Future<void> logQrCodeTabSwitch(String tabName) async {
    await AnalyticsManager.log('qr_code_tab_switch', params: {
      'tab_name': tabName,
    });
  }

  /// 生成二维码
  static Future<void> logQrCodeGenerate({
    required int contentLength,
  }) async {
    await AnalyticsManager.log('qr_code_generate', params: {
      'content_length': contentLength,
    });
  }

  /// 生成二维码失败
  static Future<void> logQrCodeGenerateFail(String reason) async {
    await AnalyticsManager.log('qr_code_generate_fail', params: {
      'reason': reason,
    });
  }

  /// 保存二维码
  static Future<void> logQrCodeSave() async {
    await AnalyticsManager.log('qr_code_save');
  }

  /// 扫描二维码
  static Future<void> logQrCodeScan({
    required int contentLength,
  }) async {
    await AnalyticsManager.log('qr_code_scan', params: {
      'content_length': contentLength,
    });
  }

  /// 从图片扫描二维码
  static Future<void> logQrCodeScanFromImage({
    required int contentLength,
  }) async {
    await AnalyticsManager.log('qr_code_scan_from_image', params: {
      'content_length': contentLength,
    });
  }

  /// 二维码扫描失败
  static Future<void> logQrCodeScanFail({
    required String scanSource,
    required String errorType,
  }) async {
    await AnalyticsManager.log('qr_code_scan_fail', params: {
      'scan_source': scanSource,
      'error_type': errorType,
    });
  }

  /// 二维码内容类型识别
  static Future<void> logQrCodeContentType(String contentType) async {
    await AnalyticsManager.log('qr_code_content_type', params: {
      'content_type': contentType,
    });
  }

  /// 复制扫描结果
  static Future<void> logQrCodeCopyScanResult() async {
    await AnalyticsManager.log('qr_code_copy_scan_result');
  }

  /// 打开二维码链接
  static Future<void> logQrCodeOpenUrl() async {
    await AnalyticsManager.log('qr_code_open_url');
  }
}
