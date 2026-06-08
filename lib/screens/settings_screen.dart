import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart';
import '../providers/settings_provider.dart';
import '../providers/memory_provider.dart';
import '../providers/chat_provider.dart';
import '../models/provider_config.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/locale_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'token_usage_screen.dart';
import 'memory_screen.dart';
import 'plugin_screen.dart';
import 'chat_screen.dart';
import 'agent_create_screen.dart';
import 'novel_history_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _roundsController = TextEditingController();
  String _languageMode = 'auto';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = ref.read(settingsProvider);
      _roundsController.text = s.maxShortTermRounds.toString();
      _languageMode = await LocaleService.getLanguageMode();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _roundsController.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? scheme.errorContainer : scheme.primaryContainer,
      showCloseIcon: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final provider = s.activeProvider;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('settings')),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sectionHeader(l10n.get('suppliers')),
          _buildSupplierSection(s, provider),
          _sectionHeader(l10n.get('agentSection')),
          _buildAgentEntry(),
          _sectionHeader(l10n.get('modelAndMode')),
          _buildModelSection(provider),
          _sectionHeader(l10n.get('personaAndCare')),
          _buildProactiveSection(s),
          _sectionHeader(l10n.get('memoryAndData')),
          _buildMemoryDataSection(s),
          _sectionHeader(l10n.get('modelPrice')),
          _buildModelPriceSection(s, provider),
          _sectionHeader(l10n.get('configImportExport')),
          _buildConfigSection(),
          _sectionHeader(l10n.get('language')),
          _buildLanguageSection(),
          _sectionHeader(l10n.get('theme')),
          _buildThemeSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(title.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.8)),
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: children)),
    );
  }

  // ═══ 1. Providers ═══

  Widget _buildAgentEntry() {
    final l10n = AppLocalizations.of(context);
    return _sectionCard(children: [
      ListTile(
        leading: const Icon(Icons.person),
        title: Text(l10n.get('createNewAgent')),
        subtitle: Text(l10n.get('manageAgentDesc')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentCreateScreen())),
      ),
    ]);
  }

  Widget _buildSupplierSection(SettingsState s, ProviderConfig? provider) {
    final l10n = AppLocalizations.of(context);
    return _sectionCard(children: [
      if (s.providers.isEmpty)
        Padding(padding: const EdgeInsets.all(16), child: Text(l10n.get('noProvider'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
      else
        ...s.providers.map((p) => _providerTile(p, s.activeProviderId)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.get('addProvider')),
          onPressed: () => _showProviderDialog(),
        ),
      ),
    ]);
  }

  Widget _providerTile(ProviderConfig p, int? activeId) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isActive = p.id == activeId;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isActive ? scheme.primary : Colors.transparent, width: 2),
      ),
      elevation: 0,
      color: isActive ? scheme.primaryContainer.withValues(alpha: 0.4) : null,
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: isActive ? scheme.primary.withValues(alpha: 0.2) : scheme.surfaceContainerHighest,
          child: Text(p.name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? scheme.primary : scheme.onSurfaceVariant)),
        ),
        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Text(p.apiBaseUrl, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (p.selectedModel.isNotEmpty)
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(4)), child: Text(p.selectedModel, style: TextStyle(fontSize: 10, color: scheme.onSecondaryContainer))),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            onSelected: (a) {
              if (a == 'activate') ref.read(settingsProvider.notifier).setActiveProvider(p.id!).then((_) => _snack('${l10n.get('switchedTo')} ${p.name}'));
              if (a == 'edit') _showProviderDialog(existing: p);
              if (a == 'delete') _confirmDeleteProvider(p);
            },
            itemBuilder: (_) => [
              if (!isActive) PopupMenuItem(value: 'activate', child: Text(l10n.get('setAsCurrent'))),
              PopupMenuItem(value: 'edit', child: Text(l10n.get('edit'))),
              PopupMenuItem(value: 'delete', child: Text(l10n.get('delete'), style: TextStyle(color: scheme.error))),
            ],
          ),
        ]),
        onTap: () => _showProviderDialog(existing: p),
      ),
    );
  }

  void _showProviderDialog({ProviderConfig? existing}) {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl = TextEditingController(text: existing?.apiBaseUrl ?? 'https://api.deepseek.com');
    final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    bool showKey = false;
    String selectedPreset = existing != null
        ? (SettingsNotifier.presetProviders.any((pr) => pr.name == existing.name) ? existing.name : l10n.get('custom'))
        : 'DeepSeek';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, ds) => AlertDialog(
      title: Text(existing != null ? l10n.get('editProvider') : l10n.get('addProvider'), style: const TextStyle(fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.get('presetProvider'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: SettingsNotifier.presetProviders.any((pr) => pr.name == selectedPreset) ? selectedPreset : l10n.get('custom'),
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            ...SettingsNotifier.presetProviders.map((pr) => DropdownMenuItem(value: pr.name, child: Text(pr.name, style: const TextStyle(fontSize: 13)))),
            DropdownMenuItem(value: l10n.get('custom'), child: Text(l10n.get('custom'), style: const TextStyle(fontSize: 13))),
          ],
          onChanged: (v) {
            if (v == null) return;
            ds(() {
              selectedPreset = v;
              if (v != l10n.get('custom')) {
                final preset = SettingsNotifier.presetProviders.firstWhere((pr) => pr.name == v);
                nameCtrl.text = preset.name;
                urlCtrl.text = preset.baseUrl;
              }
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.get('providerName'), border: const OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: urlCtrl, decoration: InputDecoration(labelText: l10n.get('apiBaseUrl'), border: const OutlineInputBorder(), hintText: 'https://api.deepseek.com')),
        const SizedBox(height: 12),
        TextField(controller: keyCtrl, obscureText: !showKey,
          decoration: InputDecoration(labelText: l10n.get('apiKey'), border: const OutlineInputBorder(),
            suffixIcon: IconButton(icon: Icon(showKey ? Icons.visibility_off : Icons.visibility), onPressed: () => ds(() => showKey = !showKey)),
          ),
        ),
        if (existing != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () { Navigator.pop(ctx); _confirmDeleteProvider(existing); },
              icon: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error, size: 18),
              label: Text(l10n.get('deleteProvider'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5))),
            ),
          ),
        ],
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('cancel'))),
        FilledButton(onPressed: () {
          final n = nameCtrl.text.trim();
          final u = urlCtrl.text.trim();
          final k = keyCtrl.text.trim();
          if (n.isEmpty || u.isEmpty || k.isEmpty) { _snack(l10n.get('pleaseFillAll'), error: true); return; }
          if (existing != null) {
            ref.read(settingsProvider.notifier).updateProvider(existing.copyWith(name: n, apiBaseUrl: u, apiKey: k));
            _snack(l10n.get('providerUpdated'));
          } else {
            ref.read(settingsProvider.notifier).addProvider(n, u, k);
            _snack(l10n.get('providerAdded'));
          }
          Navigator.pop(ctx);
        }, child: Text(l10n.get('save'))),
      ],
    )));
  }

  void _confirmDeleteProvider(ProviderConfig p) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 32),
      title: Text(l10n.get('confirmDelete')),
      content: Text(l10n.get('deleteProviderConfirm').replaceFirst('\n', '\n') + ' "${p.name}"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
          onPressed: () {
            ref.read(settingsProvider.notifier).deleteProvider(p.id!);
            _snack('${l10n.get('providerDeleted')} ${p.name}');
            Navigator.pop(ctx);
          },
          child: Text(l10n.get('delete')),
        ),
      ],
    ));
  }

  // ═══ 2. Model ═══

  Widget _buildModelSection(ProviderConfig? provider) {
    final l10n = AppLocalizations.of(context);
    final preset = provider != null
        ? SettingsNotifier.presetProviders.where((pr) => pr.name == provider.name).firstOrNull
        : null;
    final defaultModel = preset?.defaultModels.first ?? 'deepseek-chat';
    final ctrl = TextEditingController(text: provider?.selectedModel ?? '');

    if (provider == null) {
      return _sectionCard(children: [
        Padding(padding: const EdgeInsets.all(16), child: Text(l10n.get('configureProviderFirst'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
    ]);
  }

    return _sectionCard(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          TextField(
            controller: ctrl,
            decoration: InputDecoration(
              labelText: l10n.get('modelNameLabel'),
              hintText: defaultModel,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) {
              if (v.trim().isNotEmpty) {
                ref.read(settingsProvider.notifier).setSelectedModel(provider.id!, v.trim());
              }
            },
          ),
          if (provider.selectedModel.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(l10n.get('pleaseEnterModel'), style: TextStyle(color: Theme.of(context).colorScheme.tertiary, fontSize: 12))),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.wifi_find, size: 18),
              label: Text(l10n.get('testConnection')),
              onPressed: () => _testConnection(provider),
            ),
          ),
        ]),
      ),
    ]);
  }

  Future<void> _testConnection(ProviderConfig provider) async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await ApiService.testConnection(
        baseUrl: provider.apiBaseUrl,
        apiKey: provider.apiKey,
      );
      _snack(result, error: !result.startsWith(l10n.get('connectionSuccess')));
    } catch (e) {
      _snack('${l10n.get('testConnectionFailed')}: $e', error: true);
    }
  }

  Widget _buildProactiveSection(SettingsState s) {
    final l10n = AppLocalizations.of(context);
    return _sectionCard(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(l10n.get('proactiveCare')), subtitle: Text(l10n.get('proactiveCareDesc')), value: s.proactiveEnabled, onChanged: (v) { ref.read(settingsProvider.notifier).updateProactiveEnabled(v); _snack(l10n.get('updated')); }),
        if (s.proactiveEnabled) ...[
          const Divider(),
          ListTile(contentPadding: EdgeInsets.zero, title: Text(l10n.get('silenceThreshold')), subtitle: Text('${s.silenceThresholdHours.toStringAsFixed(0)} ${l10n.get('hours')}'),
            trailing: SizedBox(width: 100, child: TextField(decoration: InputDecoration(labelText: l10n.get('hours'), border: const OutlineInputBorder()), keyboardType: TextInputType.number,
              controller: TextEditingController(text: s.silenceThresholdHours.toStringAsFixed(0)),
              onChanged: (v) { final h = double.tryParse(v); if (h != null && h > 0) { ref.read(settingsProvider.notifier).updateSilenceThreshold(h); _snack(l10n.get('updated')); } }))),
          Text(l10n.get('dndPeriods'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ...s.dndPeriods.asMap().entries.map((e) => ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(e.value.toString()), trailing: IconButton(icon: Icon(Icons.delete, size: 18, color: Theme.of(context).colorScheme.error), onPressed: () { ref.read(settingsProvider.notifier).removeDndPeriod(e.key); _snack(l10n.get('periodDeleted')); }))),
          TextButton.icon(icon: const Icon(Icons.add, size: 18), label: Text(l10n.get('addPeriod')), onPressed: () => _addDnd(s)),
        ],
      ])),
    ]);
  }

  void _addDnd(SettingsState s) {
    final l10n = AppLocalizations.of(context);
    TimeOfDay start = const TimeOfDay(hour: 22, minute: 0), end = const TimeOfDay(hour: 6, minute: 0);
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, ds) => AlertDialog(
      title: Text(l10n.get('addDndTitle')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(l10n.get('startTime')), trailing: Text(start.format(context)), onTap: () async { final t = await showTimePicker(context: context, initialTime: start); if (t != null) ds(() => start = t); }),
        ListTile(title: Text(l10n.get('endTime')), trailing: Text(end.format(context)), onTap: () async { final t = await showTimePicker(context: context, initialTime: end); if (t != null) ds(() => end = t); }),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('cancel'))),
        FilledButton(onPressed: () { ref.read(settingsProvider.notifier).addDndPeriod(DndPeriod(start: start, end: end)); Navigator.pop(ctx); _snack(l10n.get('periodAdded')); }, child: Text(l10n.get('add'))),
      ],
    )));
  }

  // ═══ 4. Memory & Data ═══

  Widget _buildMemoryDataSection(SettingsState s) {
    final l10n = AppLocalizations.of(context);
    final tokenDesc = '${l10n.get('tokenTotal')} ${s.totalTokens} tokens (${l10n.get('tokenSummary').replaceFirst('{total}', s.totalTokens.toString()).replaceFirst('{input}', s.totalPromptTokens.toString()).replaceFirst('{output}', s.totalCompletionTokens.toString())})';
    final shortDesc = '${l10n.get('retain')} ${s.maxShortTermRounds} ${l10n.get('roundsUnit')}';
    return _sectionCard(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        _listTileRow(Icons.token, l10n.get('tokenUsage'), tokenDesc, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TokenUsageScreen()))),
        const Divider(height: 1),
        _listTileRow(Icons.memory, l10n.get('shortTermMemory'), shortDesc, null, trailing: SizedBox(
          width: 60,
          child: TextField(controller: _roundsController, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8)), keyboardType: TextInputType.number, textAlign: TextAlign.center,
            onChanged: (v) { final r = int.tryParse(v) ?? 20; ref.read(settingsProvider.notifier).updateMaxShortTermRounds(r); ref.read(memoryServiceProvider).maxShortTermRounds = r; }),
        )),
        const Divider(height: 1),
        _listTileRow(Icons.storage, l10n.get('longTermMemory'), l10n.get('longTermMemoryDesc'), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemoryScreen()))),
        const Divider(height: 1),
        _listTileRow(Icons.bookmark, l10n.get('baseMemory'), l10n.get('baseMemoryDesc'), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemoryScreen()))),
        const Divider(height: 1),
        _listTileRow(Icons.bug_report, l10n.get('debugLogs'), l10n.get('debugLogsDesc'), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugLogScreen()))),
        const Divider(height: 1),
        _listTileRow(Icons.extension, l10n.get('pluginManagement'), l10n.get('pluginManagementDesc'), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PluginScreen()))),
        const Divider(height: 1),
        _listTileRow(Icons.auto_awesome, '小说生成', '查看和管理生成的小说内容', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NovelHistoryScreen()))),
        const Divider(height: 1),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => ref.read(chatProvider.notifier).clearChat(),
          icon: const Icon(Icons.cleaning_services, size: 18),
          label: Text(l10n.get('clearShortTerm')),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => _confirmClearChatHistory(),
          icon: const Icon(Icons.delete_sweep, size: 18),
          label: Text(l10n.get('clearChatHistory')),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => _exportChatHistory(),
          icon: const Icon(Icons.file_download, size: 18),
          label: Text(l10n.get('exportChatHistory')),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => _confirmReset(),
          icon: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error, size: 18),
          label: Text(l10n.get('resetDefaults'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40), side: BorderSide(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5))),
        ),
      ])),
    ]);
  }

  Widget _listTileRow(IconData icon, String title, String subtitle, VoidCallback? onTap, {Widget? trailing}) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            Text(subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (trailing != null) trailing else if (onTap != null) Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
        ]),
      ),
    );
  }

  void _confirmReset() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 32),
      title: Text(l10n.get('resetDefaults')),
      content: Text(l10n.get('resetDefaultsConfirm')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
          onPressed: () async {
            Navigator.pop(ctx);
            await ref.read(settingsProvider.notifier).resetAll();
            await ref.read(longTermProvider.notifier).clearAll();
            await ref.read(baseProvider.notifier).clearAll();
            ref.read(chatProvider.notifier).clearChat();
            await ref.read(baseProvider.notifier).createSetting(defaultSystemPersona);
            _snack(l10n.get('resetDone'));
          },
          child: Text(l10n.get('confirmResetAction')),
        ),
      ],
    ));
  }

  void _confirmClearChatHistory() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      icon: Icon(Icons.delete_sweep, color: scheme.error, size: 32),
      title: Text(l10n.get('clearChatHistory')),
      content: Text(l10n.get('clearChatHistoryConfirm')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
          onPressed: () async {
            await ref.read(chatProvider.notifier).clearCurrentAgentChatMessages();
            Navigator.pop(ctx);
            _snack(l10n.get('chatHistoryCleared'));
          },
          child: Text(l10n.get('delete')),
        ),
      ],
    ));
  }

  Future<void> _exportChatHistory() async {
    final l10n = AppLocalizations.of(context);
    try {
      final chatState = ref.read(chatProvider);
      if (chatState.messages.isEmpty) { _snack(l10n.get('noChatHistory')); return; }
      final sb = StringBuffer();
      sb.writeln('=== AI Chat History ===');
      sb.writeln('Export time: ${DateTime.now().toIso8601String()}');
      sb.writeln('');
      for (final msg in chatState.messages) {
        final role = msg.isUser ? 'User' : 'AI';
        sb.writeln('[$role] ${DateFormat('yyyy-MM-dd HH:mm:ss').format(msg.timestamp)}');
        sb.writeln(msg.content);
        sb.writeln('');
      }
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/chat_history_$timestamp.txt');
      await file.writeAsString(sb.toString());

      try {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          await file.copy('${downloadDir.path}/chat_history_$timestamp.txt');
          _snack('${l10n.get('chatExported')}: chat_history_$timestamp.txt');
          return;
        }
      } catch (_) {}
      _snack('${l10n.get('chatExported')}: ${file.path}');
    } catch (e) {
      _snack('${l10n.get('exportFailed')}: $e', error: true);
    }
  }

  // ═══ Model Price ═══

  Widget _buildModelPriceSection(SettingsState s, ProviderConfig? provider) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final totalPrompt = s.totalPromptTokens;
    final totalCompletion = s.totalCompletionTokens;

    double cost = 0;
    if (s.inputPrice > 0) {
      final inDiv = s.inputUnit == 'per_10000' ? 10000.0 : (s.inputUnit == 'per_1000000' ? 1000000.0 : 1000.0);
      cost += (totalPrompt / inDiv) * s.inputPrice;
    }
    if (s.outputPrice > 0) {
      final outDiv = s.outputUnit == 'per_10000' ? 10000.0 : (s.outputUnit == 'per_1000000' ? 1000000.0 : 1000.0);
      cost += (totalCompletion / outDiv) * s.outputPrice;
    }

    return _sectionCard(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(children: [
          Icon(Icons.attach_money, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.get('modelPriceDesc'), style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text('${l10n.get('inputPrice')}: ', style: const TextStyle(fontSize: 13)),
          Text(s.inputPrice > 0 ? '${s.inputPrice} ${_unitLabel(s.inputUnit)}' : '--',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
        Row(children: [
          Text('${l10n.get('outputPrice')}: ', style: const TextStyle(fontSize: 13)),
          Text(s.outputPrice > 0 ? '${s.outputPrice} ${_unitLabel(s.outputUnit)}' : '--',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          TextButton(onPressed: _editModelPrices, child: Text(l10n.get('edit'))),
        ]),
        const Divider(height: 1),
        Row(children: [
          Text('${l10n.get('promptTokens')}: ', style: const TextStyle(fontSize: 13)),
          Text('$totalPrompt', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text('${l10n.get('completionTokens')}: ', style: const TextStyle(fontSize: 13)),
          Text('$totalCompletion', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text('${l10n.get('estimatedCost')}: ', style: const TextStyle(fontSize: 13)),
          Text(cost > 0 ? cost.toStringAsFixed(4) : '--', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary)),
        ]),
      ])),
    ]);
  }

  String _unitLabel(String unit) {
    final l10n = AppLocalizations.of(context);
    if (unit == 'per_10000') return l10n.get('perTenThousandTokens');
    if (unit == 'per_1000000') return l10n.get('perMillionTokens');
    return l10n.get('perThousandTokens');
  }

  Future<void> _editModelPrices() async {
    final l10n = AppLocalizations.of(context);
    final s = ref.read(settingsProvider);
    final inCtrl = TextEditingController(text: s.inputPrice > 0 ? s.inputPrice.toString() : '');
    final outCtrl = TextEditingController(text: s.outputPrice > 0 ? s.outputPrice.toString() : '');
    String inUnit = s.inputUnit;
    String outUnit = s.outputUnit;
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        title: Text(l10n.get('modelPrice')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l10n.get('inputPrice'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: TextField(
              controller: inCtrl,
              decoration: InputDecoration(labelText: l10n.get('pricePerUnit'), border: const OutlineInputBorder(), isDense: true),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            )),
            const SizedBox(width: 8),
            Flexible(
              child: DropdownButtonFormField<String>(
                value: inUnit,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                items: [
                  DropdownMenuItem(value: 'per_1000', child: Text(l10n.get('perThousandTokens'), style: const TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'per_10000', child: Text(l10n.get('perTenThousandTokens'), style: const TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'per_1000000', child: Text(l10n.get('perMillionTokens'), style: const TextStyle(fontSize: 12))),
                ],
                onChanged: (v) { if (v != null) setDialogState(() => inUnit = v); },
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Text(l10n.get('outputPrice'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: TextField(
              controller: outCtrl,
              decoration: InputDecoration(labelText: l10n.get('pricePerUnit'), border: const OutlineInputBorder(), isDense: true),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            )),
            const SizedBox(width: 8),
            Flexible(
              child: DropdownButtonFormField<String>(
                value: outUnit,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                items: [
                  DropdownMenuItem(value: 'per_1000', child: Text(l10n.get('perThousandTokens'), style: const TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'per_10000', child: Text(l10n.get('perTenThousandTokens'), style: const TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'per_1000000', child: Text(l10n.get('perMillionTokens'), style: const TextStyle(fontSize: 12))),
                ],
                onChanged: (v) { if (v != null) setDialogState(() => outUnit = v); },
              ),
            ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('cancel'))),
          FilledButton(onPressed: () {
            final ip = double.tryParse(inCtrl.text.trim()) ?? 0;
            final op = double.tryParse(outCtrl.text.trim()) ?? 0;
            ref.read(settingsProvider.notifier).updateModelPrices(
              inputPrice: ip, inputUnit: inUnit, outputPrice: op, outputUnit: outUnit,
            );
            Navigator.pop(ctx);
          }, child: Text(l10n.get('save'))),
        ],
      )),
    );
  }

  // ═══ 5. Config Import/Export ═══

  Widget _buildConfigSection() {
    final l10n = AppLocalizations.of(context);
    return _sectionCard(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.file_download, size: 18),
            label: Text(l10n.get('exportConfig')),
            onPressed: _exportConfig,
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.file_upload, size: 18),
            label: Text(l10n.get('importConfig')),
            onPressed: _importConfig,
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
          ),
        ),
        const Divider(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.backup, size: 18),
            label: Text(l10n.get('backupDatabase')),
            onPressed: _backupDatabase,
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.restore, size: 18),
            label: Text(l10n.get('restoreDatabase')),
            onPressed: _restoreDatabase,
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
          ),
        ),
      ])),
    ]);
  }

  Future<void> _exportConfig() async {
    final l10n = AppLocalizations.of(context);
    try {
      final config = ref.read(settingsProvider.notifier).exportConfig();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(config);
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/aichat_config_$timestamp.json');
      await file.writeAsString(jsonStr);

      try {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          final downloadFile = File('${downloadDir.path}/aichat_config_$timestamp.json');
          await downloadFile.writeAsString(jsonStr);
          _snack('${l10n.get('configExported')} aichat_config_$timestamp.json');
          return;
        }
      } catch (_) {}
      _snack('${l10n.get('configExported')}: ${file.path}');
    } catch (e) {
      _snack('${l10n.get('exportFailed')}: $e', error: true);
    }
  }

  Future<void> _importConfig() async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final config = jsonDecode(content) as Map<String, dynamic>;

      if (!mounted) return;
      final suppliers = (config['suppliers'] as List?) ?? [];
      final hasCareSettings = config['care_settings'] != null;

      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        icon: Icon(Icons.file_upload, color: Theme.of(context).colorScheme.primary, size: 32),
        title: Text(l10n.get('confirmImportTitle')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.get('configImportConfirm').replaceFirst('{n}', suppliers.length.toString())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.get('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.get('confirm'))),
        ],
      ));

      if (confirmed == true) {
        await ref.read(settingsProvider.notifier).importConfig(config);
        _snack(l10n.get('configImported'));
      }
    } catch (e) {
      _snack('${l10n.get('importFailed')}: $e', error: true);
    }
  }

  Future<void> _backupDatabase() async {
    final l10n = AppLocalizations.of(context);
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'aichat_backup_$timestamp.db';
      final dir = await getApplicationDocumentsDirectory();
      final destPath = '${dir.path}/$fileName';
      await DatabaseService.backupDatabase(destPath);

      try {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          await File(destPath).copy('${downloadDir.path}/$fileName');
          _snack('${l10n.get('backupSaved')}: $fileName');
          return;
        }
      } catch (_) {}
      _snack('${l10n.get('backupSaved')}: $destPath');
    } catch (e) {
      _snack('${l10n.get('backupFailed')}: $e', error: true);
    }
  }

  Future<void> _restoreDatabase() async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;

      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error, size: 32),
        title: Text(l10n.get('restoreDatabase')),
        content: Text(l10n.get('restoreDbConfirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.get('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.get('confirmResetAction')),
          ),
        ],
      ));

      if (confirmed == true) {
        await DatabaseService.restoreDatabase(result.files.single.path!);
        _snack(l10n.get('dbRestored'));
      }
    } catch (e) {
      _snack('${l10n.get('restoreFailed')}: $e', error: true);
    }
  }

  // ═══ 6. Theme ═══

  Widget _buildThemeSection() {
    final s = ref.watch(settingsProvider);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return _sectionCard(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.brightness_6, size: 18, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Text(l10n.get('themeMode'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'system', label: Text(l10n.get('autoTheme'), style: const TextStyle(fontSize: 12))),
            ButtonSegment(value: 'light', label: Text(l10n.get('lightTheme'), style: const TextStyle(fontSize: 12))),
            ButtonSegment(value: 'dark', label: Text(l10n.get('darkTheme'), style: const TextStyle(fontSize: 12))),
          ],
          selected: {s.themeMode},
          onSelectionChanged: (v) => ref.read(settingsProvider.notifier).updateThemeMode(v.first),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.palette, size: 18, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Text(l10n.get('themeColor'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          0xFF3F51B5, 0xFFE91E63, 0xFF009688, 0xFF673AB7,
          0xFFFF5722, 0xFF4CAF50, 0xFF2196F3, 0xFFFF9800,
        ].map((c) => GestureDetector(
          onTap: () => ref.read(settingsProvider.notifier).updatePrimaryColor(c),
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
              border: Border.all(
                color: s.primaryColor == c ? scheme.onSurface : scheme.outlineVariant,
                width: s.primaryColor == c ? 3 : 1,
              ),
              boxShadow: s.primaryColor == c ? AppTheme.shadowSm : null,
            ),
          ),
        )).toList()),
      ])),
    ]);
  }

  // ═══ 7. Language ═══

  Widget _buildLanguageSection() {
    final scheme = Theme.of(context).colorScheme;
    return _sectionCard(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.language, size: 18, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(AppLocalizations.of(context)!.get('language'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
          DropdownButton<String>(
            value: _languageMode,
            underline: const SizedBox(),
            items: [
              DropdownMenuItem(value: 'auto', child: Text(AppLocalizations.of(context)!.get('autoDetect'), style: const TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'zh', child: Text(AppLocalizations.of(context)!.get('chinese'), style: const TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'en', child: Text(AppLocalizations.of(context)!.get('english'), style: const TextStyle(fontSize: 13))),
            ],
            onChanged: (v) async {
              if (v == null) return;
              setState(() => _languageMode = v!);
              await LocaleService.setLanguageMode(v);
              Locale newLocale;
              if (v == 'auto') {
                final lang = await LocaleService.detectLanguageFromIp();
                newLocale = Locale(lang);
              } else {
                newLocale = Locale(v);
              }
              if (mounted) {
                ref.read(localeProvider.notifier).state = newLocale;
                _snack(AppLocalizations.of(context)!.get('updated'));
              }
            },
          ),
        ]),
      ),
    ]);
  }
}
