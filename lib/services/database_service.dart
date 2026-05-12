import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import '../models/planned_message.dart';
import '../models/short_term_message.dart';
import '../models/provider_config.dart';
import '../models/agent.dart';

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
    return await openDatabase(path, version: 5, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE agents (id TEXT PRIMARY KEY, name TEXT NOT NULL, gender TEXT DEFAULT '', description TEXT DEFAULT '', persona TEXT NOT NULL, avatar_color INTEGER, avatar_path TEXT, chat_background TEXT, is_active INTEGER DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE long_term_memories (id TEXT PRIMARY KEY, field TEXT NOT NULL, content TEXT NOT NULL, agent_id TEXT, updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE base_memories (id TEXT PRIMARY KEY, type TEXT NOT NULL, content TEXT NOT NULL, agent_id TEXT, updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE planned_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, scheduled_time INTEGER NOT NULL, message TEXT NOT NULL, delivered INTEGER NOT NULL DEFAULT 0, agent_id TEXT)''');
    await db.execute('''CREATE TABLE short_term_messages (id TEXT PRIMARY KEY, role TEXT NOT NULL, content TEXT NOT NULL, timestamp INTEGER NOT NULL, agent_id TEXT)''');
    await db.execute('''CREATE TABLE chat_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, content TEXT NOT NULL, timestamp INTEGER NOT NULL, short_mem_id TEXT, agent_id TEXT)''');
    await db.execute('''CREATE TABLE debug_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, request_summary TEXT NOT NULL, response_summary TEXT NOT NULL, error TEXT, duration_ms INTEGER, agent_id TEXT)''');
    await db.execute('''CREATE TABLE providers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, api_base_url TEXT NOT NULL, api_key TEXT NOT NULL, selected_model TEXT DEFAULT '', created_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE token_usage (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, prompt_tokens INTEGER NOT NULL, completion_tokens INTEGER NOT NULL, model TEXT, agent_id TEXT)''');
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
    if (oldVersion < 4) {
      await db.execute('''CREATE TABLE IF NOT EXISTS agents (id TEXT PRIMARY KEY, name TEXT NOT NULL, gender TEXT DEFAULT '', description TEXT DEFAULT '', persona TEXT NOT NULL, avatar_color INTEGER, is_active INTEGER DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
      for (final table in ['long_term_memories', 'base_memories', 'short_term_messages', 'chat_messages', 'debug_logs', 'token_usage', 'planned_messages']) {
        try { await db.execute('ALTER TABLE $table ADD COLUMN agent_id TEXT'); } catch (_) {}
      }
    }
    if (oldVersion < 5) {
      try { await db.execute("ALTER TABLE agents ADD COLUMN avatar_path TEXT"); } catch (_) {}
      try { await db.execute("ALTER TABLE agents ADD COLUMN chat_background TEXT"); } catch (_) {}
    }
  }

  // ─── Agents ──────────────────────────

  static Future<List<Agent>> getAgents() async {
    final db = await database;
    final maps = await db.query('agents', orderBy: 'created_at ASC');
    return maps.map(Agent.fromMap).toList();
  }

  static Future<Agent?> getActiveAgent() async {
    final db = await database;
    final maps = await db.query('agents', where: 'is_active = 1', limit: 1);
    return maps.isNotEmpty ? Agent.fromMap(maps.first) : null;
  }

  static Future<Agent?> getAgent(String id) async {
    final db = await database;
    final maps = await db.query('agents', where: 'id = ?', whereArgs: [id], limit: 1);
    return maps.isNotEmpty ? Agent.fromMap(maps.first) : null;
  }

  static Future<void> insertAgent(Agent agent) async {
    final db = await database;
    await db.insert('agents', agent.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateAgent(Agent agent) async {
    final db = await database;
    await db.update('agents', agent.toMap(), where: 'id = ?', whereArgs: [agent.id]);
  }

  static Future<void> deleteAgent(String id) async {
    final db = await database;
    await db.delete('agents', where: 'id = ?', whereArgs: [id]);
    for (final table in ['long_term_memories', 'base_memories', 'short_term_messages', 'chat_messages', 'planned_messages']) {
      await db.delete(table, where: 'agent_id = ?', whereArgs: [id]);
    }
  }

  static Future<void> setActiveAgent(String id) async {
    final db = await database;
    await db.update('agents', {'is_active': 0});
    await db.update('agents', {'is_active': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
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
    String? agentId,
  }) async {
    final db = await database;
    await db.insert('token_usage', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'model': model,
      'agent_id': agentId,
    });
  }

  static Future<List<Map<String, dynamic>>> getTokenUsage({int days = 30, String? agentId}) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final where = agentId != null ? 'timestamp >= ? AND agent_id = ?' : 'timestamp >= ?';
    final whereArgs = agentId != null ? [cutoff, agentId] : [cutoff];
    return await db.query('token_usage', where: where, whereArgs: whereArgs, orderBy: 'timestamp ASC');
  }

  // ─── 长期记忆 ──────────────────────

  static Future<List<LongTermMemory>> getLongTermMemories({String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      final maps = await db.query('long_term_memories', where: 'agent_id = ?', whereArgs: [agentId], orderBy: 'id ASC');
      return maps.map(LongTermMemory.fromMap).toList();
    }
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

  static Future<void> clearLongTermMemories({String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      await db.delete('long_term_memories', where: 'agent_id = ?', whereArgs: [agentId]);
    } else {
      await db.delete('long_term_memories');
    }
  }

  // ─── 基础记忆 ──────────────────────

  static Future<List<BaseMemory>> getBaseMemories({String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      final maps = await db.query('base_memories', where: 'agent_id = ?', whereArgs: [agentId], orderBy: 'id ASC');
      return maps.map(BaseMemory.fromMap).toList();
    }
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

  static Future<void> clearBaseMemories({String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      await db.delete('base_memories', where: 'agent_id = ?', whereArgs: [agentId]);
    } else {
      await db.delete('base_memories');
    }
  }

  // ─── 短期记忆 ──────────────────────

  static Future<List<ShortTermMessage>> getShortTermMessages({int? limit, String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      final maps = await db.query('short_term_messages', where: 'agent_id = ?', whereArgs: [agentId], orderBy: 'timestamp ASC', limit: limit);
      return maps.map(ShortTermMessage.fromMap).toList();
    }
    final maps = await db.query('short_term_messages', orderBy: 'timestamp ASC', limit: limit);
    return maps.map(ShortTermMessage.fromMap).toList();
  }

  static Future<int> getShortTermCount({String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM short_term_messages WHERE agent_id = ?', [agentId]);
      return result.first['cnt'] as int;
    }
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM short_term_messages');
    return result.first['cnt'] as int;
  }

  static Future<int> getMaxShortTermSeq({String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      final result = await db.rawQuery("SELECT MAX(CAST(SUBSTR(id, 2) AS INTEGER)) as max_id FROM short_term_messages WHERE agent_id = ?", [agentId]);
      return result.first['max_id'] as int? ?? 0;
    }
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

  static Future<void> clearShortTermMessages({String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      await db.delete('short_term_messages', where: 'agent_id = ?', whereArgs: [agentId]);
    } else {
      await db.delete('short_term_messages');
    }
  }

  // ─── 聊天消息 ──────────────────────

  static Future<int> insertChatMessage({required String role, required String content, required int timestampMs, String? shortMemId, String? agentId}) async {
    final db = await database;
    return await db.insert('chat_messages', {'role': role, 'content': content, 'timestamp': timestampMs, 'short_mem_id': shortMemId, 'agent_id': agentId});
  }

  static Future<List<Map<String, dynamic>>> getChatMessages({String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      return await db.query('chat_messages', where: 'agent_id = ?', whereArgs: [agentId], orderBy: 'timestamp ASC');
    }
    return await db.query('chat_messages', orderBy: 'timestamp ASC');
  }

  static Future<void> deleteChatMessage(int id) async {
    final db = await database;
    await db.delete('chat_messages', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearChatMessages({String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      await db.delete('chat_messages', where: 'agent_id = ?', whereArgs: [agentId]);
    } else {
      await db.delete('chat_messages');
    }
  }

  // ─── 调试日志 ──────────────────────

  static Future<int> insertDebugLog({required String requestSummary, required String responseSummary, String? error, int? durationMs, String? agentId}) async {
    final db = await database;
    final id = await db.insert('debug_logs', {'timestamp': DateTime.now().millisecondsSinceEpoch, 'request_summary': requestSummary, 'response_summary': responseSummary, 'error': error, 'duration_ms': durationMs, 'agent_id': agentId});
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

  static Future<List<Map<String, dynamic>>> getDebugLogs({String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      return await db.query('debug_logs', where: 'agent_id = ?', whereArgs: [agentId], orderBy: 'timestamp DESC');
    }
    return await db.query('debug_logs', orderBy: 'timestamp DESC');
  }

  static Future<void> clearDebugLogs() async {
    final db = await database;
    await db.delete('debug_logs');
  }

  // ─── 计划消息 ──────────────────────

  static Future<List<PlannedMessage>> getPlannedMessages({String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      final maps = await db.query('planned_messages', where: 'agent_id = ?', whereArgs: [agentId], orderBy: 'scheduled_time ASC');
      return maps.map(PlannedMessage.fromMap).toList();
    }
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

  // ─── ID 序号 ────────────────

  static Future<int> getMaxLongTermIdNumber({String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      final result = await db.rawQuery("SELECT MAX(CAST(SUBSTR(id, 2) AS INTEGER)) as max_id FROM long_term_memories WHERE agent_id = ?", [agentId]);
      return result.first['max_id'] as int? ?? 0;
    }
    final result = await db.rawQuery("SELECT MAX(CAST(SUBSTR(id, 2) AS INTEGER)) as max_id FROM long_term_memories");
    return result.first['max_id'] as int? ?? 0;
  }

  static Future<int> getMaxBaseIdNumber({String? agentId}) async {
    final db = await database;
    if (agentId != null) {
      final result = await db.rawQuery("SELECT MAX(CAST(SUBSTR(id, 2) AS INTEGER)) as max_id FROM base_memories WHERE agent_id = ?", [agentId]);
      return result.first['max_id'] as int? ?? 0;
    }
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
