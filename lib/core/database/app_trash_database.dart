import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/app_trash_item.dart';

/// EasyFile回收站数据库
/// 
/// 管理回收站文件的元数据存储
class AppTrashDatabase {
  static const String _databaseName = 'app_trash.db';
  static const int _databaseVersion = 1;
  static const String _tableName = 'trash_metadata';

  static Database? _database;

  /// 获取数据库实例（单例模式）
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final filePath = path.join(dbPath, _databaseName);

    logger.i('Initializing app trash database at: $filePath');

    return await openDatabase(
      filePath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    logger.i('Creating app trash database schema v$version');

    await db.execute('''
      CREATE TABLE $_tableName (
        id TEXT PRIMARY KEY,
        trash_path TEXT UNIQUE NOT NULL,
        original_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        mime_type TEXT,
        deleted_at INTEGER NOT NULL,
        thumbnail_path TEXT,
        created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000)
      )
    ''');

    // 创建索引以加速查询
    await db.execute('''
      CREATE INDEX idx_deleted_at ON $_tableName(deleted_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX idx_file_size ON $_tableName(file_size DESC)
    ''');

    await db.execute('''
      CREATE INDEX idx_original_path ON $_tableName(original_path)
    ''');

    logger.i('App trash database schema created successfully');
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    logger.i('Upgrading app trash database from v$oldVersion to v$newVersion');
    
    // 未来版本升级逻辑
    // if (oldVersion < 2) {
    //   await db.execute('ALTER TABLE $_tableName ADD COLUMN new_column TEXT');
    // }
  }

  /// 插入回收站文件记录
  Future<void> insert(AppTrashItem item) async {
    try {
      final db = await database;
      await db.insert(
        _tableName,
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      logger.d('Inserted trash item: ${item.id} - ${item.fileName}');
    } catch (e) {
      logger.e('Failed to insert trash item: $e');
      rethrow;
    }
  }

  /// 批量插入
  Future<void> insertBatch(List<AppTrashItem> items) async {
    if (items.isEmpty) return;

    try {
      final db = await database;
      final batch = db.batch();
      
      for (final item in items) {
        batch.insert(
          _tableName,
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      
      await batch.commit(noResult: true);
      logger.d('Inserted ${items.length} trash items in batch');
    } catch (e) {
      logger.e('Failed to insert batch: $e');
      rethrow;
    }
  }

  /// 根据ID删除记录
  Future<void> delete(String id) async {
    try {
      final db = await database;
      final count = await db.delete(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
      );
      
      if (count > 0) {
        logger.d('Deleted trash item: $id');
      } else {
        logger.w('Trash item not found for deletion: $id');
      }
    } catch (e) {
      logger.e('Failed to delete trash item: $e');
      rethrow;
    }
  }

  /// 批量删除
  Future<void> deleteBatch(List<String> ids) async {
    if (ids.isEmpty) return;

    try {
      final db = await database;
      final batch = db.batch();
      
      for (final id in ids) {
        batch.delete(
          _tableName,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      
      await batch.commit(noResult: true);
      logger.d('Deleted ${ids.length} trash items in batch');
    } catch (e) {
      logger.e('Failed to delete batch: $e');
      rethrow;
    }
  }

  /// 根据ID查询单个记录
  Future<AppTrashItem?> getById(String id) async {
    try {
      final db = await database;
      final results = await db.query(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (results.isNotEmpty) {
        return AppTrashItem.fromMap(results.first);
      }
      return null;
    } catch (e) {
      logger.e('Failed to get trash item by id: $e');
      rethrow;
    }
  }

  /// 获取所有回收站文件（按删除时间倒序）
  Future<List<AppTrashItem>> getAll() async {
    try {
      final db = await database;
      final results = await db.query(
        _tableName,
        orderBy: 'deleted_at DESC',
      );

      return results.map((map) => AppTrashItem.fromMap(map)).toList();
    } catch (e) {
      logger.e('Failed to get all trash items: $e');
      rethrow;
    }
  }

  /// 获取过期的文件（用于自动清理）
  Future<List<AppTrashItem>> getExpired(int retentionDays) async {
    try {
      final db = await database;
      final now = DateTime.now();
      final threshold = now.subtract(Duration(days: retentionDays));
      final thresholdMillis = threshold.millisecondsSinceEpoch;

      final results = await db.query(
        _tableName,
        where: 'deleted_at < ?',
        whereArgs: [thresholdMillis],
        orderBy: 'deleted_at ASC',
      );

      logger.d('Found ${results.length} expired items (older than $retentionDays days)');
      return results.map((map) => AppTrashItem.fromMap(map)).toList();
    } catch (e) {
      logger.e('Failed to get expired trash items: $e');
      rethrow;
    }
  }

  /// 获取即将过期的文件（距离清理少于3天）
  Future<List<AppTrashItem>> getExpiringSoon(int retentionDays) async {
    try {
      final db = await database;
      final now = DateTime.now();
      final soonThreshold = now.subtract(Duration(days: retentionDays - 3));
      final expiredThreshold = now.subtract(Duration(days: retentionDays));

      final results = await db.query(
        _tableName,
        where: 'deleted_at >= ? AND deleted_at < ?',
        whereArgs: [
          expiredThreshold.millisecondsSinceEpoch,
          soonThreshold.millisecondsSinceEpoch,
        ],
        orderBy: 'deleted_at ASC',
      );

      return results.map((map) => AppTrashItem.fromMap(map)).toList();
    } catch (e) {
      logger.e('Failed to get expiring soon items: $e');
      rethrow;
    }
  }

  /// 获取回收站文件总数
  Future<int> getTotalCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      logger.e('Failed to get total count: $e');
      rethrow;
    }
  }

  /// 获取回收站文件总大小（字节）
  Future<int> getTotalSize() async {
    try {
      final db = await database;
      final result = await db.rawQuery('SELECT SUM(file_size) as total FROM $_tableName');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      logger.e('Failed to get total size: $e');
      rethrow;
    }
  }

  /// 按文件类型统计
  Future<Map<String, int>> getCountByType() async {
    try {
      final db = await database;
      final results = await db.rawQuery('''
        SELECT mime_type, COUNT(*) as count 
        FROM $_tableName 
        GROUP BY mime_type
      ''');

      final countMap = <String, int>{};
      for (final row in results) {
        final mimeType = row['mime_type'] as String;
        final count = row['count'] as int;
        countMap[mimeType] = count;
      }

      return countMap;
    } catch (e) {
      logger.e('Failed to get count by type: $e');
      rethrow;
    }
  }

  /// 清空所有记录
  Future<void> clear() async {
    try {
      final db = await database;
      await db.delete(_tableName);
      logger.i('Cleared all trash metadata');
    } catch (e) {
      logger.e('Failed to clear trash metadata: $e');
      rethrow;
    }
  }

  /// 关闭数据库
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      logger.i('App trash database closed');
    }
  }

  /// 重置数据库（危险操作，仅用于测试）
  Future<void> reset() async {
    try {
      await close();
      final dbPath = await getDatabasesPath();
      final filePath = path.join(dbPath, _databaseName);
      await deleteDatabase(filePath);
      logger.w('App trash database reset');
    } catch (e) {
      logger.e('Failed to reset database: $e');
      rethrow;
    }
  }
}
