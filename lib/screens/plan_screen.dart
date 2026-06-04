import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/plan_provider.dart';
import '../l10n/app_localizations.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(planProvider);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('plannedMessagesTitle'))),
      body: state.plannedMessages.isEmpty
          ? Center(child: Text(l10n.get('noPlannedMessages')))
          : ListView.builder(
              itemCount: state.plannedMessages.length,
              itemBuilder: (_, i) {
                final plan = state.plannedMessages[i];
                final isPast = plan.scheduledTime.isBefore(DateTime.now());
                return Card(
                  child: ListTile(
                    leading: Icon(
                      plan.delivered ? Icons.check_circle : Icons.schedule,
                      color: plan.delivered
                          ? scheme.tertiary
                          : isPast
                              ? scheme.error
                              : scheme.primary,
                    ),
                    title: Text(
                      DateFormat('yyyy-MM-dd HH:mm')
                          .format(plan.scheduledTime),
                      style: TextStyle(
                        fontSize: 14,
                        color: isPast ? scheme.onSurfaceVariant : null,
                        decoration: plan.delivered
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    subtitle: Text(plan.message,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!plan.delivered)
                          IconButton(
                            icon: Icon(Icons.play_arrow, color: scheme.tertiary),
                            tooltip: l10n.get('triggerNow'),
                            onPressed: () {
                              ref
                                  .read(planProvider.notifier)
                                  .triggerNow(plan.id!);
                            },
                          ),
                        IconButton(
                          icon: Icon(Icons.cancel, color: scheme.error),
                          tooltip: l10n.get('cancelPlan'),
                          onPressed: () {
                            ref
                                .read(planProvider.notifier)
                                .cancelPlan(plan.id!);
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
