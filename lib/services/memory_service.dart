import '../models/short_term_message.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import 'database_service.dart';

class MemoryService {
  // ─── 短期记忆（内存+持久化） ──────────

  final List<ShortTermMessage> _shortTermMessages = [];
  int _shortTermSeq = 0;
  int maxShortTermRounds = 20;

  List<ShortTermMessage> get shortTermMessages =>
      List.unmodifiable(_shortTermMessages);

  /// 从数据库加载短期记忆
  Future<void> loadShortTermFromDb(int limit) async {
    final msgs = await DatabaseService.getShortTermMessages(limit: limit);
    _shortTermMessages.clear();
    _shortTermMessages.addAll(msgs);
    _shortTermSeq = await DatabaseService.getMaxShortTermSeq();
  }

  String _nextShortTermId() {
    _shortTermSeq++;
    return 'S${_shortTermSeq.toString().padLeft(3, '0')}';
  }

  ShortTermMessage addShortTermMessage({
    required String role,
    required String content,
  }) {
    final msg = ShortTermMessage(
      id: _nextShortTermId(),
      role: role,
      content: content,
    );
    _shortTermMessages.add(msg);
    _trimShortTerm();
    DatabaseService.insertShortTermMessage(msg);
    return msg;
  }

  void _trimShortTerm() {
    while (_shortTermMessages.length > maxShortTermRounds) {
      final removed = _shortTermMessages.removeAt(0);
      DatabaseService.deleteShortTermMessage(removed.id);
    }
  }

  void clearShortTerm() {
    for (final msg in _shortTermMessages) {
      DatabaseService.deleteShortTermMessage(msg.id);
    }
    _shortTermMessages.clear();
    _shortTermSeq = 0;
  }

  List<Map<String, dynamic>> getShortTermAsMessages() {
    return _shortTermMessages.map((m) => m.toOpenAiMessage()).toList();
  }

  void compressShortTerm(int keepRounds) {
    final keep = keepRounds.clamp(1, maxShortTermRounds);
    while (_shortTermMessages.length > keep) {
      final removed = _shortTermMessages.removeAt(0);
      DatabaseService.deleteShortTermMessage(removed.id);
    }
  }

  /// 删除单条短期记忆（用于长按删除）
  Future<void> deleteShortTermMessage(String id) async {
    _shortTermMessages.removeWhere((m) => m.id == id);
    await DatabaseService.deleteShortTermMessage(id);
  }

  // ─── 长期记忆（持久化） ────────────────

  Future<String> createLongTermMemory({
    required String field,
    required String content,
  }) async {
    final maxNum = await DatabaseService.getMaxLongTermIdNumber();
    final newId = 'L${(maxNum + 1).toString().padLeft(3, '0')}';
    final memory = LongTermMemory(
      id: newId,
      field: field,
      content: content,
    );
    await DatabaseService.insertLongTermMemory(memory);
    return newId;
  }

  Future<void> updateLongTermMemory({
    required String targetId,
    required String content,
    String? field,
  }) async {
    final all = await DatabaseService.getLongTermMemories();
    final existing = all.firstWhere((m) => m.id == targetId);
    final updated = existing.copyWith(
      content: content,
      field: field ?? existing.field,
      updatedAt: DateTime.now(),
    );
    await DatabaseService.updateLongTermMemory(updated);
  }

  Future<void> deleteLongTermMemory(String id) async {
    await DatabaseService.deleteLongTermMemory(id);
  }

  Future<List<LongTermMemory>> getLongTermMemories() async {
    return await DatabaseService.getLongTermMemories();
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

  // ─── 基础记忆（持久化） ────────────────

  Future<String> createBaseMemory({
    required String type,
    required String content,
  }) async {
    final maxNum = await DatabaseService.getMaxBaseIdNumber();
    final newId = 'B${(maxNum + 1).toString().padLeft(3, '0')}';
    final memory = BaseMemory(id: newId, type: type, content: content);
    await DatabaseService.insertBaseMemory(memory);
    return newId;
  }

  Future<void> updateBaseMemory(BaseMemory memory) async {
    await DatabaseService.updateBaseMemory(memory);
  }

  Future<void> deleteBaseMemory(String id) async {
    await DatabaseService.deleteBaseMemory(id);
  }

  Future<List<BaseMemory>> getBaseMemories() async {
    return await DatabaseService.getBaseMemories();
  }

  Future<List<BaseMemory>> compressBaseMemories(int keepEventCount) async {
    final all = await getBaseMemories();
    final settings = all.where((m) => m.isSetting).toList();
    final events = all.where((m) => m.isEvent).toList();
    events.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final toKeep = events.take(keepEventCount).toList();
    final toDelete = events.skip(keepEventCount).toList();
    for (final item in toDelete) {
      await deleteBaseMemory(item.id);
    }
    return [...settings, ...toKeep];
  }

  // ─── 提示词构建 ──────────────────────

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

  // ─── Token 估算 ──────────────────────

  static int estimateTokens(String text) {
    int chineseChars = 0;
    int otherChars = 0;
    for (final char in text.runes) {
      if (char >= 0x4E00 && char <= 0x9FFF ||
          char >= 0x3400 && char <= 0x4DBF) {
        chineseChars++;
      } else {
        otherChars++;
      }
    }
    return (chineseChars * 1.5 + otherChars * 0.25).ceil();
  }

  Future<int> estimateContextTokens() async {
    int total = 0;
    for (final msg in _shortTermMessages) {
      total += estimateTokens(msg.content);
    }
    final longTerm = await getLongTermMemories();
    for (final m in longTerm) {
      total += estimateTokens('${m.field}: ${m.content}');
    }
    final base = await getBaseMemories();
    for (final m in base) {
      total += estimateTokens(m.content);
    }
    return total;
  }
}
