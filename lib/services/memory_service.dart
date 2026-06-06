import '../models/short_term_message.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import 'database_service.dart';

class MemoryService {
  final List<ShortTermMessage> _shortTermMessages = [];
  int _shortTermSeq = 0;
  int maxShortTermRounds = 20;
  String? _agentId;
  String? _groupId;

  final Map<String, _MemorySnapshot> _cache = {};

  List<ShortTermMessage> get shortTermMessages => List.unmodifiable(_shortTermMessages);

  void setAgentId(String? id) {
    if (_agentId != id) {
      _agentId = id;
      _groupId = null;
      _shortTermMessages.clear();
      _shortTermSeq = 0;
    }
  }

  void _invalidateCache(String? key) {
    if (key != null) _cache.remove(key);
  }

  void invalidateCurrentCache() => _invalidateCache(_agentId);

  String? get agentId => _agentId;

  void setGroupId(String? id) {
    _groupId = id;
  }

  String? get groupId => _groupId;

  Future<void> loadShortTermFromDb(int limit) async {
    final msgs = await DatabaseService.getShortTermMessages(limit: limit, agentId: _agentId);
    _shortTermMessages.clear();
    _shortTermMessages.addAll(msgs);
    _shortTermSeq = await DatabaseService.getMaxShortTermSeq(agentId: _agentId);
  }

  String _nextShortTermId() {
    _shortTermSeq++;
    return 'S${_shortTermSeq.toString().padLeft(3, '0')}';
  }

  ShortTermMessage addShortTermMessage({required String role, required String content}) {
    final msg = ShortTermMessage(id: _nextShortTermId(), role: role, content: content, agentId: _agentId);
    _shortTermMessages.add(msg);
    _trimShortTerm();
    DatabaseService.insertShortTermMessage(msg);
    return msg;
  }

  void _trimShortTerm() {
    while (_shortTermMessages.length > maxShortTermRounds) {
      final removed = _shortTermMessages.removeAt(0);
      DatabaseService.deleteShortTermMessage(removed.id, agentId: _agentId);
    }
  }

  void clearShortTerm() {
    for (final msg in _shortTermMessages) {
      DatabaseService.deleteShortTermMessage(msg.id, agentId: _agentId);
    }
    _shortTermMessages.clear();
    _shortTermSeq = 0;
    if (_agentId != null) {
      DatabaseService.clearShortTermMessages(agentId: _agentId!);
    }
  }

  List<Map<String, dynamic>> getShortTermAsMessages() {
    return _shortTermMessages.map((m) => m.toOpenAiMessage()).toList();
  }

  void compressShortTerm(int keepRounds) {
    final keep = keepRounds.clamp(1, maxShortTermRounds);
    while (_shortTermMessages.length > keep) {
      final removed = _shortTermMessages.removeAt(0);
      DatabaseService.deleteShortTermMessage(removed.id, agentId: _agentId);
    }
  }

  Future<void> deleteShortTermMessage(String id) async {
    _shortTermMessages.removeWhere((m) => m.id == id);
    await DatabaseService.deleteShortTermMessage(id, agentId: _agentId);
  }

  // ─── 长期记忆 ────

  Future<String> createLongTermMemory({required String field, required String content}) async {
    _invalidateCache(_agentId);
    final maxNum = await DatabaseService.getMaxLongTermIdNumber(agentId: _agentId, groupId: _groupId);
    final newId = 'L${(maxNum + 1).toString().padLeft(3, '0')}';
    final memory = LongTermMemory(id: newId, field: field, content: content, agentId: _agentId, groupId: _groupId);
    await DatabaseService.insertLongTermMemory(memory);
    return newId;
  }

  Future<void> updateLongTermMemory({required String targetId, required String content, String? field}) async {
    _invalidateCache(_agentId);
    await DatabaseService.updateLongTermMemory(
      LongTermMemory(id: targetId, field: field ?? 'status', content: content, agentId: _agentId),
      agentId: _agentId,
    );
  }

  Future<void> deleteLongTermMemory(String id) async {
    _invalidateCache(_agentId);
    await DatabaseService.deleteLongTermMemory(id, agentId: _agentId);
  }

