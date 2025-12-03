import 'package:flutter_test/flutter_test.dart';
// import 'package:easyfile/core/services/junk_file_service.dart';  // 暂不测试Service本身
import 'package:easyfile/core/models/junk_file_scan_config.dart';
import 'package:easyfile/data/models/junk_file_item.dart';

// Helper functions to test private methods logic

/// 模拟 _isTempFile 方法逻辑
bool _isTempFileHelper(String lowerName) {
  final lower = lowerName.toLowerCase();
  return lower.endsWith('.tmp') ||
      lower.endsWith('.temp') ||
      lower.startsWith('tmp_') ||
      lower.startsWith('temp_') ||
      lower.contains('.tmp.') ||
      lower.contains('.temp.');
}

/// 模拟 _getMaxDepth 方法逻辑
int _getMaxDepthHelper(String path) {
  final lowerPath = path.toLowerCase();

  if (lowerPath.contains('android/data') || lowerPath.contains('android/obb')) {
    return 3;
  }

  if (lowerPath.contains('dcim') || lowerPath.contains('pictures')) {
    return 5;
  }

  return 10;
}

/// 模拟 _isExcluded 方法逻辑
bool _isExcludedHelper(String path, List<String> excludePaths) {
  if (excludePaths.isEmpty) return false;

  final lowerPath = path.toLowerCase();
  return excludePaths
      .any((exclude) => lowerPath.contains(exclude.toLowerCase()));
}

