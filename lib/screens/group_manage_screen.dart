import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/group_provider.dart';
import '../providers/agent_provider.dart';
import '../models/group_member.dart';
import '../l10n/app_localizations.dart';

class GroupManageScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupManageScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupManageScreen> createState() =>
      _GroupManageScreenState();
}

class _GroupManageScreenState extends ConsumerState<GroupManageScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agentProvider.notifier).refresh();
      ref.read(groupProvider.notifier).loadGroup(widget.groupId);
    });
  }

  void _refresh() {
    ref.read(agentProvider.notifier).refresh();
    ref.read(groupProvider.notifier).loadGroup(widget.groupId);
  }

  void _editGroupInfo() {
    final state = ref.read(groupProvider);
    final group = state.activeGroup;
    if (group == null) return;
    final l10n = AppLocalizations.of(context);

    final nameCtrl = TextEditingController(text: group.name);
    final descCtrl = TextEditingController(text: group.description);
    final personaCtrl = TextEditingController(text: group.groupPersona ?? '');
    String speechMode = group.speechMode;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ds) => AlertDialog(
          icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary, size: 32),
          title: Text(l10n.get('editGroup')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.get('groupName'))),
              const SizedBox(height: 12),
              TextField(controller: descCtrl, decoration: InputDecoration(labelText: l10n.get('groupDescription')), maxLines: 2),
              const SizedBox(height: 12),
              TextField(controller: personaCtrl, decoration: InputDecoration(labelText: l10n.get('groupPersona')), maxLines: 3),
              const SizedBox(height: 12),
              Text(l10n.get('speechMode'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'free', label: Text(l10n.get('freeMode'), style: const TextStyle(fontSize: 12))),
                  ButtonSegment(value: 'moderator', label: Text(l10n.get('moderatorMode'), style: const TextStyle(fontSize: 12))),
                ],
                selected: {speechMode},
                onSelectionChanged: (v) => ds(() => speechMode = v.first),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('cancel'))),
            FilledButton(onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              ref.read(groupProvider.notifier).updateGroup(group.copyWith(
                name: name,
                description: descCtrl.text.trim(),
                groupPersona: personaCtrl.text.trim().isNotEmpty ? personaCtrl.text.trim() : null,
                speechMode: speechMode,
              ));
              _refresh();
              Navigator.pop(ctx);
            }, child: Text(l10n.get('save'))),
          ],
        ),
      ),
    );
  }

  void _addMember() {
    final state = ref.read(groupProvider);
    final members = state.members;
    final agentState = ref.read(agentProvider);
    final allAgents = agentState.agents;
    final l10n = AppLocalizations.of(context);

    final existingAgentIds = members.map((m) => m.agentId).toSet();
    final available = allAgents.where((a) => !existingAgentIds.contains(a.id)).toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.get('noAgentsToSelect'))));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.person_add, color: Theme.of(context).colorScheme.primary, size: 32),
        title: Text(l10n.get('addMember')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: available.length,
            itemBuilder: (_, i) {
              final agent = available[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(agent.avatarColor),
                  child: Text(agent.name.isNotEmpty ? agent.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                ),
                title: Text(agent.name),
                subtitle: agent.description.isNotEmpty ? Text(agent.description, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                onTap: () async {
                  final gId = state.activeGroup?.id ?? widget.groupId;
                  final gm = GroupMember(groupId: gId, agentId: agent.id, role: 'member');
                  await ref.read(groupProvider.notifier).addMember(gm);
                  _refresh();
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('cancel')))],
      ),
    );
  }

  void _promoteDemote(GroupMember member) {
    final l10n = AppLocalizations.of(context);
    final newRole = member.role == 'moderator' ? 'member' : 'moderator';
    ref.read(groupProvider.notifier).updateMember(member.copyWith(role: newRole));
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l10n.get('updated')}: $newRole')));
  }

  void _deleteGroup() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final group = ref.read(groupProvider).activeGroup;
    if (group == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 32),
        title: Text(l10n.get('confirmDelete')),
        content: Text(l10n.getP('deleteGroupConfirmDetail', {'name': group.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: () async {
              await ref.read(groupProvider.notifier).deleteGroup(widget.groupId);
              Navigator.pop(ctx);
              if (mounted) Navigator.pop(context);
            },
            child: Text(l10n.get('delete')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupProvider);
    final group = state.activeGroup;
    final members = state.members;
    final l10n = AppLocalizations.of(context);

    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.get('manageGroup'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('manageGroup')),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
            tooltip: l10n.get('delete'),
            onPressed: _deleteGroup,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(group.avatarColor),
                    child: Text(group.name.isNotEmpty ? group.name[0].toUpperCase() : '#',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(group.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                        IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: _editGroupInfo),
                      ]),
                      if (group.description.isNotEmpty)
                        Text(group.description, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ]),
                  ),
                ]),
                if (group.groupPersona != null && group.groupPersona!.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(l10n.get('groupPersona'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(group.groupPersona!, style: const TextStyle(fontSize: 13)),
                ],
                const SizedBox(height: 8),
                Text('${l10n.get('speechMode')}: ${group.speechMode == 'moderator' ? l10n.get('moderatorMode') : l10n.get('freeMode')}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(l10n.get('memberList'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            TextButton.icon(
              icon: const Icon(Icons.person_add, size: 18),
              label: Text(l10n.get('addMember'), style: const TextStyle(fontSize: 13)),
              onPressed: _addMember,
            ),
          ]),
          if (members.isEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text(l10n.get('noMembers'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
          else
            ...members.map((m) {
              final agents = ref.read(agentProvider).agents;
              final agent = agents.where((a) => a.id == m.agentId).firstOrNull;
              final name = agent?.name ?? m.agentId;
              final scheme = Theme.of(context).colorScheme;
              return Card(
                margin: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: agent != null ? Color(agent.avatarColor) : scheme.surfaceContainerHighest,
                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
                  title: Row(children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    if (m.role == 'moderator')
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(4)),
                        child: Text(l10n.get('moderator'), style: TextStyle(fontSize: 10, color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
                      ),
                  ]),
                  subtitle: m.isPresent
                      ? Text(l10n.get('present'), style: TextStyle(color: scheme.tertiary, fontSize: 12, fontWeight: FontWeight.w500))
                      : Text(l10n.get('away'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(value: m.isPresent, onChanged: (v) {
                      if (m.id != null) ref.read(groupProvider.notifier).togglePresence(m.id!, v);
                    }),
                    IconButton(icon: const Icon(Icons.admin_panel_settings, size: 20), tooltip: l10n.get('setAsModerator'),
                        onPressed: () => _promoteDemote(m)),
                    IconButton(icon: Icon(Icons.remove_circle, color: scheme.error, size: 20),
                        onPressed: () {
                          if (m.id != null) {
                            ref.read(groupProvider.notifier).removeMember(m.id!);
                            _refresh();
                          }
                        }),
                  ]),
                ),
              );
            }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
