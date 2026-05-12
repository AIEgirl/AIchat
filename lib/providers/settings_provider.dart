import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/provider_config.dart';
import '../services/encryption_service.dart';
import '../services/database_service.dart';

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) { _init(); }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    final providers = await DatabaseService.getProviders();
    final decrypted = providers.map((p) => p.copyWith(apiKey: EncryptionService.decrypt(p.apiKey))).toList();

    final activeProviderId = prefs.getInt('active_provider_id');
    final modelCacheJson = prefs.getString('model_cache') ?? '{}';
    final modelCache = Map<String, List<String>>.from(
      (jsonDecode(modelCacheJson) as Map).map((k, v) => MapEntry(k as String, List<String>.from(v as List))),
    );

    final totalPromptTokens = prefs.getInt('total_prompt_tokens') ?? 0;
    final totalCompletionTokens = prefs.getInt('total_completion_tokens') ?? 0;

    state = state.copyWith(
      providers: decrypted,
      activeProviderId: activeProviderId,
      modelCache: modelCache,
      maxShortTermRounds: prefs.getInt('max_short_term_rounds') ?? 20,
      isFirstRun: prefs.getBool('is_first_run') ?? true,
      proactiveEnabled: prefs.getBool('proactive_enabled') ?? false,
      silenceThresholdHours: prefs.getDouble('silence_threshold_hours') ?? 12.0,
      dndPeriods: _loadDndPeriods(prefs),
      lastInteractionTime: prefs.getString('last_interaction_time') != null ? DateTime.tryParse(prefs.getString('last_interaction_time')!) : null,
      totalPromptTokens: totalPromptTokens,
      totalCompletionTokens: totalCompletionTokens,
      themeMode: prefs.getString('theme_mode') ?? 'system',
      primaryColor: prefs.getInt('primary_color') ?? 0xFF3F51B5,
    );
  }

  List<DndPeriod> _loadDndPeriods(SharedPreferences prefs) {
    final json = prefs.getString('dnd_periods') ?? '[]';
    return (jsonDecode(json) as List).map((e) => DndPeriod.fromJson(e as Map<String, dynamic>)).toList();
  }

  static const List<PresetProvider> presetProviders = [
    PresetProvider('DeepSeek', 'https://api.deepseek.com', ['deepseek-chat', 'deepseek-reasoner']),
    PresetProvider('Kimi (Moonshot)', 'https://api.moonshot.cn/v1', ['kimi-k2.6', 'kimi-k2.6-thinking']),
    PresetProvider('通义千问 (Qwen)', 'https://dashscope.aliyuncs.com/compatible-mode/v1', ['qwen-plus', 'qwen-max']),
    PresetProvider('智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', ['glm-4-plus', 'glm-4']),
    PresetProvider('OpenAI', 'https://api.openai.com/v1', ['gpt-4o', 'gpt-4o-mini']),
  ];

  // ─── 供应商 CRUD ─────────────────

  Future<void> addProvider(String name, String baseUrl, String apiKey) async {
    final encrypted = EncryptionService.encrypt(apiKey);
    final id = await DatabaseService.insertProvider(ProviderConfig(name: name, apiBaseUrl: baseUrl, apiKey: encrypted));
    final provider = ProviderConfig(id: id, name: name, apiBaseUrl: baseUrl, apiKey: apiKey);
    final providers = [...state.providers, provider];
    final activeId = state.activeProviderId ?? id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('active_provider_id', activeId);
    state = state.copyWith(providers: providers, activeProviderId: activeId);
  }

  Future<void> updateProvider(ProviderConfig p) async {
    final encrypted = EncryptionService.encrypt(p.apiKey);
    await DatabaseService.updateProvider(p.copyWith(apiKey: encrypted));
    final providers = state.providers.map((e) => e.id == p.id ? p : e).toList();
    state = state.copyWith(providers: providers);
  }

  Future<void> deleteProvider(int id) async {
    await DatabaseService.deleteProvider(id);
    final providers = state.providers.where((p) => p.id != id).toList();
    int? newActive = state.activeProviderId;
    if (state.activeProviderId == id) {
      newActive = providers.isNotEmpty ? providers.first.id : null;
    }
    final prefs = await SharedPreferences.getInstance();
    if (newActive != null) {
      await prefs.setInt('active_provider_id', newActive);
    } else {
      await prefs.remove('active_provider_id');
    }
    state = state.copyWith(providers: providers, activeProviderId: newActive);
  }

  Future<void> setActiveProvider(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('active_provider_id', id);
    state = state.copyWith(activeProviderId: id);
  }

  // ─── 模型管理 ─────────────────

  Future<void> setSelectedModel(int providerId, String model) async {
    final provider = state.providers.firstWhere((p) => p.id == providerId);
    final updated = provider.copyWith(selectedModel: model);
    final encrypted = EncryptionService.encrypt(updated.apiKey);
    await DatabaseService.updateProvider(updated.copyWith(apiKey: encrypted));
    final providers = state.providers.map((p) => p.id == providerId ? updated : p).toList();
    state = state.copyWith(providers: providers);
  }

  Future<void> cacheModels(int providerId, List<String> models) async {
    final newCache = Map<String, List<String>>.from(state.modelCache);
    newCache[providerId.toString()] = models;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('model_cache', jsonEncode(newCache));
    state = state.copyWith(modelCache: newCache);
  }

  // ─── Token 用量 ─────────────────

  Future<void> addTokenUsage(int promptTokens, int completionTokens) async {
    final prefs = await SharedPreferences.getInstance();
    final newPrompt = state.totalPromptTokens + promptTokens;
    final newCompletion = state.totalCompletionTokens + completionTokens;
    await prefs.setInt('total_prompt_tokens', newPrompt);
    await prefs.setInt('total_completion_tokens', newCompletion);
    state = state.copyWith(totalPromptTokens: newPrompt, totalCompletionTokens: newCompletion);
  }

  // ─── 配置导出导入 ─────────────────

  Map<String, dynamic> exportConfig() {
    return {
      'suppliers': state.providers.map((p) => {
        'name': p.name,
        'baseUrl': p.apiBaseUrl,
        'model': p.selectedModel,
        'apiKey': p.maskedKey,
      }).toList(),
      'activeProviderName': state.activeProvider?.name ?? '',
      'care_settings': {
        'proactiveEnabled': state.proactiveEnabled,
        'silenceThresholdHours': state.silenceThresholdHours,
        'dndPeriods': state.dndPeriods.map((p) => p.toJson()).toList(),
      },
      'memory_settings': {
        'maxShortTermRounds': state.maxShortTermRounds,
      },
      'export_time': DateTime.now().toIso8601String(),
    };
  }

  Future<void> importConfig(Map<String, dynamic> config) async {
    final suppliers = config['suppliers'] as List? ?? [];
    for (final s in suppliers) {
      final name = s['name'] as String? ?? '';
      final baseUrl = s['baseUrl'] as String? ?? '';
      final model = s['model'] as String? ?? '';
      if (name.isNotEmpty && baseUrl.isNotEmpty) {
        final existing = state.providers.where((p) => p.name == name && p.apiBaseUrl == baseUrl);
        if (existing.isEmpty) {
          final encrypted = EncryptionService.encrypt('');
          final id = await DatabaseService.insertProvider(ProviderConfig(name: name, apiBaseUrl: baseUrl, apiKey: encrypted, selectedModel: model));
          final newProvider = ProviderConfig(id: id, name: name, apiBaseUrl: baseUrl, apiKey: '', selectedModel: model);
          state = state.copyWith(providers: [...state.providers, newProvider]);
        }
      }
    }

    final careSettings = config['care_settings'] as Map<String, dynamic>?;
    if (careSettings != null) {
      final proactiveEnabled = careSettings['proactiveEnabled'] as bool?;
      if (proactiveEnabled != null) await updateProactiveEnabled(proactiveEnabled);
      final silenceThreshold = careSettings['silenceThresholdHours'] as double?;
      if (silenceThreshold != null) await updateSilenceThreshold(silenceThreshold);
      final dndList = careSettings['dndPeriods'] as List?;
      if (dndList != null) {
        for (final d in dndList) {
          final period = DndPeriod.fromJson(d as Map<String, dynamic>);
          await addDndPeriod(period);
        }
      }
    }

    final memorySettings = config['memory_settings'] as Map<String, dynamic>?;
    if (memorySettings != null) {
      final rounds = memorySettings['maxShortTermRounds'] as int?;
      if (rounds != null) await updateMaxShortTermRounds(rounds);
    }
  }

  // ─── 其他设置 ─────────────────

  Future<void> updateMaxShortTermRounds(int r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('max_short_term_rounds', r);
    state = state.copyWith(maxShortTermRounds: r);
  }

  Future<void> markFirstRunComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_run', false);
    state = state.copyWith(isFirstRun: false);
  }

  Future<void> updateProactiveEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('proactive_enabled', v);
    state = state.copyWith(proactiveEnabled: v);
  }

  Future<void> updateSilenceThreshold(double h) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('silence_threshold_hours', h);
    state = state.copyWith(silenceThresholdHours: h);
  }

  Future<void> addDndPeriod(DndPeriod p) async {
    final periods = [...state.dndPeriods, p];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dnd_periods', jsonEncode(periods.map((e) => e.toJson()).toList()));
    state = state.copyWith(dndPeriods: periods);
  }

  Future<void> removeDndPeriod(int i) async {
    final periods = List<DndPeriod>.from(state.dndPeriods)..removeAt(i);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dnd_periods', jsonEncode(periods.map((e) => e.toJson()).toList()));
    state = state.copyWith(dndPeriods: periods);
  }

  Future<void> updateLastInteractionTime(DateTime t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_interaction_time', t.toIso8601String());
    state = state.copyWith(lastInteractionTime: t);
  }

  Future<void> updateThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> updatePrimaryColor(int color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('primary_color', color);
    state = state.copyWith(primaryColor: color);
  }

  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    final all = await DatabaseService.getProviders();
    for (final p in all) { await DatabaseService.deleteProvider(p.id!); }
    state = const SettingsState();
  }
}

