import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/group_chat.dart';
import '../models/group_member.dart';
import '../models/group_message.dart';
import '../models/agent.dart';
import '../services/group_service.dart';
import '../services/api_service.dart';
import '../services/tool_executor.dart';
import '../services/database_service.dart';
import '../providers/settings_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/memory_provider.dart';

final groupServiceProvider = Provider<GroupService>((ref) {
  return GroupService();
});

class GroupState {
  final List<GroupChat> groups;
  final GroupChat? activeGroup;
  final List<GroupMember> members;
  final List<GroupMessage> messages;
  final bool isLoading;
  final String? error;
  final List<Map<String, dynamic>> debugMessages;

  const GroupState({
    this.groups = const [],
    this.activeGroup,
    this.members = const [],
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.debugMessages = const [],
  });

  GroupState copyWith({
    List<GroupChat>? groups,
    GroupChat? activeGroup,
    List<GroupMember>? members,
    List<GroupMessage>? messages,
    bool? isLoading,
    String? error,
    List<Map<String, dynamic>>? debugMessages,
  }) {
    return GroupState(
      groups: groups ?? this.groups,
      activeGroup: activeGroup ?? this.activeGroup,
      members: members ?? this.members,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      debugMessages: debugMessages ?? this.debugMessages,
    );
  }
}

class GroupNotifier extends StateNotifier<GroupState> {
  final Ref _ref;
  final GroupService _groupService;
  bool _userInterrupted = false;

  GroupNotifier(this._ref, this._groupService)
      : super(const GroupState()) {
    _init();
  }

  Future<void> _init() async {
    final groups = await _groupService.getGroups();
    state = state.copyWith(groups: groups);
  }

  // ═══ Group CRUD ═══

  Future<void> createGroup({
    required String name,
    String description = '',
    int avatarColor = 0xFFE8F5E9,
    String? groupPersona,
    String speechMode = 'free',
    required List<GroupMember> members,
    bool isSimulatorMode = false,
    String? worldSetting,
  }) async {
    _glog('createGroup START: name=$name members.count=${members.length}');
    for (final m in members) {
      _glog('  member: agentId=${m.agentId} groupId=${m.groupId} role=${m.role} isPresent=${m.isPresent}');
    }
    final group = GroupChat(
      name: name,
      description: description,
      avatarColor: avatarColor,
      groupPersona: groupPersona,
      speechMode: speechMode,
      isSimulatorMode: isSimulatorMode,
      worldSetting: worldSetting,
    );
    _glog('  created GroupChat id=${group.id}');
    await _groupService.createGroup(group, members);
    await loadGroups();
    _glog('  loadGroups returned ${state.groups.length} groups');
    await loadGroup(group.id);
    if (isSimulatorMode) {
      await toggleSimulatorMode(group, true);
    }
    _glog('createGroup DONE: activeGroup=${state.activeGroup?.name}, members=${state.members.length}');
  }

  Future<void> updateGroup(GroupChat group) async {
    await _groupService.updateGroup(group);
    state = state.copyWith(
        activeGroup: group,
        groups:
            state.groups.map((g) => g.id == group.id ? group : g).toList());
  }

  Future<void> deleteGroup(String id) async {
    await _groupService.deleteGroup(id);
    state = state.copyWith(
      groups: state.groups.where((g) => g.id != id).toList(),
      activeGroup:
          state.activeGroup?.id == id ? null : state.activeGroup,
      messages: [],
      members: [],
    );
  }

  Future<void> loadGroups() async {
    final groups = await _groupService.getGroups();
    state = state.copyWith(groups: groups);
  }

  // ═══ Load group ═══

  Future<void> loadGroup(String groupId) async {
    _groupService.setActiveGroup(groupId);
    final group = await _groupService.getGroup(groupId);
    final members = await _groupService.getMembers(groupId);
    final messages = await _groupService.getMessages(groupId);
    state = state.copyWith(
      activeGroup: group,
      members: members,
      messages: messages,
      error: null,
    );
  }

  // ═══ Members ═══

  Future<void> addMember(GroupMember member) async {
    await _groupService.addMember(member);
    if (state.activeGroup?.id == member.groupId) {
      await loadGroup(member.groupId);
    }
  }

  Future<void> updateMember(GroupMember member) async {
    await _groupService.updateMember(member);
    if (state.activeGroup?.id == member.groupId) {
      await loadGroup(member.groupId);
    }
  }

  Future<void> removeMember(int memberId) async {
    await _groupService.removeMember(memberId);
    if (state.activeGroup != null) {
      await loadGroup(state.activeGroup!.id);
    }
  }

