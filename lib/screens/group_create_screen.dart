import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/agent_provider.dart';
import '../providers/group_provider.dart';
import '../models/group_member.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class GroupCreateScreen extends ConsumerStatefulWidget {
  final String? groupId;

  const GroupCreateScreen({super.key, this.groupId});

  @override
  ConsumerState<GroupCreateScreen> createState() =>
      _GroupCreateScreenState();
}

class _GroupCreateScreenState extends ConsumerState<GroupCreateScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _personaCtrl;
  int _avatarColor = 0xFFE8F5E9;
  String _speechMode = 'free';
  bool _simulatorMode = false;
  final Set<String> _selectedAgentIds = {};
  String? _moderatorAgentId;

  bool get isEditing => widget.groupId != null;

  static const _colors = [
    0xFFE8F5E9,
    0xFFFFF3E0,
    0xFFFCE4EC,
    0xFFE3F2FD,
    0xFFF3E5F5,
    0xFFE0F2F1,
    0xFFFFF8E1,
    0xFFFBE9E7,
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _personaCtrl = TextEditingController();

    if (isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final state = ref.read(groupProvider);
        final group = state.groups
            .where((g) => g.id == widget.groupId)
            .firstOrNull;
        if (group != null) {
          _nameCtrl.text = group.name;
          _descCtrl.text = group.description;
          _personaCtrl.text = group.groupPersona ?? '';
          _avatarColor = group.avatarColor;
          _speechMode = group.speechMode;
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _personaCtrl.dispose();
    super.dispose();
  }

  void _toggleAgent(String agentId) {
    setState(() {
      if (_selectedAgentIds.contains(agentId)) {
        _selectedAgentIds.remove(agentId);
        if (_moderatorAgentId == agentId) _moderatorAgentId = null;
        debugPrint('[GroupCreate] deselected agent $agentId, remaining: $_selectedAgentIds');
      } else {
        _selectedAgentIds.add(agentId);
        debugPrint('[GroupCreate] selected agent $agentId, current: $_selectedAgentIds');
      }
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _nameCtrl.text.trim();
    debugPrint('[GroupCreate] _save called. name="$name" selectedIds=$_selectedAgentIds moderator=$_moderatorAgentId');
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('nameRequired'))));
      return;
    }
    if (!_simulatorMode && _selectedAgentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.get('selectMembersRequired'))));
      return;
    }

    final notifier = ref.read(groupProvider.notifier);

    if (isEditing) {
      final state = ref.read(groupProvider);
      final group = state.groups
          .where((g) => g.id == widget.groupId)
          .firstOrNull;
      if (group != null) {
        await notifier.updateGroup(group.copyWith(
          name: name,
          description: _descCtrl.text.trim(),
          avatarColor: _avatarColor,
          groupPersona: _personaCtrl.text.trim().isNotEmpty
              ? _personaCtrl.text.trim()
              : null,
          speechMode: _speechMode,
        ));
      }
      if (mounted) Navigator.pop(context);
      return;
    }

    final members = _simulatorMode
        ? <GroupMember>[]
        : _selectedAgentIds.map((agentId) {
            return GroupMember(
              groupId: '',
              agentId: agentId,
              role: agentId == _moderatorAgentId ? 'moderator' : 'member',
            );
          }).toList();

    try {
      await notifier.createGroup(
        name: name,
        description: _descCtrl.text.trim(),
        avatarColor: _avatarColor,
        groupPersona: _personaCtrl.text.trim().isNotEmpty
            ? _personaCtrl.text.trim()
            : null,
        speechMode: _speechMode,
        members: members,
        isSimulatorMode: _simulatorMode,
        worldSetting: _personaCtrl.text.trim().isNotEmpty ? _personaCtrl.text.trim() : null,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.get('groupChat')} creation failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final agentState = ref.watch(agentProvider);
    final agents = agentState.agents.where((a) => !a.isSimCharacter).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing
            ? l10n.get('editGroup')
            : l10n.get('createGroup')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                    labelText: l10n.get('groupName')),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descCtrl,
                decoration: InputDecoration(
                    labelText: l10n.get('groupDescription')),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Text(l10n.get('groupAvatarColor'),
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(
                  spacing: 6,
                  children: _colors
                      .map((c) => GestureDetector(
                            onTap: () =>
                                setState(() => _avatarColor = c),
                            child: AnimatedContainer(
                                duration: AppTheme.durFast,
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                    color: Color(c),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: _avatarColor == c
                                            ? Theme.of(context).colorScheme.primary
                                            : Colors.transparent,
                                        width: _avatarColor == c ? 3 : 0),
                                    boxShadow: _avatarColor == c ? AppTheme.shadowSm : null)),
                          ))
                      .toList()),
              const SizedBox(height: 16),
              Text(l10n.get('groupPersona'),
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _personaCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                    hintText: l10n.get('groupPersonaHint')),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (!isEditing) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.get('simulatorMode')),
                  subtitle: Text(l10n.get('simulatorModeDesc'), style: const TextStyle(fontSize: 12)),
                  value: _simulatorMode,
                  onChanged: (v) => setState(() => _simulatorMode = v),
                ),
                const SizedBox(height: 16),
              ],
              if (!_simulatorMode) ...[
                Text(l10n.get('speechMode'),
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'free',
                        label: Text(l10n.get('freeMode'),
                            style: const TextStyle(fontSize: 12))),
                    ButtonSegment(
                        value: 'moderator',
                        label: Text(l10n.get('moderatorMode'),
                            style: const TextStyle(fontSize: 12))),
                  ],
                  selected: {_speechMode},
                  onSelectionChanged: (v) =>
                      setState(() => _speechMode = v.first),
                ),
                const SizedBox(height: 16),
                Text(l10n.get('selectMembers'),
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
              ],
              if (!_simulatorMode) ...[
                if (agents.isEmpty)
                  Text(l10n.get('noAgentsToSelect'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
                else
                  ...agents.map((a) {
                    final selected = _selectedAgentIds.contains(a.id);
                    final isMod =
                        _moderatorAgentId == a.id;
                    final scheme = Theme.of(context).colorScheme;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                            color: selected
                                ? scheme.primary
                                : Colors.transparent,
                            width: 2),
                      ),
                      color: selected ? scheme.primaryContainer.withValues(alpha: 0.3) : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(a.avatarColor),
                          child: Text(
                              a.name.isNotEmpty
                                  ? a.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87)),
                        ),
                        title: Text(a.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w500)),
                        subtitle: isMod
                            ? Text(l10n.get('moderator'),
                                style: TextStyle(
                                    color: scheme.primary, fontSize: 12, fontWeight: FontWeight.w600))
                            : null,
                        trailing: _speechMode == 'moderator' &&
                                selected
                            ? IconButton(
                                icon: Icon(Icons.verified,
                                    color: isMod
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant),
                                tooltip: l10n.get('setAsModerator'),
                                onPressed: () => setState(
                                    () => _moderatorAgentId = a.id),
                              )
                            : null,
                        onTap: () => _toggleAgent(a.id),
                      ),
                    );
                  }),
              ],
              const SizedBox(height: 24),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: _save,
                      child: Text(isEditing
                          ? l10n.get('saveChanges')
                          : l10n.get('createGroup')))),
              const SizedBox(height: 32),
            ]),
      ),
    );
  }
}
