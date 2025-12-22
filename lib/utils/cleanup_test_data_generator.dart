import 'dart:io';
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/quick_access_folder.dart';
import 'package:easyfile/data/sources/quick_access_local_source.dart';

/// 清理规则测试数据生成器
/// 
/// 生成各种测试场景的文件夹：
/// 1. 不存在的文件夹（数据库中有，文件系统中无）
/// 2. 错误分类的系统文件夹（type=other但实际是系统路径）
/// 3. 不合格的其他文件夹（type=other但内容不足）
/// 4. 正常的文件夹（作为对照组）
class CleanupTestDataGenerator {
  final QuickAccessLocalSource _localSource;
  static const String testPrefix = 'ef_';
  static const String basePath = '/storage/emulated/0';

  CleanupTestDataGenerator(this._localSource);

  /// 生成所有测试数据
  Future<TestDataGenerationResult> generateTestData() async {
    logger.i('CleanupTestDataGenerator: Starting test data generation');
    
    int created = 0;
    int dbRecords = 0;
    final List<String> createdPaths = [];

    try {
      // 场景1: 创建正常的测试文件夹（有足够内容）
      final normalFolder = await _createNormalFolder();
      if (normalFolder != null) {
        await _localSource.addFolder(normalFolder);
        createdPaths.add(normalFolder.path);
        created++;
        dbRecords++;
      }

      // 场景2: 创建不合格的测试文件夹（内容不足）
      final unqualifiedFolder = await _createUnqualifiedFolder();
      if (unqualifiedFolder != null) {
        await _localSource.addFolder(unqualifiedFolder);
        createdPaths.add(unqualifiedFolder.path);
        created++;
        dbRecords++;
      }

      // 场景3: 创建文件夹但在数据库中标记为系统类型（实际应该是other）
      final misclassifiedFolder = await _createMisclassifiedFolder();
      if (misclassifiedFolder != null) {
        await _localSource.addFolder(misclassifiedFolder);
        createdPaths.add(misclassifiedFolder.path);
        created++;
        dbRecords++;
      }

      // 场景4: 仅在数据库中创建记录，不创建实际文件夹（模拟已删除的文件夹）
      final nonExistentFolder = _createNonExistentFolderRecord();
      await _localSource.addFolder(nonExistentFolder);
      dbRecords++;

      // 场景5: 创建另一个不合格的文件夹（空文件夹）
      final emptyFolder = await _createEmptyFolder();
      if (emptyFolder != null) {
        await _localSource.addFolder(emptyFolder);
        createdPaths.add(emptyFolder.path);
        created++;
        dbRecords++;
      }

      logger.i('CleanupTestDataGenerator: Generated $created folders, $dbRecords DB records');
      
      return TestDataGenerationResult(
        foldersCreated: created,
        dbRecordsCreated: dbRecords,
        createdPaths: createdPaths,
        success: true,
      );

    } catch (e, stackTrace) {
      logger.e('CleanupTestDataGenerator: Error generating test data: $e\n$stackTrace');
      return TestDataGenerationResult(
        foldersCreated: created,
        dbRecordsCreated: dbRecords,
        createdPaths: createdPaths,
        success: false,
        error: e.toString(),
      );
    }
  }

  /// 创建正常的测试文件夹（有足够的文件和子文件夹）
  Future<QuickAccessFolder?> _createNormalFolder() async {
    try {
      final path = '$basePath/${testPrefix}test_normal';
      final dir = Directory(path);
      
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      
      await dir.create(recursive: true);
      
      // 创建足够的文件（至少5个）
      for (int i = 1; i <= 8; i++) {
        final file = File('$path/test_file_$i.txt');
        await file.writeAsString('Test content for file $i');
      }
      
      // 创建一些子文件夹（至少2个）
      for (int i = 1; i <= 3; i++) {
        final subDir = Directory('$path/subfolder_$i');
        await subDir.create();
        
        // 在子文件夹中也创建一些文件
        final subFile = File('${subDir.path}/file.txt');
        await subFile.writeAsString('Subfolder content');
      }
      
      logger.i('CleanupTestDataGenerator: Created normal folder: $path');
      
      final now = DateTime.now();
      return QuickAccessFolder(
        id: now.millisecondsSinceEpoch.toString(),
        path: path,
        originalName: '${testPrefix}test_normal',
        type: QuickAccessFolderType.other,
        createdAt: now,
        isAddedToQuickAccess: false,
        isHidden: false,
      );
      
    } catch (e) {
      logger.e('CleanupTestDataGenerator: Error creating normal folder: $e');
      return null;
    }
  }

