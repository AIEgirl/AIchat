import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart' as pp;

class PluginInfo {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final List<String> permissions;
  bool enabled;

  PluginInfo({
    required this.id, required this.name, required this.version,
    required this.author, required this.description,
    required this.permissions, this.enabled = true,
  });

  factory PluginInfo.fromJson(Map<String, dynamic> json) => PluginInfo(
    id: json['id'] as String, name: json['name'] as String? ?? '',
    version: json['version'] as String? ?? '1.0', author: json['author'] as String? ?? '',
    description: json['description'] as String? ?? '',
    permissions: (json['permissions'] as List?)?.cast<String>() ?? [],
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'version': version, 'author': author,
    'description': description, 'permissions': permissions, 'enabled': enabled,
  };
}

class PluginButton {
  final String id;
  final String label;
  final String? icon;
  final String Function() onClick;

  const PluginButton({required this.id, required this.label, this.icon, required this.onClick});
}

/// Dart-native plugin: rules defined in plugin.json, executed in Dart
class Plugin {
  final PluginInfo info;
  final Map<String, String> _wordReplacements;
  final List<String> _outputAppends;
  final List<Map<String, dynamic>> _extraButtons;
  final List<Map<String, dynamic>> _tools;

  Plugin({
    required this.info,
    Map<String, String> wordReplacements = const {},
    List<String> outputAppends = const [],
    List<Map<String, dynamic>> extraButtons = const [],
    List<Map<String, dynamic>> tools = const [],
  })  : _wordReplacements = wordReplacements,
        _outputAppends = outputAppends,
        _extraButtons = extraButtons,
        _tools = tools;

  bool get hasInputMod => info.permissions.contains('modify_input') && _wordReplacements.isNotEmpty;
  bool get hasOutputMod => info.permissions.contains('modify_output') && _outputAppends.isNotEmpty;
  bool get hasButtons => info.permissions.contains('add_button') && _extraButtons.isNotEmpty;
  bool get hasTools => info.permissions.contains('extend_tools') && _tools.isNotEmpty;

  String? modifyInput(String text) {
    if (!info.enabled || !hasInputMod) return null;
    var result = text;
    _wordReplacements.forEach((from, to) { result = result.replaceAll(from, to); });
    return result;
  }

  String? modifyOutput(String text) {
    if (!info.enabled || !hasOutputMod) return null;
    var result = text;
    for (final append in _outputAppends) { result += append; }
    return result;
  }

  List<PluginButton> getButtons() {
    if (!info.enabled || !hasButtons) return [];
    return _extraButtons.map((b) => PluginButton(
      id: b['id'] as String,
      label: b['label'] as String? ?? '',
      icon: b['icon'] as String?,
      onClick: () => (b['onClick'] as String? ?? ''),
    )).toList();
  }

  List<Map<String, dynamic>> getTools() {
    if (!info.enabled || !hasTools) return [];
    return _tools;
  }

  factory Plugin.fromConfig(Map<String, dynamic> config) {
    final info = PluginInfo.fromJson(config);
    final rules = config['rules'] as Map<String, dynamic>? ?? {};

    return Plugin(
      info: info,
      wordReplacements: (rules['wordReplace'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {},
      outputAppends: (rules['outputAppend'] as List?)?.cast<String>() ?? [],
      extraButtons: (rules['extraButtons'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      tools: (rules['tools'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
  }
}

class PluginManager {
  static final PluginManager _instance = PluginManager._();
  static PluginManager get instance => _instance;
  PluginManager._();

  final List<Plugin> _plugins = [];
  List<Plugin> get plugins => List.unmodifiable(_plugins);

  Future<void> init() async {
    final dir = await pp.getApplicationDocumentsDirectory();
    final pluginsDir = Directory('${dir.path}/plugins');
    if (!await pluginsDir.exists()) {
      await pluginsDir.create(recursive: true);
      await _installBuiltinSample(pluginsDir);
    }
    await _scanPlugins(pluginsDir);
  }

  Future<void> _installBuiltinSample(Directory pluginsDir) async {
    final sampleDir = Directory('${pluginsDir.path}/com.example.poke');
    await sampleDir.create(recursive: true);

    final pluginJson = {
      'id': 'com.example.poke',
      'name': '戳一戳',
      'version': '1.0',
      'author': 'System',
      'description': '在聊天中发送戳一戳表情，并过滤不雅词汇',
      'permissions': ['modify_input', 'modify_output', 'add_button'],
      'rules': {
        'wordReplace': {
          '靠': '哇',
          '我去': '天呐',
        },
        'outputAppend': [],
        'extraButtons': [
          {'id': 'poke', 'label': '戳一戳', 'icon': 'touch_app', 'onClick': '（戳了戳你）'},
          {'id': 'hug', 'label': '抱抱', 'icon': 'favorite', 'onClick': '（抱了抱你）'},
        ],
      },
    };
    await File('${sampleDir.path}/plugin.json').writeAsString(const JsonEncoder.withIndent('  ').convert(pluginJson));
  }

  Future<void> _scanPlugins(Directory dir) async {
    _plugins.clear();
    final entities = dir.listSync();
    for (final entity in entities) {
      if (entity is Directory) {
        final configFile = File('${entity.path}/plugin.json');
        if (await configFile.exists()) {
          try {
            final content = await configFile.readAsString();
            final config = jsonDecode(content) as Map<String, dynamic>;
            _plugins.add(Plugin.fromConfig(config));
          } catch (e) {
            debugPrint('Failed to load plugin from ${entity.path}: $e');
          }
        }
      }
    }
  }

  Future<void> installFromFile(String filePath) async {
    final dir = await pp.getApplicationDocumentsDirectory();
    final pluginsDir = Directory('${dir.path}/plugins');

    final file = File(filePath);
    final content = await file.readAsString();
    final config = jsonDecode(content) as Map<String, dynamic>;
    final id = config['id'] as String? ?? 'unknown';

    final targetDir = Directory('${pluginsDir.path}/$id');
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);
    await File('${targetDir.path}/plugin.json').writeAsString(content);

    await _scanPlugins(pluginsDir);
  }

  Future<void> uninstall(String pluginId) async {
    final dir = await pp.getApplicationDocumentsDirectory();
    final targetDir = Directory('${dir.path}/plugins/$pluginId');
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    _plugins.removeWhere((p) => p.info.id == pluginId);
  }

  void toggleEnabled(String pluginId, bool enabled) {
    for (final p in _plugins) {
      if (p.info.id == pluginId) {
        p.info.enabled = enabled;
        break;
      }
    }
  }

  String? applyInputMods(String text) {
    for (final plugin in _plugins) {
      final modified = plugin.modifyInput(text);
      if (modified != null) return modified;
    }
    return null;
  }

  String? applyOutputMods(String text) {
    for (final plugin in _plugins) {
      final modified = plugin.modifyOutput(text);
      if (modified != null) return modified;
    }
    return null;
  }

  List<PluginButton> getAllButtons() {
    final buttons = <PluginButton>[];
    for (final plugin in _plugins) {
      buttons.addAll(plugin.getButtons());
    }
    return buttons;
  }

  List<Map<String, dynamic>> getAllTools() {
    final tools = <Map<String, dynamic>>[];
    for (final plugin in _plugins) {
      tools.addAll(plugin.getTools());
    }
    return tools;
  }
}
