import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import '../models/planned_message.dart';
import '../models/short_term_message.dart';
import '../models/provider_config.dart';

class DatabaseService {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'aichat.db');
    return await openDatabase(path, version: 3, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE long_term_memories (id TEXT PRIMARY KEY, field TEXT NOT NULL, content TEXT NOT NULL, updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE base_memories (id TEXT PRIMARY KEY, type TEXT NOT NULL, content TEXT NOT NULL, updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE planned_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, scheduled_time INTEGER NOT NULL, message TEXT NOT NULL, delivered INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE short_term_messages (id TEXT PRIMARY KEY, role TEXT NOT NULL, content TEXT NOT NULL, timestamp INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE chat_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, content TEXT NOT NULL, timestamp INTEGER NOT NULL, short_mem_id TEXT)''');
    await db.execute('''CREATE TABLE debug_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, request_summary TEXT NOT NULL, response_summary TEXT NOT NULL, error TEXT, duration_ms INTEGER)''');
    await db.execute('''CREATE TABLE providers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, api_base_url TEXT NOT NULL, api_key TEXT NOT NULL, selected_model TEXT DEFAULT '', created_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE token_usage (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, prompt_tokens INTEGER NOT NULL, completion_tokens INTEGER NOT NULL, model TEXT)''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''CREATE TABLE IF NOT EXISTS short_term_messages (id TEXT PRIMARY KEY, role TEXT NOT NULL, content TEXT NOT NULL, timestamp INTEGER NOT NULL)''');
      await db.execute('''CREATE TABLE IF NOT EXISTS chat_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, content TEXT NOT NULL, timestamp INTEGER NOT NULL, short_mem_id TEXT)''');
      await db.execute('''CREATE TABLE IF NOT EXISTS debug_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, request_summary TEXT NOT NULL, response_summary TEXT NOT NULL, error TEXT, duration_ms INTEGER)''');
    }
    if (oldVersion < 3) {
      await db.execute('''CREATE TABLE IF NOT EXISTS providers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, api_base_url TEXT NOT NULL, api_key TEXT NOT NULL, selected_model TEXT DEFAULT '', created_at INTEGER NOT NULL)''');
      await db.execute('''CREATE TABLE IF NOT EXISTS token_usage (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, prompt_tokens INTEGER NOT NULL, completion_tokens INTEGER NOT NULL, model TEXT)''');
    }
  }

  // ─── 供应商 ────────────────────────

  static Future<List<ProviderConfig>> getProviders() async {
    final db = await database;
    final maps = await db.query('providers', orderBy: 'id ASC');
    return maps.map(ProviderConfig.fromMap).toList();
  }

  static Future<int> insertProvider(ProviderConfig p) async {
    final db = await database;
    return await db.insert('providers', p.toMap());
  }

  static Future<void> updateProvider(ProviderConfig p) async {
    final db = await database;
    await db.update('providers', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }

  static Future<void> deleteProvider(int id) async {
    final db = await database;
    await db.delete('providers', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Token 用量 ────────────────────

  static Future<void> insertTokenUsage({
    required int promptTokens,
    required int completionTokens,
    String? model,
  }) async {
    final db = await database;
    await db.insert('token_usage', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'model': model,
    });
  }

  static Future<List<Map<String, dynamic>>> getTokenUsage({int days = 30}) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    return await db.query('token_usage',
        where: 'timestamp >= ?', whereArgs: [cutoff], orderBy: 'timestamp ASC');
  }

  // ─── 长期记忆 / 基础记忆 / 短期记忆 / 聊天消息 / 调试日志 / 计划消息 ───
  // (keep existing methods unchanged)

  static Future<List<LongTermMemory>> getLongTermMemories() async {
    final db = await database;
    final maps = await db.query('long_term_memories', orderBy: 'id ASC');
    return maps.map(LongTermMemory.fromMap).toList();
  }

  static Future<void> insertLongTermMemory(LongTermMemory memory) async {
    final db = await database;
    await db.insert('long_term_memories', memory.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateLongTermMemory(LongTermMemory memory) async {
    final db = await database;
    await db.update('long_term_memories', {'field': memory.field, 'content': memory.content, 'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [memory.id]);
  }

  static Future<void> deleteLongTermMemory(String id) async {
    final db = await database;
    await db.delete('long_term_memories', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearLongTermMemories() async {
    final db = await database;
    await db.delete('long_term_memories');
  }

  static Future<List<BaseMemory>> getBaseMemories() async {
    final db = await database;
    final maps = await db.query('base_memories', orderBy: 'id ASC');
    return maps.map(BaseMemory.fromMap).toList();
  }

  static Future<void> insertBaseMemory(BaseMemory memory) async {
    final db = await database;
    await db.insert('base_memories', memory.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateBaseMemory(BaseMemory memory) async {
    final db = await database;
    await db.update('base_memories', {'type': memory.type, 'content': memory.content, 'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [memory.id]);
  }

  static Future<void> deleteBaseMemory(String id) async {
    final db = await database;
    await db.delete('base_memories', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearBaseMemories() async {
    final db = await database;
    await db.delete('base_memories');
  }

  static Future<List<ShortTermMessage>> getShortTermMessages({int? limit}) async {
    final db = await database;
    final maps = await db.query('short_term_messages', orderBy: 'timestamp ASC', limit: limit);
    return maps.map(ShortTermMessage.fromMap).toList();
  }

  static Future<int> getShortTermCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM short_term_messages');
    return result.first['cnt'] as int;
  }

  static Future<int> getMaxShortTermSeq() async {
    final db = await database;
    final result = await db.rawQuery("SELECT MAX(CAST(SUBSTR(id, 2) AS INTEGER)) as max_id FROM short_term_messages");
    return result.first['max_id'] as int? ?? 0;
  }

  static Future<void> insertShortTermMessage(ShortTermMessage msg) async {
    final db = await database;
    await db.insert('short_term_messages', msg.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteShortTermMessage(String id) async {
    final db = await database;
    await db.delete('short_term_messages', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearShortTermMessages() async {
    final db = await database;
    await db.delete('short_term_messages');
  }

  static Future<int> insertChatMessage({required String role, required String content, required int timestampMs, String? shortMemId}) async {
    final db = await database;
    return await db.insert('chat_messages', {'role': role, 'content': content, 'timestamp': timestampMs, 'short_mem_id': shortMemId});
  }

  static Future<List<Map<String, dynamic>>> getChatMessages() async {
    final db = await database;
    return await db.query('chat_messages', orderBy: 'timestamp ASC');
  }

  static Future<void> deleteChatMessage(int id) async {
    final db = await database;
    await db.delete('chat_messages', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearChatMessages() async {
    final db = await database;
    await db.delete('chat_messages');
  }

  static Future<int> insertDebugLog({required String requestSummary, required String responseSummary, String? error, int? durationMs}) async {
    final db = await database;
    final id = await db.insert('debug_logs', {'timestamp': DateTime.now().millisecondsSinceEpoch, 'request_summary': requestSummary, 'response_summary': responseSummary, 'error': error, 'duration_ms': durationMs});
    await _trimDebugLogs(db);
    return id;
  }

  static Future<void> _trimDebugLogs(Database db) async {
    const maxLogs = 500;
    final countResult = await db.rawQuery('SELECT COUNT(*) as cnt FROM debug_logs');
    final count = countResult.first['cnt'] as int;
    if (count > maxLogs) {
      await db.execute('DELETE FROM debug_logs WHERE id NOT IN (SELECT id FROM debug_logs ORDER BY timestamp DESC LIMIT $maxLogs)');
    }
  }

  static Future<List<Map<String, dynamic>>> getDebugLogs() async {
    final db = await database;
    return await db.query('debug_logs', orderBy: 'timestamp DESC');
  }

  static Future<Map<String, dynamic>?> getDebugLog(int id) async {
    final db = await database;
    final result = await db.query('debug_logs', where: 'id = ?', whereArgs: [id]);
    return result.isNotEmpty ? result.first : null;
  }

  static Future<void> clearDebugLogs() async {
    final db = await database;
    await db.delete('debug_logs');
  }

  static Future<List<PlannedMessage>> getPlannedMessages() async {
    final db = await database;
    final maps = await db.query('planned_messages', orderBy: 'scheduled_time ASC');
    return maps.map(PlannedMessage.fromMap).toList();
  }

  static Future<int> insertPlannedMessage(PlannedMessage msg) async {
    final db = await database;
    return await db.insert('planned_messages', msg.toMap());
  }

  static Future<void> updatePlannedMessage(PlannedMessage msg) async {
    final db = await database;
    await db.update('planned_messages', msg.toMap(), where: 'id = ?', whereArgs: [msg.id]);
  }

  static Future<void> deletePlannedMessage(int id) async {
    final db = await database;
    await db.delete('planned_messages', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> markDelivered(int id) async {
    final db = await database;
    await db.update('planned_messages', {'delivered': 1}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> getMaxLongTermIdNumber() async {
    final db = await database;
    final result = await db.rawQuery("SELECT MAX(CAST(SUBSTR(id, 2) AS INTEGER)) as max_id FROM long_term_memories");
    return result.first['max_id'] as int? ?? 0;
  }

  static Future<int> getMaxBaseIdNumber() async {
    final db = await database;
    final result = await db.rawQuery("SELECT MAX(CAST(SUBSTR(id, 2) AS INTEGER)) as max_id FROM base_memories");
    return result.first['max_id'] as int? ?? 0;
  }

  // ─── 数据库备份与恢复 ─────────────

  static Future<File> backupDatabase(String destPath) async {
    final dbPath = join(await getDatabasesPath(), 'aichat.db');
    final source = File(dbPath);
    final dest = File(destPath);
    await source.copy(destPath);
    return dest;
  }

  static Future<void> restoreDatabase(String sourcePath) async {
    final db = await database;
    await db.close();
    _database = null;
    final dbPath = join(await getDatabasesPath(), 'aichat.db');
    final dest = File(dbPath);
    if (await dest.exists()) {
      await dest.delete();
    }
    await File(sourcePath).copy(dbPath);
  }

  // ─── 人设迁移 ────────────────────

  static Future<void> migrateDefaultPersona(String newPersona) async {
    final db = await database;
    final oldKeywords = ['你是用户的AI智能助手', '你是用户的私人AI管家'];
    final existing = await db.query('base_memories', where: 'type = ?', whereArgs: ['setting']);
    for (final row in existing) {
      final content = row['content'] as String;
      for (final kw in oldKeywords) {
        if (content.contains(kw)) {
          await db.update('base_memories', {'content': newPersona, 'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [row['id']]);
          break;
        }
      }
    }
  }
}