void main() {
  group('JunkFileService Tests', () {
    // 注意：由于 JunkFileService 依赖 FilePresenter 和 JunkFileCacheManager
    // 这里仅测试数据模型和辅助函数逻辑

    group('_isTempFile logic tests', () {
      test('should identify .tmp files', () {
        expect(_isTempFileHelper('file.tmp'), true);
        expect(_isTempFileHelper('document.tmp'), true);
        expect(_isTempFileHelper('FILE.TMP'), true); // 小写检查
      });

      test('should identify .temp files', () {
        expect(_isTempFileHelper('cache.temp'), true);
        expect(_isTempFileHelper('data.temp'), true);
        expect(_isTempFileHelper('CACHE.TEMP'), true);
      });

      test('should identify tmp_ prefix files', () {
        expect(_isTempFileHelper('tmp_12345'), true);
        expect(_isTempFileHelper('tmp_cache'), true);
        expect(_isTempFileHelper('TMP_FILE'), true);
      });

      test('should identify temp_ prefix files', () {
        expect(_isTempFileHelper('temp_download'), true);
        expect(_isTempFileHelper('temp_123'), true);
        expect(_isTempFileHelper('TEMP_DATA'), true);
      });

      test('should identify files with .tmp. in middle', () {
        expect(_isTempFileHelper('file.tmp.backup'), true);
        expect(_isTempFileHelper('data.tmp.old'), true);
      });

      test('should identify files with .temp. in middle', () {
        expect(_isTempFileHelper('file.temp.backup'), true);
        expect(_isTempFileHelper('data.temp.old'), true);
      });

      test('should NOT identify normal files', () {
        expect(_isTempFileHelper('document.pdf'), false);
        expect(_isTempFileHelper('image.jpg'), false);
        expect(_isTempFileHelper('video.mp4'), false);
        expect(_isTempFileHelper('template.docx'),
            false); // contains 'temp' but not temp file
        expect(_isTempFileHelper('temptation.txt'),
            false); // starts with 'temp' but not temp_
      });

      test('should NOT identify APK files as temp', () {
        expect(_isTempFileHelper('app.apk'), false);
        expect(_isTempFileHelper('installer.apk'), false);
      });
    });

    group('_getMaxDepth logic tests', () {
      test('should return 3 for android/data paths', () {
        expect(_getMaxDepthHelper('/storage/emulated/0/Android/data'), 3);
        expect(
            _getMaxDepthHelper('/storage/emulated/0/android/data/com.example'),
            3);
        expect(_getMaxDepthHelper('/STORAGE/ANDROID/DATA'), 3);
      });

      test('should return 3 for android/obb paths', () {
        expect(_getMaxDepthHelper('/storage/emulated/0/Android/obb'), 3);
        expect(
            _getMaxDepthHelper('/storage/emulated/0/android/obb/com.game'), 3);
      });

      test('should return 5 for DCIM paths', () {
        expect(_getMaxDepthHelper('/storage/emulated/0/DCIM'), 5);
        expect(_getMaxDepthHelper('/storage/emulated/0/DCIM/Camera'), 5);
        expect(_getMaxDepthHelper('/DCIM/Screenshots'), 5);
      });

      test('should return 5 for Pictures paths', () {
        expect(_getMaxDepthHelper('/storage/emulated/0/Pictures'), 5);
        expect(
            _getMaxDepthHelper('/storage/emulated/0/pictures/Screenshots'), 5);
      });

      test('should return 10 for other paths', () {
        expect(_getMaxDepthHelper('/storage/emulated/0/Download'), 10);
        expect(_getMaxDepthHelper('/storage/emulated/0/Documents'), 10);
        expect(_getMaxDepthHelper('/storage/emulated/0/Music'), 10);
        expect(_getMaxDepthHelper('/some/random/path'), 10);
      });
    });

    group('_isExcluded logic tests', () {
      test('should return false for empty exclude list', () {
        expect(_isExcludedHelper('/any/path', []), false);
      });

      test('should exclude paths matching exclude list', () {
        final excludes = ['system', 'android/data'];
        expect(_isExcludedHelper('/storage/system/app', excludes), true);
        expect(_isExcludedHelper('/storage/Android/data/app', excludes), true);
      });

      test('should NOT exclude paths not in exclude list', () {
        final excludes = ['system', 'android/data'];
        expect(_isExcludedHelper('/storage/Download', excludes), false);
        expect(_isExcludedHelper('/storage/Pictures', excludes), false);
      });

      test('should be case insensitive', () {
        final excludes = ['system'];
        expect(_isExcludedHelper('/storage/SYSTEM/app', excludes), true);
        expect(_isExcludedHelper('/storage/System/app', excludes), true);
      });
    });

    group('JunkFileScanConfig tests', () {
      test('should have correct default values with system exclude paths', () {
        const config = JunkFileScanConfig();
        expect(config.scanApk, true);
        expect(config.scanTempFiles, true);
        expect(config.scanEmptyFolders, true);
        expect(config.onlyInstalledApk, false); // 修复后的默认值
        expect(config.minTempFileDays, 7);

        // 验证默认排除路径（防止扫描系统目录）
        expect(config.excludePaths.length, 5);
        expect(config.excludePaths, contains('Android/data'));
        expect(config.excludePaths, contains('Android/obb'));
        expect(config.excludePaths, contains('Android/media'));
        expect(config.excludePaths, contains('.thumbnails'));
        expect(config.excludePaths, contains('lost+found'));
      });

      test('should serialize to JSON correctly', () {
        const config = JunkFileScanConfig(
          scanApk: false,
          minTempFileDays: 14,
          excludePaths: ['system', 'android/data'],
        );
        final json = config.toJson();
        expect(json['scanApk'], false);
        expect(json['minTempFileDays'], 14);
        expect(json['excludePaths'], ['system', 'android/data']);
      });

      test('should deserialize from JSON correctly', () {
        final json = {
          'scanApk': false,
          'scanTempFiles': true,
          'scanEmptyFolders': false,
          'onlyInstalledApk': true,
          'minTempFileDays': 14,
          'excludePaths': ['test'],
        };
        final config = JunkFileScanConfig.fromJson(json);
        expect(config.scanApk, false);
        expect(config.scanTempFiles, true);
        expect(config.scanEmptyFolders, false);
        expect(config.onlyInstalledApk, true);
        expect(config.minTempFileDays, 14);
        expect(config.excludePaths, ['test']);
      });

      test('should generate description correctly', () {
        const config = JunkFileScanConfig(
          scanApk: true,
          scanTempFiles: false,
          scanEmptyFolders: true,
          onlyInstalledApk: false,
          minTempFileDays: 10,
        );
        expect(
            config.description, 'APK:true(仅已装:false)|临时:false(10天+)|空文件夹:true');
      });

      test('should create copy with modified values', () {
        const original = JunkFileScanConfig();
        final modified = original.copyWith(
          scanApk: false,
          minTempFileDays: 14,
        );
        expect(modified.scanApk, false);
        expect(modified.minTempFileDays, 14);
        expect(modified.scanTempFiles, original.scanTempFiles); // unchanged
        expect(
            modified.scanEmptyFolders, original.scanEmptyFolders); // unchanged
      });

      test('should compare configs by description', () {
        const config1 = JunkFileScanConfig(minTempFileDays: 7);
        const config2 = JunkFileScanConfig(minTempFileDays: 7);
        const config3 = JunkFileScanConfig(minTempFileDays: 14);

        expect(config1 == config2, true);
        expect(config1 == config3, false);
        expect(config1.hashCode == config2.hashCode, true);
      });
    });

    group('JunkFileType extension tests', () {
      test('should have correct display names', () {
        expect(JunkFileType.apk.displayName, 'APK安装包');
        expect(JunkFileType.tempFile.displayName, '临时文件');
        expect(JunkFileType.emptyFolder.displayName, '空文件夹');
      });

      test('should have correct icons', () {
        expect(JunkFileType.apk.icon, '📦');
        expect(JunkFileType.tempFile.icon, '🗑️');
        expect(JunkFileType.emptyFolder.icon, '📂');
      });

      test('should have correct descriptions', () {
        expect(JunkFileType.apk.description, '已安装应用的安装包，可安全删除');
        expect(JunkFileType.tempFile.description, '应用产生的临时文件，可安全删除');
        expect(JunkFileType.emptyFolder.description, '空的文件夹，可安全删除');
      });
    });

    group('JunkFileItem tests', () {
      test('should create item correctly', () {
        final modified = DateTime(2024, 1, 1);
        final item = JunkFileItem(
          name: 'test.apk',
          path: '/storage/Download/test.apk',
          size: 1024 * 1024,
          type: JunkFileType.apk,
          modified: modified,
          packageName: 'com.example.app',
          isInstalled: true,
        );

        expect(item.name, 'test.apk');
        expect(item.path, '/storage/Download/test.apk');
        expect(item.size, 1024 * 1024);
        expect(item.type, JunkFileType.apk);
        expect(item.modified, modified);
        expect(item.packageName, 'com.example.app');
        expect(item.isInstalled, true);
      });

      test('should get parent directory name correctly', () {
        final item = JunkFileItem(
          name: 'test.tmp',
          path: '/storage/emulated/0/Download/test.tmp',
          size: 100,
          type: JunkFileType.tempFile,
          modified: DateTime.now(),
        );

        expect(item.parentDirectoryName, 'Download');
      });

      test('should handle root path parent directory', () {
        final item = JunkFileItem(
          name: 'test.tmp',
          path: '/test.tmp',
          size: 100,
          type: JunkFileType.tempFile,
          modified: DateTime.now(),
        );

        expect(item.parentDirectoryName, '');
      });

      test('should serialize to JSON correctly', () {
        final modified = DateTime(2024, 1, 1);
        final item = JunkFileItem(
          name: 'test.apk',
          path: '/storage/test.apk',
          size: 1024,
          type: JunkFileType.apk,
          modified: modified,
          packageName: 'com.example',
          isInstalled: true,
        );

        final json = item.toJson();
        expect(json['name'], 'test.apk');
        expect(json['path'], '/storage/test.apk');
        expect(json['size'], 1024);
        expect(json['type'], 'apk');
        expect(json['modified'], modified.toIso8601String());
        expect(json['packageName'], 'com.example');
        expect(json['isInstalled'], true);
      });

      test('should deserialize from JSON correctly', () {
        final json = {
          'name': 'test.tmp',
          'path': '/storage/test.tmp',
          'size': 2048,
          'type': 'tempFile',
          'modified': '2024-01-01T00:00:00.000',
          'packageName': null,
          'isInstalled': false,
        };

        final item = JunkFileItem.fromJson(json);
        expect(item.name, 'test.tmp');
        expect(item.path, '/storage/test.tmp');
        expect(item.size, 2048);
        expect(item.type, JunkFileType.tempFile);
        expect(item.packageName, null);
        expect(item.isInstalled, false);
      });
    });
  });
}