  Future<List<LongTermMemory>> getLongTermMemories() async {
    final result = await DatabaseService.getLongTermMemories(agentId: _agentId, groupId: _groupId);
    if (_agentId != null) {
      _cache[_agentId!] = (_cache[_agentId!] ?? _MemorySnapshot()).copyWith(longTerm: result);
    }
    return result;
  }

  Future<List<LongTermMemory>> compressLongTerm(int keepCount) async {
    final all = await getLongTermMemories();
    if (all.length <= keepCount) return all;
    all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final toKeep = all.take(keepCount).toList();
    for (final item in all.skip(keepCount)) {
      await deleteLongTermMemory(item.id);
    }
    return toKeep;
  }

  // ─── 基础记忆 ────

  Future<String> createBaseMemory({required String type, required String content}) async {
    _invalidateCache(_agentId);
    final maxNum = await DatabaseService.getMaxBaseIdNumber(agentId: _agentId, groupId: _groupId);
    final newId = 'B${(maxNum + 1).toString().padLeft(3, '0')}';
    final memory = BaseMemory(id: newId, type: type, content: content, agentId: _agentId, groupId: _groupId);
    await DatabaseService.insertBaseMemory(memory);
    return newId;
  }

  Future<void> updateBaseMemory(BaseMemory memory) async {
    _invalidateCache(_agentId);
    await DatabaseService.updateBaseMemory(memory, agentId: _agentId);
  }

  Future<void> deleteBaseMemory(String id) async {
    _invalidateCache(_agentId);
    await DatabaseService.deleteBaseMemory(id, agentId: _agentId);
  }

  Future<List<BaseMemory>> getBaseMemories() async {
    final result = await DatabaseService.getBaseMemories(agentId: _agentId, groupId: _groupId);
    if (_agentId != null) {
      _cache[_agentId!] = (_cache[_agentId!] ?? _MemorySnapshot()).copyWith(base: result);
    }
    return result;
  }

  Future<List<BaseMemory>> compressBaseMemories(int keepEventCount) async {
    final all = await getBaseMemories();
    final settings = all.where((m) => m.isSetting).toList();
    final events = all.where((m) => m.isEvent).toList();
    events.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final toKeep = events.take(keepEventCount).toList();
    for (final item in events.skip(keepEventCount)) {
      await deleteBaseMemory(item.id);
    }
    return [...settings, ...toKeep];
  }

  // ─── 提示词构建 ──

  Future<String> buildLongTermPrompt() async {
    final memories = await getLongTermMemories();
    if (memories.isEmpty) return '（暂无长期记忆条目）';
    return memories.map((m) => m.toPromptLine()).join('\n');
  }

  Future<String> buildBasePrompt() async {
    final memories = await getBaseMemories();
    if (memories.isEmpty) return '（暂无基础记忆条目）';
    return memories.map((m) => m.toPromptLine()).join('\n');
  }

  static int estimateTokens(String text) {
    int chineseChars = 0, otherChars = 0;
    for (final char in text.runes) {
      if (char >= 0x4E00 && char <= 0x9FFF || char >= 0x3400 && char <= 0x4DBF) { chineseChars++; } else { otherChars++; }
    }
    return (chineseChars * 1.5 + otherChars * 0.25).ceil();
  }

  Future<int> estimateContextTokens() async {
    int total = 0;
    for (final msg in _shortTermMessages) { total += estimateTokens(msg.content); }
    final longTerm = await getLongTermMemories();
    for (final m in longTerm) { total += estimateTokens('${m.field}: ${m.content}'); }
    final base = await getBaseMemories();
    for (final m in base) { total += estimateTokens(m.content); }
    return total;
  }
}

class _MemorySnapshot {
  final List<LongTermMemory> longTerm;
  final List<BaseMemory> base;
  const _MemorySnapshot({this.longTerm = const [], this.base = const []});
  _MemorySnapshot copyWith({List<LongTermMemory>? longTerm, List<BaseMemory>? base}) =>
      _MemorySnapshot(longTerm: longTerm ?? this.longTerm, base: base ?? this.base);
}
