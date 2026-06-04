import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import '../models/planned_message.dart';
import '../models/short_term_message.dart';
import '../models/provider_config.dart';
import '../models/agent.dart';
import '../models/group_chat.dart';
import '../models/group_member.dart';
import '../models/group_message.dart';
import '../models/group_shared_memory.dart';

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
    final db = await openDatabase(path, version: 9, onCreate: _onCreate, onUpgrade: _onUpgrade);
    await _ensureGroupTablesExist(db);
    return db;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE agents (id TEXT PRIMARY KEY, name TEXT NOT NULL, gender TEXT DEFAULT '', description TEXT DEFAULT '', persona TEXT NOT NULL, opening_line TEXT, avatar_color INTEGER, avatar_path TEXT, chat_background TEXT, is_active INTEGER DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE long_term_memories (id TEXT PRIMARY KEY, field TEXT NOT NULL, content TEXT NOT NULL, agent_id TEXT, group_id TEXT, updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE base_memories (id TEXT PRIMARY KEY, type TEXT NOT NULL, content TEXT NOT NULL, agent_id TEXT, group_id TEXT, updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE planned_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, scheduled_time INTEGER NOT NULL, message TEXT NOT NULL, delivered INTEGER NOT NULL DEFAULT 0, agent_id TEXT, group_id TEXT)''');
    await db.execute('''CREATE TABLE short_term_messages (id TEXT PRIMARY KEY, role TEXT NOT NULL, content TEXT NOT NULL, timestamp INTEGER NOT NULL, agent_id TEXT, group_id TEXT)''');
    await db.execute('''CREATE TABLE chat_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, content TEXT NOT NULL, timestamp INTEGER NOT NULL, short_mem_id TEXT, agent_id TEXT, group_id TEXT, image_path TEXT)''');
    await db.execute('''CREATE TABLE debug_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, request_summary TEXT NOT NULL, response_summary TEXT NOT NULL, error TEXT, duration_ms INTEGER, agent_id TEXT)''');
    await db.execute('''CREATE TABLE providers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, api_base_url TEXT NOT NULL, api_key TEXT NOT NULL, selected_model TEXT DEFAULT '', created_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE token_usage (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, prompt_tokens INTEGER NOT NULL, completion_tokens INTEGER NOT NULL, model TEXT, agent_id TEXT)''');
    await db.execute('''CREATE TABLE group_chats (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT DEFAULT '', avatar_color INTEGER, group_persona TEXT, speech_mode TEXT DEFAULT 'free', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE group_members (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, agent_id TEXT NOT NULL, role TEXT DEFAULT 'member', is_present INTEGER DEFAULT 1, joined_at INTEGER, FOREIGN KEY (group_id) REFERENCES group_chats(id) ON DELETE CASCADE, FOREIGN KEY (agent_id) REFERENCES agents(id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE group_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, sender_type TEXT NOT NULL, sender_id TEXT, sender_name TEXT, content TEXT NOT NULL, timestamp INTEGER, tool_call_data TEXT, FOREIGN KEY (group_id) REFERENCES group_chats(id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE group_short_term (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, role TEXT NOT NULL, sender_name TEXT, content TEXT, timestamp INTEGER, FOREIGN KEY (group_id) REFERENCES group_chats(id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE group_shared_memories (id TEXT PRIMARY KEY, group_id TEXT NOT NULL, field TEXT NOT NULL, content TEXT NOT NULL, updated_at INTEGER, FOREIGN KEY (group_id) REFERENCES group_chats(id) ON DELETE CASCADE)''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('[DB] onUpgrade: $oldVersion -> $newVersion');
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
    if (oldVersion < 6) {
      try { await db.execute("ALTER TABLE chat_messages ADD COLUMN image_path TEXT"); } catch (_) {}
    }
    if (oldVersion < 7) {
      await db.execute('''CREATE TABLE IF NOT EXISTS group_chats (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT DEFAULT '', avatar_color INTEGER, group_persona TEXT, speech_mode TEXT DEFAULT 'free', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
      await db.execute('''CREATE TABLE IF NOT EXISTS group_members (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, agent_id TEXT NOT NULL, role TEXT DEFAULT 'member', is_present INTEGER DEFAULT 1, joined_at INTEGER)''');
      await db.execute('''CREATE TABLE IF NOT EXISTS group_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, sender_type TEXT NOT NULL, sender_id TEXT, sender_name TEXT, content TEXT NOT NULL, timestamp INTEGER, tool_call_data TEXT)''');
      await db.execute('''CREATE TABLE IF NOT EXISTS group_short_term (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, role TEXT NOT NULL, sender_name TEXT, content TEXT, timestamp INTEGER)''');
      await db.execute('''CREATE TABLE IF NOT EXISTS group_shared_memories (id TEXT PRIMARY KEY, group_id TEXT NOT NULL, field TEXT NOT NULL, content TEXT NOT NULL, updated_at INTEGER)''');
      for (final table in ['long_term_memories', 'base_memories', 'short_term_messages', 'chat_messages', 'planned_messages']) {
        try { await db.execute("ALTER TABLE $table ADD COLUMN group_id TEXT"); } catch (_) {}
      }
    }
    if (oldVersion < 8) {
      debugPrint('[DB] v8 migration: ensuring group tables exist');
      await _ensureGroupTablesExist(db);
    }
    if (oldVersion < 9) {
      try { await db.execute("ALTER TABLE agents ADD COLUMN opening_line TEXT"); } catch (_) {}
      debugPrint('[DB] v9 migration: added opening_line column');
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
    await db.delete('group_members', where: 'agent_id = ?', whereArgs: [id]);
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

  static Future<int> insertChatMessage({required String role, required String content, required int timestampMs, String? shortMemId, String? agentId, String? imagePath}) async {
    final db = await database;
    return await db.insert('chat_messages', {'role': role, 'content': content, 'timestamp': timestampMs, 'short_mem_id': shortMemId, 'agent_id': agentId, 'image_path': imagePath});
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

  // ══════════════════════════════════════
  // 群聊 — Group Chats
  // ══════════════════════════════════════

  static Future<List<GroupChat>> getGroupChats() async {
    final db = await database;
    final maps =
        await db.query('group_chats', orderBy: 'updated_at DESC');
    return maps.map(GroupChat.fromMap).toList();
  }

  static Future<GroupChat?> getGroupChat(String id) async {
    final db = await database;
    final maps =
        await db.query('group_chats', where: 'id = ?', whereArgs: [id], limit: 1);
    return maps.isNotEmpty ? GroupChat.fromMap(maps.first) : null;
  }

  static Future<void> insertGroupChat(GroupChat g) async {
    final db = await database;
    await db.insert('group_chats', g.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateGroupChat(GroupChat g) async {
    final db = await database;
    await db.update('group_chats', g.toMap(),
        where: 'id = ?', whereArgs: [g.id]);
  }

  static Future<void> deleteGroupChat(String id) async {
    final db = await database;
    await db.execute('PRAGMA foreign_keys = ON');
    await db.delete('group_chats', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteGroupChatCascade(String groupId) async {
    final db = await database;
    await db.execute('PRAGMA foreign_keys = ON');
    await db.delete('group_short_term', where: 'group_id = ?', whereArgs: [groupId]);
    await db.delete('group_shared_memories', where: 'group_id = ?', whereArgs: [groupId]);
    await db.delete('group_messages', where: 'group_id = ?', whereArgs: [groupId]);
    await db.delete('group_members', where: 'group_id = ?', whereArgs: [groupId]);
    await db.delete('long_term_memories', where: 'group_id = ?', whereArgs: [groupId]);
    await db.delete('base_memories', where: 'group_id = ?', whereArgs: [groupId]);
    await db.delete('group_chats', where: 'id = ?', whereArgs: [groupId]);
    debugPrint('[DB] Cascade deleted group $groupId');
  }

  static Future<void> deleteGroupMembersForGroup(String groupId) async {
    final db = await database;
    await db.delete('group_members', where: 'group_id = ?', whereArgs: [groupId]);
  }

  static Future<void> deleteGroupMessagesForGroup(String groupId) async {
    final db = await database;
    await db.delete('group_messages', where: 'group_id = ?', whereArgs: [groupId]);
  }

  static Future<void> deleteGroupSharedMemoriesForGroup(String groupId) async {
    final db = await database;
    await db.delete('group_shared_memories', where: 'group_id = ?', whereArgs: [groupId]);
  }

  // ═══ 群成员 — Group Members ═══

  static Future<List<GroupMember>> getGroupMembers(String groupId) async {
    final db = await database;
    final maps = await db.query('group_members',
        where: 'group_id = ?', whereArgs: [groupId], orderBy: 'joined_at ASC');
    return maps.map(GroupMember.fromMap).toList();
  }

  static Future<void> insertGroupMember(GroupMember m) async {
    final db = await database;
    await db.insert('group_members', m.toMap());
  }

  static Future<void> updateGroupMember(GroupMember m) async {
    final db = await database;
    await db.update('group_members', m.toMap(),
        where: 'id = ?', whereArgs: [m.id]);
  }

  static Future<void> deleteGroupMember(int id) async {
    final db = await database;
    await db.delete('group_members', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteAllGroupMembers(String groupId) async {
    final db = await database;
    await db.delete('group_members',
        where: 'group_id = ?', whereArgs: [groupId]);
  }

  // ═══ 群聊消息 — Group Messages ═══

  static Future<List<GroupMessage>> getGroupMessages(String groupId) async {
    final db = await database;
    final maps = await db.query('group_messages',
        where: 'group_id = ?', whereArgs: [groupId], orderBy: 'timestamp ASC');
    return maps.map(GroupMessage.fromMap).toList();
  }

  static Future<int> insertGroupMessage(GroupMessage msg) async {
    final db = await database;
    return await db.insert('group_messages', msg.toMap());
  }

  static Future<void> deleteGroupMessage(int id) async {
    final db = await database;
    await db.delete('group_messages', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearGroupMessages(String groupId) async {
    final db = await database;
    await db.delete('group_messages',
        where: 'group_id = ?', whereArgs: [groupId]);
  }

  // ═══ 群短记忆 — Group Short Term ═══

  static Future<void> insertGroupShortTerm({
    required String groupId,
    required String role,
    String? senderName,
    required String content,
    required int timestamp,
  }) async {
    final db = await database;
    await db.insert('group_short_term', {
      'group_id': groupId,
      'role': role,
      'sender_name': senderName,
      'content': content,
      'timestamp': timestamp,
    });
  }

  static Future<List<Map<String, dynamic>>> getGroupShortTerm(
      String groupId) async {
    final db = await database;
    return await db.query('group_short_term',
        where: 'group_id = ?', whereArgs: [groupId], orderBy: 'timestamp ASC');
  }

  static Future<int> getGroupShortTermCount(String groupId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM group_short_term WHERE group_id = ?',
        [groupId]);
    return result.first['cnt'] as int;
  }

  static Future<void> deleteOldestGroupShortTerm(
      String groupId, int keep) async {
    final db = await database;
    final countResult = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM group_short_term WHERE group_id = ?',
        [groupId]);
    final total = countResult.first['cnt'] as int;
    if (total > keep) {
      final toDelete = total - keep;
      await db.rawDelete(
          'DELETE FROM group_short_term WHERE group_id = ? AND id IN (SELECT id FROM group_short_term WHERE group_id = ? ORDER BY timestamp ASC LIMIT ?)',
          [groupId, groupId, toDelete]);
    }
  }

  static Future<void> clearGroupShortTerm(String groupId) async {
    final db = await database;
    await db.delete('group_short_term',
        where: 'group_id = ?', whereArgs: [groupId]);
  }

  // ═══ 群共享记忆 — Group Shared Memories ═══

  static Future<List<GroupSharedMemory>> getGroupSharedMemories(
      String groupId) async {
    final db = await database;
    final maps = await db.query('group_shared_memories',
        where: 'group_id = ?', whereArgs: [groupId], orderBy: 'id ASC');
    return maps.map(GroupSharedMemory.fromMap).toList();
  }

  static Future<void> insertGroupSharedMemory(GroupSharedMemory m) async {
    final db = await database;
    await db.insert('group_shared_memories', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateGroupSharedMemory(GroupSharedMemory m) async {
    final db = await database;
    await db.update('group_shared_memories', {
      'field': m.field,
      'content': m.content,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [m.id]);
  }

  static Future<void> deleteGroupSharedMemory(String id) async {
    final db = await database;
    await db.delete('group_shared_memories',
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> getMaxGroupSharedIdNumber(String groupId) async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT MAX(CAST(SUBSTR(id, 3) AS INTEGER)) as max_id FROM group_shared_memories WHERE group_id = ?",
        [groupId]);
    return result.first['max_id'] as int? ?? 0;
  }

  // ─── 支持 group_id 的长期记忆查询 ──────

  static Future<List<LongTermMemory>> getLongTermMemoriesForGroup(
      String agentId, String groupId) async {
    final db = await database;
    final maps = await db.query('long_term_memories',
        where: 'agent_id = ? AND group_id = ?',
        whereArgs: [agentId, groupId],
        orderBy: 'id ASC');
    return maps.map(LongTermMemory.fromMap).toList();
  }

  static Future<List<BaseMemory>> getBaseMemoriesForGroup(
      String agentId, String groupId) async {
    final db = await database;
    final maps = await db.query('base_memories',
        where: 'agent_id = ? AND group_id = ?',
        whereArgs: [agentId, groupId],
        orderBy: 'id ASC');
    return maps.map(BaseMemory.fromMap).toList();
  }

  /// Ensure all group-related tables exist, regardless of migration state.
  static Future<void> _ensureGroupTablesExist(Database db) async {
    debugPrint('[DB] _ensureGroupTablesExist: checking...');
    try {
      await db.execute('''CREATE TABLE IF NOT EXISTS group_chats (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT DEFAULT '', avatar_color INTEGER, group_persona TEXT, speech_mode TEXT DEFAULT 'free', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
      await db.execute('''CREATE TABLE IF NOT EXISTS group_members (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, agent_id TEXT NOT NULL, role TEXT DEFAULT 'member', is_present INTEGER DEFAULT 1, joined_at INTEGER)''');
      await db.execute('''CREATE TABLE IF NOT EXISTS group_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, sender_type TEXT NOT NULL, sender_id TEXT, sender_name TEXT, content TEXT NOT NULL, timestamp INTEGER, tool_call_data TEXT)''');
      await db.execute('''CREATE TABLE IF NOT EXISTS group_short_term (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id TEXT NOT NULL, role TEXT NOT NULL, sender_name TEXT, content TEXT, timestamp INTEGER)''');
      try { await db.execute("UPDATE group_short_term SET role = 'assistant' WHERE role = 'agent'"); } catch (_) {}
      await db.execute('''CREATE TABLE IF NOT EXISTS group_shared_memories (id TEXT PRIMARY KEY, group_id TEXT NOT NULL, field TEXT NOT NULL, content TEXT NOT NULL, updated_at INTEGER)''');
      for (final table in ['long_term_memories', 'base_memories', 'short_term_messages', 'chat_messages', 'planned_messages']) {
        try { await db.execute("ALTER TABLE $table ADD COLUMN group_id TEXT"); } catch (_) {}
      }
      try { await db.execute("ALTER TABLE agents ADD COLUMN opening_line TEXT"); } catch (_) {}
      try { await db.execute("UPDATE group_short_term SET role = 'assistant' WHERE role = 'agent'"); } catch (_) {}
      final result = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='group_chats'");
      debugPrint('[DB] group_chats table exists: ${result.isNotEmpty}');
    } catch (e) {
      debugPrint('[DB] _ensureGroupTablesExist error: $e');
    }
  }
}
