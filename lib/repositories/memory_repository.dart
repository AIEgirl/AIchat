import 'package:flutter/foundation.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import '../models/short_term_message.dart';
import '../services/database_service.dart';

class MemoryRepository {
  const MemoryRepository();

  Future<List<LongTermMemory>> getLongTermMemories({required String agentId, String? groupId}) async {
    try {
      return await DatabaseService.getLongTermMemories(agentId: agentId, groupId: groupId);
    } catch (e) {
      debugPrint('[MemoryRepo] getLongTermMemories error: $e');
      return [];
    }
  }

  Future<String> createLongTermMemory({required String agentId, required String field, required String content, String? groupId}) async {
    final maxNum = await DatabaseService.getMaxLongTermIdNumber(agentId: agentId, groupId: groupId);
    final id = 'L${(maxNum + 1).toString().padLeft(3, '0')}';
    final m = LongTermMemory(id: id, field: field, content: content, agentId: agentId, groupId: groupId);
    await DatabaseService.insertLongTermMemory(m);
    return id;
  }

  Future<void> updateLongTermMemory({required String targetId, required String content, String? field, String? agentId}) async {
    final m = LongTermMemory(id: targetId, field: field ?? 'status', content: content, agentId: agentId);
    await DatabaseService.updateLongTermMemory(m, agentId: agentId);
  }

  Future<void> deleteLongTermMemory(String id, {String? agentId}) async {
    await DatabaseService.deleteLongTermMemory(id, agentId: agentId);
  }

  Future<List<BaseMemory>> getBaseMemories({required String agentId, String? groupId}) async {
    try {
      return await DatabaseService.getBaseMemories(agentId: agentId, groupId: groupId);
    } catch (e) {
      debugPrint('[MemoryRepo] getBaseMemories error: $e');
      return [];
    }
  }

  Future<String> createBaseMemory({required String agentId, required String type, required String content, String? groupId}) async {
    final maxNum = await DatabaseService.getMaxBaseIdNumber(agentId: agentId, groupId: groupId);
    final id = 'B${(maxNum + 1).toString().padLeft(3, '0')}';
    final m = BaseMemory(id: id, type: type, content: content, agentId: agentId, groupId: groupId);
    await DatabaseService.insertBaseMemory(m);
    return id;
  }

  Future<void> updateBaseMemory(BaseMemory memory, {String? agentId}) async {
    await DatabaseService.updateBaseMemory(memory, agentId: agentId);
  }

  Future<void> deleteBaseMemory(String id, {String? agentId}) async {
    await DatabaseService.deleteBaseMemory(id, agentId: agentId);
  }

  Future<List<ShortTermMessage>> getShortTermMessages({required String agentId, int? limit}) async {
    try {
      return await DatabaseService.getShortTermMessages(agentId: agentId, limit: limit);
    } catch (e) {
      debugPrint('[MemoryRepo] getShortTermMessages error: $e');
      return [];
    }
  }

  Future<int> getMaxShortTermSeq({required String agentId}) async {
    return await DatabaseService.getMaxShortTermSeq(agentId: agentId);
  }

  Future<void> insertShortTermMessage(ShortTermMessage msg) async {
    await DatabaseService.insertShortTermMessage(msg);
  }

  Future<void> deleteShortTermMessage(String id) async {
    await DatabaseService.deleteShortTermMessage(id);
  }

  Future<void> clearShortTermMessages({required String agentId}) async {
    await DatabaseService.clearShortTermMessages(agentId: agentId);
  }

  Future<void> deleteByAgent(String agentId) async {
    await DatabaseService.clearLongTermMemories(agentId: agentId);
    await DatabaseService.clearBaseMemories(agentId: agentId);
    await DatabaseService.clearShortTermMessages(agentId: agentId);
  }
}
