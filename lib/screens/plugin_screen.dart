import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/plugin_manager.dart';
import '../l10n/app_localizations.dart';

class PluginScreen extends StatefulWidget {
  const PluginScreen({super.key});

  @override
  State<PluginScreen> createState() => _PluginScreenState();
}

class _PluginScreenState extends State<PluginScreen> {
  final _manager = PluginManager.instance;

  void _refresh() => setState(() {});

  Future<void> _installPlugin() async {
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.any, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      await _manager.installFromFile(result.files.single.path!);
      _refresh();
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.get('pluginInstalled'))));
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.get('pluginInstallFailed')}: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final plugins = _manager.plugins;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('pluginManagement')),
        actions: [
          IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: l10n.get('installPlugin'),
              onPressed: _installPlugin)
        ],
      ),
      body: plugins.isEmpty
          ? Center(child: Text(l10n.get('noPlugins'), textAlign: TextAlign.center))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: plugins.length,
              itemBuilder: (_, i) {
                final plugin = plugins[i];
                final info = plugin.info;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(info.name,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600))),
                            Switch(
                                value: info.enabled,
                                onChanged: (v) {
                                  _manager.toggleEnabled(info.id, v);
                                  _refresh();
                                }),
                          ]),
                          const SizedBox(height: 4),
                          Text('${info.id} \u00b7 v${info.version} \u00b7 ${info.author}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant)),
                          if (info.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(info.description,
                                style: const TextStyle(fontSize: 13)),
                          ],
                          const SizedBox(height: 8),
                          Row(children: [
                            OutlinedButton.icon(
                                icon: Icon(Icons.delete_outline, color: scheme.error, size: 18),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: scheme.error,
                                  side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                                ),
                                onPressed: () {
                                  _manager.uninstall(info.id);
                                  _refresh();
                                },
                                label: Text(l10n.get('delete'))),
                          ]),
                        ]),
                  ),
                );
              },
            ),
    );
  }
}
