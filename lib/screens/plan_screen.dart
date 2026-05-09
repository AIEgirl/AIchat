import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/plan_provider.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(planProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('计划消息')),
      body: state.plannedMessages.isEmpty
          ? const Center(child: Text('暂无计划消息'))
          : ListView.builder(
              itemCount: state.plannedMessages.length,
              itemBuilder: (_, i) {
                final plan = state.plannedMessages[i];
                final isPast = plan.scheduledTime.isBefore(DateTime.now());
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: Icon(
                      plan.delivered ? Icons.check_circle : Icons.schedule,
                      color: plan.delivered
                          ? Colors.green
                          : isPast
                              ? Colors.orange
                              : Colors.blue,
                    ),
                    title: Text(
                      DateFormat('yyyy-MM-dd HH:mm').format(plan.scheduledTime),
                      style: TextStyle(
                        fontSize: 14,
                        color: isPast ? Colors.grey : null,
                        decoration: plan.delivered ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Text(plan.message, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!plan.delivered)
                          IconButton(
                            icon: const Icon(Icons.play_arrow, color: Colors.green),
                            tooltip: '立即触发',
                            onPressed: () {
                              ref.read(planProvider.notifier).triggerNow(plan.id!);
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          tooltip: '取消计划',
                          onPressed: () {
                            ref.read(planProvider.notifier).cancelPlan(plan.id!);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
