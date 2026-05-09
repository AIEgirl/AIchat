import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/long_term_memory.dart';
import '../models/base_memory.dart';
import '../services/memory_service.dart';

final memoryServiceProvider = Provider<MemoryService>((ref) {
  return MemoryService();
});

class LongTermState {
  final List<LongTermMemory> memories;
  final bool isLoading;

  const LongTermState({this.memories = const [], this.isLoading = false});

  LongTermState copyWith({List<LongTermMemory>? memories, bool? isLoading}) {
    return LongTermState(
      memories: memories ?? this.memories,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class LongTermNotifier extends StateNotifier<LongTermState> {
  final MemoryService _memoryService;

  LongTermNotifier(this._memoryService) : super(const LongTermState()) {
    loadMemories();
  }

  Future<void> loadMemories() async {
    state = state.copyWith(isLoading: true);
    final memories = await _memoryService.getLongTermMemories();
    state = state.copyWith(memories: memories, isLoading: false);
  }

  Future<void> updateMemory(LongTermMemory memory) async {
    await _memoryService.updateLongTermMemory(
      targetId: memory.id,
      content: memory.content,
      field: memory.field,
    );
    await loadMemories();
  }

  Future<void> deleteMemory(String id) async {
    await _memoryService.deleteLongTermMemory(id);
    await loadMemories();
  }

  Future<void> clearAll() async {
    await _memoryService.compressLongTerm(0);
    await loadMemories();
  }
}

class BaseState {
  final List<BaseMemory> memories;
  final bool isLoading;

  const BaseState({this.memories = const [], this.isLoading = false});

  BaseState copyWith({List<BaseMemory>? memories, bool? isLoading}) {
    return BaseState(
      memories: memories ?? this.memories,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class BaseNotifier extends StateNotifier<BaseState> {
  final MemoryService _memoryService;

  BaseNotifier(this._memoryService) : super(const BaseState()) {
    loadMemories();
  }

  Future<void> loadMemories() async {
    state = state.copyWith(isLoading: true);
    final memories = await _memoryService.getBaseMemories();
    state = state.copyWith(memories: memories, isLoading: false);
  }

  Future<void> updateMemory(BaseMemory memory) async {
    await _memoryService.updateBaseMemory(memory);
    await loadMemories();
  }

  Future<void> deleteMemory(String id) async {
    await _memoryService.deleteBaseMemory(id);
    await loadMemories();
  }

  Future<void> createSetting(String content) async {
    await _memoryService.createBaseMemory(type: 'setting', content: content);
    await loadMemories();
  }

  Future<void> clearEvents() async {
    final all = await _memoryService.getBaseMemories();
    for (final m in all.where((m) => m.isEvent)) {
      await _memoryService.deleteBaseMemory(m.id);
    }
    await loadMemories();
  }

  Future<void> clearAll() async {
    final all = await _memoryService.getBaseMemories();
    for (final m in all) {
      await _memoryService.deleteBaseMemory(m.id);
    }
    await loadMemories();
  }
}

final longTermProvider =
    StateNotifierProvider<LongTermNotifier, LongTermState>((ref) {
  return LongTermNotifier(ref.read(memoryServiceProvider));
});

final baseProvider = StateNotifierProvider<BaseNotifier, BaseState>((ref) {
  return BaseNotifier(ref.read(memoryServiceProvider));
});
