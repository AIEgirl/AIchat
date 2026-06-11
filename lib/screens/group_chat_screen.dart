import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/group_provider.dart';
import '../providers/agent_provider.dart';
import '../models/group_message.dart';
import '../services/tool_executor.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/responsive_layout.dart';
import 'group_manage_screen.dart';

class GroupChatScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupChatScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  bool _multiSelectMode = false;
  final Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(groupProvider.notifier).loadGroup(widget.groupId);
      _inputFocus.unfocus();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    _inputFocus.unfocus();
    ref
        .read(groupProvider.notifier)
        .sendUserMessage(widget.groupId, text);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollAfter(200));
  }

  void _scrollAfter(int ms) {
    Future.delayed(Duration(milliseconds: ms), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _interrupt() {
    ref.read(groupProvider.notifier).interruptAgents();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).get('agentInterrupted')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showMessageActions(GroupMessage msg, int index, Offset position) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    Widget btn(IconData icon, String label, VoidCallback onTap, {Color? color}) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () { Navigator.pop(context); onTap(); },
        child: SizedBox(
          width: 64,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 24, color: color ?? scheme.onSurface),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(fontSize: 10, color: (color ?? scheme.onSurface).withValues(alpha: 0.8)),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      );
    }

    showMenu(
      context: context,
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: IntrinsicWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 8,
                children: [
                  btn(Icons.copy, l10n.get('copyText'), () {
                    Clipboard.setData(ClipboardData(text: msg.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.get('copied')), duration: const Duration(seconds: 1)));
                  }),
                  if (msg.isAgent) ...[
                    btn(Icons.refresh, l10n.get('regenerate'), () {}),
                    if (msg.toolCallData != null || msg.toolLogs != null)
                      btn(Icons.code, l10n.get('viewToolCalls'), () {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _showToolLogsForGroupMessage(context, msg);
                        });
                      }),
                  ],
                  btn(Icons.checklist, '多选', () => _enterMultiSelect(index), color: scheme.primary),
                  btn(Icons.delete, l10n.get('deleteMessage'), () => ref.read(groupProvider.notifier).deleteMessage(msg), color: scheme.error),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showToolLogsForGroupMessage(BuildContext context, GroupMessage msg) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final logs = msg.toolLogs ?? [];
    if (logs.isEmpty) {
      try {
        final data = jsonDecode(msg.toolCallData ?? '[]') as List;
        for (final e in data) {
          logs.add(ToolExecutionLog(
            toolName: e['toolName'] as String,
            arguments: Map<String, dynamic>.from(e['arguments'] as Map),
            result: e['result'] as String,
          ));
        }
      } catch (_) {}
    }
    if (logs.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.get('toolCalls'), style: const TextStyle(fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: logs.length,
            itemBuilder: (_, i) {
              final log = logs[i];
              final formattedArgs = const JsonEncoder.withIndent('  ').convert(log.arguments);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(log.toolName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: scheme.primary)),
                  const SizedBox(height: 4),
                  Text(formattedArgs, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                  const SizedBox(height: 4),
                  Text(log.result, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ]),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('close')))],
      ),
    );
  }

  void _showGroupMemoryPanel({String? initialAgentId, String? initialAgentName}) async {
    final l10n = AppLocalizations.of(context);
    final groupService = ref.read(groupServiceProvider);
    final groupId = widget.groupId;
    final members = ref.read(groupProvider).members;
    final agentList = ref.read(agentProvider).agents;

    final agents = members.map((m) {
      final a = agentList.where((x) => x.id == m.agentId).firstOrNull;
      return (id: m.agentId, name: a?.name ?? m.agentId.substring(0, 6));
    }).toList();

    if (agents.isEmpty) return;

    String selId = initialAgentId ?? agents.first.id;
    String selName = initialAgentName ?? agents.first.name;

    List<dynamic> personalMems = [];
    List<dynamic> sharedMems = [];
    bool memsLoading = true;

    Future<void> loadMems() async {
      memsLoading = true;
      final p = await groupService.getAgentGroupLongTermMemories(selId, groupId);
      final s = await groupService.getSharedMemories(groupId);
      personalMems = p;
      sharedMems = s;
      memsLoading = false;
    }

    await loadMems();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) => SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: DefaultTabController(
              length: 2,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(children: [
                    Text('$selName ${l10n.get("memoryManagementTitle")}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: agents.map((a) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(a.name, style: const TextStyle(fontSize: 12)),
                          selected: selId == a.id,
                          onSelected: (_) async {
                            selId = a.id;
                            selName = a.name;
                            setSheetState(() { memsLoading = true; });
                            final p = await groupService.getAgentGroupLongTermMemories(selId, groupId);
                            final s = await groupService.getSharedMemories(groupId);
                            setSheetState(() {
                              personalMems = p;
                              sharedMems = s;
                              memsLoading = false;
                            });
                          },
                        ),
                      )).toList()),
                    ),
                  ]),
                ),
                const Divider(height: 1),
                TabBar(
                  tabs: [
                    Tab(text: '${l10n.get("longTermTab")} (${memsLoading ? '...' : personalMems.length})'),
                    Tab(text: '${l10n.get("sharedMemories")} (${memsLoading ? '...' : sharedMems.length})'),
                  ],
                ),
                Expanded(
                  child: memsLoading
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      : TabBarView(children: [
                          personalMems.isEmpty
                              ? Center(child: Text(l10n.get('noLongTermMemory')))
                              : ListView.builder(
                                  itemCount: personalMems.length,
                                  itemBuilder: (_, i) => ListTile(dense: true, title: Text(personalMems[i].toPromptLine(), style: const TextStyle(fontSize: 13))),
                                ),
                          sharedMems.isEmpty
                              ? Center(child: Text(l10n.get('noBaseMemory')))
                              : ListView.builder(
                                  itemCount: sharedMems.length,
                                  itemBuilder: (_, i) => ListTile(dense: true, title: Text(sharedMems[i].toPromptLine(), style: const TextStyle(fontSize: 13))),
                                ),
                        ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  void _showAgentMemories(GroupMessage msg) {
    if (msg.senderId == null) return;
    _showGroupMemoryPanel(initialAgentId: msg.senderId, initialAgentName: msg.senderName);
  }

  void _openMemoryPanel() {
    _showGroupMemoryPanel();
  }

  void _enterMultiSelect(int index) =>
      setState(() { _multiSelectMode = true; _selectedIndices.add(index); });

  void _exitMultiSelect() =>
      setState(() { _multiSelectMode = false; _selectedIndices.clear(); });

  void _toggleSelect(int index) => setState(() {
    if (_selectedIndices.contains(index)) {
      _selectedIndices.remove(index);
      if (_selectedIndices.isEmpty) _multiSelectMode = false;
    } else {
      _selectedIndices.add(index);
    }
  });

  void _copySelected() {
    final state = ref.read(groupProvider);
    final lines = _selectedIndices.toList()..sort();
    final buf = StringBuffer();
    for (final i in lines) {
      if (i < state.messages.length) {
        final msg = state.messages[i];
        buf.writeln('${msg.senderName ?? (msg.isUser ? 'User' : 'Agent')}: ${msg.content}');
      }
    }
    if (buf.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: buf.toString()));
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已复制 ${lines.length} 条'), duration: const Duration(seconds: 1)));
    }
  }

  void _deleteSelected() {
    final state = ref.read(groupProvider);
    final indices = _selectedIndices.toList()..sort((a, b) => b.compareTo(a));
    for (final i in indices) {
      if (i < state.messages.length) {
        ref.read(groupProvider.notifier).deleteMessage(state.messages[i]);
      }
    }
    _exitMultiSelect();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupProvider);
    final group = state.activeGroup;
    final messages = state.messages;
    final members = state.members;
    final l10n = AppLocalizations.of(context);

    final presentNames = members
        .where((m) => m.isPresent)
        .map((m) {
      final agentList = ref.read(agentProvider).agents;
      final agent =
          agentList.where((a) => a.id == m.agentId).firstOrNull;
      return agent?.name ?? m.agentId.substring(0, 6);
    }).join(', ');

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: _multiSelectMode
            ? IconButton(icon: const Icon(Icons.close), onPressed: _exitMultiSelect)
            : null,
        title: _multiSelectMode
            ? Text('已选 ${_selectedIndices.length} 条',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group?.name ?? l10n.get('groupChat'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(presentNames.isNotEmpty ? presentNames : l10n.get('noMembers'),
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
        actions: _multiSelectMode
            ? null
            : [
          if (state.isLoading)
            IconButton(
              icon: Icon(Icons.stop_circle, color: Theme.of(context).colorScheme.error),
              tooltip: l10n.get('stopGenerating'),
              onPressed: _interrupt,
            ),
          IconButton(
            icon: const Icon(Icons.storage),
            tooltip: l10n.get('memoryManagement'),
            onPressed: _openMemoryPanel,
          ),
          IconButton(
            icon: const Icon(Icons.manage_accounts),
            tooltip: l10n.get('manageGroup'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      GroupManageScreen(groupId: widget.groupId)),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => _inputFocus.unfocus(),
        child: Column(children: [
          Expanded(
            child: messages.isEmpty
                ? Center(child: Text(l10n.get('startGroupChat')))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final msg = messages[i];
                      final name = _getAgentName(msg);
                      final color = _getAgentColor(msg);
                      return _GroupBubble(
                        message: msg,
                        agentName: name,
                        agentColor: color,
                        multiSelectMode: _multiSelectMode,
                        isSelected: _selectedIndices.contains(i),
                        onLongPress: (pos) => _showMessageActions(msg, i, pos),
                        onToggle: () => _toggleSelect(i),
                        onAvatarTap: msg.isAgent
                            ? () => _showAgentMemories(msg)
                            : null,
                      );
                    },
                  ),
          ),
          if (!_multiSelectMode && state.isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text(l10n.get('agentsReplying'),
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ]),
            ),
          if (!_multiSelectMode && state.error != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(state.error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ),
          if (_multiSelectMode) _buildMultiSelectBar(),
          if (!_multiSelectMode) _buildInputArea(l10n),
        ]),
      ),
    );
  }

  Widget _buildMultiSelectBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: SafeArea(
        child: Row(children: [
          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: _exitMultiSelect),
          const SizedBox(width: 4),
          Text('${_selectedIndices.length} 条', style: const TextStyle(fontSize: 13)),
          const Spacer(),
          IconButton(tooltip: '复制', icon: const Icon(Icons.copy, size: 20), onPressed: _copySelected),
          IconButton(tooltip: '删除', icon: Icon(Icons.delete, size: 20, color: scheme.error), onPressed: _deleteSelected),
        ]),
      ),
    );
  }

  Widget _buildInputArea(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        child: Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5))),
              child: TextField(
                focusNode: _inputFocus,
                controller: _inputCtrl,
                decoration: InputDecoration(
                    hintText: l10n.get('typeMessage'),
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: scheme.primary,
            shape: const CircleBorder(),
            elevation: 2,
            shadowColor: scheme.primary.withValues(alpha: 0.3),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _send,
              child: const SizedBox(
                width: 44, height: 44,
                child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  String _getAgentName(GroupMessage msg) {
    if (msg.isUser) return 'You';
    if (msg.senderName != null && msg.senderName!.isNotEmpty) {
      return msg.senderName!;
    }
    final agents = ref.read(agentProvider).agents;
    final agent =
        agents.where((a) => a.id == msg.senderId).firstOrNull;
    return agent?.name ?? 'AI';
  }

  int _getAgentColor(GroupMessage msg) {
    if (msg.senderId != null) {
      final agents = ref.read(agentProvider).agents;
      final agent =
          agents.where((a) => a.id == msg.senderId).firstOrNull;
      if (agent != null) return agent.avatarColor;
    }
    return 0xFFCFD8DC;
  }
}

class _GroupBubble extends StatelessWidget {
  final GroupMessage message;
  final String agentName;
  final int agentColor;
  final bool multiSelectMode;
  final bool isSelected;
  final void Function(Offset position)? onLongPress;
  final VoidCallback? onToggle;
  final VoidCallback? onAvatarTap;

  const _GroupBubble({
    required this.message,
    required this.agentName,
    required this.agentColor,
    this.multiSelectMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.onToggle,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final scheme = Theme.of(context).colorScheme;
    final timeStr =
        DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(message.timestamp));

    final bubbleColor = isUser ? scheme.primaryContainer : scheme.surface;
    final onBubbleColor = isUser ? scheme.onPrimaryContainer : scheme.onSurface;
    final borderColor = isUser ? Colors.transparent : scheme.outlineVariant.withValues(alpha: 0.6);
    final selectedBorder = isSelected ? scheme.primary : borderColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (multiSelectMode && !isUser)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: 24, height: 24,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => onToggle?.call(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          if (!isUser) GestureDetector(onTap: onAvatarTap, child: _agentAvatar()),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onLongPressStart: onLongPress != null
                  ? (d) {
                      HapticFeedback.lightImpact();
                      onLongPress!(d.globalPosition);
                    }
                  : null,
              onTap: multiSelectMode ? onToggle : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: ResponsiveLayout.bubbleMaxWidth(context)),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(AppTheme.radiusLg),
                      topRight: const Radius.circular(AppTheme.radiusLg),
                      bottomLeft: Radius.circular(isUser ? AppTheme.radiusLg : 4),
                      bottomRight: Radius.circular(isUser ? 4 : AppTheme.radiusLg),
                    ),
                    border: Border.all(color: selectedBorder, width: isSelected ? 2 : 1),
                    boxShadow: AppTheme.shadowSm,
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isUser)
                          Text(agentName,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.onSurfaceVariant)),
                        if (!isUser) const SizedBox(height: 2),
                        Text(message.content,
                            style: TextStyle(fontSize: 14, color: onBubbleColor, height: 1.4)),
                        const SizedBox(height: 2),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(timeStr,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: onBubbleColor.withValues(alpha: 0.6))),
                        ),
                      ]),
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (multiSelectMode && isUser)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: 24, height: 24,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => onToggle?.call(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          if (!multiSelectMode && isUser)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: scheme.primary, shape: BoxShape.circle),
              child: Icon(Icons.person,
                  color: scheme.onPrimary, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _agentAvatar() {
    return CircleAvatar(
      radius: 16,
      backgroundColor: Color(agentColor),
      child: Text(
          agentName.isNotEmpty
              ? agentName[0].toUpperCase()
              : '?',
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.black87)),
    );
  }
}