class PresetProvider {
  final String name;
  final String baseUrl;
  final List<String> defaultModels;
  const PresetProvider(this.name, this.baseUrl, this.defaultModels);
}

class DndPeriod {
  final TimeOfDay start;
  final TimeOfDay end;
  const DndPeriod({required this.start, required this.end});

  bool contains(DateTime time) {
    final now = TimeOfDay(hour: time.hour, minute: time.minute);
    if (start.hour < end.hour || (start.hour == end.hour && start.minute < end.minute)) {
      return _between(now, start, end);
    }
    return !_between(now, end, start);
  }

  bool _between(TimeOfDay t, TimeOfDay a, TimeOfDay b) {
    final tMin = t.hour * 60 + t.minute;
    return tMin >= a.hour * 60 + a.minute && tMin < b.hour * 60 + b.minute;
  }

  Map<String, dynamic> toJson() => {'start': {'hour': start.hour, 'minute': start.minute}, 'end': {'hour': end.hour, 'minute': end.minute}};
  factory DndPeriod.fromJson(Map<String, dynamic> j) => DndPeriod(start: TimeOfDay(hour: j['start']['hour'], minute: j['start']['minute']), end: TimeOfDay(hour: j['end']['hour'], minute: j['end']['minute']));
  @override
  String toString() => '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} - ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
}

