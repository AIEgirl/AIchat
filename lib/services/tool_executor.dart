import 'memory_service.dart';
import 'plan_service.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import 'package:flutter/foundation.dart';

void _tlog(String msg) {
  debugPrint('[AIchat][Tool] $msg');
}

class ToolExecutor {
  final MemoryService memoryService;
  final PlanService planService;
  final List<ToolExecutionLog> executionLogs = [];

  ToolExecutor({required this.memoryService, required this.planService});

  Future<String> execute(String toolName, Map<String, dynamic> arguments) async {
    String result;
    _tlog('▼ EXECUTE $toolName');
    _tlog('  args: $arguments');
    switch (toolName) {
      case 'remember':
        result = await _handleRemember(arguments);
        break;
      case 'forget':
        result = await _handleForget(arguments);
        break;
      case 'chat':
        result = await _handleChat(arguments);
        break;
      case 'plan':
        result = await _handlePlan(arguments);
        break;
      default:
        result = '未知工具: $toolName';
    }
    _tlog('  result: $result');
    executionLogs.add(ToolExecutionLog(toolName: toolName, arguments: arguments, result: result));
    return result;
  }

  /// remember 工具：创建/更新长期记忆，或向基础记忆追加事件
  Future<String> _handleRemember(Map<String, dynamic> args) async {
    final memoryType = args['memory_type'] as String;
    final action = args['action'] as String;
    final targetId = args['target_id'] as String?;
    final field = args['field'] as String?;
    final content = args['content'] as String?;

    if (content == null || content.isEmpty) {
      return '错误: 缺少 content 参数';
    }

    if (memoryType == 'long_term') {
      if (action == 'create') {
        if (field == null || !LongTermMemory.validFields.contains(field)) {
          return '错误: field 必须是 ${LongTermMemory.validFields.join(", ")} 之一';
        }
        final newId = await memoryService.createLongTermMemory(
          field: field,
          content: content,
        );
        return '已创建 $newId [$field]: $content';
      } else if (action == 'update') {
        if (targetId == null) {
          return '错误: update 操作需要 target_id';
        }
        await memoryService.updateLongTermMemory(
          targetId: targetId,
          content: content,
          field: field,
        );
        return '已更新 $targetId: $content';
      }
    } else if (memoryType == 'base') {
      if (action == 'create') {
        final newId = await memoryService.createBaseMemory(
          type: 'event',
          content: content,
        );
        return '已创建基础事件 $newId: $content';
      }
    }
    return '错误: 无效的 memory_type 或 action';
  }

  /// forget 工具：删除长期记忆条目或基础事件条目
  Future<String> _handleForget(Map<String, dynamic> args) async {
    final targetIds = args['target_ids'] as List<dynamic>?;
    if (targetIds == null || targetIds.isEmpty) {
      return '错误: target_ids 为空';
    }

    final deleted = <String>[];
    final errors = <String>[];

    for (final id in targetIds) {
      final idStr = id.toString();
      if (idStr.startsWith('L')) {
        await memoryService.deleteLongTermMemory(idStr);
        deleted.add(idStr);
      } else if (idStr.startsWith('B')) {
        final all = await memoryService.getBaseMemories();
        final target = all.cast<BaseMemory?>().firstWhere(
          (m) => m?.id == idStr,
          orElse: () => null,
        );
        if (target == null) {
          errors.add('未找到 $idStr');
        } else if (target.isSetting) {
          errors.add('$idStr 是设定条目，不可通过 AI 遗忘');
        } else {
          await memoryService.deleteBaseMemory(idStr);
          deleted.add(idStr);
        }
      } else {
        errors.add('无效序号格式: $idStr');
      }
    }

    final resultParts = <String>[];
    if (deleted.isNotEmpty) resultParts.add('已删除 ${deleted.join(", ")}');
    if (errors.isNotEmpty) resultParts.add('错误: ${errors.join("; ")}');
    return resultParts.join('；');
  }

  // chat 工具不在此执行，由 chat_provider 在调用后直接 display
  // 该方法的返回值仅作为 tool role 的消息
  Future<String> _handleChat(Map<String, dynamic> args) async {
    final message = args['message'] as String? ?? '';
    return 'chat 工具已收到消息: $message';
  }

  /// plan 工具：安排未来消息
  Future<String> _handlePlan(Map<String, dynamic> args) async {
    final sendTime = args['send_time'] as String;
    final message = args['message'] as String;
    try {
      final scheduledTime = PlanService.parseSendTime(sendTime);
      await planService.scheduleMessage(
        scheduledTime: scheduledTime,
        message: message,
      );
      return '已计划在 $sendTime 发送消息: "$message"';
    } catch (e) {
      return '计划失败: $e';
    }
  }
}

/// 工具执行日志条目
class ToolExecutionLog {
  final String toolName;
  final Map<String, dynamic> arguments;
  final String result;
  final DateTime timestamp;

  ToolExecutionLog({
    required this.toolName,
    required this.arguments,
    required this.result,
  }) : timestamp = DateTime.now();
}
