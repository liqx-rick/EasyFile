import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/services/file_display_settings_service.dart';

void main() {
  group('FileDisplaySettingsService 测试', () {
    group('隐藏文件判断测试', () {
      test('应该正确识别隐藏文件（以.开头）', () {
        expect(FileDisplaySettingsService.isHiddenFile('.hidden'), true);
        expect(FileDisplaySettingsService.isHiddenFile('.gitignore'), true);
        expect(FileDisplaySettingsService.isHiddenFile('.DS_Store'), true);
        expect(FileDisplaySettingsService.isHiddenFile('.android'), true);
      });

      test('应该正确识别非隐藏文件', () {
        expect(FileDisplaySettingsService.isHiddenFile('normal.txt'), false);
        expect(FileDisplaySettingsService.isHiddenFile('Documents'), false);
        expect(FileDisplaySettingsService.isHiddenFile('photo.jpg'), false);
        expect(FileDisplaySettingsService.isHiddenFile('test.hidden'), false);
      });

      test('边界情况 - 空字符串和特殊字符', () {
        expect(FileDisplaySettingsService.isHiddenFile(''), false);
        expect(FileDisplaySettingsService.isHiddenFile('.'), true);
        expect(FileDisplaySettingsService.isHiddenFile('..'), true);
      });
    });

    group('系统文件夹判断测试', () {
      test('应该正确识别系统文件夹', () {
        expect(FileDisplaySettingsService.isSystemFolder('Android'), true);
        expect(FileDisplaySettingsService.isSystemFolder('lost+found'), true);
        expect(FileDisplaySettingsService.isSystemFolder('.thumbnails'), true);
        expect(FileDisplaySettingsService.isSystemFolder('.cache'), true);
        expect(FileDisplaySettingsService.isSystemFolder('.trash'), true);
      });

      test('应该正确识别非系统文件夹', () {
        expect(FileDisplaySettingsService.isSystemFolder('Documents'), false);
        expect(FileDisplaySettingsService.isSystemFolder('DCIM'), false);
        expect(FileDisplaySettingsService.isSystemFolder('Download'), false);
        expect(FileDisplaySettingsService.isSystemFolder('Pictures'), false);
      });

      test('大小写不敏感性测试', () {
        // 应该是大小写不敏感的
        expect(FileDisplaySettingsService.isSystemFolder('android'), true);
        expect(FileDisplaySettingsService.isSystemFolder('ANDROID'), true);
        expect(FileDisplaySettingsService.isSystemFolder('Android'), true);
        expect(FileDisplaySettingsService.isSystemFolder('.CACHE'), true);
      });
    });

    group('系统文件判断测试', () {
      test('应该正确识别系统文件', () {
        expect(FileDisplaySettingsService.isSystemFile('.nomedia'), true);
        expect(FileDisplaySettingsService.isSystemFile('thumbs.db'), true);
        expect(FileDisplaySettingsService.isSystemFile('desktop.ini'), true);
        expect(FileDisplaySettingsService.isSystemFile('.ds_store'), true);
      });

      test('应该正确识别非系统文件', () {
        expect(FileDisplaySettingsService.isSystemFile('photo.jpg'), false);
        expect(FileDisplaySettingsService.isSystemFile('document.pdf'), false);
        expect(FileDisplaySettingsService.isSystemFile('readme.txt'), false);
      });

      test('大小写不敏感性测试', () {
        // 系统文件判断应该不区分大小写
        expect(FileDisplaySettingsService.isSystemFile('Thumbs.db'), true);
        expect(FileDisplaySettingsService.isSystemFile('THUMBS.DB'), true);
        expect(FileDisplaySettingsService.isSystemFile('Desktop.ini'), true);
        expect(FileDisplaySettingsService.isSystemFile('.DS_Store'), true);
      });
    });
  });
}
