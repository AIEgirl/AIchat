import 'package:flutter/foundation.dart';
import '../models/group_chat.dart';
import '../models/group_member.dart';
import '../models/group_message.dart';
import '../models/group_shared_memory.dart';
import '../models/agent.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import 'database_service.dart';

void _glog(String msg) {
  debugPrint('[GroupService] $msg');
}

class GroupService {
  String? _activeGroupId;
  final int maxShortTermRounds = 20;

  String? get activeGroupId => _activeGroupId;

  // ═══ Group CRUD ═══

  Future<List<GroupChat>> getGroups() async {
    return await DatabaseService.getGroupChats();
  }

  Future<GroupChat?> getGroup(String id) async {
    return await DatabaseService.getGroupChat(id);
  }

  Future<void> createGroup(GroupChat group, List<GroupMember> members) async {
    await DatabaseService.insertGroupChat(group);
    _activeGroupId = group.id;
    _glog('Creating group ${group.name} (${group.id}) with ${members.length} members');
    for (final member in members) {
      final fixed = member.copyWith(groupId: group.id);
      await DatabaseService.insertGroupMember(fixed);
      _glog('  inserted member agentId=${fixed.agentId} groupId=${fixed.groupId} role=${fixed.role}');
    }
    _glog('Created group ${group.name} with ${members.length} members');
  }

  Future<void> updateGroup(GroupChat group) async {
    await DatabaseService.updateGroupChat(group);
  }

  Future<void> deleteGroup(String id) async {
    await DatabaseService.deleteGroupMembersForGroup(id);
    await DatabaseService.deleteGroupMessagesForGroup(id);
    await DatabaseService.deleteGroupSharedMemoriesForGroup(id);
    await DatabaseService.deleteGroupChatCascade(id);
    if (_activeGroupId == id) _activeGroupId = null;
    _glog('Deleted group $id and all associated data');
  }

  void setActiveGroup(String? id) {
    _activeGroupId = id;
  }

  // ═══ Members ═══

  Future<List<GroupMember>> getMembers(String groupId) async {
    return await DatabaseService.getGroupMembers(groupId);
  }

  Future<List<GroupMember>> getPresentMembers(String groupId) async {
    final all = await getMembers(groupId);
    return all.where((m) => m.isPresent).toList();
  }

  Future<void> addMember(GroupMember member) async {
    await DatabaseService.insertGroupMember(member);
  }

  Future<void> updateMember(GroupMember member) async {
    await DatabaseService.updateGroupMember(member);
  }

  Future<void> removeMember(int memberId) async {
    await DatabaseService.deleteGroupMember(memberId);
  }

  Future<void> togglePresence(int memberId, bool present) async {
    final members = await getMembers(_activeGroupId ?? '');
    final target =
        members.cast<GroupMember?>().firstWhere((m) => m?.id == memberId,
            orElse: () => null);
    if (target != null) {
      await DatabaseService.updateGroupMember(
          target.copyWith(isPresent: present));
    }
  }

  // ═══ Messages ═══

  Future<List<GroupMessage>> getMessages(String groupId) async {
    return await DatabaseService.getGroupMessages(groupId);
  }

  Future<GroupMessage> sendUserMessage(String groupId, String content) async {
    final msg = GroupMessage(
      groupId: groupId,
      senderType: 'user',
      content: content,
    );
    final id = await DatabaseService.insertGroupMessage(msg);
    await _addToShortTerm(
        groupId: groupId, role: 'user', content: content);
    return msg.copyWith(id: id);
  }

  Future<GroupMessage> sendAgentMessage({
    required String groupId,
    required String agentId,
    required String agentName,
    required String content,
  }) async {
    final msg = GroupMessage(
      groupId: groupId,
      senderType: 'agent',
      senderId: agentId,
      senderName: agentName,
      content: content,
    );
    final id = await DatabaseService.insertGroupMessage(msg);
    await _addToShortTerm(
        groupId: groupId,
        role: 'assistant',
        senderName: agentName,
        content: content);
    return msg.copyWith(id: id);
  }

  // ═══ Short-term memory ═══

