import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/config/app_config.dart';
import 'package:easyfile/core/config/storage/mock_config_storage.dart';
import 'package:easyfile/data/models/file_category.dart';

void main() {
  group('AppConfig Tests', () {
    late MockConfigStorage mockStorage;

    setUp(() async {
      // 使用 Mock 存储，完全隔离 SharedPreferences
      mockStorage = MockConfigStorage();
      await AppConfig.instance.initialize(storage: mockStorage);
    });

    tearDown(() async {
      await AppConfig.instance.resetToDefaults();
    });

    group('FeatureConfig', () {
      test('should get default feature values', () {
        expect(AppConfig.instance.feature.isNewFilesEnabled, true);
        expect(AppConfig.instance.feature.isLargeFilesEnabled, true);
        expect(AppConfig.instance.feature.isDuplicateFilesEnabled, true);
        expect(AppConfig.instance.feature.isTrashEnabled, true);
        expect(AppConfig.instance.feature.isFavoritesEnabled, true);
      });

      test('should set feature flag', () async {
        // 设置功能开关
        await AppConfig.instance.feature.setFeature('new_files', enabled: false);
        
        // 验证已生效
        expect(AppConfig.instance.feature.isNewFilesEnabled, false);
      });

      test('should merge remote flags', () async {
        // 批量更新功能开关
        await AppConfig.instance.feature.mergeWith({
          'new_files': false,
          'large_files': false,
          'premium': true,
        });

        expect(AppConfig.instance.feature.isNewFilesEnabled, false);
        expect(AppConfig.instance.feature.isLargeFilesEnabled, false);
        expect(AppConfig.instance.feature.isPremiumEnabled, true);
      });

      test('should reset to defaults', () async {
        // 修改配置
        await AppConfig.instance.feature.setFeature('new_files', enabled: false);
        expect(AppConfig.instance.feature.isNewFilesEnabled, false);

        // 重置
        await AppConfig.instance.feature.reset();

        // 应该恢复默认值
        expect(AppConfig.instance.feature.isNewFilesEnabled, true);
      });
    });

    group('FileScanConfig', () {
      test('should get default scan config values', () {
        expect(AppConfig.instance.fileScan.largeFileThreshold, 50);
        expect(AppConfig.instance.fileScan.newFilesRetentionDays, 7);
        expect(AppConfig.instance.fileScan.trashRetentionDays, 7);
        expect(AppConfig.instance.fileScan.scanConcurrency, 4);
      });

      test('should set large file threshold', () async {
        await AppConfig.instance.fileScan.setLargeFileThreshold(100);
        expect(AppConfig.instance.fileScan.largeFileThreshold, 100);
      });

      test('should set new files retention days', () async {
        await AppConfig.instance.fileScan.setNewFilesRetentionDays(15);
        expect(AppConfig.instance.fileScan.newFilesRetentionDays, 15);
      });

      test('should set trash retention days with validation', () async {
        // 合法值
        await AppConfig.instance.fileScan.setTrashRetentionDays(15);
        expect(AppConfig.instance.fileScan.trashRetentionDays, 15);

        // 非法值应该抛出异常
        expect(
          () async => await AppConfig.instance.fileScan.setTrashRetentionDays(100),
          throwsArgumentError,
        );
      });

      test('should merge remote config', () async {
        await AppConfig.instance.fileScan.mergeWith({
          'large_file_threshold': 200,
          'new_files_retention': 30,
          'scan_concurrency': 8,
        });

        expect(AppConfig.instance.fileScan.largeFileThreshold, 200);
        expect(AppConfig.instance.fileScan.newFilesRetentionDays, 30);
        expect(AppConfig.instance.fileScan.scanConcurrency, 8);
      });
    });

    group('BuildConfig', () {
      test('should get environment info', () {
        // BuildConfig 不依赖存储，直接读取编译期常量
        expect(AppConfig.instance.build.packageName, 'com.guangqi.easyfile');
        expect(AppConfig.instance.build.appName, 'EasyFile');
        expect(AppConfig.instance.build.supportsAndroid, true);
        expect(AppConfig.instance.build.supportsIOS, false);
      });

      test('should identify debug mode', () {
        // 在测试环境下，isDebug 应该为 true
        expect(AppConfig.instance.build.isDebug, true);
      });
    });

    group('FileTypesConfig', () {
      test('should get default file extensions', () {
        // 验证图片扩展名
        final imageExts = AppConfig.instance.fileTypes.imageExtensions;
        expect(imageExts, contains('jpg'));
        expect(imageExts, contains('png'));
        expect(imageExts, contains('webp'));
        
        // 验证视频扩展名
        final videoExts = AppConfig.instance.fileTypes.videoExtensions;
        expect(videoExts, contains('mp4'));
        expect(videoExts, contains('avi'));
        
        // 验证音频扩展名
        final audioExts = AppConfig.instance.fileTypes.audioExtensions;
        expect(audioExts, contains('mp3'));
        expect(audioExts, contains('flac'));
      });

      test('should categorize file by extension', () {
        // 图片类型
        expect(
          AppConfig.instance.fileTypes.getCategoryByExtension('jpg'),
          FileCategory.image,
        );
        expect(
          AppConfig.instance.fileTypes.getCategoryByExtension('PNG'),
          FileCategory.image,
        );
        
        // 视频类型
        expect(
          AppConfig.instance.fileTypes.getCategoryByExtension('mp4'),
          FileCategory.video,
        );
        
        // 音频类型
        expect(
          AppConfig.instance.fileTypes.getCategoryByExtension('mp3'),
          FileCategory.audio,
        );
        
        // 文档类型
        expect(
          AppConfig.instance.fileTypes.getCategoryByExtension('pdf'),
          FileCategory.document,
        );
        
        // 压缩包类型
        expect(
          AppConfig.instance.fileTypes.getCategoryByExtension('zip'),
          FileCategory.archive,
        );
        
        // APK 类型
        expect(
          AppConfig.instance.fileTypes.getCategoryByExtension('apk'),
          FileCategory.apk,
        );
        
        // 未知类型
        expect(
          AppConfig.instance.fileTypes.getCategoryByExtension('unknown'),
          FileCategory.other,
        );
      });

      test('should support premium file types', () {
        // 默认情况下，会员扩展名列表为空
        expect(AppConfig.instance.fileTypes.premiumImageExtensions, isEmpty);
        
        // 模拟远程配置开启会员格式
        mockStorage.setString('premium_image_extensions', 'psd,ai,sketch');
        
        // 重新初始化配置
        final fileTypes = AppConfig.instance.fileTypes;
        expect(fileTypes.premiumImageExtensions, ['psd', 'ai', 'sketch']);
      });

      test('should get all supported extensions', () {
        final allExts = AppConfig.instance.fileTypes.getAllSupportedExtensions();
        
        // 应包含基础类型
        expect(allExts, contains('jpg'));
        expect(allExts, contains('mp4'));
        expect(allExts, contains('mp3'));
        expect(allExts, contains('pdf'));
        
        // 不包含会员格式（默认）
        expect(allExts, isNot(contains('psd')));
      });

      test('should check if extension requires premium', () {
        // 默认基础格式不需要会员
        expect(AppConfig.instance.fileTypes.requiresPremium('jpg'), false);
        expect(AppConfig.instance.fileTypes.requiresPremium('mp4'), false);
        
        // 模拟配置会员格式
        mockStorage.setString('premium_image_extensions', 'psd,ai');
        
        // 会员格式需要权限
        expect(AppConfig.instance.fileTypes.requiresPremium('psd'), true);
        expect(AppConfig.instance.fileTypes.requiresPremium('ai'), true);
      });

      test('should merge remote file type config', () async {
        // 远程配置添加新的文件类型
        await AppConfig.instance.fileTypes.mergeWith({
          'image_extensions': 'jpg,png,avif,jpeg-xl',
          'premium_image_extensions': 'psd,ai,sketch',
        });

        // 验证已更新
        expect(mockStorage.getString('image_extensions'), 'jpg,png,avif,jpeg-xl');
        expect(mockStorage.getString('premium_image_extensions'), 'psd,ai,sketch');
      });
    });
  });
}
