import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/group_provider.dart';
import '../providers/agent_provider.dart';
import '../models/group_message.dart';
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

  void _showMessageActions(GroupMessage msg) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: Text(l10n.get('copyText')),
            onTap: () { Navigator.pop(ctx); Clipboard.setData(ClipboardData(text: msg.content)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.get('copied')), duration: const Duration(seconds: 1))); },
          ),
          if (msg.isAgent) ...[
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(l10n.get('regenerate')),
              onTap: () { Navigator.pop(ctx); },
            ),
          ],
          ListTile(
            leading: Icon(Icons.delete, color: scheme.error),
            title: Text(l10n.get('deleteMessage'), style: TextStyle(color: scheme.error)),
            onTap: () { Navigator.pop(ctx); ref.read(groupProvider.notifier).deleteMessage(msg); },
          ),
        ]),
      ),
    );
  }

  void _showAgentMemories(GroupMessage msg) async {
    final l10n = AppLocalizations.of(context);
    final groupService = ref.read(groupServiceProvider);
    final agentId = msg.senderId ?? '';
    final groupId = widget.groupId;
    if (agentId.isEmpty) return;

    final personalMems = await groupService.getAgentGroupLongTermMemories(agentId, groupId);
    final sharedMems = await groupService.getSharedMemories(groupId);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SizedBox(
        height: 400,
        child: DefaultTabController(
          length: 2,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('${msg.senderName ?? "Agent"} ${l10n.get("memoryManagementTitle")}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            TabBar(
              tabs: [
                Tab(text: '${l10n.get("longTermTab")} (${personalMems.length})'),
                Tab(text: '${l10n.get("sharedMemories")} (${sharedMems.length})'),
              ],
            ),
            Expanded(
              child: TabBarView(children: [
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group?.name ?? l10n.get('groupChat'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            Text(presentNames.isNotEmpty ? presentNames : l10n.get('noMembers'),
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          if (state.isLoading)
            IconButton(
              icon: Icon(Icons.stop_circle, color: Theme.of(context).colorScheme.error),
              tooltip: l10n.get('stopGenerating'),
              onPressed: _interrupt,
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
                        onTap: () => _showMessageActions(msg),
                        onAvatarTap: msg.isAgent
                            ? () => _showAgentMemories(msg)
                            : null,
                      );
                    },
                  ),
          ),
          if (state.isLoading)
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
          if (state.error != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(state.error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ),
          _buildInputArea(l10n),
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
  final VoidCallback? onTap;
  final VoidCallback? onAvatarTap;

  const _GroupBubble({
    required this.message,
    required this.agentName,
    required this.agentColor,
    this.onTap,
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) GestureDetector(onTap: onAvatarTap, child: _agentAvatar()),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onTap: onTap,
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
                    border: Border.all(color: borderColor),
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
          if (isUser)
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
