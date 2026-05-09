import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/planned_message.dart';
import '../services/plan_service.dart';
import 'chat_provider.dart' show planServiceProvider;

class PlanState {
  final List<PlannedMessage> plannedMessages;
  final bool isLoading;

  const PlanState({this.plannedMessages = const [], this.isLoading = false});

  PlanState copyWith({List<PlannedMessage>? plannedMessages, bool? isLoading}) {
    return PlanState(
      plannedMessages: plannedMessages ?? this.plannedMessages,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class PlanNotifier extends StateNotifier<PlanState> {
  final PlanService _planService;

  PlanNotifier(this._planService) : super(const PlanState()) {
    loadPlans();
  }

  Future<void> loadPlans() async {
    state = state.copyWith(isLoading: true);
    final plans = await _planService.getPlannedMessages();
    state = state.copyWith(plannedMessages: plans, isLoading: false);
  }

  Future<void> cancelPlan(int id) async {
    await _planService.cancelPlan(id);
    await loadPlans();
  }

  Future<void> triggerNow(int id) async {
    await _planService.triggerNow(id);
    await loadPlans();
  }
}

final planProvider =
    StateNotifierProvider<PlanNotifier, PlanState>((ref) {
  return PlanNotifier(ref.read(planServiceProvider));
});
