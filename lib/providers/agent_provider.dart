import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent.dart';
import '../services/database_service.dart';

class AgentNotifier extends StateNotifier<AgentState> {
  AgentNotifier() : super(const AgentState()) { _init(); }

  Future<void> _init() async {
    final agents = await DatabaseService.getAgents();
    final active = agents.where((a) => a.isActive).firstOrNull;
    if (active != null) {
      state = state.copyWith(agents: agents, currentAgent: active);
    } else if (agents.isNotEmpty) {
      await setActiveAgent(agents.first.id);
    }
  }

  List<Agent> get agents => state.agents;
  Agent? get currentAgent => state.currentAgent;

  Future<void> createAgent({required String name, String gender = '', String description = '', required String persona, int avatarColor = 0xFFE8F5E9}) async {
    final agent = Agent(name: name, gender: gender, description: description, persona: persona, avatarColor: avatarColor, isActive: true);
    await DatabaseService.insertAgent(agent);
    await DatabaseService.setActiveAgent(agent.id);
    final agents = await DatabaseService.getAgents();
    state = state.copyWith(agents: agents, currentAgent: agent);
  }

  Future<void> updateAgent(Agent agent) async {
    await DatabaseService.updateAgent(agent);
    final agents = await DatabaseService.getAgents();
    final current = agents.firstWhere((a) => a.id == agent.id, orElse: () => agents.firstWhere((a) => a.isActive));
    state = state.copyWith(agents: agents, currentAgent: current.id == state.currentAgent?.id ? agent : state.currentAgent);
  }

  Future<void> deleteAgent(String id) async {
    await DatabaseService.deleteAgent(id);
    final agents = await DatabaseService.getAgents();
    if (state.currentAgent?.id == id) {
      if (agents.isNotEmpty) {
        await DatabaseService.setActiveAgent(agents.first.id);
        state = state.copyWith(agents: agents, currentAgent: agents.first);
      } else {
        state = AgentState(agents: agents, currentAgent: null);
      }
    } else {
      state = state.copyWith(agents: agents);
    }
  }

  Future<void> setActiveAgent(String id) async {
    await DatabaseService.setActiveAgent(id);
    final agents = await DatabaseService.getAgents();
    final newActive = agents.firstWhere((a) => a.id == id);
    state = state.copyWith(agents: agents, currentAgent: newActive);
  }

  Future<void> refresh() async {
    final agents = await DatabaseService.getAgents();
    final active = agents.where((a) => a.isActive).firstOrNull;
    state = state.copyWith(agents: agents, currentAgent: active ?? state.currentAgent);
  }
}

class AgentState {
  final List<Agent> agents;
  final Agent? currentAgent;

  const AgentState({this.agents = const [], this.currentAgent});

  AgentState copyWith({List<Agent>? agents, Agent? currentAgent}) {
    return AgentState(agents: agents ?? this.agents, currentAgent: currentAgent ?? this.currentAgent);
  }
}

final agentProvider = StateNotifierProvider<AgentNotifier, AgentState>((ref) => AgentNotifier());