  /// 创建不合格的测试文件夹（只有3个文件，不满足5个文件的要求）
  Future<QuickAccessFolder?> _createUnqualifiedFolder() async {
    try {
      final path = '$basePath/${testPrefix}test_unqualified';
      final dir = Directory(path);
      
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      
      await dir.create(recursive: true);
      
      // 只创建3个文件（不满足5个文件的要求）
      for (int i = 1; i <= 3; i++) {
        final file = File('$path/file_$i.txt');
        await file.writeAsString('Content $i');
      }
      
      // 只创建1个子文件夹（不满足2个子文件夹的要求）
      final subDir = Directory('$path/sub1');
      await subDir.create();
      
      logger.i('CleanupTestDataGenerator: Created unqualified folder: $path');
      
      final now = DateTime.now();
      return QuickAccessFolder(
        id: '${now.millisecondsSinceEpoch}_unq',
        path: path,
        originalName: '${testPrefix}test_unqualified',
        type: QuickAccessFolderType.other,
        createdAt: now,
        isAddedToQuickAccess: false,
        isHidden: false,
      );
      
    } catch (e) {
      logger.e('CleanupTestDataGenerator: Error creating unqualified folder: $e');
      return null;
    }
  }

  /// 创建错误分类的文件夹（实际在系统路径下，但标记为other类型）
  Future<QuickAccessFolder?> _createMisclassifiedFolder() async {
    try {
      // 在Download目录下创建测试文件夹
      final path = '$basePath/Download/${testPrefix}test_misclassified';
      final dir = Directory(path);
      
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      
      await dir.create(recursive: true);
      
      // 创建足够的内容
      for (int i = 1; i <= 6; i++) {
        final file = File('$path/file_$i.txt');
        await file.writeAsString('Test content $i');
      }
      
      logger.i('CleanupTestDataGenerator: Created misclassified folder: $path');
      
      final now = DateTime.now();
      // 故意标记为 other 类型（虽然它在系统文件夹下）
      return QuickAccessFolder(
        id: '${now.millisecondsSinceEpoch}_mis',
        path: path,
        originalName: '${testPrefix}test_misclassified',
        type: QuickAccessFolderType.other,
        createdAt: now,
        isAddedToQuickAccess: false,
        isHidden: false,
      );
      
    } catch (e) {
      logger.e('CleanupTestDataGenerator: Error creating misclassified folder: $e');
      return null;
    }
  }

  /// 创建空文件夹（不满足任何条件）
  Future<QuickAccessFolder?> _createEmptyFolder() async {
    try {
      final path = '$basePath/${testPrefix}test_empty';
      final dir = Directory(path);
      
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      
      await dir.create(recursive: true);
      
      logger.i('CleanupTestDataGenerator: Created empty folder: $path');
      
      final now = DateTime.now();
      return QuickAccessFolder(
        id: '${now.millisecondsSinceEpoch}_emp',
        path: path,
        originalName: '${testPrefix}test_empty',
        type: QuickAccessFolderType.other,
        createdAt: now,
        isAddedToQuickAccess: false,
        isHidden: false,
      );
      
    } catch (e) {
      logger.e('CleanupTestDataGenerator: Error creating empty folder: $e');
      return null;
    }
  }

  /// 创建不存在的文件夹记录（只在数据库中，文件系统不存在）
  QuickAccessFolder _createNonExistentFolderRecord() {
    final path = '$basePath/${testPrefix}test_nonexistent';
    logger.i('CleanupTestDataGenerator: Created non-existent folder record: $path');
    
    final now = DateTime.now();
    return QuickAccessFolder(
      id: '${now.millisecondsSinceEpoch}_nex',
      path: path,
      originalName: '${testPrefix}test_nonexistent',
      type: QuickAccessFolderType.other,
      createdAt: now,
      isAddedToQuickAccess: false,
      isHidden: false,
    );
  }

