import 'package:flutter/foundation.dart';
import '../services/database_service.dart';

class DebugRepository {
  const DebugRepository();

  Future<int> insertLog({
    required String requestSummary,
    required String responseSummary,
    String? error,
    int? durationMs,
    String? agentId,
    int? promptTokens,
    int? completionTokens,
  }) async {
    try {
      return await DatabaseService.insertDebugLog(
        requestSummary: requestSummary,
        responseSummary: responseSummary,
        error: error,
        durationMs: durationMs,
        agentId: agentId,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
      );
    } catch (e) {
      debugPrint('[DebugRepo] insertLog error: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getLogs({String? agentId}) async {
    try {
      return await DatabaseService.getDebugLogs(agentId: agentId);
    } catch (e) {
      debugPrint('[DebugRepo] getLogs error: $e');
      return [];
    }
  }

  Future<void> clearLogs({String? agentId}) async {
    await DatabaseService.clearDebugLogs(agentId: agentId);
  }

  Future<void> insertTokenUsage({required int promptTokens, required int completionTokens, String? model, String? agentId}) async {
    await DatabaseService.insertTokenUsage(promptTokens: promptTokens, completionTokens: completionTokens, model: model, agentId: agentId);
  }

  Future<List<Map<String, dynamic>>> getTokenUsage({int days = 30, String? agentId}) async {
    return await DatabaseService.getTokenUsage(days: days, agentId: agentId);
  }
}
