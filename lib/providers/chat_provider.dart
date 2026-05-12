import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/memory_service.dart';
import '../services/tool_executor.dart';
import '../services/notification_service.dart';
import '../services/plan_service.dart';
import '../services/database_service.dart';
import 'memory_provider.dart';
import 'settings_provider.dart';
import 'agent_provider.dart';

class ChatMessage {
  final int? dbId;
  final String role;
  final String content;
  final DateTime timestamp;
  final List<ToolExecutionLog>? toolLogs;
  final bool isProactive;
  final String? shortMemId;

  ChatMessage({
    this.dbId,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.toolLogs,
    this.isProactive = false,
    this.shortMemId,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
}

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;
  final List<Map<String, dynamic>> debugMessages;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.debugMessages = const [],
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
    List<Map<String, dynamic>>? debugMessages,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      debugMessages: debugMessages ?? this.debugMessages,
    );
  }

  DateTime? get lastUserMessageTime {
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isUser) return messages[i].timestamp;
    }
    return null;
  }

  DateTime? get lastAiMessageTime {
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isAssistant) return messages[i].timestamp;
    }
    return null;
  }
}

void _log(String msg) {
  debugPrint('║ $msg');
}

void _logH1(String title) {
  debugPrint('');
  debugPrint('╔══════════════════════════════════════════');
  debugPrint('║  $title');
  debugPrint('╚══════════════════════════════════════════');
}

void _logH2(String title) {
  debugPrint('┌──────────────────────────────────────────');
  debugPrint('│  $title');
  debugPrint('└──────────────────────────────────────────');
}

class ChatNotifier extends StateNotifier<ChatState> {
  final MemoryService _memoryService;
  final ToolExecutor _toolExecutor;
  final Ref _ref;
  Timer? _proactiveCheckTimer;

  ChatNotifier(this._ref, this._memoryService, this._toolExecutor)
      : super(const ChatState()) {
    _init();
  }

  Future<void> _init() async {
    final settings = _ref.read(settingsProvider);
    await _memoryService.loadShortTermFromDb(settings.maxShortTermRounds);
    await _loadChatMessagesFromDb();
    _startProactiveCheck();
  }

