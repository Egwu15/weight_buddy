import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/chat_message.dart';
import '../models/exercise_recommendation.dart';
import '../models/log_entry.dart';
import '../models/memory.dart';
import '../models/weigh_in.dart';

/// Local, offline-first persistence. Schema follows the PRD:
/// logs: id, timestamp, type (meal/exercise), summary, calories,
///       protein_g, carbs_g, fat_g, raw_transcript.
///
/// v2 adds the v2 feature set: weigh_ins, app_settings (KV), chat_messages,
/// memories and exercise_recommendations.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static const _dbName = 'weight_buddy.db';
  static const _dbVersion = 2;

  /// Opens (and migrates) the local database.
  ///
  /// Uses the active [databaseFactory] from sqflite, so tests can point it at
  /// an in-memory FFI database. Web is not supported by sqflite yet.
  static Future<AppDatabase> open({String? path}) async {
    if (kIsWeb) {
      throw UnsupportedError('Local database is not available on web yet.');
    }
    final dbPath = path ??
        p.join((await getApplicationDocumentsDirectory()).path, _dbName);
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: (db, version) async {
          await _createV1(db);
          await _createV2(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createV2(db);
          }
        },
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        type TEXT NOT NULL,
        summary TEXT NOT NULL,
        calories REAL NOT NULL DEFAULT 0,
        protein_g REAL NOT NULL DEFAULT 0,
        carbs_g REAL NOT NULL DEFAULT 0,
        fat_g REAL NOT NULL DEFAULT 0,
        raw_transcript TEXT NOT NULL DEFAULT '',
        items TEXT NOT NULL DEFAULT '[]'
      )
    ''');
    await db.execute('CREATE INDEX idx_logs_timestamp ON logs (timestamp)');
  }

  static Future<void> _createV2(Database db) async {
    await db.execute('''
      CREATE TABLE weigh_ins (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date INTEGER NOT NULL,
        weight_kg REAL NOT NULL,
        note TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_weigh_ins_date ON weigh_ins (date)',
    );

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE memories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        topic TEXT NOT NULL,
        content TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'note',
        source TEXT NOT NULL DEFAULT 'auto',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_memories_topic ON memories (topic) WHERE active = 1',
    );

    await db.execute('''
      CREATE TABLE exercise_recommendations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        muscle_groups TEXT NOT NULL DEFAULT '[]',
        sets INTEGER,
        reps INTEGER,
        rest_seconds INTEGER,
        duration_minutes INTEGER,
        difficulty TEXT NOT NULL DEFAULT '',
        plan_name TEXT NOT NULL DEFAULT '',
        source_chat_id INTEGER,
        created_at INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_exercises_archived ON exercise_recommendations (archived)',
    );
  }

  // ---------------------------------------------------------------------
  // Logs
  // ---------------------------------------------------------------------

  Future<int> insertLog(LogEntry entry) async {
    return _db.insert('logs', entry.toMap());
  }

  Future<List<LogEntry>> logsForDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final end = start + const Duration(days: 1).inMilliseconds;
    return logsForRange(
      DateTime.fromMillisecondsSinceEpoch(start).toLocal(),
      DateTime.fromMillisecondsSinceEpoch(end).toLocal(),
    );
  }

  /// All logs in the half-open local-day range [start, end].
  Future<List<LogEntry>> logsForRange(DateTime start, DateTime end) async {
    final s = DateTime(start.year, start.month, start.day).millisecondsSinceEpoch;
    final e = DateTime(end.year, end.month, end.day).millisecondsSinceEpoch +
        const Duration(days: 1).inMilliseconds;
    final rows = await _db.query(
      'logs',
      where: 'timestamp >= ? AND timestamp < ?',
      whereArgs: [s, e],
      orderBy: 'timestamp ASC',
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  Future<List<LogEntry>> allLogs() async {
    final rows = await _db.query('logs', orderBy: 'timestamp DESC');
    return rows.map(LogEntry.fromMap).toList();
  }

  Future<void> deleteLog(int id) async {
    await _db.delete('logs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllLogs() async {
    await _db.delete('logs');
  }

  // ---------------------------------------------------------------------
  // Weigh-ins
  // ---------------------------------------------------------------------

  Future<int> insertWeighIn(WeighIn weighIn) async {
    return _db.insert('weigh_ins', weighIn.toMap());
  }

  Future<List<WeighIn>> weighIns({int? limit}) async {
    final rows = await _db.query(
      'weigh_ins',
      orderBy: 'date DESC',
      limit: limit,
    );
    return rows.map(WeighIn.fromMap).toList();
  }

  Future<void> deleteWeighIn(int id) async {
    await _db.delete('weigh_ins', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------
  // App settings (non-secret KV)
  // ---------------------------------------------------------------------

  Future<String?> getSetting(String key) async {
    final rows =
        await _db.query('app_settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------
  // Chat thread
  // ---------------------------------------------------------------------

  Future<int> insertChatMessage(ChatMessage message) async {
    return _db.insert('chat_messages', message.toMap());
  }

  /// The persisted thread, oldest first, bounded to [limit] most recent.
  Future<List<ChatMessage>> chatMessages({int? limit}) async {
    final rows = await _db.query(
      'chat_messages',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.reversed.map(ChatMessage.fromMap).toList();
  }

  Future<void> clearChat() async {
    await _db.delete('chat_messages');
  }

  // ---------------------------------------------------------------------
  // Memories
  // ---------------------------------------------------------------------

  /// Latest-wins upsert by [Memory.topic] on the active row.
  Future<int> upsertMemory(Memory memory) async {
    final existing = await _db.query(
      'memories',
      where: 'topic = ? AND active = 1',
      whereArgs: [memory.topic],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await _db.update(
        'memories',
        {
          'content': memory.content,
          'category': memory.category.apiName,
          'updated_at': memory.updatedAt,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    return _db.insert('memories', memory.toMap());
  }

  Future<List<Memory>> memories({bool activeOnly = true}) async {
    final rows = await _db.query(
      'memories',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'updated_at DESC',
    );
    return rows.map(Memory.fromMap).toList();
  }

  Future<void> updateMemoryContent(int id, String content) async {
    await _db.update(
      'memories',
      {'content': content, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Soft-delete: keeps the row but stops injection/retrieval.
  Future<void> deactivateMemory(int id) async {
    await _db.update(
      'memories',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------
  // Exercise recommendations
  // ---------------------------------------------------------------------

  /// Inserts unless a non-archived recommendation with the same name already
  /// exists (case-insensitive dedupe). Returns the row id, or null when the
  /// exercise was already saved.
  Future<int?> insertExercise(ExerciseRecommendation exercise) async {
    final existing = await _db.query(
      'exercise_recommendations',
      where: 'LOWER(name) = ? AND archived = 0',
      whereArgs: [exercise.name.trim().toLowerCase()],
      limit: 1,
    );
    if (existing.isNotEmpty) return null;
    return _db.insert('exercise_recommendations', exercise.toMap());
  }

  Future<List<ExerciseRecommendation>> exercises(
      {bool archivedOnly = false}) async {
    final rows = await _db.query(
      'exercise_recommendations',
      where: archivedOnly ? 'archived = 1' : null,
      orderBy: 'created_at DESC',
    );
    return rows.map(ExerciseRecommendation.fromMap).toList();
  }

  Future<void> archiveExercise(int id) async {
    await _db.update(
      'exercise_recommendations',
      {'archived': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> unarchiveExercise(int id) async {
    await _db.update(
      'exercise_recommendations',
      {'archived': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------
  // Whole-app wipe
  // ---------------------------------------------------------------------

  /// Removes every user record across all tables (settings preserved).
  Future<void> wipeAllData() async {
    await _db.delete('logs');
    await _db.delete('weigh_ins');
    await _db.delete('chat_messages');
    await _db.delete('memories');
    await _db.delete('exercise_recommendations');
  }

  Future<void> close() => _db.close();
}
