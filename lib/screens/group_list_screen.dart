import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/group_provider.dart';
import '../models/group_chat.dart';
import '../l10n/app_localizations.dart';
import 'group_create_screen.dart';
import 'group_chat_screen.dart';
import 'group_manage_screen.dart';

class GroupListScreen extends ConsumerStatefulWidget {
  const GroupListScreen({super.key});

  @override
  ConsumerState<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends ConsumerState<GroupListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(groupProvider.notifier);
    });
  }

  void _refreshGroups() {
    ref.read(groupProvider.notifier).loadGroups();
  }

  void _confirmDelete(BuildContext context, GroupChat group) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
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
              await ref.read(groupProvider.notifier).deleteGroup(group.id);
              _refreshGroups();
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
    final state = ref.watch(groupProvider);
    final groups = state.groups;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('groupChats'))),
      body: groups.isEmpty
          ? Center(child: Text(l10n.get('noGroupChats')))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: groups.length,
              itemBuilder: (_, i) {
                final group = groups[i];
                return _buildGroupCard(context, group, l10n);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupCreateScreen()));
          _refreshGroups();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildGroupCard(BuildContext context, GroupChat group, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _enterGroup(context, group),
        onLongPress: () => _showGroupMenu(context, group, l10n, scheme),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Color(group.avatarColor),
              child: Text(group.name.isNotEmpty ? group.name[0].toUpperCase() : '#',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(group.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                if (group.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(group.description, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    group.speechMode == 'moderator' ? l10n.get('moderatorMode') : l10n.get('freeMode'),
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  ),
                ),
              ]),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
          ]),
        ),
      ),
    );
  }

  void _enterGroup(BuildContext context, GroupChat group) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id)));
  }

  void _showGroupMenu(BuildContext context, GroupChat group, AppLocalizations l10n, ColorScheme scheme) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: Text(l10n.get('editGroup')),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => GroupManageScreen(groupId: group.id))).then((_) => _refreshGroups());
            },
          ),
          ListTile(
            leading: Icon(Icons.chat_bubble_outline, color: scheme.primary),
            title: Text(l10n.get('enterGroupChat')),
            onTap: () {
              Navigator.pop(ctx);
              _enterGroup(context, group);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete, color: scheme.error),
            title: Text(l10n.get('delete'), style: TextStyle(color: scheme.error)),
            onTap: () {
              Navigator.pop(ctx);
              _confirmDelete(context, group);
            },
          ),
        ]),
      ),
    );
  }
}
