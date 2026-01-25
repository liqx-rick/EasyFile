import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:easyfile/core/logger.dart';
import 'package:easyfile/data/models/extraction_record.dart';

/// 解压记录数据库
///
/// 管理压缩包解压历史记录
class ExtractionRecordDatabase {
  static const String _databaseName = 'extraction_records.db';
  static const int _databaseVersion = 1;
  static const String _tableName = 'extraction_records';

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

    logger.i('Initializing extraction records database at: $filePath');

    return await openDatabase(
      filePath,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    logger.i('Creating extraction records database schema v$version');

    await db.execute('''
      CREATE TABLE $_tableName (
        id TEXT PRIMARY KEY,
        archive_path TEXT NOT NULL,
        archive_name TEXT NOT NULL,
        archive_md5 TEXT,
        archive_size INTEGER NOT NULL,
        target_path TEXT NOT NULL,
        folder_name TEXT NOT NULL,
        file_count INTEGER NOT NULL,
        extracted_at INTEGER NOT NULL
      )
    ''');

    // 创建索引以加速查询
    await db.execute('''
      CREATE INDEX idx_archive_path ON $_tableName(archive_path)
    ''');

    await db.execute('''
      CREATE INDEX idx_archive_md5 ON $_tableName(archive_md5)
    ''');

    await db.execute('''
      CREATE INDEX idx_extracted_at ON $_tableName(extracted_at DESC)
    ''');

    logger.i('Extraction records database schema created successfully');
  }

  /// 插入解压记录
  Future<void> insert(ExtractionRecord record) async {
    final db = await database;
    await db.insert(
      _tableName,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    logger.i('Inserted extraction record: ${record.id}');
  }

  /// 删除记录
  Future<void> delete(String id) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
    logger.i('Deleted extraction record: $id');
  }

  /// 清空所有记录
  Future<void> deleteAll() async {
    final db = await database;
    await db.delete(_tableName);
    logger.i('Deleted all extraction records');
  }

  /// 查询所有记录（按时间倒序）
  Future<List<ExtractionRecord>> getAll() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      orderBy: 'extracted_at DESC',
    );

    return List.generate(maps.length, (i) {
      return ExtractionRecord.fromMap(maps[i]);
    });
  }

  /// 根据压缩包路径查询记录
  Future<List<ExtractionRecord>> getByArchivePath(String archivePath) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'archive_path = ?',
      whereArgs: [archivePath],
      orderBy: 'extracted_at DESC',
    );

    return List.generate(maps.length, (i) {
      return ExtractionRecord.fromMap(maps[i]);
    });
  }

  /// 根据MD5查询记录
  Future<List<ExtractionRecord>> getByMD5(String md5) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'archive_md5 = ?',
      whereArgs: [md5],
      orderBy: 'extracted_at DESC',
    );

    return List.generate(maps.length, (i) {
      return ExtractionRecord.fromMap(maps[i]);
    });
  }

  /// 批量查询：根据多个压缩包路径查询
  Future<Map<String, List<ExtractionRecord>>> getBatchByPaths(
    List<String> paths,
  ) async {
    if (paths.isEmpty) return {};

    final db = await database;
    final placeholders = List.filled(paths.length, '?').join(',');
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'archive_path IN ($placeholders)',
      whereArgs: paths,
    );

    // 按路径分组
    final Map<String, List<ExtractionRecord>> grouped = {};
    for (final map in maps) {
      final record = ExtractionRecord.fromMap(map);
      grouped.putIfAbsent(record.archivePath, () => []).add(record);
    }

    return grouped;
  }

  /// 获取记录总数
  Future<int> getCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM $_tableName');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 关闭数据库
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      logger.i('Extraction records database closed');
    }
  }
}
