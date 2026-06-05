import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart' as pp;
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../services/database_service.dart';
import '../services/plugin_manager.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/responsive_layout.dart';
import 'memory_screen.dart';
import 'plan_screen.dart';
import 'settings_screen.dart';
import '../providers/agent_provider.dart';
import '../providers/memory_provider.dart';
import '../providers/group_provider.dart';
import '../models/agent.dart';
import '../models/group_chat.dart';
import '../services/agent_export_service.dart';
import 'agent_create_screen.dart';
import 'group_create_screen.dart';
import 'group_chat_screen.dart';
import 'group_manage_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _sendTrigger = 0;
  File? _pendingImage;
  final FocusNode _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();

    // Defocus input on first frame to prevent keyboard auto-popup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocus.unfocus();
      final planService = ref.read(planServiceProvider);
      planService.onPlanTriggered = (message) {
        ref.read(chatProvider.notifier).addSystemMessage(message);
      };
      final notificationService = ref.read(notificationServiceProvider);
      notificationService.onNotificationTapped = (id) {
        ref.read(planServiceProvider).deliverFromNotification(id);
      };
      notificationService.onAiMessageTapped = (payload) {
        if (payload != null && payload.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(payload.length > 100
                    ? '${payload.substring(0, 100)}...'
                    : payload)),
          );
        }
      };
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _sendTrigger++;
    ref.read(chatProvider.notifier).sendMessage(text);
    _inputFocus.unfocus();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToBottom());
  }

  void _sendMessageOrImage() {
    if (_pendingImage != null) {
      ref
          .read(chatProvider.notifier)
          .sendImageMessage(_pendingImage!, _controller.text.trim());
      _controller.clear();
      setState(() => _pendingImage = null);
      _sendTrigger++;
      _inputFocus.unfocus();
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToBottom());
    } else {
      _sendMessage();
    }
  }

  void _showAttachmentOptions() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => SafeArea(
                child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                        leading: const Icon(Icons.photo_library),
                        title: Text(l10n.get('album')),
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickImage(ImageSource.gallery);
                        }),
                    ListTile(
                        leading: const Icon(Icons.camera_alt),
                        title: Text(l10n.get('takePhoto')),
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickImage(ImageSource.camera);
                        }),
                  ]),
            )));
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final img =
          await picker.pickImage(source: source, maxWidth: 2048);
      if (img != null) setState(() => _pendingImage = File(img.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _onDeleteMessage(ChatMessage message) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_outline, color: scheme.error, size: 32),
        title: Text(l10n.get('confirmDelete')),
        content: Text(l10n.get('deleteMessageConfirm'),
            textAlign: TextAlign.center),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.get('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError),
            onPressed: () {
              ref.read(chatProvider.notifier).deleteMessage(message);
              Navigator.pop(ctx);
            },
            child: Text(l10n.get('delete')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveLayout.isDesktop(context);

    if (isDesktop) {
      return _buildDesktopLayout();
    }
    return _buildMobileLayout();
  }

  // ═══ Mobile Layout (existing) ═══
  Widget _buildMobileLayout() {
    final chatState = ref.watch(chatProvider);
    final settings = ref.watch(settingsProvider);
    final model = settings.effectiveModel;
    final l10n = AppLocalizations.of(context);
    final agent = ref.watch(agentProvider).currentAgent;
    final appTitle = agent?.name ?? l10n.get('appTitle');

    return Scaffold(
      drawer: _buildDrawerMobile(),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: Builder(
            builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer())),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appTitle,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            Text(model.isNotEmpty ? model : l10n.get('noModel'),
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiary,
                          shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(l10n.get('online'),
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
          ),
          IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: l10n.get('debugLogs'),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DebugLogScreen()))),
          IconButton(
              icon: const Icon(Icons.storage),
              tooltip: l10n.get('memoryManagement'),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const MemoryScreen()))),
          IconButton(
              icon: const Icon(Icons.schedule),
              tooltip: l10n.get('plannedMessages'),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PlanScreen()))),
        ],
      ),
      body: _buildChatBody(chatState),
    );
  }

  // ═══ Desktop Layout (new) ═══
  Widget _buildDesktopLayout() {
    final chatState = ref.watch(chatProvider);
    final settings = ref.watch(settingsProvider);
    final model = settings.effectiveModel;
    final l10n = AppLocalizations.of(context);
    final agentState = ref.watch(agentProvider);
    final scheme = Theme.of(context).colorScheme;
    final appTitle = agentState.currentAgent?.name ?? l10n.get('appTitle');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appTitle,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            Text(model.isNotEmpty ? model : l10n.get('noModel'),
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: scheme.tertiary,
                          shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(l10n.get('online'),
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ]),
          ),
          IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: l10n.get('debugLogs'),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DebugLogScreen()))),
          IconButton(
              icon: const Icon(Icons.settings),
              tooltip: l10n.get('settings'),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SettingsScreen()))),
        ],
      ),
      body: Row(children: [
        SizedBox(
          width: ResponsiveLayout.sidebarWidth,
          child: _buildDesktopSidebar(agentState, l10n),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildChatBody(chatState)),
      ]),
    );
  }

  Widget _buildDesktopSidebar(AgentState agentState, AppLocalizations l10n) {
    final current = agentState.currentAgent;
    final agents = agentState.agents;
    final groupState = ref.watch(groupProvider);
    final groups = groupState.groups;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _agentAvatar(current),
            const SizedBox(height: 8),
            Text(current?.name ?? l10n.get('noAgentSelected'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (current?.description.isNotEmpty == true)
              Text(current!.description, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
          ]),
        ),
        Expanded(
          child: ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentCreateScreen())),
                child: Text(l10n.get('createNewAgent'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              ),
            ),
            for (final a in agents)
              _agentListTile(a, current, l10n),
            const Divider(indent: 16, endIndent: 16),
            if (groups.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: InkWell(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupCreateScreen()));
                    ref.read(groupProvider.notifier).loadGroups();
                  },
                  child: Text(l10n.get('createGroup'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                ),
              ),
              for (final g in groups)
                _groupListTile(g, l10n),
            ] else
              Padding(
                padding: const EdgeInsets.all(16),
                child: InkWell(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupCreateScreen()));
                    ref.read(groupProvider.notifier).loadGroups();
                  },
                  child: Text(l10n.get('createGroup'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                ),
              ),
          ]),
        ),
        const Divider(height: 1),
        ListTile(
          dense: true,
          leading: const Icon(Icons.settings, size: 20),
          title: Text(l10n.get('settings'), style: const TextStyle(fontSize: 13)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _agentListTile(Agent a, Agent? current, AppLocalizations l10n) {
    final isCurrent = a.id == current?.id;
    return Tooltip(
      message: a.description.isNotEmpty ? a.description : a.name,
      child: ListTile(
        dense: true,
        leading: _agentAvatar(a, radius: 16, fontSize: 12),
        title: Text(a.name,
            style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, fontSize: 14)),
        selected: isCurrent,
        selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () => _switchAgent(a, current),
        onLongPress: () => _showSidebarAgentMenu(a, isCurrent, l10n),
      ),
    );
  }

  void _showSidebarAgentMenu(Agent a, bool isCurrent, AppLocalizations l10n) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: Text(l10n.get('edit')),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => AgentCreateScreen(agent: a)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_upload),
            title: Text(l10n.get('export')),
            onTap: () {
              Navigator.pop(ctx);
              _exportAgentFromSidebar(a);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: Text(l10n.get('delete'), style: const TextStyle(color: Colors.red)),
            enabled: !isCurrent,
            onTap: isCurrent ? null : () {
              Navigator.pop(ctx);
              _confirmDeleteAgentFromSidebar(a);
            },
          ),
        ]),
      ),
    );
  }

  void _exportAgentFromSidebar(Agent a) async {
    try {
      final l10n = AppLocalizations.of(context);
      final data = await AgentExportService.exportAgent(a);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await pp.getApplicationDocumentsDirectory();
      final fileName = '${a.name}_export.agent.json';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonStr);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.getP('agentExported', {'path': '${dir.path}/$fileName'}))));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${AppLocalizations.of(context).get('agentExportFailed')}: $e')));
      }
    }
  }

  void _confirmDeleteAgentFromSidebar(Agent a) {
    final l10n = AppLocalizations.of(context);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error, size: 32),
      title: Text(l10n.get('confirmDeleteAgentTitle')),
      content: Text(l10n.getP('confirmDeleteAgentContent', {'name': a.name, 'activeNote': ''})),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () {
            ref.read(agentProvider.notifier).deleteAgent(a.id);
            Navigator.pop(ctx);
          },
          child: Text(l10n.get('delete')),
        ),
      ],
    ));
  }

  Widget _groupListTile(GroupChat group, AppLocalizations l10n) {
    return Tooltip(
      message: group.description.isNotEmpty ? group.description : group.name,
      child: ListTile(
        dense: true,
        leading: Icon(Icons.group, size: 20, color: Theme.of(context).colorScheme.secondary),
        title: Text(group.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id))),
        onLongPress: () => _showSidebarGroupMenu(group, l10n),
      ),
    );
  }

  void _showSidebarGroupMenu(GroupChat group, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(Icons.chat_bubble_outline, color: scheme.primary),
            title: Text(l10n.get('enterGroupChat')),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: Text(l10n.get('editGroup')),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => GroupManageScreen(groupId: group.id)));
            },
          ),
          ListTile(
            leading: Icon(Icons.delete, color: scheme.error),
            title: Text(l10n.get('delete'), style: TextStyle(color: scheme.error)),
            onTap: () {
              Navigator.pop(ctx);
              _confirmDeleteGroupFromSidebar(group);
            },
          ),
        ]),
      ),
    );
  }

  void _confirmDeleteGroupFromSidebar(GroupChat group) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 32),
      title: Text(l10n.get('confirmDelete')),
      content: Text(l10n.getP('deleteGroupConfirmDetail', {'name': group.name})),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
          onPressed: () async {
            await ref.read(groupProvider.notifier).deleteGroup(group.id);
            Navigator.pop(ctx);
          },
          child: Text(l10n.get('delete')),
        ),
      ],
    ));
  }

  Future<void> _switchAgent(Agent a, Agent? current) async {
    if (a.id == current?.id) return;
    await ref.read(agentProvider.notifier).setActiveAgent(a.id);
    ref.read(memoryServiceProvider).setAgentId(a.id);
    await ref.read(memoryServiceProvider).loadShortTermFromDb(ref.read(settingsProvider).maxShortTermRounds);
    ref.read(chatProvider.notifier).reloadChatFromDb(a.id);
  }

  // ═══ Shared Chat Body ═══
  Widget _buildChatBody(ChatState chatState) {
    return Builder(builder: (ctx) {
      final agent = ref.watch(agentProvider).currentAgent;
      final bg = agent?.chatBackground;
      Widget body = Column(children: [
        Expanded(
          child: chatState.messages.isEmpty && !chatState.isLoading
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 8),
                  itemCount: chatState.messages.length,
                  itemBuilder: (context, index) {
                    return _AnimatedBubble(
                      key: ValueKey(
                          chatState.messages[index].dbId ??
                              chatState.messages[index].timestamp
                                  .millisecondsSinceEpoch),
                      message: chatState.messages[index],
                      onDelete: () =>
                          _onDeleteMessage(chatState.messages[index]),
                      onRegenerate: !chatState.messages[index].isUser
                          ? () {
                              ref
                                  .read(chatProvider.notifier)
                                  .regenerateMessage(index);
                            }
                          : null,
                    );
                  },
                ),
        ),
        if (chatState.isLoading) const BouncingDotsIndicator(),
        if (chatState.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 4),
            child: Text(chatState.error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ),
        _buildPluginButtons(),
        _buildInputArea(),
      ]);
      if (bg != null) {
        if (bg.startsWith('#')) {
          body = Container(
              color: Color(int.parse(bg.substring(1), radix: 16) |
                  0xFF000000),
              child: body);
        } else if (File(bg).existsSync()) {
          body = Container(
              decoration: BoxDecoration(
                  image: DecorationImage(
                      image: FileImage(File(bg)),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                          Colors.white.withValues(alpha: 0.8),
                          BlendMode.dstATop))),
              child: body);
        }
      }
      // Tap blank area to dismiss keyboard
      return GestureDetector(
        onTap: () => _inputFocus.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: body,
      );
    });
  }

  Widget _buildDrawerMobile() {
    final state = ref.watch(agentProvider);
    final current = state.currentAgent;
    final agents = state.agents;
    final groupState = ref.watch(groupProvider);
    final groups = groupState.groups;
    final l10n = AppLocalizations.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              _agentAvatar(current),
              const SizedBox(height: 8),
              Text(current?.name ?? l10n.get('noAgentSelected'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (current?.description.isNotEmpty == true)
                Text(current!.description, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
            ]),
          ),
          Expanded(
            child: ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: InkWell(
                  onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentCreateScreen())); },
                  child: Text(l10n.get('createNewAgent'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                ),
              ),
              for (final a in agents)
                ListTile(
                  dense: true,
                  leading: _agentAvatar(a, radius: 18, fontSize: 14),
                  title: Text(a.name),
                  subtitle: a.description.isNotEmpty
                      ? Text(a.description, maxLines: 1, overflow: TextOverflow.ellipsis)
                      : null,
                  trailing: a.id == current?.id
                      ? Container(width: 10, height: 10, decoration: BoxDecoration(color: Theme.of(context).colorScheme.tertiary, shape: BoxShape.circle))
                      : null,
                  onTap: () async { Navigator.pop(context); await _switchAgent(a, current); },
                  onLongPress: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => AgentCreateScreen(agent: a))); },
                ),
              const Divider(indent: 16, endIndent: 16),
              if (groups.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: InkWell(
                    onTap: () async {
                      Navigator.pop(context);
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupCreateScreen()));
                      ref.read(groupProvider.notifier).loadGroups();
                    },
                    child: Text(l10n.get('createGroup'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                  ),
                ),
              ],
              for (final g in groups)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.group, size: 20, color: Theme.of(context).colorScheme.secondary),
                  title: Text(g.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: g.id))); },
                  onLongPress: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => GroupManageScreen(groupId: g.id))); },
                ),
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: InkWell(
                    onTap: () async {
                      Navigator.pop(context);
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupCreateScreen()));
                      ref.read(groupProvider.notifier).loadGroups();
                    },
                    child: Text(l10n.get('createGroup'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                  ),
                ),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(l10n.get('settings')),
            onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); },
          ),
        ]),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chat_bubble_outline,
                  size: 44, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Text(l10n.get('startChat'),
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
            const SizedBox(height: 6),
            Text(l10n.get('startChatSub'),
                style: TextStyle(
                    fontSize: 13, color: scheme.onSurfaceVariant)),
          ]),
    );
  }

  Widget _agentAvatar(Agent? agent,
      {double radius = 28, double fontSize = 24}) {
    if (agent?.avatarPath != null &&
        agent!.avatarPath!.isNotEmpty &&
        File(agent.avatarPath!).existsSync()) {
      return ClipOval(
          child: Image.file(File(agent.avatarPath!),
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover));
    }
    return CircleAvatar(
        radius: radius,
        backgroundColor:
            agent != null ? Color(agent.avatarColor) : Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(
            agent?.name.isNotEmpty == true ? agent!.name[0].toUpperCase() : '?',
            style: TextStyle(
                fontSize: fontSize, fontWeight: FontWeight.bold, color: Colors.black87)));
  }

  Widget _buildPluginButtons() {
    final buttons = PluginManager.instance.getAllButtons();
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
            children: buttons
                .map((b) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: b.icon != null
                            ? Icon(_resolveIcon(b.icon!), size: 16)
                            : null,
                        label: Text(b.label),
                        onPressed: () {
                          final text = b.onClick();
                          if (text.isNotEmpty) {
                            _controller.text +=
                                _controller.text.isEmpty
                                    ? text
                                    : '\n$text';
                            _controller.selection =
                                TextSelection.collapsed(
                                    offset:
                                        _controller.text.length);
                          }
                        },
                      ),
                    ))
                .toList()),
      ),
    );
  }

  Widget _buildInputArea() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pendingImage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  height: 80,
                  child: Stack(children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(_pendingImage!,
                            fit: BoxFit.cover)),
                    Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                            icon: const Icon(Icons.close,
                                size: 18, color: Colors.white),
                            style: IconButton.styleFrom(
                                backgroundColor:
                                    Colors.black.withValues(alpha: 0.5),
                                minimumSize: const Size(20, 20)),
                            onPressed: () => setState(() =>
                                _pendingImage = null))),
                  ]),
                ),
              Row(children: [
                IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        size: 28),
                    onPressed: _showAttachmentOptions,
                    tooltip: l10n.get('attachmentMenu')),
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.5))),
                    child: CallbackShortcuts(
                      bindings: {
                        SingleActivator(
                                LogicalKeyboardKey.enter,
                                control: true): _sendMessageOrImage,
                      },
                      child: Focus(
                        child: TextField(
                          focusNode: _inputFocus,
                          controller: _controller,
                          decoration: InputDecoration(
                              hintText: l10n.get('typeMessage'),
                              border: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.zero),
                          maxLines: 4,
                          minLines: 1,
                          textInputAction: TextInputAction.newline,
                          onSubmitted: (_) =>
                              _sendMessageOrImage(),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Send (Ctrl+Enter)',
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_sendTrigger),
                    tween: Tween(begin: 0.85, end: 1.0),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    builder: (ctx, value, child) =>
                        Transform.scale(scale: value, child: child),
                    child: Material(
                      color: scheme.primary,
                      shape: const CircleBorder(),
                      elevation: 2,
                      shadowColor: scheme.primary.withValues(alpha: 0.3),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sendMessageOrImage,
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ]),
      ),
    );
  }

  IconData _resolveIcon(String name) {
    switch (name) {
      case 'touch_app':
        return Icons.touch_app;
      case 'favorite':
        return Icons.favorite;
      case 'star':
        return Icons.star;
      case 'waving_hand':
        return Icons.waving_hand;
      case 'thumb_up':
        return Icons.thumb_up;
      case 'send':
        return Icons.send;
      case 'mic':
        return Icons.mic;
      default:
        return Icons.extension;
    }
  }
}

