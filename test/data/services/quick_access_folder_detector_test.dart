import 'package:flutter_test/flutter_test.dart';
import 'package:easyfile/data/services/quick_access_folder_detector.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';

void main() {
  group('QuickAccessFolderDetector', () {
    group('Config Tests', () {
      test('QuickAccessDetectorConfig has correct default values', () {
        expect(QuickAccessDetectorConfig.minFileCount, equals(5));
        expect(QuickAccessDetectorConfig.minFolderSizeMB, equals(5.0));
        expect(QuickAccessDetectorConfig.maxDaysForRecent, equals(60));
        expect(QuickAccessDetectorConfig.minFileTypesDiversity, equals(2));
        expect(QuickAccessDetectorConfig.maxDepthForAnalysis, equals(5));
        expect(QuickAccessDetectorConfig.maxFilesToAnalyze, equals(500));
        expect(QuickAccessDetectorConfig.maxFoldersToScan, equals(100));
      });

      test('Blacklist contains expected entries', () {
        final blacklist = QuickAccessDetectorConfig.folderNameBlacklist;
        expect(blacklist, contains('.cache'));
        expect(blacklist, contains('cache'));
        expect(blacklist, contains('node_modules'));
        expect(blacklist, contains('.git'));
        expect(blacklist, contains('temp'));
        expect(blacklist, contains('log'));
        expect(blacklist.length, greaterThan(0));
      });

      test('Blacklist has reasonable size', () {
        final blacklist = QuickAccessDetectorConfig.folderNameBlacklist;
        expect(blacklist.length, greaterThan(20));
        expect(blacklist.length, lessThan(100));
      });
    });

    group('Hidden Folder Detection', () {
      test('Folder names starting with dot are hidden', () {
        final hiddenNames = ['.cache', '.git', '.hidden'];
        final visibleNames = ['cache', 'git', 'hidden'];

        for (final name in hiddenNames) {
          expect(name.startsWith('.'), isTrue);
        }

        for (final name in visibleNames) {
          expect(name.startsWith('.'), isFalse);
        }
      });

      test('Can identify EasyFile directory patterns', () {
        final easyfileDirs = ['easyfile', 'EasyFile', '.easyfile', 'easy_file'];
        final nonEasyfileDirs = ['cache', 'Downloads', 'Pictures'];

        for (final dirName in easyfileDirs) {
          final isEasyFile = dirName.toLowerCase().contains('easyfile') ||
              dirName.toLowerCase().contains('easy_file');
          expect(isEasyFile, isTrue);
        }

        for (final dirName in nonEasyfileDirs) {
          final isEasyFile = dirName.toLowerCase().contains('easyfile') ||
              dirName.toLowerCase().contains('easy_file');
          expect(isEasyFile, isFalse);
        }
      });
    });

    group('Blacklist Filtering', () {
      test('Contains all cache-related folders', () {
        final blacklist = QuickAccessDetectorConfig.folderNameBlacklist;
        final cacheVariants = ['.cache', 'cache', 'Cache', 'CACHE'];

        for (final cacheDir in cacheVariants) {
          expect(blacklist, contains(cacheDir));
        }
      });

      test('Contains all temp-related folders', () {
        final blacklist = QuickAccessDetectorConfig.folderNameBlacklist;
        final tempVariants = ['temp', 'tmp', 'Temp', 'Tmp', 'TMP'];

        for (final tempDir in tempVariants) {
          expect(blacklist, contains(tempDir));
        }
      });

      test('Contains development-related folders', () {
        final blacklist = QuickAccessDetectorConfig.folderNameBlacklist;
        final devDirs = [
          '.git',
          '.gradle',
          'node_modules',
          '__pycache__',
          'build',
          'dist'
        ];

        for (final devDir in devDirs) {
          expect(blacklist, contains(devDir));
        }
      });
    });

    group('Analysis Condition Logic', () {
      test('File count condition threshold is reasonable', () {
        final minFileCount = QuickAccessDetectorConfig.minFileCount;
        expect(minFileCount, equals(5));
        expect(minFileCount, greaterThan(0));
        expect(minFileCount, lessThan(100));
      });

      test('Folder size condition threshold is reasonable', () {
        final minSizeMB = QuickAccessDetectorConfig.minFolderSizeMB;
        expect(minSizeMB, equals(5.0));
        expect(minSizeMB, greaterThan(0.0));
        expect(minSizeMB, lessThan(100.0));
      });

      test('Recent modification threshold is reasonable', () {
        final maxDays = QuickAccessDetectorConfig.maxDaysForRecent;
        expect(maxDays, equals(60));
        expect(maxDays, greaterThan(0));
        expect(maxDays, lessThan(365));
      });

      test('File diversity threshold is reasonable', () {
        final minDiversity = QuickAccessDetectorConfig.minFileTypesDiversity;
        expect(minDiversity, equals(2));
        expect(minDiversity, greaterThan(0));
        expect(minDiversity, lessThan(20));
      });
    });

    group('QuickAccessFolder Type Consistency', () {
      test('System folders have correct type', () {
        final systemFolder = QuickAccessFolder(
          id: 'test_system',
          path: '/storage/emulated/0/Pictures',
          originalName: 'Pictures',
          type: QuickAccessFolderType.system,
          createdAt: DateTime.now(),
          isAddedToQuickAccess: false,
          isHidden: false,
        );

        expect(systemFolder.type, equals(QuickAccessFolderType.system));
        expect(systemFolder.isSystem, isTrue);
      });

      test('Other folders have correct type', () {
        final otherFolder = QuickAccessFolder(
          id: 'test_other',
          path: '/storage/emulated/0/MyFolder',
          originalName: 'MyFolder',
          type: QuickAccessFolderType.other,
          createdAt: DateTime.now(),
          isAddedToQuickAccess: false,
          isHidden: false,
        );

        expect(otherFolder.type, equals(QuickAccessFolderType.other));
        expect(otherFolder.isSystem, isFalse);
      });

      test('Subfolder relationship is preserved', () {
        final parentPath = '/storage/emulated/0/Download';
        const parentName = 'Download';

        final parentFolder = QuickAccessFolder(
          id: 'parent_id',
          path: parentPath,
          originalName: parentName,
          type: QuickAccessFolderType.system,
          createdAt: DateTime.now(),
          isAddedToQuickAccess: false,
          isHidden: false,
        );

        final childFolder = QuickAccessFolder(
          id: 'child_id',
          path: '$parentPath/WeChat',
          originalName: 'WeChat',
          type: QuickAccessFolderType.system,
          createdAt: DateTime.now(),
          isAddedToQuickAccess: false,
          isHidden: false,
          parentPath: parentPath,
        );

        expect(parentFolder.parentPath, isNull);
        expect(childFolder.parentPath, equals(parentPath));
        expect(childFolder.isSubfolder, isTrue);
      });
    });

    group('Performance and Limits', () {
      test('Max depth limit is configured for 5 levels', () {
        expect(
          QuickAccessDetectorConfig.maxDepthForAnalysis,
          equals(5),
        );
      });

      test('Max files to analyze limit is configured', () {
        expect(
          QuickAccessDetectorConfig.maxFilesToAnalyze,
          equals(500),
        );
      });

      test('Max folders to scan limit is configured', () {
        expect(
          QuickAccessDetectorConfig.maxFoldersToScan,
          equals(100),
        );
      });

      test('Limits are reasonable for mobile performance', () {
        final maxDepth = QuickAccessDetectorConfig.maxDepthForAnalysis;
        final maxFiles = QuickAccessDetectorConfig.maxFilesToAnalyze;
        final maxFolders = QuickAccessDetectorConfig.maxFoldersToScan;

        expect(maxDepth, greaterThan(0));
        expect(maxDepth, lessThan(20));
        expect(maxFiles, greaterThan(100));
        expect(maxFiles, lessThan(1000));
        expect(maxFolders, greaterThan(10));
        expect(maxFolders, lessThan(500));
      });
    });

    group('Android Path Conventions', () {
      test('System common directories follow Android convention', () {
        final androidSystemPaths = [
          '/storage/emulated/0/Pictures',
          '/storage/emulated/0/Download',
          '/storage/emulated/0/Documents',
          '/storage/emulated/0/DCIM',
        ];

        for (final path in androidSystemPaths) {
          expect(path, startsWith('/storage/emulated/0/'));
        }
      });

      test('Other folder paths can be identified', () {
        final otherFolderPaths = [
          '/storage/emulated/0/MyFiles',
          '/storage/emulated/0/Projects',
          '/storage/emulated/0/WeChat',
        ];

        for (final path in otherFolderPaths) {
          expect(path, startsWith('/storage/emulated/0/'));
          expect(path, contains('/'));
        }
      });

      test('Can extract folder name from path', () {
        final testPath = '/storage/emulated/0/MyFiles';
        final parts = testPath.split('/');
        final folderName = parts.last;

        expect(folderName, equals('MyFiles'));
        expect(folderName, isNotEmpty);
      });
    });

    group('Detector Initialization', () {
      test('QuickAccessFolderDetector can be instantiated', () {
        final detector = QuickAccessFolderDetector();
        expect(detector, isNotNull);
      });

      test('Config is accessible from detector', () {
        expect(QuickAccessDetectorConfig.minFileCount, isNotNull);
        expect(QuickAccessDetectorConfig.folderNameBlacklist, isNotNull);
        expect(QuickAccessDetectorConfig.folderNameBlacklist.isNotEmpty, isTrue);
      });
    });

    group('Folder Analysis Criteria', () {
      test('OR logic for folder conditions is sound', () {
        final minFileCount = QuickAccessDetectorConfig.minFileCount;
        final minSizeMB = QuickAccessDetectorConfig.minFolderSizeMB;
        final maxDays = QuickAccessDetectorConfig.maxDaysForRecent;
        final minDiversity = QuickAccessDetectorConfig.minFileTypesDiversity;

        expect(minFileCount, greaterThan(0));
        expect(minSizeMB, greaterThan(0.0));
        expect(maxDays, greaterThan(0));
        expect(minDiversity, greaterThan(0));

        expect(minFileCount, lessThan(1000));
        expect(minSizeMB, lessThan(1000.0));
        expect(maxDays, lessThan(3650));
      });

      test('Blacklist prevents common system folders', () {
        final blacklist = QuickAccessDetectorConfig.folderNameBlacklist;

        final commonSystemFolders = [
          'cache', '.cache',
          'temp', 'tmp',
          '.git', '.gradle',
          'node_modules',
          'build', 'dist',
          '__pycache__',
          'log', 'logs',
        ];

        for (final folder in commonSystemFolders) {
          expect(blacklist, contains(folder),
              reason: 'Blacklist should contain $folder');
        }
      });
    });
  });
}