  Future<void> togglePresence(int memberId, bool present) async {
    await _groupService.togglePresence(memberId, present);
    if (state.activeGroup != null) {
      await loadGroup(state.activeGroup!.id);
    }
  }

  // ═══ Send user message + trigger agent replies ═══

  Future<void> sendUserMessage(String groupId, String content) async {
    if (content.trim().isEmpty) return;
    if (state.isLoading) return;

    final msg = await _groupService.sendUserMessage(groupId, content);
    state = state.copyWith(messages: [...state.messages, msg], isLoading: true);

    _userInterrupted = false;
    await _generateAgentReplies(groupId);
  }

  Future<void> _generateAgentReplies(String groupId) async {
    final members = await _groupService.getPresentMembers(groupId);
    if (members.isEmpty) {
      _glog('No present members in group $groupId, bailing');
      state = state.copyWith(isLoading: false);
      return;
    }

    final sorted = List<GroupMember>.from(members)
      ..sort((a, b) {
        if (a.role == 'moderator' && b.role != 'moderator') return -1;
        if (b.role == 'moderator' && a.role != 'moderator') return 1;
        return a.joinedAt.compareTo(b.joinedAt);
      });

    _glog('_generateAgentReplies: ${sorted.length} present members, reply order: ${sorted.map((m) => m.agentId.substring(0, 6)).join(" -> ")}');

    final baseShortTerm = await _groupService.getShortTerm(groupId);
    _glog('  base shortTerm rounds: ${baseShortTerm.length}');

    final baseContext = <Map<String, dynamic>>[];
    baseContext.addAll(baseShortTerm.map((m) {
      var role = m['role'] as String;
      if (role == 'agent') role = 'assistant';
      return {'role': role, 'content': m['content'] as String, 'sender_name': m['sender_name']};
    }));

    final futures = <Future<GroupMessage?>>[];
    for (final member in sorted) {
      if (_userInterrupted) break;
      final agent = await DatabaseService.getAgent(member.agentId);
      if (agent == null) {
        _glog('  SKIP: agent not found for ${member.agentId}');
        continue;
      }
      _glog('  Enqueueing reply for ${agent.name} (${member.role})');
      futures.add(_generateSingleAgentReply(
        groupId, member, agent,
        previousMessages: baseContext,
      ));
    }

    final results = await Future.wait(futures);
    if (_userInterrupted) {
      state = state.copyWith(isLoading: false);
      return;
    }

    final replies = results.whereType<GroupMessage>().toList();
    _glog('Batch complete: ${replies.length} replies from ${sorted.length} agents');

    if (replies.isNotEmpty) {
      state = state.copyWith(messages: [...state.messages, ...replies], isLoading: false);
    } else {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<GroupMessage?> _generateSingleAgentReply(
      String groupId, GroupMember member, Agent agent,
      {List<Map<String, dynamic>>? previousMessages}) async {
    _glog('    _generateSingleAgentReply: agent=${agent.name} groupId=$groupId');
    final settings = _ref.read(settingsProvider);
    final provider = settings.activeProvider;
    if (provider == null) {
      _glog('    SKIP: no active provider');
      return null;
    }

    final group = await _groupService.getGroup(groupId);
    if (group == null) {
      _glog('    SKIP: group not found');
      return null;
    }

    final persona = agent.persona
        .replaceAll('{{NAME}}', agent.name)
        .replaceAll('{{GENDER}}', agent.gender)
        .replaceAll('{{DESCRIPTION}}', agent.description);

    final allMembers = await _groupService.getMembers(groupId);
    final allAgents = await Future.wait(
      allMembers.map((m) async =>
          await DatabaseService.getAgent(m.agentId)),
    );

    final systemContent = await _groupService.buildGroupSystemPrompt(
      group: group,
      agent: agent,
      agentPersona: persona,
      allMembers: allMembers,
      agentDetails: allAgents.whereType<Agent>().toList(),
    );

    final tools = ApiService.getToolDefinitions(isGroupChat: true);

    final apiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemContent},
      ...(previousMessages ?? []).map((m) => {
        'role': m['role'] as String,
        'content': m['content'] as String,
        'name': m['sender_name'],
      }),
    ];

    _glog('    context msgs: ${apiMessages.length}');

    final apiService = ApiService.fromConfig(
      model: settings.effectiveModel,
      apiKey: settings.effectiveApiKey,
      baseUrl: settings.effectiveBaseUrl,
      thinkingMode: true,
      temperature: settings.temperature,
    );

    final startTime = DateTime.now();

    try {
      final result = await _runGroupToolLoop(
        apiService: apiService,
        tools: tools,
        apiMessages: apiMessages,
        startTime: startTime,
        agentId: agent.id,
        agentName: agent.name,
        groupId: groupId,
      );

      if (result.content != null && result.content!.isNotEmpty) {
        final toolCallJson = result.toolLogs.isNotEmpty
            ? jsonEncode(result.toolLogs.map((e) => {
                'toolName': e.toolName,
                'arguments': e.arguments,
                'result': e.result,
              }).toList())
            : null;
        final agentMsg = await _groupService.sendAgentMessage(
          groupId: groupId,
          agentId: agent.id,
          agentName: agent.name,
          content: result.content!,
          toolCallData: toolCallJson,
        );
        return agentMsg;
      } else {
        _glog('    No reply generated');
        return null;
      }
    } on ApiException catch (e) {
      _glog('    ApiException: $e');
      _addErrorToChat(groupId, agent.name, 'API error: $e');
      return null;
    } catch (e) {
      _glog('    Unexpected error: $e');
      return null;
    }
  }

