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
    );
    _glog('  created GroupChat id=${group.id}');
    await _groupService.createGroup(group, members);
    await loadGroups();
    _glog('  loadGroups returned ${state.groups.length} groups');
    await loadGroup(group.id);
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

    int idx = 0;
    for (final member in sorted) {
      if (_userInterrupted) {
        _glog('User interrupted at agent $idx/${sorted.length}, stopping');
        state = state.copyWith(isLoading: false);
        return;
      }

      final agent = await DatabaseService.getAgent(member.agentId);
      if (agent == null) {
        _glog('  SKIP idx=$idx: agent not found for ${member.agentId}');
        idx++;
        continue;
      }

      _glog('  [${idx + 1}/${sorted.length}] Generating reply for ${agent.name} (${member.role})');
      await _generateSingleAgentReply(groupId, member, agent);

      // Yield to Flutter so the UI rebuilds with the latest message before next agent
      await Future.delayed(const Duration(milliseconds: 50));
      idx++;
    }

    if (_userInterrupted) {
      _glog('Interrupted during agent loop');
    } else {
      _glog('All ${sorted.length} agents replied successfully');
    }
    state = state.copyWith(isLoading: false);
  }

  Future<void> _generateSingleAgentReply(
      String groupId, GroupMember member, Agent agent) async {
    _glog('    _generateSingleAgentReply: agent=${agent.name} groupId=$groupId');
    final settings = _ref.read(settingsProvider);
    final provider = settings.activeProvider;
    if (provider == null) {
      _glog('    SKIP: no active provider');
      return;
    }

    final group = await _groupService.getGroup(groupId);
    if (group == null) {
      _glog('    SKIP: group not found');
      return;
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

    final shortTerm = await _groupService.getShortTerm(groupId);
    _glog('    shortTerm rounds: ${shortTerm.length}');

    final apiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemContent},
      ...shortTerm.map((m) {
            var role = m['role'] as String;
            if (role == 'agent') role = 'assistant';
            return {'role': role, 'content': m['content'] as String};
          }),
    ];

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
        final updatedMessages = [...state.messages, agentMsg];
        state = state.copyWith(messages: updatedMessages);
        _glog('    REPLY stored: "${result.length > 60 ? '${result.substring(0, 60)}...' : result}"');
      } else {
        _glog('    No reply generated');
      }
    } on ApiException catch (e) {
      _glog('    ApiException: $e');
      _addErrorToChat(groupId, agent.name, 'API error: $e');
    } catch (e) {
      _glog('    Unexpected error: $e');
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
    ToolExecutor toolExecutor = _ref.read(toolExecutorProvider);

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