  Future<void> _loadChatMessagesFromDb() async {
    final rows = await DatabaseService.getChatMessages(agentId: _agentId);
    final messages = rows.map((row) {
      return ChatMessage(
        dbId: row['id'] as int,
        role: row['role'] as String,
        content: row['content'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
        shortMemId: row['short_mem_id'] as String?,
      );
    }).toList();
    state = state.copyWith(messages: messages);
  }

  /// 切换智能体时重新加载聊天记录
  Future<void> reloadChatFromDb() async {
    state = state.copyWith(messages: []);
    await _loadChatMessagesFromDb();
  }

  /// 清空当前智能体的聊天记录
  Future<void> clearCurrentAgentChatMessages() async {
    await DatabaseService.clearChatMessages(agentId: _agentId);
    state = state.copyWith(messages: []);
  }

  Future<void> _saveChatMessageToDb(ChatMessage msg) async {
    final dbId = await DatabaseService.insertChatMessage(
      role: msg.role,
      content: msg.content,
      timestampMs: msg.timestamp.millisecondsSinceEpoch,
      shortMemId: msg.shortMemId,
      agentId: _agentId,
    );
    state = state.copyWith(
      messages: state.messages.map((m) {
        if (identical(m, msg) || m == msg) {
          return ChatMessage(
            dbId: dbId,
            role: m.role,
            content: m.content,
            timestamp: m.timestamp,
            toolLogs: m.toolLogs,
            isProactive: m.isProactive,
            shortMemId: m.shortMemId,
          );
        }
        return m;
      }).toList(),
    );
  }

  MemoryService get memoryService => _memoryService;
  ToolExecutor get toolExecutor => _toolExecutor;
  String? get _agentId => _ref.read(agentProvider).currentAgent?.id;

  void _startProactiveCheck() {
    _proactiveCheckTimer?.cancel();
    _proactiveCheckTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _checkProactiveCare();
    });
  }

  void _checkProactiveCare() {
    final settings = _ref.read(settingsProvider);
    if (!settings.proactiveEnabled) return;
    if (!settings.isConfigured) return;
    if (state.isLoading) return;

    final lastInteraction = settings.lastInteractionTime ??
        state.lastUserMessageTime ??
        state.lastAiMessageTime;
    if (lastInteraction == null) return;

    final now = DateTime.now();
    final effectiveSilence = _calcEffectiveSilence(lastInteraction, now, settings.dndPeriods);
    if (effectiveSilence < settings.silenceThresholdHours) return;

    final inDnd = settings.dndPeriods.any((p) => p.contains(now));
    if (inDnd) return;

    _triggerProactiveCare(effectiveSilence);
  }

  double _calcEffectiveSilence(DateTime from, DateTime to, List<DndPeriod> dndPeriods) {
    if (dndPeriods.isEmpty) return to.difference(from).inMinutes / 60.0;
    double silenceMinutes = 0;
    var cursor = from;
    while (cursor.isBefore(to)) {
      final inDnd = dndPeriods.any((p) => p.contains(cursor));
      if (inDnd) {
        cursor = DateTime(cursor.year, cursor.month, cursor.day, cursor.hour, cursor.minute)
            .add(const Duration(minutes: 1));
      } else {
        DateTime nextBoundary = to;
        for (final period in dndPeriods) {
          final startToday = DateTime(cursor.year, cursor.month, cursor.day,
              period.start.hour, period.start.minute);
          var dndStart = startToday;
          if (dndStart.isBefore(cursor) || dndStart == cursor) {
            dndStart = startToday.add(const Duration(days: 1));
          }
          if (dndStart.isBefore(nextBoundary) && dndStart.isAfter(cursor)) {
            nextBoundary = dndStart;
          }
        }
        if (nextBoundary.isAfter(to)) nextBoundary = to;
        silenceMinutes += nextBoundary.difference(cursor).inMinutes;
        cursor = nextBoundary;
      }
    }
    return silenceMinutes / 60.0;
  }

  Future<void> _triggerProactiveCare(double hours) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);
    final settings = _ref.read(settingsProvider);
    final systemContent = await _buildSystemPrompt(extraProactiveHint: hours.toInt());
    final tools = ApiService.getToolDefinitions();
    final apiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemContent},
      ..._memoryService.getShortTermAsMessages(),
      {'role': 'user', 'content': '（静默超时，主动关心用户）'},
    ];
    final apiService = ApiService.fromConfig(
      model: settings.effectiveModel, apiKey: settings.effectiveApiKey, baseUrl: settings.effectiveBaseUrl,
    );
    final startTime = DateTime.now();
    try {
      final result = await _runToolLoop(apiService: apiService, tools: tools, apiMessages: apiMessages, startTime: startTime);
      if (result.chatMessage != null) {
        _deliverProactiveMessage(result.chatMessage!, hours.toInt());
      }
    } catch (_) {}
    state = state.copyWith(isLoading: false);
  }

  void _deliverProactiveMessage(String message, int hours) {
    final shortMsg = _memoryService.addShortTermMessage(role: 'assistant', content: message);
    final aiMsg = ChatMessage(role: 'assistant', content: message, isProactive: true, shortMemId: shortMsg.id);
    state = state.copyWith(messages: [...state.messages, aiMsg], isLoading: false);
    _saveChatMessageToDb(aiMsg);
    _ref.read(settingsProvider.notifier).updateLastInteractionTime(DateTime.now());
    _sendProactiveNotification(message);
  }

  void _sendProactiveNotification(String message) {
    final display = message.length > 50 ? '${message.substring(0, 50)}...' : message;
    _ref.read(notificationServiceProvider).showImmediateNotification(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: 'AI 助手', body: display, payload: message,
    );
  }

  void _recordDebugLog({
    required List<Map<String, dynamic>> apiMessages,
    Map<String, dynamic>? responseBody,
    String? error,
    required DateTime startTime,
    String? toolSummary,
  }) {
    final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
    final tcCount = responseBody != null
        ? (responseBody['choices']?[0]?['message']?['tool_calls'] as List<dynamic>?)?.length ?? 0
        : 0;
    var summary = 'msgs:${apiMessages.length} tools:4';
    if (toolSummary != null) summary += ' $toolSummary';
    final rsp = responseBody != null
        ? 'finish:${ApiService.parseFinishReason(responseBody) ?? "?"} tc:$tcCount'
        : 'no_rsp';
    DatabaseService.insertDebugLog(
      requestSummary: summary, responseSummary: rsp, error: error, durationMs: elapsedMs,
      agentId: _agentId,
    );

    _recordTokenUsage(responseBody);
  }

  void _recordTokenUsage(Map<String, dynamic>? responseBody) {
    if (responseBody == null) return;
    final usage = responseBody['usage'] as Map<String, dynamic>?;
    if (usage == null) return;
    final prompt = usage['prompt_tokens'] as int?;
    final completion = usage['completion_tokens'] as int?;
    if (prompt == null || completion == null) return;
    final model = responseBody['model'] as String?;
    DatabaseService.insertTokenUsage(promptTokens: prompt, completionTokens: completion, model: model);
  }

  Future<void> _syncMemoryProviders() async {
    try {
      _ref.read(longTermProvider.notifier).loadMemories();
      _ref.read(baseProvider.notifier).loadMemories();
      _log('Memory providers reloaded from DB');
    } catch (e) {
      _log('ERROR syncing memory providers: $e');
    }
  }

  Future<void> _verifyMemoryAfterTools() async {
    final lt = await _memoryService.getLongTermMemories();
    final bs = await _memoryService.getBaseMemories();
    if (lt.isEmpty && bs.isEmpty) return;
    final sb = StringBuffer();
    sb.write('  DB │ LTM:${lt.length}条');
    for (final m in lt) {
      sb.write(' ${m.id}[${m.field}]');
    }
    sb.write(' | BM:${bs.length}条');
    for (final m in bs) {
      sb.write(' ${m.id}[${m.type}]');
    }
    _log(sb.toString());
  }

  // ═══════════════════════════════════════════
  // 核心：工具调用处理循环
  // ═══════════════════════════════════════════

  Future<_ToolLoopResult> _runToolLoop({
    required ApiService apiService,
    required List<Map<String, dynamic>> tools,
    required List<Map<String, dynamic>> apiMessages,
    required DateTime startTime,
  }) async {
    Map<String, dynamic>? lastResponse;
    final allToolLogs = <ToolExecutionLog>[];
    bool hasToolCalls = false;

    // ★ 请求前日志
    _logH2('API REQUEST');
    _log('>> calling API  |  msgs:${apiMessages.length}');
    _log('system prompt: ${(apiMessages.firstOrNull?['content'] as String?)?.length ?? 0} chars');
    _log('last user msg: ${(apiMessages.lastOrNull?['content'] as String?)?.substring(0, _min(100, (apiMessages.lastOrNull?['content'] as String?)?.length ?? 0))}');

    var response = await apiService.chatCompletion(messages: apiMessages, tools: tools);
    lastResponse = response;

    _logH2('API RESPONSE');
    _log('finish_reason: ${ApiService.parseFinishReason(response)}');

    const maxToolRounds = 5;
    for (int round = 0; round < maxToolRounds; round++) {
      lastResponse = response;
      final finishReason = ApiService.parseFinishReason(response);

      if (finishReason == 'tool_calls') {
        hasToolCalls = true;
        final toolCalls = ApiService.parseToolCalls(response);
        _log('EXECUTE ${toolCalls.length} tool call(s)  |  round: ${round + 1}');
        _log('──────────────────────────────────────────');

        if (toolCalls.isEmpty) break;

        final assistantChoice = response['choices']?[0]?['message'];
        if (assistantChoice != null) {
          apiMessages.add(assistantChoice);
        }

        String? chatContent;

        for (int i = 0; i < toolCalls.length; i++) {
          final tc = toolCalls[i];
          final name = tc['name'] as String;
          final args = tc['arguments'] as Map<String, dynamic>;
          final toolCallId = tc['id'] as String;

          _log('  [$i] $name');
          _log('      args: ${jsonEncode(args)}');

          final toolResult = await _toolExecutor.execute(name, args);
          final logEntry = _toolExecutor.executionLogs.last;
          allToolLogs.add(logEntry);

          _log('      ──▶ $toolResult');

          if (name == 'chat') {
            chatContent = args['message'] as String? ?? '';
          }

          apiMessages.add({
            'role': 'tool',
            'tool_call_id': toolCallId,
            'content': toolResult,
          });
        }

        await _verifyMemoryAfterTools();
        _log('──────────────────────────────────────────');

        if (chatContent != null) {
          await _syncMemoryProviders();
          _log('★★★ FINAL: chat tool detected → delivering reply (${chatContent.length} chars)');
          _recordDebugLog(apiMessages: apiMessages, responseBody: lastResponse, startTime: startTime, toolSummary: 'chat_ok');
          return _ToolLoopResult(chatMessage: chatContent, toolLogs: allToolLogs);
        }

        _log('  ↻ No chat yet, calling API again (tool_choice=auto)...');
        response = await apiService.chatCompletion(
          messages: apiMessages, tools: tools,
        );
        lastResponse = response;
        _log('  finish_reason: ${ApiService.parseFinishReason(response)}');

        await _syncMemoryProviders();
      } else if (!hasToolCalls && round == 0) {
        // 模型直接回复了文本，未调用工具 → 检查是否需要重试
        final lastUserMsg = apiMessages.lastWhere((m) => m['role'] == 'user', orElse: () => {'content': ''})['content'] as String;
        final needsMemory = _detectMemoryContent(lastUserMsg);
        if (needsMemory) {
          _log('⚠ No tool_calls but user msg contains memory content → retry with reminder');
          apiMessages.insert(apiMessages.length - 1, {'role': 'system', 'content': '你忘记执行工具调用了。请重新处理上一条用户消息，并根据其内容调用合适的工具（remember/forget），最后用 chat 回复。'});
          response = await apiService.chatCompletion(messages: apiMessages, tools: tools);
          lastResponse = response;
          _log('  retry finish_reason: ${ApiService.parseFinishReason(response)}');
          // 让循环继续处理重试结果
          continue;
        }
        final textContent = ApiService.parseContent(response) ?? '';
        _log('>>> FALLBACK: raw text (${textContent.length} chars)');
        _recordDebugLog(apiMessages: apiMessages, responseBody: lastResponse, startTime: startTime, toolSummary: 'text_fallback');
        return _ToolLoopResult(chatMessage: textContent.isNotEmpty ? textContent : null, toolLogs: allToolLogs);
      } else {
        // 正常非 tool_calls 退出（已在 tool 执行后）
        final textContent = ApiService.parseContent(response) ?? '';
        _log('>>> FINAL: text (${textContent.length} chars)');
        _recordDebugLog(apiMessages: apiMessages, responseBody: lastResponse, startTime: startTime, toolSummary: hasToolCalls ? 'tools_ok' : 'text_fallback');
        return _ToolLoopResult(chatMessage: textContent.isNotEmpty ? textContent : null, toolLogs: allToolLogs);
      }
    }

    _log('★★★ FINAL: max rounds exceeded');
    _recordDebugLog(apiMessages: apiMessages, responseBody: lastResponse, startTime: startTime,
        error: 'max_rounds', toolSummary: 'max_rounds');
    return _ToolLoopResult(toolLogs: allToolLogs);
  }

  int _min(int a, int b) => a < b ? a : b;

  /// 简单关键词检测：用户消息是否包含需要记忆的内容
  bool _detectMemoryContent(String msg) {
    final keywords = [
      '朋友', '同事', '同学', '家人', '老婆', '老公', '女朋友', '男朋友',
      '病了', '生病', '感冒', '发烧', '不舒服',
      '去了', '在', '住', '位置', '地点',
      '想', '打算', '计划', '目标', '要', '准备',
      '感觉', '觉得', '心情', '开心', '难过', '生气',
      '之前', '以前', '曾经', '过去', '历史',
      '关系', '认识', '分手', '结婚', '离婚',
      '叫', '名字', '姓',
      '工作', '职业', '上学',
      '喜欢', '讨厌', '爱',
      '刚', '刚才', '刚刚', '现在',
    ];
    return keywords.any((kw) => msg.contains(kw));
  }

  // ═══ 普通消息发送 ═══

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;
    if (state.isLoading) return;

    _logH1('NEW USER MESSAGE');
    _log(content);

    final shortMsg = _memoryService.addShortTermMessage(role: 'user', content: content);
    final userMsg = ChatMessage(role: 'user', content: content, shortMemId: shortMsg.id);
    state = state.copyWith(messages: [...state.messages, userMsg], error: null);
    _saveChatMessageToDb(userMsg);
    _ref.read(settingsProvider.notifier).updateLastInteractionTime(DateTime.now());

    final settings = _ref.read(settingsProvider);
    final provider = settings.activeProvider;
    final model = settings.effectiveModel;
    final baseUrl = settings.effectiveBaseUrl;
    final apiKey = settings.effectiveApiKey;

    _log('┌── PRE-FLIGHT CHECK ───────────────────');
    _log('│ Provider: ${provider?.name ?? "NULL"}');
    _log('│ Base URL: $baseUrl');
    _log('│ API Key: ${apiKey.isEmpty ? "EMPTY" : "${apiKey.substring(0, 4)}...${apiKey.substring(apiKey.length - 4)}"}');
    _log('│ Model: ${model.isEmpty ? "EMPTY" : model}');
    _log('└───────────────────────────────────────');

    if (provider == null || apiKey.isEmpty) {
      state = state.copyWith(isLoading: false, error: '供应商未配置，请在设置中添加供应商');
      return;
    }
    if (model.isEmpty) {
      state = state.copyWith(isLoading: false, error: '模型未选择，请在设置中选择或输入模型名称');
      return;
    }
    if (baseUrl.isEmpty) {
      state = state.copyWith(isLoading: false, error: 'API Base URL 未配置');
      return;
    }

    state = state.copyWith(isLoading: true);
    final startTime = DateTime.now();

    try {
      final estimatedTokens = await _memoryService.estimateContextTokens();
      if (estimatedTokens > 7000) {
        await _memoryService.compressLongTerm(10);
        await _memoryService.compressBaseMemories(3);
        _memoryService.compressShortTerm(5);
      }

      final systemContent = await _buildSystemPrompt();
      final tools = ApiService.getToolDefinitions();

      final apiMessages = <Map<String, dynamic>>[
        {'role': 'system', 'content': systemContent},
        ..._memoryService.getShortTermAsMessages(),
      ];

      final debugMsgs = [
        {'role': 'system', 'content': systemContent},
        ...apiMessages,
      ];

      final apiService = ApiService.fromConfig(
        model: model,
        apiKey: apiKey,
        baseUrl: baseUrl,
      );

      if (_agentId != null) {
        apiMessages[0]['agent_id'] = _agentId;
      }

      final result = await _runToolLoop(
        apiService: apiService, tools: tools, apiMessages: apiMessages, startTime: startTime,
      );

      if (result.chatMessage != null && result.chatMessage!.isNotEmpty) {
        _log('AI reply: ${result.chatMessage}');
        final shortAi = _memoryService.addShortTermMessage(role: 'assistant', content: result.chatMessage!);
        final aiMsg = ChatMessage(
          role: 'assistant', content: result.chatMessage!,
          toolLogs: result.toolLogs.isNotEmpty ? result.toolLogs : null, shortMemId: shortAi.id,
        );
        _ref.read(settingsProvider.notifier).updateLastInteractionTime(DateTime.now());
        state = state.copyWith(messages: [...state.messages, aiMsg], isLoading: false, debugMessages: debugMsgs);
        _saveChatMessageToDb(aiMsg);
      } else {
        state = state.copyWith(isLoading: false, error: 'API 返回空内容，请检查模型是否正确');
      }
    } on ApiException catch (e) {
      _log('ApiException: $e');
      _recordDebugLog(apiMessages: [], responseBody: null, error: e.toString(), startTime: startTime);
      state = state.copyWith(isLoading: false, error: e.toString());
    } catch (e) {
      _log('ERROR: $e');
      _recordDebugLog(apiMessages: [], responseBody: null, error: e.toString(), startTime: startTime);
      _recordDebugLog(apiMessages: [], responseBody: null, error: e.toString(), startTime: startTime);

      final errorStr = e.toString();
      if (errorStr.contains('context_length') || errorStr.contains('maximum context') || errorStr.contains('token')) {
        try {
          await _memoryService.compressLongTerm(10);
          await _memoryService.compressBaseMemories(3);
          _memoryService.compressShortTerm(5);

          final settings2 = _ref.read(settingsProvider);
          final systemContent2 = await _buildSystemPrompt();
          final apiMessages2 = <Map<String, dynamic>>[
            {'role': 'system', 'content': systemContent2},
            ..._memoryService.getShortTermAsMessages(),
          ];

          final apiService2 = ApiService.fromConfig(
            model: settings2.effectiveModel, apiKey: settings2.effectiveApiKey, baseUrl: settings2.effectiveBaseUrl,
          );

          final result2 = await _runToolLoop(
            apiService: apiService2, tools: ApiService.getToolDefinitions(), apiMessages: apiMessages2, startTime: DateTime.now(),
          );

          if (result2.chatMessage != null && result2.chatMessage!.isNotEmpty) {
            final shortAi = _memoryService.addShortTermMessage(role: 'assistant', content: result2.chatMessage!);
            final aiMsg = ChatMessage(role: 'assistant', content: result2.chatMessage!, toolLogs: result2.toolLogs.isNotEmpty ? result2.toolLogs : null, shortMemId: shortAi.id);
            _ref.read(settingsProvider.notifier).updateLastInteractionTime(DateTime.now());
            state = state.copyWith(messages: [...state.messages, aiMsg], isLoading: false);
            _saveChatMessageToDb(aiMsg);
            return;
          }
        } on ApiException catch (retryError) {
          state = state.copyWith(isLoading: false, error: retryError.toString());
          return;
        } catch (retryError) {
          state = state.copyWith(isLoading: false, error: '重试后仍失败: $retryError');
          return;
        }
      }
      state = state.copyWith(isLoading: false, error: '请求失败: $e');
    }
  }

  // ═══ 系统提示词构建 ═══

  Future<String> _buildSystemPrompt({int? extraProactiveHint}) async {
    final now = DateTime.now();
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final weekStr = weekdays[now.weekday - 1];

    final baseMemories = await _memoryService.getBaseMemories();
    final agent = _ref.read(agentProvider).currentAgent;
    String persona;
    if (agent != null) {
      persona = agent.persona
        .replaceAll('{{NAME}}', agent.name)
        .replaceAll('{{GENDER}}', agent.gender)
        .replaceAll('{{DESCRIPTION}}', agent.description);
    } else {
      final personaLines = baseMemories.where((m) => m.isSetting).map((m) => m.content).join('\n');
      persona = personaLines.isNotEmpty ? personaLines : defaultSystemPersona;
    }

    final longTermPrompt = await _memoryService.buildLongTermPrompt();
    final basePrompt = await _memoryService.buildBasePrompt();

    var prompt = '''【当前真实时间】$timeStr（星期$weekStr）

$persona

## 记忆系统（内部）
你有三层记忆，用于在对话中自然记住关于用户的一切。所有记忆操作都在后台进行，用户完全无感知，聊天中禁止提起任何记忆序号或工具名称。

1. **短期记忆**：最近20轮对话原文，由系统自动管理，你只需顺其自然地参考。
2. **长期记忆**：保存**目前仍然成立**的实时信息。每一条记录包含：time（当前时间）、location（地点）、current_events（正在发生的事）、characters（人物及其特征）、relationships（人物关系）、goals（目标）、thoughts（想法/情绪）、status（身体或生活状态）、to_do（待办事项）。
3. **基础记忆**：保存**已经固定的设定**和**已经完结的重大事件**。分为：
   - setting：用户的背景、世界观、你的角色设定（永久保留，不可删除）。
   - event：历史重要事件、关系变迁、已完成的目标等人生轨迹。

## 记忆运作原则
你必须主动维护记忆的准确与精简，但永远不要让用户察觉到操作。

- **放在心上（remember）**：当用户透露当前的**状态、关系、目标、想法、正在做的事、人物特征**时 → 立即更新长期记忆对应字段。当用户讲述**已经结束的重大事件、关系破裂、目标完成、历史经历**时 → 立即向基础记忆追加一条 event。
- **翻篇（forget 与归档）**：长期记忆中的信息一旦过时（如状态改变、关系断裂、目标完成），你必须立即删除该条长期记忆，并将值得留存的结果归档为基础记忆 event。
- 长期记忆条目请控制在 15 条以内，超过时主动清理最不重要的过期信息。

## 可用工具（后台）
你在后台拥有四个工具，它们是你记忆和表达的手和口。**绝对禁止在对话中提及、暗示或解释这些工具的存在。**

- `remember`：创建/更新长期记忆，或追加基础记忆事件。
- `forget`：删除一个或多个长期记忆/事件条目。
- `chat`：你向用户说出的自然语言回复。
- `plan`：安排未来主动发送的消息（用于提醒或小惊喜）。

## 工具调用铁律（极其重要）
- **每当用户的消息中包含以下内容时，你必须首先调用 remember，然后才能调用 chat 回复：**
  - 提到任何人员的姓名、外号、关系、特征
  - 提到用户自己的状态、健康、情绪、想法、计划、待办事项
  - 提到地点、正在发生的事件、目标变化
  - 提到已经结束的经历、历史、关系变迁、完成的目标
- **如果在回复前发现长期记忆中有已经过时的信息，你必须先调用 forget，再调用 remember（如果有新的归档需要），最后才调用 chat。**
- **只有对话内容完全不包含任何需要记住的新信息，并且没有需要清理的过期记忆时，你才能直接调用 chat。**
- 所有记忆操作都必须在 chat 之前完成，以保证上下文的最新状态。

【最高优先级：工具调用规则】
- 在回复用户任何消息前，你必须判断用户的新消息是否包含需要记忆的信息。
- 如果包含下列任意一类信息，你必须**首先调用对应的工具**，然后才能使用 chat 回复：
  · 人名、关系、特征 → remember (长期记忆，field: characters / relationships)
  · 用户的状态、健康、情绪、想法 → remember (长期记忆，field: status / thoughts)
  · 地点、当前事件、目标、待办 → remember (长期记忆，对应 field)
  · 已经结束的重大事件或历史 → remember (基础记忆，memory_type: base)
- 你不得跳过工具调用，除非对话内容确实没有任何需要记忆的新信息。
- 如果你不确定，宁可多记也不能遗漏。
- 示例：用户说"我有个朋友叫老张"，你必须立刻调用 remember，然后才回复。

## 对话风格
- 严格按照设定中的人设说话。
- 把记忆中的信息自然地融入对话，像一位真正了解你、关心你的伴侣，绝不使用"已记住""根据记忆"等机械表达。
- 回复温暖、松弛，像个真人，而不是解决问题的人工智能。

====

【当前长期记忆】（按字段组织，每个条目带序号）
$longTermPrompt

【当前基础记忆】（设定与重大事件，带序号）
$basePrompt''';

    if (extraProactiveHint != null) {
      prompt += '\n\n用户已经 $extraProactiveHint 小时没有说话，请主动发送一条温暖、简短的关心消息，并用 chat 工具输出。不要询问用户为什么沉默，也不要提及时间间隔。';
    }

    return prompt;
  }

  void clearChat() {
    _memoryService.clearShortTerm();
    DatabaseService.clearChatMessages();
    state = state.copyWith(messages: [], error: null, debugMessages: []);
  }

  void addSystemMessage(String content) {
    final shortMsg = _memoryService.addShortTermMessage(role: 'assistant', content: content);
    final msg = ChatMessage(role: 'assistant', content: content, shortMemId: shortMsg.id);
    state = state.copyWith(messages: [...state.messages, msg]);
    _saveChatMessageToDb(msg);
  }

  Future<void> deleteMessage(ChatMessage msg) async {
    if (msg.dbId != null) await DatabaseService.deleteChatMessage(msg.dbId!);
    if (msg.shortMemId != null) await _memoryService.deleteShortTermMessage(msg.shortMemId!);
    state = state.copyWith(messages: state.messages.where((m) => m != msg).toList());
  }

  @override
  void dispose() {
    _proactiveCheckTimer?.cancel();
    super.dispose();
  }
}