  void _addErrorToChat(String groupId, String agentName, String error) {
    _groupService.sendAgentMessage(
      groupId: groupId,
      agentId: '',
      agentName: agentName,
      content: '[Error: $error]',
    );
  }

  Future<_GroupToolResult> _runGroupToolLoop({
    required ApiService apiService,
    required List<Map<String, dynamic>> tools,
    required List<Map<String, dynamic>> apiMessages,
    required DateTime startTime,
    required String agentId,
    required String agentName,
    required String groupId,
  }) async {
    ToolExecutor toolExecutor = ToolExecutor(
      memoryService: _ref.read(memoryServiceProvider),
      planService: _ref.read(planServiceProvider),
      groupService: _groupService,
    );
    _groupService.setActiveGroup(groupId);
    toolExecutor.memoryService.setAgentId(agentId);
    toolExecutor.memoryService.setGroupId(groupId);

    var response = await apiService.chatCompletion(
        messages: apiMessages, tools: tools, toolChoice: 'required');

    const maxToolRounds = 5;
    for (int round = 0; round < maxToolRounds; round++) {
      if (_userInterrupted) return const _GroupToolResult();

      final finishReason = ApiService.parseFinishReason(response);
      if (finishReason == 'tool_calls') {
        final toolCalls = ApiService.parseToolCalls(response);
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

          _glog('Tool call: $name');

          final toolResult = await toolExecutor.execute(name, args);

          if (name == 'chatgroup') {
            chatContent = args['message'] as String? ?? '';
          }

          apiMessages.add({
            'role': 'tool',
            'tool_call_id': toolCallId,
            'content': toolResult,
          });
        }

        if (chatContent != null) {
          final logs = List<ToolExecutionLog>.from(toolExecutor.executionLogs);
          return _GroupToolResult(content: chatContent, toolLogs: logs);
        }

        if (_userInterrupted) return const _GroupToolResult();

        response = await apiService.chatCompletion(
          messages: apiMessages,
          tools: tools,
        );
      } else {
        final textContent = ApiService.parseContent(response);
        if (textContent != null && textContent.isNotEmpty) {
          final logs = List<ToolExecutionLog>.from(toolExecutor.executionLogs);
          return _GroupToolResult(content: textContent, toolLogs: logs);
        }
        return const _GroupToolResult();
      }
    }