/// Animated chat bubble with slide/fade entrance
class _AnimatedBubble extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback onDelete;
  final VoidCallback? onRegenerate;

  const _AnimatedBubble(
      {super.key,
      required this.message,
      required this.onDelete,
      this.onRegenerate});

  @override
  State<_AnimatedBubble> createState() => _AnimatedBubbleState();
}

class _AnimatedBubbleState extends State<_AnimatedBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
            begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.isUser;
    final scheme = Theme.of(context).colorScheme;
    final agentState = ProviderScope.containerOf(context, listen: false)
        .read(agentProvider);

    final bubbleColor =
        isUser ? scheme.primaryContainer : scheme.surface;
    final onBubbleColor =
        isUser ? scheme.onPrimaryContainer : scheme.onSurface;
    final borderColor = isUser
        ? Colors.transparent
        : scheme.outlineVariant.withValues(alpha: 0.6);
    final maxBubbleWidth = ResponsiveLayout.bubbleMaxWidth(context);

    return FadeTransition(
        opacity: _fade,
        child: SlideTransition(
            position: _slide,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: 4, horizontal: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: isUser
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: [
                  if (!isUser)
                    _agentAvatarSmall(agentState.currentAgent),
                  if (!isUser) const SizedBox(width: 8),
                  Flexible(
                    child: MouseRegion(
                      onEnter: (_) =>
                          setState(() => _isHovered = true),
                      onExit: (_) =>
                          setState(() => _isHovered = false),
                      child: GestureDetector(
                        onTap: () => _showActionBar(context),
                        onSecondaryTapDown:
                            ResponsiveLayout.isDesktop(context)
                                ? (d) =>
                                    _showContextMenu(context, d.globalPosition)
                                : null,
                        child: AnimatedContainer(
                          duration: AppTheme.durFast,
                          constraints:
                              BoxConstraints(maxWidth: maxBubbleWidth),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                              color: _isHovered && !isUser
                                  ? scheme.surfaceContainerHighest
                                  : bubbleColor,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(AppTheme.radiusLg),
                                topRight: const Radius.circular(AppTheme.radiusLg),
                                bottomLeft: Radius.circular(
                                    isUser ? AppTheme.radiusLg : 4),
                                bottomRight: Radius.circular(
                                    isUser ? 4 : AppTheme.radiusLg),
                              ),
                              border: Border.all(color: borderColor),
                              boxShadow: AppTheme.shadowSm),
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                if (message.imagePath != null &&
                                    File(message.imagePath!)
                                        .existsSync())
                                  ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(AppTheme.radiusSm),
                                      child: Image.file(
                                          File(message.imagePath!),
                                          fit: BoxFit.cover,
                                          width: double.infinity)),
                                if (message.content.isNotEmpty) ...[
                                  if (message.imagePath != null)
                                    const SizedBox(height: 4),
                                  Text(message.content,
                                      style: TextStyle(
                                          fontSize: 15,
                                          color: onBubbleColor,
                                          height: 1.4)),
                                ],
                                const SizedBox(height: 4),
                                Align(
                                  alignment: isUser
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Text(
                                      DateFormat('HH:mm').format(
                                          message.timestamp),
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: onBubbleColor
                                              .withValues(alpha: 0.6))),
                                ),
                              ]),
                        ),
                      ),
                    ),
                  ),
                  if (isUser) const SizedBox(width: 8),
                  if (isUser)
                    Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle),
                        child: Icon(Icons.person,
                            color: scheme.onPrimary, size: 20)),
                ],
              ),
            )));
  }

  Widget _agentAvatarSmall(dynamic agent) {
    if (agent?.avatarPath != null &&
        agent!.avatarPath!.isNotEmpty &&
        File(agent.avatarPath!).existsSync()) {
      return ClipOval(
          child: Image.file(File(agent.avatarPath!),
              width: 36, height: 36, fit: BoxFit.cover));
    }
    return CircleAvatar(
        radius: 18,
        backgroundColor:
            agent != null ? Color(agent.avatarColor) : Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(
            agent?.name.isNotEmpty == true
                ? agent!.name[0].toUpperCase()
                : 'AI',
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)));
  }

  void _showActionBar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isUser = widget.message.isUser;
    // Unfocus before showing overlay to prevent keyboard popup on dismiss
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                  leading: const Icon(Icons.copy),
                  title: Text(l10n.get('copyText')),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(
                        text: widget.message.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(l10n.get('copied')),
                            duration:
                                const Duration(seconds: 1)));
                  }),
              if (!isUser) ...[
                ListTile(
                    leading: const Icon(Icons.refresh),
                    title: Text(l10n.get('regenerate')),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onRegenerate?.call();
                    }),
                if (widget.message.toolLogs != null)
                  ListTile(
                      leading: const Icon(Icons.code),
                      title: Text(l10n.get('viewToolCalls')),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showToolLogs(context);
                      }),
              ],
              ListTile(
                  leading: Icon(Icons.delete,
                      color: Theme.of(context).colorScheme.error),
                  title: Text(l10n.get('deleteMessage'),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onDelete();
                  }),
            ]),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final l10n = AppLocalizations.of(context);
    final isUser = widget.message.isUser;
    FocusManager.instance.primaryFocus?.unfocus();
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
            child: ListTile(
                dense: true,
                leading: const Icon(Icons.copy, size: 18),
                title: Text(l10n.get('copyText'))),
            onTap: () {
              Clipboard.setData(
                  ClipboardData(text: widget.message.content));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(l10n.get('copied')),
                  duration: const Duration(seconds: 1)));
            }),
        if (!isUser) ...[
          if (widget.onRegenerate != null)
            PopupMenuItem(
                child: ListTile(
                    dense: true,
                    leading:
                        const Icon(Icons.refresh, size: 18),
                    title: Text(l10n.get('regenerate'))),
                onTap: () => widget.onRegenerate?.call()),
          if (widget.message.toolLogs != null)
            PopupMenuItem(
                child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.code, size: 18),
                    title: Text(l10n.get('viewToolCalls'))),
                onTap: () => _showToolLogs(context)),
        ],
        PopupMenuItem(
            child: ListTile(
                dense: true,
                leading: Icon(Icons.delete,
                    size: 18, color: Theme.of(context).colorScheme.error),
                title: Text(l10n.get('deleteMessage'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error))),
            onTap: () => widget.onDelete()),
      ],
    );
  }

  void _showToolLogs(BuildContext context) {
    if (widget.message.toolLogs == null) return;
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.get('toolCalls'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.message.promptTokens != null || widget.message.completionTokens != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l10n.get('tokenUsage'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 4),
                    if (widget.message.promptTokens != null)
                      Text('${l10n.get("promptTokens")}: ${widget.message.promptTokens}', style: const TextStyle(fontSize: 12)),
                    if (widget.message.completionTokens != null)
                      Text('${l10n.get("completionTokens")}: ${widget.message.completionTokens}', style: const TextStyle(fontSize: 12)),
                    if (widget.message.promptTokens != null && widget.message.completionTokens != null)
                      Text('${l10n.get("totalTokens")}: ${widget.message.promptTokens! + widget.message.completionTokens!}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              Flexible(
                child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.message.toolLogs!.length,
            itemBuilder: (_, i) {
              final log = widget.message.toolLogs![i];
              final formattedArgs =
                  const JsonEncoder.withIndent('  ')
                      .convert(log.arguments);
              return Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${l10n.get('tool')}: ${log.toolName}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('Args:',
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(
                              top: 2, bottom: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius:
                                  BorderRadius.circular(6)),
                          child: Text(formattedArgs,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace')),
                        ),
                        Text('Result: ${log.result}',
                            style:
                                const TextStyle(fontSize: 13)),
                      ]),
                ),
              );
            },
          ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.get('close')))
        ],
      ),
    );
  }
}