  Future<void> _addToShortTerm({
    required String groupId,
    required String role,
    String? senderName,
    required String content,
  }) async {
    await DatabaseService.insertGroupShortTerm(
      groupId: groupId,
      role: role,
      senderName: senderName,
      content: content,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await DatabaseService.deleteOldestGroupShortTerm(
        groupId, maxShortTermRounds);
  }

  Future<List<Map<String, dynamic>>> getShortTerm(
      String groupId) async {
    return await DatabaseService.getGroupShortTerm(groupId);
  }

  Future<void> clearShortTerm(String groupId) async {
    await DatabaseService.clearGroupShortTerm(groupId);
  }

  void loadMessageToShortTerm(GroupMessage msg) async {
    await _addToShortTerm(
      groupId: msg.groupId,
      role: msg.senderType,
      senderName: msg.senderName,
      content: msg.content,
    );
  }

  // ═══ Shared Memories ═══

  Future<List<GroupSharedMemory>> getSharedMemories(
      String groupId) async {
    return await DatabaseService.getGroupSharedMemories(groupId);
  }

  Future<String> createSharedMemory({
    required String groupId,
    required String field,
    required String content,
  }) async {
    final maxNum =
        await DatabaseService.getMaxGroupSharedIdNumber(groupId);
    final newId = 'GS${(maxNum + 1).toString().padLeft(3, '0')}';
    final mem = GroupSharedMemory(
      id: newId,
      groupId: groupId,
      field: field,
      content: content,
    );
    await DatabaseService.insertGroupSharedMemory(mem);
    return newId;
  }

  Future<void> updateSharedMemory(GroupSharedMemory memory) async {
    await DatabaseService.updateGroupSharedMemory(memory);
  }

  Future<void> deleteSharedMemory(String id) async {
    await DatabaseService.deleteGroupSharedMemory(id);
  }

  // ═══ Personal memories in group context ═══

  Future<List<LongTermMemory>> getAgentGroupLongTermMemories(
      String agentId, String groupId) async {
    return await DatabaseService.getLongTermMemoriesForGroup(
        agentId, groupId);
  }

  Future<List<BaseMemory>> getAgentGroupBaseMemories(
      String agentId, String groupId) async {
    return await DatabaseService.getBaseMemoriesForGroup(
        agentId, groupId);
  }

  // ═══ System prompt builder for group chat ═══

  Future<String> buildGroupSystemPrompt({
    required GroupChat group,
    required Agent agent,
    required String agentPersona,
    required List<GroupMember> allMembers,
    required List<Agent> agentDetails,
  }) async {
    final now = DateTime.now();
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final timeStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final weekStr = weekdays[now.weekday - 1];

    final otherPresent = allMembers
        .where((m) =>
            m.isPresent && m.agentId != agent.id)
        .toList();

    final otherPresentLines = otherPresent.map((m) {
      final detail =
          agentDetails.cast<Agent?>().firstWhere((a) => a?.id == m.agentId,
              orElse: () => null);
      final name = detail?.name ?? m.agentId;
      return '- $name（${m.role}）';
    }).join('\n');

    final sharedMems = await getSharedMemories(group.id);
    final sharedLines = sharedMems.isNotEmpty
        ? sharedMems.map((m) => m.toPromptLine()).join('\n')
        : '（暂无群共享记忆）';

    final personalMems =
        await getAgentGroupLongTermMemories(agent.id, group.id);
    final personalLines = personalMems.isNotEmpty
        ? personalMems.map((m) => m.toPromptLine()).join('\n')
        : '（暂无个人群聊记忆）';

    final isModerator =
        allMembers.any((m) => m.agentId == agent.id && m.role == 'moderator');
    return '''【当前真实时间】$timeStr（星期$weekStr）

你是群聊「${group.name}」的成员。你的名字是 ${agent.name}。

【群聊设定】
${group.groupPersona != null && group.groupPersona!.isNotEmpty ? group.groupPersona! : '（无特殊群聊设定，遵循个人设定）'}

【你的个人设定】
$agentPersona

${isModerator ? '【你的角色】你是本群的主持人（moderator），负责引导话题、维持秩序。' : ''}

【当前在场的其他成员】
${otherPresent.isNotEmpty ? otherPresentLines : '（暂无其他成员）'}

【群共享记忆】（群内所有人都知道的事情）
$sharedLines

【你个人的群聊记忆】（只有你知道的事情）
$personalLines

【群聊工具规则】
- 使用 chatgroup 工具在群聊中发言。
- 你需要记住的信息使用 remember 工具，group_scope 设为 "personal"（个人群内记忆）或 "shared"（群共享记忆）。
- 遗忘信息时使用 forget 工具，memory_source 设为 "personal" 或 "shared"。
- 可以 @其他成员 点名交流。
- 保持与你人设一致的说话风格。
- 使用 plan 工具可安排在群聊中未来发送消息。

【群聊最高优先级：工具调用规则】
- 在回复任何消息前，判断是否需要记忆处理。
- 如果消息包含需要记住的信息 → 使用 remember 工具。
- 如果有过时的记忆 → 使用 forget 工具。
- 使用 chatgroup 工具来发送你的回复。
- 所有记忆操作必须在 chatgroup 之前完成。''';
  }
}
