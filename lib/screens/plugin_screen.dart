import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/plugin_manager.dart';

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
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      await _manager.installFromFile(result.files.single.path!);
      _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('插件已安装')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('安装失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final plugins = _manager.plugins;
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件管理'),
        actions: [IconButton(icon: const Icon(Icons.file_download), tooltip: '安装插件', onPressed: _installPlugin)],
      ),
      body: plugins.isEmpty
          ? const Center(child: Text('暂无插件\n使用右上角按钮安装 plugin.json 文件', textAlign: TextAlign.center))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: plugins.length,
              itemBuilder: (_, i) {
                final plugin = plugins[i];
                final info = plugin.info;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(info.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                        Switch(value: info.enabled, onChanged: (v) { _manager.toggleEnabled(info.id, v); _refresh(); }),
                      ]),
                      const SizedBox(height: 4),
                      Text('${info.id} · v${info.version} · ${info.author}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      if (info.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(info.description, style: const TextStyle(fontSize: 13)),
                      ],
                      if (info.permissions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 4, runSpacing: 4, children: info.permissions.map((p) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                          child: Text(p, style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
                        )).toList()),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                          label: const Text('卸载', style: TextStyle(color: Colors.red)),
                          onPressed: () => _confirmUninstall(info.id, info.name),
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }

  void _confirmUninstall(String id, String name) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('确认卸载'),
      content: Text('确定要卸载插件 "$name" 吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () { _manager.uninstall(id); Navigator.pop(ctx); _refresh(); }, child: const Text('卸载')),
      ],
    ));
  }
}