/// Bouncing dots loading indicator
class BouncingDotsIndicator extends StatefulWidget {
  const BouncingDotsIndicator({super.key});

  @override
  State<BouncingDotsIndicator> createState() =>
      _BouncingDotsIndicatorState();
}

class _BouncingDotsIndicatorState extends State<BouncingDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _dot(0),
            const SizedBox(width: 6),
            _dot(1),
            const SizedBox(width: 6),
            _dot(2),
          ]),
    );
  }

  Widget _dot(int index) {
    final delay = index * 0.2;
    final anim = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.4), weight: 0.5),
      TweenSequenceItem(
          tween: Tween(begin: 1.4, end: 1.0), weight: 0.5),
    ]).animate(CurvedAnimation(
        parent: _ctrl,
        curve: Interval(delay, delay + 0.4,
            curve: Curves.easeInOut)));

    return AnimatedBuilder(
      animation: anim,
      builder: (_, child) => Transform.scale(
          scale: anim.value,
          child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  shape: BoxShape.circle))),
    );
  }
}

/// Debug log screen
class DebugLogScreen extends ConsumerStatefulWidget {
  const DebugLogScreen({super.key});
  @override
  ConsumerState<DebugLogScreen> createState() =>
      _DebugLogScreenState();
}

class _DebugLogScreenState extends ConsumerState<DebugLogScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final logs = await DatabaseService.getDebugLogs();
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  Future<void> _exportLogs() async {
    final l10n = AppLocalizations.of(context);
    final sb = StringBuffer();
    sb.writeln('=== AI Chat Debug Logs ===');
    sb.writeln(
        'Export time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    sb.writeln('');

    for (final log in _logs) {
      final ts = DateTime.fromMillisecondsSinceEpoch(
          log['timestamp'] as int);
      sb.writeln(
          '--- ${DateFormat('yyyy-MM-dd HH:mm:ss').format(ts)} ---');
      sb.writeln('Request: ${log['request_summary']}');
      sb.writeln('Response: ${log['response_summary']}');
      if (log['error'] != null) {
        sb.writeln('Error: ${log['error']}');
      }
      sb.writeln('Duration: ${log['duration_ms'] ?? 0}ms');
      sb.writeln('');
    }

    try {
      final dir = await pp.getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/debug_logs_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.txt');
      await file.writeAsString(sb.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${l10n.get('logsExported')} ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('${l10n.get('exportFailed')}: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('debugLogTitle')),
        actions: [
          IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: l10n.get('clearLogs'),
              onPressed: () async {
                await DatabaseService.clearDebugLogs();
                _loadLogs();
              }),
          IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: l10n.get('exportLogs'),
              onPressed: _exportLogs),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? Center(child: Text(l10n.get('noLogs')))
              : ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (_, i) {
                    final log = _logs[i];
                    final ts =
                        DateTime.fromMillisecondsSinceEpoch(
                            log['timestamp'] as int);
                    final hasError = log['error'] != null;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      child: ExpansionTile(
                        leading: Icon(
                            hasError
                                ? Icons.error
                                : Icons.check_circle,
                            color: hasError
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.tertiary,
                            size: 20),
                        title: Text(
                            DateFormat('MM-dd HH:mm:ss')
                                .format(ts),
                            style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace')),
                        subtitle: Text(
                            '${log['request_summary']} | ${log['response_summary']} | ${log['duration_ms'] ?? 0}ms',
                            style: const TextStyle(
                                fontSize: 10),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        children: [
                          Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        'Request: ${log['request_summary']}',
                                        style: const TextStyle(
                                            fontSize: 12)),
                                    Text(
                                        'Response: ${log['response_summary']}',
                                        style: const TextStyle(
                                            fontSize: 12)),
                                    Text(
                                        'Duration: ${log['duration_ms'] ?? 0}ms',
                                        style: const TextStyle(
                                            fontSize: 12)),
                                    if (log['error'] != null)
                                      Text(
                                          'Error: ${log['error']}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context).colorScheme.error)),
                                  ])),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
