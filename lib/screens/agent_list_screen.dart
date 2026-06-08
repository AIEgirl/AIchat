import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart' as pp;
import '../providers/agent_provider.dart';
import '../services/agent_export_service.dart';
import '../l10n/app_localizations.dart';
import 'agent_create_screen.dart';

class AgentListScreen extends ConsumerWidget {
  const AgentListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentProvider);
    final agents = state.agents.where((a) => !a.isSimCharacter).toList();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('agentManagement')),
        actions: [
          IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: l10n.get('importAgent'),
              onPressed: () => _importAgent(context, ref)),
        ],
      ),
      body: agents.isEmpty
          ? Center(child: Text(l10n.get('noAgents')))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: agents.length,
              itemBuilder: (_, i) {
                final agent = agents[i];
                final isActive = agent.id == state.currentAgent?.id;
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: isActive ? Colors.green : Colors.transparent,
                        width: 2),
                  ),
                  color: isActive ? Colors.green.shade50 : null,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(agent.avatarColor),
                      child: Text(
                          agent.name.isNotEmpty ? agent.name[0] : '?',
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    title: Row(children: [
                      Expanded(
                          child: Text(agent.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500))),
                      if (isActive)
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(l10n.get('current'),
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.green))),
                    ]),
                    subtitle: Text(
                        agent.description.isNotEmpty
                            ? agent.description
                            : agent.gender,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    onTap: () {
                      if (!isActive) {
                        ref
                            .read(agentProvider.notifier)
                            .setActiveAgent(agent.id);
                      }
                      Navigator.pop(context);
                    },
                    onLongPress: () => _showAgentMenu(context, ref, agent, isActive),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AgentCreateScreen())),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAgentMenu(BuildContext context, WidgetRef ref, dynamic agent, bool isActive) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!isActive)
            ListTile(
              leading: const Icon(Icons.check_circle_outline, color: Colors.green),
              title: Text(l10n.get('switchToThisAgent')),
              onTap: () {
                ref.read(agentProvider.notifier).setActiveAgent(agent.id);
                Navigator.pop(ctx); Navigator.pop(context);
              },
            ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: Text(l10n.get('edit')),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => AgentCreateScreen(agent: agent)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_upload),
            title: Text(l10n.get('export')),
            onTap: () {
              Navigator.pop(ctx);
              _exportAgent(context, ref, agent);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: Text(l10n.get('delete'), style: const TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(ctx);
              _confirmDelete(context, ref, agent);
            },
          ),
        ]),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, dynamic agent) {
    final l10n = AppLocalizations.of(context);
    final isActive = ref.read(agentProvider).currentAgent?.id == agent.id;
    final activeNote = isActive ? l10n.get('activeAgentNote') : '';
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(l10n.get('confirmDeleteAgentTitle')),
              content: Text(l10n.getP('confirmDeleteAgentContent', {
                'name': agent.name,
                'activeNote': activeNote,
              })),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(l10n.get('cancel'))),
                FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.red),
                    onPressed: () {
                      ref.read(agentProvider.notifier).deleteAgent(agent.id);
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                    },
                    child: Text(l10n.get('delete'))),
              ],
            ));
  }

  void _exportAgent(
      BuildContext context, WidgetRef ref, dynamic agent) async {
    final l10n = AppLocalizations.of(context);
    try {
      final data = await AgentExportService.exportAgent(agent);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await pp.getApplicationDocumentsDirectory();
      final fileName = '${agent.name}_export.agent.json';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonStr);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                l10n.getP('agentExported', {'path': '${dir.path}/$fileName'}))));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${l10n.get('agentExportFailed')}: $e')));
      }
    }
  }

  void _importAgent(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.any, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      if (data['version'] == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.get('invalidAgentFile'))));
        }
        return;
      }
      final imported = await AgentExportService.importAgent(data);

      if (!context.mounted) return;
      final confirmed =
          await showDialog<bool>(context: context, builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.get('confirmImportTitle')),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${l10n.get('nameLabel')}: ${imported.name}'),
                if (imported.gender.isNotEmpty)
                  Text('${l10n.get('gender')}: ${imported.gender}'),
                if (imported.description.isNotEmpty)
                  Text(
                      '${l10n.get('description')}: ${imported.description}'),
              ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.get('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.get('importAgent'))),
          ],
        );
      });

      if (confirmed == true) {
        await ref.read(agentProvider.notifier).createAgent(
              name: imported.name,
              gender: imported.gender,
              description: imported.description,
              persona: imported.persona,
              avatarColor: imported.avatarColor,
            );
        final agents = ref.read(agentProvider).agents;
        final newAgent = agents.last;
        if (imported.avatarPath != null || imported.chatBackground != null) {
          ref.read(agentProvider.notifier).updateAgent(newAgent.copyWith(
                avatarPath: imported.avatarPath,
                chatBackground: imported.chatBackground,
              ));
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  l10n.getP('agentImported', {'name': imported.name}))));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${l10n.get('agentImportFailed')}: $e')));
      }
    }
  }
}