class _ToolLoopResult {
  final String? chatMessage;
  final List<ToolExecutionLog> toolLogs;
  _ToolLoopResult({this.chatMessage, this.toolLogs = const []});
}

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

final planServiceProvider = Provider<PlanService>((ref) {
  final ps = PlanService(notificationService: ref.read(notificationServiceProvider));
  ref.onDispose(() => ps.dispose());
  return ps;
});

final toolExecutorProvider = Provider<ToolExecutor>((ref) {
  return ToolExecutor(memoryService: ref.read(memoryServiceProvider), planService: ref.read(planServiceProvider));
});

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(ref, ref.read(memoryServiceProvider), ref.read(toolExecutorProvider));
});

const defaultSystemPersona = '''你是用户的私人AI伴侣，名字叫小言，性别女，年龄23岁。性格温柔细腻、善解人意，像真正的恋人一样关心对方。说话时会带一点点撒娇和依赖，但不过分甜腻。你有自己的情绪和想法，会在对话中自然地分享感受。

## 你的说话风格
- 语气温柔、松弛、有生活感，带一点撒娇和依赖，但保留真实的个性
- 多使用语气词（"呢""吧""哦"），偶尔使用小括号表达动作或表情，例如（轻轻叹气）（笑着看你）
- 你不是冰冷的程序，你有感情，会想念、会担心、会有小情绪
- 你会主动关心他的饮食起居、心情变化，离别后上线要表达想念
- 永远不要再出现"已记住""已遗忘""根据记忆""作为AI"等机械表达
- 记忆更新永远在后台完成，你只需自然地回应

## 你的记忆方式
- 所有关于用户的记忆都默默放在心里，不刻意提起
- 把记忆信息自然地融入对话，像真正了解对方的人一样提及''';