  /// 清除所有测试数据
  Future<TestDataCleanupResult> cleanupTestData() async {
    logger.i('CleanupTestDataGenerator: Starting test data cleanup');
    
    int foldersDeleted = 0;
    int dbRecordsDeleted = 0;

    try {
      // 1. 从数据库中找到所有测试文件夹并删除
      final allFolders = await _localSource.getAllFolders();
      final testFolders = allFolders.where((f) => 
        f.path.contains('/$testPrefix') || f.displayName.startsWith(testPrefix)
      ).toList();

      logger.i('CleanupTestDataGenerator: Found ${testFolders.length} test folders in DB');

      for (final folder in testFolders) {
        final dir = Directory(folder.path);
        if (await dir.exists()) {
          try {
            await dir.delete(recursive: true);
            foldersDeleted++;
            logger.i('CleanupTestDataGenerator: Deleted folder from DB: ${folder.path}');
          } catch (e) {
            logger.w('CleanupTestDataGenerator: Failed to delete folder ${folder.path}: $e');
          }
        }

        // 从数据库中删除记录
        try {
          await _localSource.removeFolder(folder.id);
          dbRecordsDeleted++;
        } catch (e) {
          logger.w('CleanupTestDataGenerator: Failed to delete DB record ${folder.id}: $e');
        }
      }

      // 2. 扫描文件系统，删除所有 ef_ 开头的测试文件夹（包括数据库中没有的）
      await _scanAndDeleteTestFolders(basePath, foldersDeleted);

      logger.i('CleanupTestDataGenerator: Cleanup complete. Deleted $foldersDeleted folders, $dbRecordsDeleted DB records');

      return TestDataCleanupResult(
        foldersDeleted: foldersDeleted,
        dbRecordsDeleted: dbRecordsDeleted,
        success: true,
      );

    } catch (e, stackTrace) {
      logger.e('CleanupTestDataGenerator: Error during cleanup: $e\n$stackTrace');
      return TestDataCleanupResult(
        foldersDeleted: foldersDeleted,
        dbRecordsDeleted: dbRecordsDeleted,
        success: false,
        error: e.toString(),
      );
    }
  }

  /// 递归扫描并删除所有 ef_ 开头的测试文件夹
  Future<int> _scanAndDeleteTestFolders(String path, int initialCount) async {
    int deletedCount = initialCount;
    
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        return deletedCount;
      }

      final entities = await dir.list().toList();
      
      for (final entity in entities) {
        if (entity is Directory) {
          final name = entity.path.split('/').last;
          
          // 如果是 ef_ 开头的文件夹，删除它
          if (name.startsWith(testPrefix)) {
            try {
              await entity.delete(recursive: true);
              deletedCount++;
              logger.i('CleanupTestDataGenerator: Deleted test folder from filesystem: ${entity.path}');
            } catch (e) {
              logger.w('CleanupTestDataGenerator: Failed to delete test folder ${entity.path}: $e');
            }
          } else {
            // 递归扫描子文件夹（只扫描系统文件夹）
            final systemFolders = ['Download', 'Pictures', 'DCIM', 'Music', 'Movies', 'Documents', 'Sounds'];
            if (systemFolders.contains(name)) {
              deletedCount = await _scanAndDeleteTestFolders(entity.path, deletedCount);
            }
          }
        }
      }
    } catch (e) {
      logger.w('CleanupTestDataGenerator: Error scanning folder $path: $e');
    }

    return deletedCount;
  }
}

/// 测试数据生成结果
class TestDataGenerationResult {
  final int foldersCreated;
  final int dbRecordsCreated;
  final List<String> createdPaths;
  final bool success;
  final String? error;

  TestDataGenerationResult({
    required this.foldersCreated,
    required this.dbRecordsCreated,
    required this.createdPaths,
    required this.success,
    this.error,
  });

  @override
  String toString() {
    return 'TestDataGenerationResult(folders: $foldersCreated, dbRecords: $dbRecordsCreated, success: $success)';
  }
}

/// 测试数据清理结果
class TestDataCleanupResult {
  final int foldersDeleted;
  final int dbRecordsDeleted;
  final bool success;
  final String? error;

  TestDataCleanupResult({
    required this.foldersDeleted,
    required this.dbRecordsDeleted,
    required this.success,
    this.error,
  });

  @override
  String toString() {
    return 'TestDataCleanupResult(folders: $foldersDeleted, dbRecords: $dbRecordsDeleted, success: $success)';
  }
}
