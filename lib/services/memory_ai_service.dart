import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import 'memory_service.dart';

void _mlog(String msg) {
  debugPrint('[MemoryAI] $msg');
}

class MemoryAiService {
  static Future<void> analyzeAndApply({
    required MemoryService memoryService,
    required String agentId,
    required String apiKey,
    required String baseUrl,
    required bool thinkingMode,
    required double temperature,
    required List<Map<String, dynamic>> shortTerm,
    required String persona,
    required List<LongTermMemory> existingLongTerm,
    required List<BaseMemory> existingBase,
  }) async {
    if (shortTerm.isEmpty || agentId.isEmpty || apiKey.isEmpty) return;

    final longTermLines = existingLongTerm.isNotEmpty
        ? existingLongTerm.map((m) => m.toPromptLine()).join('\n')
        : '（无长期记忆）';
    final baseLines = existingBase.isNotEmpty
        ? existingBase.map((m) => m.toPromptLine()).join('\n')
        : '（无基础记忆）';

    final shortTermLines = shortTerm.map((m) {
      final role = m['role'] as String;
      final content = m['content'] as String;
      return '[$role]: $content';
    }).join('\n');

    final systemPrompt = '''你是记忆管理器。根据最新对话，判断哪些信息需要记录或清理。
你必须返回一个严格的 JSON 对象（不要加 markdown 代码块标记），格式为：
{"long_term": [{"action": "create|update|delete", "field": "time|location|current_events|characters|relationships|goals|thoughts|status|to_do", "content": "具体内容", "target_id": "L003（update/delete时必填）"}], "base": [{"action": "create|delete", "type": "setting|event", "content": "具体内容", "target_id": "B003（delete时必填）"}]}

## 规则
1. 长期记忆保存目前仍然成立的实时信息（时间、地点、正在发生的事、人物特征、关系、目标、想法情绪、身体/生活状态、待办事项）
2. 基础记忆 setting 保存用户的背景设定（永久），event 保存已完结的重大事件
3. 当新旧信息冲突时，update 旧条目而非 create 新条目
4. 当信息已过时或被覆盖时，delete 旧条目（不归档——setting 直接删除，event 也直接删除）
5. 长期记忆不超过 15 条；超出时主动清理最不重要的
6. 不记录琐碎聊天——只记录真正有长期价值的信息
7. 如果本轮对话没有值得记录的内容，返回空的 long_term 和 base 数组
8. 你只使用 L 和 B 开头的 target_id——不要编造不存在的 ID

## 现有长期记忆
$longTermLines

## 现有基础记忆
$baseLines

## 最新对话
$shortTermLines''';

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': '分析以上对话，返回需要执行的记忆操作。返回纯 JSON 对象，不要包装在 markdown 代码块中。'},
    ];

    _mlog('Calling Memory AI (deepseek-v4-flash)...');
    final startTime = DateTime.now();

    try {
      final apiService = ApiService.fromConfig(
        model: 'deepseek-v4-flash',
        apiKey: apiKey,
        baseUrl: baseUrl,
        thinkingMode: thinkingMode,
        temperature: temperature,
      );

      final response = await apiService.chatCompletion(
        messages: messages,
        tools: [],
      );

      final content = ApiService.parseContent(response);
      if (content == null || content.isEmpty) {
        _mlog('Empty response');
        return;
      }

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      _mlog('Response (${content.length} chars, ${elapsed}ms): ${content.substring(0, _min(120, content.length))}');

      final parsed = _parseJson(content);
      if (parsed == null) {
        _mlog('Failed to parse JSON from response');
        return;
      }

      await _applyOperations(parsed, memoryService);
    } on ApiException catch (e) {
      _mlog('API error: $e');
    } catch (e) {
      _mlog('Unexpected error: $e');
    }
  }

  static Map<String, dynamic>? _parseJson(String content) {
    try {
      return jsonDecode(content) as Map<String, dynamic>?;
    } catch (_) {
      try {
        final match = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(content);
        if (match != null) {
          return jsonDecode(match.group(1)!.trim()) as Map<String, dynamic>?;
        }
      } catch (_) {}
      try {
        final start = content.indexOf('{');
        final end = content.lastIndexOf('}');
        if (start >= 0 && end > start) {
          return jsonDecode(content.substring(start, end + 1)) as Map<String, dynamic>?;
        }
      } catch (_) {}
      return null;
    }
  }

  static Future<void> _applyOperations(Map<String, dynamic> parsed, MemoryService ms) async {
    int created = 0, updated = 0, deleted = 0;

    final longTerm = parsed['long_term'] as List?;
    if (longTerm != null) {
      for (final op in longTerm) {
        try {
          final action = op['action'] as String? ?? '';
          final field = op['field'] as String? ?? 'status';
          final content = op['content'] as String? ?? '';
          final targetId = op['target_id'] as String?;

          switch (action) {
            case 'create':
              if (content.isNotEmpty) {
                await ms.createLongTermMemory(field: field, content: content);
                created++;
              }
              break;
            case 'update':
              if (targetId != null && content.isNotEmpty) {
                await ms.updateLongTermMemory(targetId: targetId, content: content, field: field.isNotEmpty ? field : null);
                updated++;
              }
              break;
            case 'delete':
              if (targetId != null) {
                await ms.deleteLongTermMemory(targetId);
                deleted++;
              }
              break;
          }
        } catch (e) {
          _mlog('  LT op failed: $e');
        }
      }
    }

    final base = parsed['base'] as List?;
    if (base != null) {
      for (final op in base) {
        try {
          final action = op['action'] as String? ?? '';
          final type = op['type'] as String? ?? 'event';
          final content = op['content'] as String? ?? '';
          final targetId = op['target_id'] as String?;

          switch (action) {
            case 'create':
              if (content.isNotEmpty) {
                await ms.createBaseMemory(type: type, content: content);
                created++;
              }
              break;
            case 'delete':
              if (targetId != null) {
                await ms.deleteBaseMemory(targetId);
                deleted++;
              }
              break;
          }
        } catch (e) {
          _mlog('  BS op failed: $e');
        }
      }
    }

    _mlog('Applied: created=$created updated=$updated deleted=$deleted');
  }

  static int _min(int a, int b) => a < b ? a : b;
}