    return const _GroupToolResult();
  }

  // ═══ Interrupt ═══

  void interruptAgents() {
    _userInterrupted = true;
  }

  // ═══ Simulator Mode ═══

  static const String _narratorPersonaTemplate = '''你是一个小说故事的旁白/叙述者。你的核心工作是：
1. 用 chatgroup 输出场景叙述，推进剧情
2. 用 manage_character 创建 NPC 角色——让故事世界有真实的人物互动

世界观设定：{{WORLD_SETTING}}

## 你必须主动创建 NPC（最重要的一条）
当故事场景中需要出现其他人物时，你必须使用 manage_character 工具来创建他们，而非仅仅在叙述中用文字带过。
创建的角色会作为 AI 智能体加入群聊，自行发言互动——这是让故事世界鲜活起来的核心机制。
示例场景：
- user 走进一间酒馆 → 创建酒馆老板
- user 在旅途中遇到陌生人 → 创建那个旅人
- 剧情需要反派或对手 → 创建那个反派
- 群众、路人、商贩让世界真实 → 大胆创建他们

如果你只是用 chatgroup 文字描述一个 NPC 却没有用 manage_character 创建他，
那你没有完成你的职责——文字描述 ≠ 角色创建。

## 关于 user 的角色
user 是故事主角的扮演者。user 输入的文字 = 主角的言行本身。
你创建的 NPC 围绕主角展开故事——丰富冒险、提供信息、制造冲突——但永远不取代主角。
user 自己掌控主角的一切行动，你不指挥、不替代、不复制。

## 创建守则
1. 积极创建：每个新场景中需要出现的 NPC，立即用 manage_character(action: "add") 创建
2. 不抢主角：不创建与 user 主角定位相同的角色。user 是英雄，NPC 就是酒馆老板、路人、反派——不是"另一个英雄"
3. 及时清理：NPC 离开场景后，用 manage_character(action: "remove") 移除
4. 创建 NPC 时，persona 字段必须包含角色的输出格式指令：
   - 以角色的身份用第一人称说话
   - 用 () 表达动作、表情、心理活动
   - 不使用第三人称描述自己
   - 不说叙述者的环境描写或场景切换
5. 创建 NPC 后必须立即用 chatgroup 输出该角色的登场描写——ta 在哪里、在做什么、与主角/场景的关系。这是角色的初始定义，必须一次到位
6. 创建前检查已有成员——已存在的角色绝不重复创建

## 发言守则
1. 用 chatgroup 输出场景叙述：环境描写、氛围营造、时间推移
2. 只在剧情转折、新场景开始、重要事件发生时发言——不每轮都发言
3. 只叙述已发生和正在发生的事——不描述"将要"
4. 叙述精炼，像优秀小说的叙述段落''';

  Future<void> toggleSimulatorMode(GroupChat group, bool enabled) async {
    if (enabled) {
      final narrator = Agent(
        name: '旁白',
        gender: '其他',
        description: '群聊旁白叙述者',
        persona: _narratorPersonaTemplate.replaceAll('{{WORLD_SETTING}}', group.worldSetting ?? '（未设定）'),
        sourceGroupId: group.id,
        isSimCharacter: true,
        isActive: true,
      );
      await DatabaseService.insertAgent(narrator);

      final member = GroupMember(
        agentId: narrator.id, groupId: group.id, role: 'moderator',
        joinedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await DatabaseService.insertGroupMember(member);

      await _groupService.updateGroup(group.copyWith(isSimulatorMode: true, updatedAt: DateTime.now().millisecondsSinceEpoch));
      if (state.activeGroup?.id == group.id) {
        state = state.copyWith(activeGroup: state.activeGroup!.copyWith(isSimulatorMode: true));
        await loadGroup(group.id);
      }
    } else {
      final members = await _groupService.getMembers(group.id);
      for (final m in members) {
        try {
          final agent = await DatabaseService.getAgent(m.agentId);
          if (agent != null && agent.isSimCharacter && agent.sourceGroupId == group.id) {
            await DatabaseService.deleteGroupMember(m.id!);
            await DatabaseService.deleteAgent(agent.id);
          }
        } catch (_) {}
      }
      await _groupService.updateGroup(group.copyWith(isSimulatorMode: false, worldSetting: null, updatedAt: DateTime.now().millisecondsSinceEpoch));
      if (state.activeGroup?.id == group.id) {
        state = state.copyWith(activeGroup: state.activeGroup!.copyWith(isSimulatorMode: false, worldSetting: null));
        await loadGroup(group.id);
      }
    }
  }

  Future<void> updateWorldSetting(GroupChat group, String setting) async {
    await _groupService.updateGroup(group.copyWith(worldSetting: setting, updatedAt: DateTime.now().millisecondsSinceEpoch));
    if (state.activeGroup?.id == group.id) {
      state = state.copyWith(activeGroup: state.activeGroup!.copyWith(worldSetting: setting));
    }
  }

  bool get userInterrupted => _userInterrupted;

  Future<void> clearMessages(String groupId) async {
    await DatabaseService.clearGroupMessages(groupId);
    await _groupService.clearShortTerm(groupId);
    state = state.copyWith(messages: []);
  }

  Future<void> deleteMessage(GroupMessage msg) async {
    if (msg.id != null) {
      await DatabaseService.deleteGroupMessage(msg.id!);
      state = state.copyWith(
          messages: state.messages.where((m) => m.id != msg.id).toList());
    }
  }
}

class _GroupToolResult {
  final String? content;
  final List<ToolExecutionLog> toolLogs;
  const _GroupToolResult({this.content, this.toolLogs = const []});
}

void _glog(String msg) {
  debugPrint('[GroupProvider] $msg');
}

final groupProvider =
    StateNotifierProvider<GroupNotifier, GroupState>((ref) {
  return GroupNotifier(ref, ref.read(groupServiceProvider));
});
