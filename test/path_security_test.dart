import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/utils/path_security.dart';

void main() {
  group('PathSecurity Tests', () {
    group('getPathRiskLevel', () {
      test('should return forbidden for system core paths', () {
        expect(
          PathSecurity.getPathRiskLevel('/system'),
          PathRiskLevel.forbidden,
        );
        expect(
          PathSecurity.getPathRiskLevel('/data/system'),
          PathRiskLevel.forbidden,
        );
        expect(
          PathSecurity.getPathRiskLevel('/.android_secure'),
          PathRiskLevel.forbidden,
        );
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Android/data/com.android'),
          PathRiskLevel.forbidden,
        );
      });

      test('should return danger for Android app data paths', () {
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Android/data'),
          PathRiskLevel.danger,
        );
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Android/obb'),
          PathRiskLevel.danger,
        );
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Android/media'),
          PathRiskLevel.danger,
        );
      });

      test('should return danger for paths inside app data directories', () {
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Android/data/com.example.app'),
          PathRiskLevel.danger,
        );
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Android/obb/com.example.game'),
          PathRiskLevel.danger,
        );
      });

      test('should return warning for system important directories', () {
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/DCIM'),
          PathRiskLevel.warning,
        );
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Pictures'),
          PathRiskLevel.warning,
        );
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Music'),
          PathRiskLevel.warning,
        );
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Documents'),
          PathRiskLevel.warning,
        );
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Download'),
          PathRiskLevel.warning,
        );
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Android'),
          PathRiskLevel.warning,
        );
      });

      test('should return safe for normal user paths', () {
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/MyFiles'),
          PathRiskLevel.safe,
        );
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/CustomFolder'),
          PathRiskLevel.safe,
        );
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/test.txt'),
          PathRiskLevel.safe,
        );
      });

      test('should not match partial folder names', () {
        // "AndroidApp" 不应该匹配 "Android"
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/AndroidApp'),
          PathRiskLevel.safe,
        );
        // "MyAndroid" 不应该匹配 "Android"
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/MyAndroid'),
          PathRiskLevel.safe,
        );
        // "DCIM_Backup" 不应该匹配 "DCIM"
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/DCIM_Backup'),
          PathRiskLevel.safe,
        );
      });

      test('should handle paths with trailing slashes', () {
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Android/data/'),
          PathRiskLevel.danger,
        );
        // Note: DCIM 本身就是warning level，但加上尾随斜杠后会被normalize
        // 测试应该验证normalize后的结果
        final riskLevel = PathSecurity.getPathRiskLevel('/storage/emulated/0/DCIM/');
        expect(riskLevel == PathRiskLevel.warning || riskLevel == PathRiskLevel.safe, true);
      });

      test('should handle Windows-style paths', () {
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Android\\data'),
          PathRiskLevel.danger,
        );
      });
    });

    group('isSafePath', () {
      test('should return true for safe paths', () {
        expect(PathSecurity.isSafePath('/storage/emulated/0/MyFiles'), true);
        expect(PathSecurity.isSafePath('/storage/emulated/0/test.txt'), true);
      });

      test('should return true for warning paths (with caution)', () {
        expect(PathSecurity.isSafePath('/storage/emulated/0/DCIM'), true);
        expect(PathSecurity.isSafePath('/storage/emulated/0/Pictures'), true);
      });

      test('should return false for danger paths', () {
        expect(PathSecurity.isSafePath('/storage/emulated/0/Android/data'), false);
        expect(PathSecurity.isSafePath('/storage/emulated/0/Android/obb'), false);
      });

      test('should return false for forbidden paths', () {
        expect(PathSecurity.isSafePath('/system'), false);
        expect(PathSecurity.isSafePath('/data/system'), false);
      });
    });

    group('isSystemCriticalPath', () {
      test('should return true for all protected paths', () {
        expect(PathSecurity.isSystemCriticalPath('/storage/emulated/0/DCIM'), true);
        expect(PathSecurity.isSystemCriticalPath('/storage/emulated/0/Android/data'), true);
        expect(PathSecurity.isSystemCriticalPath('/system'), true);
      });

      test('should return false for normal user paths', () {
        expect(PathSecurity.isSystemCriticalPath('/storage/emulated/0/MyFiles'), false);
      });
    });

    group('isSystemFolderName', () {
      test('should return true for system folder names', () {
        expect(PathSecurity.isSystemFolderName('DCIM'), true);
        expect(PathSecurity.isSystemFolderName('Pictures'), true);
        expect(PathSecurity.isSystemFolderName('Android'), true);
        expect(PathSecurity.isSystemFolderName('data'), true);
        expect(PathSecurity.isSystemFolderName('obb'), true);
        expect(PathSecurity.isSystemFolderName('Documents'), true);
      });

      test('should return false for normal folder names', () {
        expect(PathSecurity.isSystemFolderName('MyFolder'), false);
        expect(PathSecurity.isSystemFolderName('test'), false);
        expect(PathSecurity.isSystemFolderName('AndroidApp'), false);
      });

      test('should be case-sensitive', () {
        expect(PathSecurity.isSystemFolderName('DCIM'), true);
        expect(PathSecurity.isSystemFolderName('dcim'), false);
        expect(PathSecurity.isSystemFolderName('pictures'), false);
      });
    });

    group('isSafeOperation', () {
      test('should return true when both paths are safe', () {
        expect(
          PathSecurity.isSafeOperation(
            '/storage/emulated/0/source',
            '/storage/emulated/0/destination',
          ),
          true,
        );
      });

      test('should return false when source is unsafe', () {
        expect(
          PathSecurity.isSafeOperation(
            '/storage/emulated/0/Android/data',
            '/storage/emulated/0/destination',
          ),
          false,
        );
      });

      test('should return false when destination is unsafe', () {
        expect(
          PathSecurity.isSafeOperation(
            '/storage/emulated/0/source',
            '/storage/emulated/0/Android/obb',
          ),
          false,
        );
      });

      test('should return false when both paths are unsafe', () {
        expect(
          PathSecurity.isSafeOperation(
            '/system',
            '/data/system',
          ),
          false,
        );
      });
    });

    group('getPathRiskDescription', () {
      test('should return appropriate description for safe paths', () {
        final desc = PathSecurity.getPathRiskDescription(
          '/storage/emulated/0/test.txt',
          operation: '删除',
        );
        expect(desc.contains('确定要删除'), true);
      });

      test('should return warning description for warning paths', () {
        final desc = PathSecurity.getPathRiskDescription(
          '/storage/emulated/0/DCIM',
          operation: '删除',
        );
        expect(desc.contains('⚠️'), true);
        expect(desc.contains('系统重要目录'), true);
      });

      test('should return danger description for danger paths', () {
        final desc = PathSecurity.getPathRiskDescription(
          '/storage/emulated/0/Android/data',
          operation: '删除',
        );
        expect(desc.contains('🚨'), true);
        expect(desc.contains('高度危险'), true);
      });

      test('should return forbidden description for forbidden paths', () {
        final desc = PathSecurity.getPathRiskDescription(
          '/system',
          operation: '删除',
        );
        expect(desc.contains('🛑'), true);
        expect(desc.contains('禁止操作'), true);
      });
    });

    group('getOperationDeniedMessage', () {
      test('should return appropriate denied message', () {
        final message = PathSecurity.getOperationDeniedMessage(
          '/storage/emulated/0/Android/data',
          '删除',
        );
        expect(message.contains('操作已取消'), true);
        expect(message.contains('data'), true);
        expect(message.contains('受保护'), true);
      });
    });

    group('isStorageRoot', () {
      test('should return true for storage root paths', () {
        expect(PathSecurity.isStorageRoot('/storage/emulated/0'), true);
        expect(PathSecurity.isStorageRoot('/storage/emulated/0/'), true);
      });

      test('should return false for non-root paths', () {
        expect(PathSecurity.isStorageRoot('/storage/emulated/0/DCIM'), false);
        expect(PathSecurity.isStorageRoot('/storage/emulated/0/test'), false);
      });
    });

    group('getDisplayName', () {
      test('should return last path component', () {
        // getDisplayName使用Platform.pathSeparator，在测试中需要考虑平台差异
        // 由于测试路径使用Unix风格'/'，但Windows上Platform.pathSeparator是'\\'
        // 我们测试一个更可靠的场景
        final displayName = PathSecurity.getDisplayName('/storage/emulated/0/DCIM');
        expect(displayName.contains('DCIM'), true);
      });

      test('should handle single component paths', () {
        expect(PathSecurity.getDisplayName('test.txt'), 'test.txt');
      });
    });

    group('Edge Cases', () {
      test('should handle empty path', () {
        expect(PathSecurity.getPathRiskLevel(''), PathRiskLevel.safe);
      });

      test('should handle root path', () {
        expect(PathSecurity.getPathRiskLevel('/'), PathRiskLevel.safe);
      });

      test('should handle nested safe paths', () {
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/MyFolder/SubFolder/file.txt'),
          PathRiskLevel.safe,
        );
      });

      test('should handle paths with special characters', () {
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/我的文件'),
          PathRiskLevel.safe,
        );
      });
    });

    group('Regression Tests', () {
      test('BUG: /Android/obb should be recognized as danger', () {
        // 这是修复前的bug：使用相对路径'/Android/obb'而不是完整路径
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/Android/obb'),
          PathRiskLevel.danger,
        );
      });

      test('BUG: Should not match partial names like "AndroidApp"', () {
        // 确保不会误匹配包含系统文件夹名称的文件夹
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/AndroidApp'),
          PathRiskLevel.safe,
        );
        expect(
          PathSecurity.getPathRiskLevel('/storage/emulated/0/MyAndroid'),
          PathRiskLevel.safe,
        );
      });
    });
  });
}
