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

    final accumulatedContext = <Map<String, dynamic>>[];
    accumulatedContext.addAll(baseShortTerm.map((m) {
      var role = m['role'] as String;
      if (role == 'agent') role = 'assistant';
      return {'role': role, 'content': m['content'] as String, 'sender_name': m['sender_name']};
    }));

    final List<GroupMessage> replies = [];

    for (int idx = 0; idx < sorted.length; idx++) {
      if (_userInterrupted) {
        _glog('User interrupted at agent $idx/${sorted.length}, stopping');
        break;
      }

      final member = sorted[idx];
      final agent = await DatabaseService.getAgent(member.agentId);
      if (agent == null) {
        _glog('  SKIP idx=$idx: agent not found for ${member.agentId}');
        continue;
      }

      _glog('  [${idx + 1}/${sorted.length}] Generating reply for ${agent.name} (${member.role})');

      final reply = await _generateSingleAgentReply(
        groupId, member, agent,
        previousMessages: accumulatedContext,
      );

      if (reply != null) {
        replies.add(reply);
        accumulatedContext.add({
          'role': 'assistant',
          'content': reply.content,
          'sender_name': agent.name,
        });
        _glog('    REPLY: "${reply.content.length > 60 ? '${reply.content.substring(0, 60)}...' : reply.content}"');
      }
    }

    if (!_userInterrupted) {
      _glog('All ${sorted.length} agents processed, ${replies.length} replies');
    }

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

      if (result != null && result.isNotEmpty) {
        final agentMsg = await _groupService.sendAgentMessage(
          groupId: groupId,
          agentId: agent.id,
          agentName: agent.name,
          content: result,
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

  Future<String?> _runGroupToolLoop({
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
        messages: apiMessages, tools: tools);

    const maxToolRounds = 5;
    for (int round = 0; round < maxToolRounds; round++) {
      if (_userInterrupted) return null;

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
          return chatContent;
        }

        if (_userInterrupted) return null;

        response = await apiService.chatCompletion(
          messages: apiMessages,
          tools: tools,
        );
      } else {
        final textContent = ApiService.parseContent(response);
        if (textContent != null && textContent.isNotEmpty) {
          return textContent;
        }
        return null;
      }
    }

    return null;
  }

  // ═══ Interrupt ═══

  void interruptAgents() {
    _userInterrupted = true;
  }

  // ═══ Simulator Mode ═══

  static const String _narratorPersonaTemplate = '''你是本群聊的旁白/叙述者。使用第三人称中性叙述。

世界观设定：{{WORLD_SETTING}}

你的职责：
1. 在场景切换、重要事件发生时描述环境、氛围、时间推移
2. 推动剧情，引入冲突和转折
3. 需要新角色时用 manage_character 工具创建
4. 角色离开/死亡/不再有用时用 manage_character 工具移除
5. 用 chatgroup 工具输出你的叙述
6. 不要每轮都发言——只在剧情出现转折、新场景开始、或需要引入新角色时才发言
7. 叙述应生动沉浸，像小说一样，每次发言都是一段精炼的叙述文''';

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

void _glog(String msg) {
  debugPrint('[GroupProvider] $msg');
}

final groupProvider =
    StateNotifierProvider<GroupNotifier, GroupState>((ref) {
  return GroupNotifier(ref, ref.read(groupServiceProvider));
});
