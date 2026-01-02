import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/core/config/file_types_config.dart';
import 'package:easyfile/core/config/storage/mock_config_storage.dart';
import 'package:easyfile/data/models/file_category.dart';

void main() {
  group('FileTypesConfig', () {
    late FileTypesConfig config;

    setUp(() {
      config = FileTypesConfig(storage: MockConfigStorage());
    });

    group('基础文件类型', () {
      test('should have image extensions', () {
        final extensions = config.imageExtensions;
        expect(extensions, isNotEmpty);
        expect(extensions, contains('jpg'));
        expect(extensions, contains('jpeg'));
        expect(extensions, contains('png'));
        expect(extensions, contains('gif'));
        expect(extensions, contains('webp'));
        expect(extensions, contains('bmp'));
      });

      test('should have video extensions', () {
        final extensions = config.videoExtensions;
        expect(extensions, isNotEmpty);
        expect(extensions, contains('mp4'));
        expect(extensions, contains('avi'));
        expect(extensions, contains('mkv'));
        expect(extensions, contains('mov'));
      });

      test('should have audio extensions', () {
        final extensions = config.audioExtensions;
        expect(extensions, isNotEmpty);
        expect(extensions, contains('mp3'));
        expect(extensions, contains('flac'));
        expect(extensions, contains('wav'));
        expect(extensions, contains('aac'));
      });

      test('should have document extensions', () {
        final extensions = config.documentExtensions;
        expect(extensions, isNotEmpty);
        expect(extensions, contains('pdf'));
        expect(extensions, contains('doc'));
        expect(extensions, contains('docx'));
        expect(extensions, contains('txt'));
      });

      test('should have archive extensions', () {
        final extensions = config.archiveExtensions;
        expect(extensions, isNotEmpty);
        expect(extensions, contains('zip'));
        expect(extensions, contains('rar'));
        expect(extensions, contains('7z'));
      });

      test('should have apk extension', () {
        final extensions = config.apkExtensions;
        expect(extensions, contains('apk'));
      });

      test('all extension lists should be non-empty', () {
        expect(config.imageExtensions.isNotEmpty, true);
        expect(config.videoExtensions.isNotEmpty, true);
        expect(config.audioExtensions.isNotEmpty, true);
        expect(config.documentExtensions.isNotEmpty, true);
        expect(config.archiveExtensions.isNotEmpty, true);
        expect(config.apkExtensions.isNotEmpty, true);
      });
    });

    group('分类识别', () {
      test('should recognize image extensions', () {
        expect(config.getCategoryByExtension('jpg'), FileCategory.image);
        expect(config.getCategoryByExtension('JPG'), FileCategory.image);
        expect(config.getCategoryByExtension('png'), FileCategory.image);
        expect(config.getCategoryByExtension('PNG'), FileCategory.image);
        expect(config.getCategoryByExtension('webp'), FileCategory.image);
        expect(config.getCategoryByExtension('gif'), FileCategory.image);
      });

      test('should recognize video extensions', () {
        expect(config.getCategoryByExtension('mp4'), FileCategory.video);
        expect(config.getCategoryByExtension('MP4'), FileCategory.video);
        expect(config.getCategoryByExtension('mkv'), FileCategory.video);
        expect(config.getCategoryByExtension('avi'), FileCategory.video);
        expect(config.getCategoryByExtension('mov'), FileCategory.video);
      });

      test('should recognize audio extensions', () {
        expect(config.getCategoryByExtension('mp3'), FileCategory.audio);
        expect(config.getCategoryByExtension('MP3'), FileCategory.audio);
        expect(config.getCategoryByExtension('flac'), FileCategory.audio);
        expect(config.getCategoryByExtension('wav'), FileCategory.audio);
      });

      test('should recognize document extensions', () {
        expect(config.getCategoryByExtension('pdf'), FileCategory.document);
        expect(config.getCategoryByExtension('PDF'), FileCategory.document);
        expect(config.getCategoryByExtension('docx'), FileCategory.document);
        expect(config.getCategoryByExtension('txt'), FileCategory.document);
      });

      test('should recognize archive extensions', () {
        expect(config.getCategoryByExtension('zip'), FileCategory.archive);
        expect(config.getCategoryByExtension('ZIP'), FileCategory.archive);
        expect(config.getCategoryByExtension('rar'), FileCategory.archive);
        expect(config.getCategoryByExtension('7z'), FileCategory.archive);
      });

      test('should recognize apk extension', () {
        expect(config.getCategoryByExtension('apk'), FileCategory.apk);
        expect(config.getCategoryByExtension('APK'), FileCategory.apk);
      });

      test('should return other for unknown extension', () {
        expect(config.getCategoryByExtension('xyz'), FileCategory.other);
        expect(config.getCategoryByExtension('unknown'), FileCategory.other);
        expect(config.getCategoryByExtension(''), FileCategory.other);
      });

      test('should be case-insensitive', () {
        expect(
          config.getCategoryByExtension('JPG'),
          config.getCategoryByExtension('jpg'),
        );
        expect(
          config.getCategoryByExtension('Mp4'),
          config.getCategoryByExtension('mp4'),
        );
      });
    });

    group('会员功能', () {
      test('should check if premium required', () {
        // 基础格式不需要会员
        expect(config.requiresPremium('jpg'), false);
        expect(config.requiresPremium('mp4'), false);
        expect(config.requiresPremium('pdf'), false);
      });

      test('premium extensions should be empty by default', () {
        // 目前没有会员格式
        expect(config.premiumImageExtensions.isEmpty, true);
        expect(config.premiumVideoExtensions.isEmpty, true);
        expect(config.premiumAudioExtensions.isEmpty, true);
      });

      test('should get all supported extensions', () {
        final all = config.getAllSupportedExtensions(includePremium: false);
        expect(all, isNotEmpty);
        expect(all, contains('jpg'));
        expect(all, contains('mp4'));
        expect(all, contains('mp3'));
        expect(all, contains('pdf'));
        expect(all, contains('zip'));
        expect(all, contains('apk'));
      });

      test('getAllSupportedExtensions should not have duplicates', () {
        final all = config.getAllSupportedExtensions(includePremium: false);
        final unique = all.toSet();
        expect(all.length, unique.length);
      });
    });

    group('扩展名格式验证', () {
      test('all extensions should be lowercase', () {
        final allExtensions = [
          ...config.imageExtensions,
          ...config.videoExtensions,
          ...config.audioExtensions,
          ...config.documentExtensions,
          ...config.archiveExtensions,
          ...config.apkExtensions,
        ];

        for (final ext in allExtensions) {
          expect(ext, ext.toLowerCase());
        }
      });

      test('extensions should not contain dots', () {
        final allExtensions = [
          ...config.imageExtensions,
          ...config.videoExtensions,
          ...config.audioExtensions,
          ...config.documentExtensions,
          ...config.archiveExtensions,
          ...config.apkExtensions,
        ];

        for (final ext in allExtensions) {
          expect(ext.contains('.'), false);
        }
      });

      test('extensions should not be empty strings', () {
        final allExtensions = [
          ...config.imageExtensions,
          ...config.videoExtensions,
          ...config.audioExtensions,
          ...config.documentExtensions,
          ...config.archiveExtensions,
          ...config.apkExtensions,
        ];

        for (final ext in allExtensions) {
          expect(ext.isNotEmpty, true);
        }
      });
    });

    group('常见文件格式覆盖', () {
      test('should support common image formats', () {
        final commonFormats = ['jpg', 'png', 'gif', 'webp'];
        for (final format in commonFormats) {
          expect(config.imageExtensions, contains(format));
        }
      });

      test('should support common video formats', () {
        final commonFormats = ['mp4', 'avi', 'mkv'];
        for (final format in commonFormats) {
          expect(config.videoExtensions, contains(format));
        }
      });

      test('should support common audio formats', () {
        final commonFormats = ['mp3', 'flac', 'wav'];
        for (final format in commonFormats) {
          expect(config.audioExtensions, contains(format));
        }
      });

      test('should support common document formats', () {
        final commonFormats = ['pdf', 'doc', 'docx', 'txt'];
        for (final format in commonFormats) {
          expect(config.documentExtensions, contains(format));
        }
      });
    });

    group('边界情况', () {
      test('should handle empty extension', () {
        expect(config.getCategoryByExtension(''), FileCategory.other);
      });

      test('should handle null-like strings', () {
        expect(config.getCategoryByExtension('null'), FileCategory.other);
        expect(config.getCategoryByExtension('undefined'), FileCategory.other);
      });

      test('should handle special characters', () {
        expect(config.getCategoryByExtension('!@#'), FileCategory.other);
        expect(config.getCategoryByExtension('***'), FileCategory.other);
      });

      test('should handle very long extension', () {
        final longExt = 'x' * 1000;
        expect(config.getCategoryByExtension(longExt), FileCategory.other);
      });
    });

    group('远程配置合并', () {
      test('should have mergeWith method', () async {
        // 验证方法存在（即使当前可能是空实现）
        expect(
          () async => await config.mergeWith({}),
          returnsNormally,
        );
      });
    });
  });
}
