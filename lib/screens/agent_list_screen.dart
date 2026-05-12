import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/agent_provider.dart';
import 'agent_create_screen.dart';

class AgentListScreen extends ConsumerWidget {
  const AgentListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentProvider);
    final agents = state.agents;

    return Scaffold(
      appBar: AppBar(title: const Text('智能体管理')),
      body: agents.isEmpty
          ? const Center(child: Text('暂无智能体'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: agents.length,
              itemBuilder: (_, i) {
                final agent = agents[i];
                final isActive = agent.id == state.currentAgent?.id;
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: isActive ? Colors.green : Colors.transparent, width: 2),
                  ),
                  color: isActive ? Colors.green.shade50 : null,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(agent.avatarColor),
                      child: Text(agent.name.isNotEmpty ? agent.name[0] : '?', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    title: Row(children: [
                      Expanded(child: Text(agent.name, style: const TextStyle(fontWeight: FontWeight.w500))),
                      if (isActive) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)), child: const Text('当前', style: TextStyle(fontSize: 10, color: Colors.green))),
                    ]),
                    subtitle: Text(agent.description.isNotEmpty ? agent.description : agent.gender, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!isActive)
                        IconButton(icon: const Icon(Icons.check_circle_outline, color: Colors.green), tooltip: '切换到此智能体', onPressed: () {
                          ref.read(agentProvider.notifier).setActiveAgent(agent.id);
                          Navigator.pop(context);
                        }),
                      IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AgentCreateScreen(agent: agent)))),
                      IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () => _confirmDelete(context, ref, agent)),
                    ]),
                    onTap: () {
                      if (!isActive) ref.read(agentProvider.notifier).setActiveAgent(agent.id);
                      Navigator.pop(context);
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentCreateScreen())),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, dynamic agent) {
    final isActive = ref.read(agentProvider).currentAgent?.id == agent.id;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('确认删除'),
      content: Text('删除智能体"${agent.name}"将同时清除其所有记忆和聊天记录，不可恢复。${isActive ? "\n\n注意：这是当前激活的智能体。" : ""}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () { ref.read(agentProvider.notifier).deleteAgent(agent.id); Navigator.pop(ctx); Navigator.pop(context); }, child: const Text('删除')),
      ],
    ));
  }
}