class SettingsState {
  final List<ProviderConfig> providers;
  final int? activeProviderId;
  final Map<String, List<String>> modelCache;
  final int maxShortTermRounds;
  final bool isFirstRun;
  final bool proactiveEnabled;
  final double silenceThresholdHours;
  final List<DndPeriod> dndPeriods;
  final DateTime? lastInteractionTime;
  final int totalPromptTokens;
  final int totalCompletionTokens;
  final String themeMode;
  final int primaryColor;

  const SettingsState({
    this.providers = const [],
    this.activeProviderId,
    this.modelCache = const {},
    this.maxShortTermRounds = 20,
    this.isFirstRun = true,
    this.proactiveEnabled = false,
    this.silenceThresholdHours = 12.0,
    this.dndPeriods = const [],
    this.lastInteractionTime,
    this.totalPromptTokens = 0,
    this.totalCompletionTokens = 0,
    this.themeMode = 'system',
    this.primaryColor = 0xFF3F51B5,
  });

  int get totalTokens => totalPromptTokens + totalCompletionTokens;

  ProviderConfig? get activeProvider => activeProviderId != null
      ? providers.cast<ProviderConfig?>().firstWhere((p) => p?.id == activeProviderId, orElse: () => null)
      : (providers.isNotEmpty ? providers.first : null);

  String get effectiveApiKey => activeProvider?.apiKey ?? '';
  String get effectiveBaseUrl => activeProvider?.apiBaseUrl ?? 'https://api.openai.com';
  String get effectiveModel => activeProvider?.selectedModel ?? '';
  bool get isConfigured => effectiveApiKey.isNotEmpty;

  List<String> getAvailableModels() {
    final provider = activeProvider;
    if (provider == null) return [];
    return modelCache[provider.id.toString()] ?? [];
  }

  SettingsState copyWith({
    List<ProviderConfig>? providers, int? activeProviderId, Map<String, List<String>>? modelCache,
    int? maxShortTermRounds, bool? isFirstRun, bool? proactiveEnabled, double? silenceThresholdHours,
    List<DndPeriod>? dndPeriods, DateTime? lastInteractionTime,
    int? totalPromptTokens, int? totalCompletionTokens,
    String? themeMode, int? primaryColor,
  }) {
    return SettingsState(
      providers: providers ?? this.providers, activeProviderId: activeProviderId ?? this.activeProviderId,
      modelCache: modelCache ?? this.modelCache, maxShortTermRounds: maxShortTermRounds ?? this.maxShortTermRounds,
      isFirstRun: isFirstRun ?? this.isFirstRun, proactiveEnabled: proactiveEnabled ?? this.proactiveEnabled,
      silenceThresholdHours: silenceThresholdHours ?? this.silenceThresholdHours,
      dndPeriods: dndPeriods ?? this.dndPeriods, lastInteractionTime: lastInteractionTime ?? this.lastInteractionTime,
      totalPromptTokens: totalPromptTokens ?? this.totalPromptTokens,
      totalCompletionTokens: totalCompletionTokens ?? this.totalCompletionTokens,
      themeMode: themeMode ?? this.themeMode, primaryColor: primaryColor ?? this.primaryColor,
    );
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) => SettingsNotifier());
