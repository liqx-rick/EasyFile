import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/app_trash_item.dart';

/// EasyFile回收站数据库
///
/// 管理回收站文件的元数据存储
///
/// 状态说明：
/// - pending: 已标记删除，文件仍在原位，待后台移动
/// - moved: 已移动到回收站
/// - failed: 移动失败，需要重试
class AppTrashDatabase {
  static const String _databaseName = 'app_trash.db';
  static const int _databaseVersion = 2; // 升级到v2
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
  ///
  /// Schema v2 字段说明：
  /// - id: 唯一标识符（UUID）
  /// - trash_path: 回收站中的文件路径（唯一）
  /// - original_path: 原始文件路径
  /// - file_name: 文件名
  /// - size: 文件大小（字节）
  /// - mime_type: MIME类型
  /// - deleted_at: 删除时间戳
  /// - status: 文件状态（pending/moved/failed）
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
        status TEXT DEFAULT 'pending',
        moved_at INTEGER,
        retry_count INTEGER DEFAULT 0,
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

    await db.execute('''
      CREATE INDEX idx_status ON $_tableName(status)
    ''');

    logger.i('App trash database schema created successfully');
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    logger.i('Upgrading app trash database from v$oldVersion to v$newVersion');

    if (oldVersion < 2) {
      // 添加status相关字段
      await db.execute(
          'ALTER TABLE $_tableName ADD COLUMN status TEXT DEFAULT "moved"');
      await db.execute('ALTER TABLE $_tableName ADD COLUMN moved_at INTEGER');
      await db.execute(
          'ALTER TABLE $_tableName ADD COLUMN retry_count INTEGER DEFAULT 0');
      await db.execute('CREATE INDEX idx_status ON $_tableName(status)');
      logger.i('Added status tracking fields for soft delete support');
    }
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

      logger.d(
          'Found ${results.length} expired items (older than $retentionDays days)');
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
      final result =
          await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
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
      final result =
          await db.rawQuery('SELECT SUM(file_size) as total FROM $_tableName');
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

  /// 标记文件为待删除（软删除）
  ///
  /// 文件状态变为'pending'，等待后台移动到回收站
  Future<String> markAsDeleted(AppTrashItem item) async {
    try {
      final db = await database;

      final data = item.toMap();
      data['status'] = 'pending';
      data['moved_at'] = null;

      await db.insert(
        _tableName,
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      logger.i('Marked file as deleted (pending): ${item.originalPath}');
      return item.id;
    } catch (e) {
      logger.e('Failed to mark file as deleted: $e');
      rethrow;
    }
  }

  /// 批量标记文件为待删除
  Future<List<String>> markBatchAsDeleted(List<AppTrashItem> items) async {
    try {
      final db = await database;
      final batch = db.batch();
      final ids = <String>[];

      for (final item in items) {
        final data = item.toMap();
        data['status'] = 'pending';
        data['moved_at'] = null;

        batch.insert(
          _tableName,
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        ids.add(item.id);
      }

      await batch.commit(noResult: true);
      logger.i('Marked ${items.length} files as deleted (pending)');
      return ids;
    } catch (e) {
      logger.e('Failed to mark batch as deleted: $e');
      rethrow;
    }
  }

  /// 更新文件状态为已移动
  Future<void> updateStatusMoved(String id) async {
    try {
      final db = await database;
      await db.update(
        _tableName,
        {
          'status': 'moved',
          'moved_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      logger.d('Updated status to moved: $id');
    } catch (e) {
      logger.e('Failed to update status: $e');
      rethrow;
    }
  }

  /// 更新文件状态为失败
  Future<void> updateStatusFailed(String id) async {
    try {
      final db = await database;
      await db.rawUpdate(
        'UPDATE $_tableName SET status = ?, retry_count = retry_count + 1 WHERE id = ?',
        ['failed', id],
      );
      logger.w('Updated status to failed: $id');
    } catch (e) {
      logger.e('Failed to update status: $e');
      rethrow;
    }
  }

  /// 获取所有待移动的文件
  Future<List<AppTrashItem>> getPendingFiles() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _tableName,
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'deleted_at ASC', // 先删除的先处理
      );

      return maps.map((map) => AppTrashItem.fromMap(map)).toList();
    } catch (e) {
      logger.e('Failed to get pending files: $e');
      return [];
    }
  }

  /// 获取所有已删除文件的原始路径（用于查询过滤）
  Future<Set<String>> getDeletedFilePaths() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _tableName,
        columns: ['original_path'],
        where: 'status IN (?, ?)',
        whereArgs: ['pending', 'moved'],
      );

      return maps.map((map) => map['original_path'] as String).toSet();
    } catch (e) {
      logger.e('Failed to get deleted file paths: $e');
      return {};
    }
  }

  /// 从待删除队列移除（用于恢复文件）
  Future<void> removeFromTrash(String originalPath) async {
    try {
      final db = await database;
      await db.delete(
        _tableName,
        where: 'original_path = ?',
        whereArgs: [originalPath],
      );
      logger.i('Removed from trash: $originalPath');
    } catch (e) {
      logger.e('Failed to remove from trash: $e');
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
