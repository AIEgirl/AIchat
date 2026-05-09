import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../providers/settings_provider.dart';
import '../providers/memory_provider.dart';
import '../providers/chat_provider.dart';
import '../models/provider_config.dart';
import '../services/model_service.dart';
import '../services/database_service.dart';
import '../services/locale_service.dart';
import '../l10n/app_localizations.dart';
import 'token_usage_screen.dart';
import 'memory_screen.dart';
import 'chat_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _roundsController = TextEditingController();

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final provider = s.activeProvider;
    final models = s.getAvailableModels();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('settings'), style: const TextStyle(fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sectionHeader(l10n.get('suppliers')),
          _buildSupplierSection(s, provider),
          _sectionHeader(l10n.get('modelAndMode')),
          _buildModelSection(provider, models),
          _sectionHeader(l10n.get('personaAndCare')),
          _buildPersonaSection(),
          _buildProactiveSection(s),
          _sectionHeader(l10n.get('memoryAndData')),
          _buildMemoryDataSection(s),
          _sectionHeader(l10n.get('configImportExport')),
          _buildConfigSection(),
          _sectionHeader(l10n.get('language')),
          _buildLanguageSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.5)),
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: children)),
    );
  }

  // ═══ 1. 供应商 ═══

  Widget _buildSupplierSection(SettingsState s, ProviderConfig? provider) {
    return _sectionCard(children: [
      if (s.providers.isEmpty)
        const Padding(padding: EdgeInsets.all(16), child: Text('暂无供应商，点击下方按钮添加', style: TextStyle(color: Colors.grey)))
      else
        ...s.providers.map((p) => _providerTile(p, s.activeProviderId)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加供应商'),
          onPressed: () => _showProviderDialog(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    ]);
  }

  Widget _providerTile(ProviderConfig p, int? activeId) {
    final isActive = p.id == activeId;
    final preset = SettingsNotifier.presetProviders.where((pr) => pr.name == p.name).firstOrNull;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isActive ? Colors.green : Colors.transparent, width: 2),
      ),
      elevation: 0,
      color: isActive ? Colors.green.shade50 : null,
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: isActive ? Colors.green.shade100 : Colors.grey.shade200,
          child: Text(p.name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.green.shade800 : Colors.grey.shade700)),
        ),
        title: Text(p.name, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Text(p.apiBaseUrl, style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (p.selectedModel.isNotEmpty)
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)), child: Text(p.selectedModel, style: TextStyle(fontSize: 10, color: Colors.blue.shade700))),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            onSelected: (a) {
              if (a == 'activate') ref.read(settingsProvider.notifier).setActiveProvider(p.id!).then((_) => _snack('已切换至 ${p.name}'));
              if (a == 'edit') _showProviderDialog(existing: p);
              if (a == 'delete') _confirmDeleteProvider(p);
            },
            itemBuilder: (_) => [
              if (!isActive) const PopupMenuItem(value: 'activate', child: Text('设为当前')),
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
              const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
            ],
          ),
        ]),
        onTap: () => _showProviderDialog(existing: p),
      ),
    );
  }

  void _showProviderDialog({ProviderConfig? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl = TextEditingController(text: existing?.apiBaseUrl ?? 'https://api.deepseek.com');
    final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    bool showKey = false;
    String selectedPreset = existing != null
        ? (SettingsNotifier.presetProviders.any((pr) => pr.name == existing.name) ? existing.name : '自定义')
        : 'DeepSeek';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, ds) => AlertDialog(
      title: Text(existing != null ? '编辑供应商' : '添加供应商', style: const TextStyle(fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('预设供应商', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: SettingsNotifier.presetProviders.any((pr) => pr.name == selectedPreset) ? selectedPreset : '自定义',
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            ...SettingsNotifier.presetProviders.map((pr) => DropdownMenuItem(value: pr.name, child: Text(pr.name, style: const TextStyle(fontSize: 13)))),
            const DropdownMenuItem(value: '自定义', child: Text('自定义', style: TextStyle(fontSize: 13))),
          ],
          onChanged: (v) {
            if (v == null) return;
            ds(() {
              selectedPreset = v!;
              if (v != '自定义') {
                final preset = SettingsNotifier.presetProviders.firstWhere((pr) => pr.name == v);
                nameCtrl.text = preset.name;
                urlCtrl.text = preset.baseUrl;
              }
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '供应商名称', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'API Base URL', border: OutlineInputBorder(), hintText: 'https://api.deepseek.com')),
        const SizedBox(height: 12),
        TextField(controller: keyCtrl, obscureText: !showKey,
          decoration: InputDecoration(labelText: 'API Key', border: const OutlineInputBorder(),
            suffixIcon: IconButton(icon: Icon(showKey ? Icons.visibility_off : Icons.visibility), onPressed: () => ds(() => showKey = !showKey)),
          ),
        ),
        if (existing != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () { Navigator.pop(ctx); _confirmDeleteProvider(existing); },
              icon: const Icon(Icons.delete_forever, color: Colors.red, size: 18),
              label: const Text('删除此供应商', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
            ),
          ),
        ],
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () {
          final n = nameCtrl.text.trim();
          final u = urlCtrl.text.trim();
          final k = keyCtrl.text.trim();
          if (n.isEmpty || u.isEmpty || k.isEmpty) { _snack('请填写完整信息', error: true); return; }
          if (existing != null) {
            ref.read(settingsProvider.notifier).updateProvider(existing.copyWith(name: n, apiBaseUrl: u, apiKey: k));
            _snack('供应商已更新');
          } else {
            ref.read(settingsProvider.notifier).addProvider(n, u, k);
            _snack('供应商已添加');
          }
          Navigator.pop(ctx);
        }, child: const Text('保存')),
      ],
    )));
  }

  void _confirmDeleteProvider(ProviderConfig p) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('确认删除'),
      content: Text('确定要删除供应商 "${p.name}" 吗？\nAPI Key 信息将被永久删除。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () {
          ref.read(settingsProvider.notifier).deleteProvider(p.id!);
          _snack('已删除 ${p.name}');
          Navigator.pop(ctx);
        }, child: const Text('删除')),
      ],
    ));
  }

  // ═══ 2. 模型与模式 ═══

  Widget _buildModelSection(ProviderConfig? provider, List<String> models) {
    return _sectionCard(children: [
      if (provider == null)
        const Padding(padding: EdgeInsets.all(16), child: Text('请先配置供应商', style: TextStyle(color: Colors.grey)))
      else
        Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: _modelDropdown(provider, models)),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.refresh), tooltip: '刷新模型列表', onPressed: () => _fetchModels(provider)),
          ]),
          if (provider.selectedModel.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 4), child: Text('请选择一个模型', style: TextStyle(color: Colors.orange, fontSize: 12))),
        ])),
    ]);
  }

  Widget _modelDropdown(ProviderConfig provider, List<String> models) {
    final preset = SettingsNotifier.presetProviders.where((pr) => pr.name == provider.name).firstOrNull;
    final suggestions = preset?.defaultModels ?? [];
    final allOptions = <String>{...suggestions, ...models, if (provider.selectedModel.isNotEmpty) provider.selectedModel}.toList();

    if (allOptions.isEmpty) {
      return TextButton.icon(
        icon: const Icon(Icons.cloud_download), label: const Text('点击获取模型列表'),
        onPressed: () => _fetchModels(provider),
      );
    }
    return Column(children: [
      DropdownButtonFormField<String>(
        value: allOptions.contains(provider.selectedModel) ? provider.selectedModel : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '选择模型', border: OutlineInputBorder()),
        hint: const Text('选择模型'),
        items: allOptions.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: (v) {
          if (v != null) {
            ref.read(settingsProvider.notifier).setSelectedModel(provider.id!, v);
            _snack('模型已更新');
          }
        },
      ),
      TextButton.icon(
        icon: const Icon(Icons.edit, size: 16),
        label: const Text('手动输入模型名', style: TextStyle(fontSize: 12)),
        onPressed: () => _showManualModelInput(provider),
      ),
    ]);
  }

  void _showManualModelInput(ProviderConfig provider) {
    final ctrl = TextEditingController(text: provider.selectedModel);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('手动输入模型名'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '例如: deepseek-chat', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () {
          if (ctrl.text.trim().isNotEmpty) {
            ref.read(settingsProvider.notifier).setSelectedModel(provider.id!, ctrl.text.trim());
            _snack('模型已更新');
            Navigator.pop(ctx);
          }
        }, child: const Text('保存')),
      ],
    ));
  }

  Future<void> _fetchModels(ProviderConfig provider) async {
    try {
      final models = await ModelService.fetchModels(baseUrl: provider.apiBaseUrl, apiKey: provider.apiKey);
      if (models.isNotEmpty) {
        ref.read(settingsProvider.notifier).cacheModels(provider.id!, models);
        if (provider.selectedModel.isEmpty || !models.contains(provider.selectedModel)) {
          ref.read(settingsProvider.notifier).setSelectedModel(provider.id!, models.first);
        }
        _snack('获取到 ${models.length} 个模型');
      }
    } catch (e) {
      _snack('获取模型失败: $e', error: true);
      _showManualModelInput(provider);
    }
  }

  // ═══ 3. 人设与关心 ═══

  Widget _buildPersonaSection() {
    final bs = ref.watch(baseProvider);
    final settings = bs.memories.where((m) => m.isSetting).toList();
    return _sectionCard(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (settings.isEmpty)
          const Text('暂无设定条目', style: TextStyle(color: Colors.grey, fontSize: 13))
        else
          ...settings.map((m) => Card(
            color: Colors.blue.shade50,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: ListTile(
              dense: true,
              title: Text(m.id, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              subtitle: Text(m.content, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editPersona(m.id, m.content)),
                IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => ref.read(baseProvider.notifier).deleteMemory(m.id)),
              ]),
            ),
          )),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('新增'), onPressed: _addPersona),
          const SizedBox(width: 8),
          OutlinedButton.icon(icon: const Icon(Icons.restore, size: 18), label: const Text('恢复默认'), onPressed: () async {
            await ref.read(baseProvider.notifier).clearAll();
            await ref.read(baseProvider.notifier).createSetting(defaultSystemPersona);
            _snack('已恢复默认人设');
          }),
        ]),
      ])),
    ]);
  }

  void _editPersona(String id, String current) {
    final ctrl = TextEditingController(text: current);
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('编辑 $id'), content: TextField(controller: ctrl, maxLines: 4, decoration: const InputDecoration(labelText: '设定内容')), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
      FilledButton(onPressed: () {
        final mem = ref.read(baseProvider).memories.firstWhere((m) => m.id == id);
        ref.read(baseProvider.notifier).updateMemory(mem.copyWith(content: ctrl.text.trim()));
        Navigator.pop(ctx);
        _snack('人设已更新');
      }, child: const Text('保存')),
    ]));
  }

  void _addPersona() {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('新增设定'), content: TextField(controller: ctrl, maxLines: 4, decoration: const InputDecoration(hintText: '设定内容...')), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
      FilledButton(onPressed: () { if (ctrl.text.trim().isNotEmpty) { ref.read(baseProvider.notifier).createSetting(ctrl.text.trim()); Navigator.pop(ctx); _snack('设定已添加'); } }, child: const Text('添加')),
    ]));
  }

  Widget _buildProactiveSection(SettingsState s) {
    return _sectionCard(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('主动关心'), subtitle: const Text('长时间不说话时主动关心'), value: s.proactiveEnabled, onChanged: (v) { ref.read(settingsProvider.notifier).updateProactiveEnabled(v); _snack('已更新'); }),
        if (s.proactiveEnabled) ...[
          const Divider(),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('静默阈值'), subtitle: Text('${s.silenceThresholdHours.toStringAsFixed(0)} 小时'),
            trailing: SizedBox(width: 100, child: TextField(decoration: const InputDecoration(labelText: '小时', border: OutlineInputBorder()), keyboardType: TextInputType.number,
              controller: TextEditingController(text: s.silenceThresholdHours.toStringAsFixed(0)),
              onChanged: (v) { final h = double.tryParse(v); if (h != null && h > 0) { ref.read(settingsProvider.notifier).updateSilenceThreshold(h); _snack('已更新'); } }))),
          const Text('免打扰时段', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ...s.dndPeriods.asMap().entries.map((e) => ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(e.value.toString()), trailing: IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () { ref.read(settingsProvider.notifier).removeDndPeriod(e.key); _snack('已删除'); }))),
          TextButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('添加时段'), onPressed: () => _addDnd(s)),
        ],
      ])),
    ]);
  }

  void _addDnd(SettingsState s) {
    TimeOfDay start = const TimeOfDay(hour: 22, minute: 0), end = const TimeOfDay(hour: 6, minute: 0);
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, ds) => AlertDialog(title: const Text('添加免打扰时段'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(title: const Text('开始'), trailing: Text(start.format(context)), onTap: () async { final t = await showTimePicker(context: context, initialTime: start); if (t != null) ds(() => start = t); }),
      ListTile(title: const Text('结束'), trailing: Text(end.format(context)), onTap: () async { final t = await showTimePicker(context: context, initialTime: end); if (t != null) ds(() => end = t); }),
    ]), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
      FilledButton(onPressed: () { ref.read(settingsProvider.notifier).addDndPeriod(DndPeriod(start: start, end: end)); Navigator.pop(ctx); _snack('免打扰时段已添加'); }, child: const Text('添加')),
    ])));
  }

  // ═══ 4. 记忆与数据 ═══

  Widget _buildMemoryDataSection(SettingsState s) {
    return _sectionCard(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        _listTileRow(Icons.token, 'Token 用量', '累计 ${s.totalTokens} tokens (输入 ${s.totalPromptTokens} + 输出 ${s.totalCompletionTokens})', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TokenUsageScreen()))),
        const Divider(height: 1),
        _listTileRow(Icons.memory, '短期记忆', '保留 ${s.maxShortTermRounds} 轮', null, trailing: SizedBox(
          width: 60,
          child: TextField(controller: _roundsController, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8)), keyboardType: TextInputType.number, textAlign: TextAlign.center,
            onChanged: (v) { final r = int.tryParse(v) ?? 20; ref.read(settingsProvider.notifier).updateMaxShortTermRounds(r); ref.read(memoryServiceProvider).maxShortTermRounds = r; }),
        )),
        const Divider(height: 1),
        _listTileRow(Icons.storage, '长期记忆', '查看 / 管理长期记忆', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemoryScreen()))),
        const Divider(height: 1),
        _listTileRow(Icons.bookmark, '基础记忆', '查看设定与历史事件', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemoryScreen()))),
        const Divider(height: 1),
        _listTileRow(Icons.bug_report, '调试日志', '查看 API 请求/响应记录', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugLogScreen()))),
        const Divider(height: 1),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => ref.read(chatProvider.notifier).clearChat(),
          icon: const Icon(Icons.cleaning_services, size: 18),
          label: const Text('清除短期记忆'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => _confirmReset(),
          icon: const Icon(Icons.delete_forever, color: Colors.red, size: 18),
          label: const Text('恢复默认设置', style: TextStyle(color: Colors.red)),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40), side: const BorderSide(color: Colors.red)),
        ),
      ])),
    ]);
  }

  Widget _listTileRow(IconData icon, String title, String subtitle, VoidCallback? onTap, {Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14)),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ])),
          if (trailing != null) trailing else if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        ]),
      ),
    );
  }

  void _confirmReset() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('恢复默认设置'),
      content: const Text('将清除所有自定义设置、记忆数据和配置，恢复为初始状态。此操作不可撤销。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () async {
          Navigator.pop(ctx);
          await ref.read(settingsProvider.notifier).resetAll();
          await ref.read(longTermProvider.notifier).clearAll();
          await ref.read(baseProvider.notifier).clearAll();
          ref.read(chatProvider.notifier).clearChat();
          await ref.read(baseProvider.notifier).createSetting(defaultSystemPersona);
          _snack('已恢复默认设置');
        }, child: const Text('确认重置')),
      ],
    ));
  }

  // ═══ 5. 配置导入导出 ═══

  Widget _buildConfigSection() {
    return _sectionCard(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.file_download, size: 18),
            label: const Text('导出配置'),
            onPressed: _exportConfig,
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.file_upload, size: 18),
            label: const Text('导入配置'),
            onPressed: _importConfig,
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
          ),
        ),
        const Divider(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.backup, size: 18),
            label: const Text('完整备份数据库'),
            onPressed: _backupDatabase,
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('从备份恢复数据库'),
            onPressed: _restoreDatabase,
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
          ),
        ),
      ])),
    ]);
  }

  Future<void> _exportConfig() async {
    try {
      final config = ref.read(settingsProvider.notifier).exportConfig();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(config);
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/aichat_config_$timestamp.json');
      await file.writeAsString(jsonStr);

      // Also copy to Downloads
      try {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          final downloadFile = File('${downloadDir.path}/aichat_config_$timestamp.json');
          await downloadFile.writeAsString(jsonStr);
          _snack('已导出到下载目录: aichat_config_$timestamp.json');
          return;
        }
      } catch (_) {}

      _snack('已导出到: ${file.path}');
    } catch (e) {
      _snack('导出失败: $e', error: true);
    }
  }

  Future<void> _importConfig() async {
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
        title: const Text('确认导入配置'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('即将导入: ${suppliers.length} 个供应商${hasCareSettings ? "、关心设置" : ""}'),
          const SizedBox(height: 8),
          const Text('注意: API Key 为脱敏占位，导入后需手动补填完整 Key。', style: TextStyle(color: Colors.orange, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认导入')),
        ],
      ));

      if (confirmed == true) {
        await ref.read(settingsProvider.notifier).importConfig(config);
        _snack('配置已导入，请手动补充 API Key');
      }
    } catch (e) {
      _snack('导入失败: $e', error: true);
    }
  }

  Future<void> _backupDatabase() async {
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
          _snack('备份已保存到下载目录: $fileName');
          return;
        }
      } catch (_) {}

      _snack('备份已保存: $destPath');
    } catch (e) {
      _snack('备份失败: $e', error: true);
    }
  }

  Future<void> _restoreDatabase() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;

      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('恢复数据库'),
        content: const Text('恢复将替换所有当前数据（供应商、记忆、聊天记录等），此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('确认恢复')),
        ],
      ));

      if (confirmed == true) {
        await DatabaseService.restoreDatabase(result.files.single.path!);
        _snack('数据库已恢复，请重启应用');
      }
    } catch (e) {
      _snack('恢复失败: $e', error: true);
    }
  }

  // ═══ 6. 语言切换 ═══

  String _languageMode = 'auto';

  Widget _buildLanguageSection() {
    return _sectionCard(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Icon(Icons.language, color: Colors.indigo),
          const SizedBox(width: 16),
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
