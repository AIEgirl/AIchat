import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/memory_provider.dart';
import '../providers/chat_provider.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆管理'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '短期记忆'),
            Tab(text: '长期记忆'),
            Tab(text: '基础记忆'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ShortTermTab(),
          _LongTermTab(),
          _BaseMemoryTab(),
        ],
      ),
    );
  }
}

// ─── 短期记忆标签页 ──────────────────

class _ShortTermTab extends ConsumerWidget {
  const _ShortTermTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoryService = ref.read(memoryServiceProvider);
    final messages = memoryService.shortTermMessages;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('当前轮数: ${messages.length}',
                  style: const TextStyle(fontSize: 16)),
              TextButton.icon(
                onPressed: () {
                  ref.read(chatProvider.notifier).clearChat();
                },
                icon: const Icon(Icons.delete),
                label: const Text('清空'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: messages.length,
            itemBuilder: (_, i) {
              final msg = messages[i];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  child: Text(
                    msg.role == 'user' ? 'U' : 'A',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                title: Text(
                  '${msg.id} [${msg.role}]',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(msg.content, maxLines: 3, overflow: TextOverflow.ellipsis),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── 长期记忆标签页 ──────────────────

class _LongTermTab extends ConsumerWidget {
  const _LongTermTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(longTermProvider);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () => _showCreateDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('手动新增'),
            ),
            TextButton.icon(
              onPressed: () => _confirmClear(context, ref),
              icon: const Icon(Icons.delete_forever),
              label: const Text('清空全部'),
            ),
          ],
        ),
        Expanded(
          child: state.memories.isEmpty
              ? const Center(child: Text('暂无长期记忆'))
              : ListView.builder(
                  itemCount: state.memories.length,
                  itemBuilder: (_, i) {
                    final m = state.memories[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        title: Text(
                          '${m.id} [${m.field}]',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(m.content),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _showEditDialog(context, ref, m),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                              onPressed: () {
                                ref.read(longTermProvider.notifier).deleteMemory(m.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('共 ${state.memories.length} 条长期记忆',
              style: const TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final contentController = TextEditingController();
    String selectedField = 'time';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新增长期记忆'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedField,
                decoration: const InputDecoration(labelText: '字段'),
                items: LongTermMemory.validFields.map((f) {
                  return DropdownMenuItem(value: f, child: Text(f));
                }).toList(),
                onChanged: (v) => setDialogState(() => selectedField = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                decoration: const InputDecoration(labelText: '内容'),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (contentController.text.trim().isNotEmpty) {
                  await ref.read(memoryServiceProvider).createLongTermMemory(
                    field: selectedField,
                    content: contentController.text.trim(),
                  );
                  ref.read(longTermProvider.notifier).loadMemories();
                  Navigator.pop(ctx);
                }
              },
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, LongTermMemory m) {
    final contentController = TextEditingController(text: m.content);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑 ${m.id} [${m.field}]'),
        content: TextField(
          controller: contentController,
          decoration: const InputDecoration(labelText: '内容'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final updated = m.copyWith(content: contentController.text.trim());
              ref.read(longTermProvider.notifier).updateMemory(updated);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有长期记忆吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref.read(longTermProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }
}

// ─── 基础记忆标签页 ──────────────────

class _BaseMemoryTab extends ConsumerWidget {
  const _BaseMemoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(baseProvider);
    final settings = state.memories.where((m) => m.isSetting).toList();
    final events = state.memories.where((m) => m.isEvent).toList();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () => _showCreateDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('新增设定'),
            ),
            TextButton.icon(
              onPressed: () => _confirmClearEvents(context, ref),
              icon: const Icon(Icons.delete_forever),
              label: const Text('清空事件'),
            ),
            TextButton.icon(
              onPressed: () => _confirmClearAll(context, ref),
              icon: const Icon(Icons.delete_forever),
              label: const Text('重置全部'),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            children: [
              if (settings.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('设定条目（不可被 AI 遗忘）:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                ...settings.map((m) => Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: Colors.blue.shade50,
                      child: ListTile(
                        title: Text(m.id,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                        subtitle: Text(m.content),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _showEditDialog(context, ref, m),
                        ),
                      ),
                    )),
              ],
              if (events.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('事件条目（AI 可遗忘）:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                ...events.map((m) => Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        title: Text(m.id,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                        subtitle: Text(m.content),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                          onPressed: () {
                            ref.read(baseProvider.notifier).deleteMemory(m.id);
                          },
                        ),
                      ),
                    )),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
              '设定 ${settings.length} 条 | 事件 ${events.length} 条',
              style: const TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增基础设定'),
        content: TextField(
          controller: contentController,
          decoration: const InputDecoration(labelText: '设定内容'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (contentController.text.trim().isNotEmpty) {
                await ref.read(baseProvider.notifier).createSetting(
                      contentController.text.trim(),
                    );
                Navigator.pop(ctx);
              }
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, BaseMemory m) {
    final contentController = TextEditingController(text: m.content);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑 ${m.id}'),
        content: TextField(
          controller: contentController,
          decoration: const InputDecoration(labelText: '内容'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final updated = BaseMemory(
                id: m.id,
                type: m.type,
                content: contentController.text.trim(),
                createdAt: m.createdAt,
              );
              ref.read(baseProvider.notifier).updateMemory(updated);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _confirmClearEvents(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空事件'),
        content: const Text('确定要清空所有基础事件条目吗？设定条目不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref.read(baseProvider.notifier).clearEvents();
              Navigator.pop(ctx);
            },
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认重置'),
        content: const Text('确定要清空所有基础记忆（包括设定）吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref.read(baseProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
  }
}
