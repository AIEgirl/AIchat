import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart' as pp;
import '../models/agent.dart';

class AgentExportService {
  static Future<Map<String, dynamic>> exportAgent(Agent agent) async {
    final Map<String, dynamic> data = {
      'version': 1,
      'agent': {
        'name': agent.name,
        'gender': agent.gender,
        'description': agent.description,
        'persona': agent.persona,
        'avatar_color': agent.avatarColor,
        'avatar': null,
        'chat_background': null,
      },
    };

    if (agent.avatarPath != null && agent.avatarPath!.isNotEmpty && File(agent.avatarPath!).existsSync()) {
      final bytes = await File(agent.avatarPath!).readAsBytes();
      final ext = agent.avatarPath!.split('.').last;
      data['agent']['avatar'] = 'data:image/${ext == 'png' ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}';
    }

    if (agent.chatBackground != null && agent.chatBackground!.isNotEmpty) {
      if (agent.chatBackground!.startsWith('#')) {
        data['agent']['chat_background'] = agent.chatBackground;
      } else if (File(agent.chatBackground!).existsSync()) {
        final bytes = await File(agent.chatBackground!).readAsBytes();
        final ext = agent.chatBackground!.split('.').last;
        data['agent']['chat_background'] = 'data:image/${ext == 'png' ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}';
      }
    }

    return data;
  }

  static Future<Agent> importAgent(Map<String, dynamic> data) async {
    final a = data['agent'] as Map<String, dynamic>;
    final dir = await pp.getApplicationDocumentsDirectory();

    String? avatarPath;
    final avatarData = a['avatar'] as String?;
    if (avatarData != null && avatarData.startsWith('data:image/')) {
      final parts = avatarData.split(';base64,');
      if (parts.length == 2) {
        final mime = parts[0].replaceFirst('data:', '');
        final ext = mime.contains('png') ? 'png' : 'jpg';
        final bytes = base64Decode(parts[1]);
        final path = '${dir.path}/avatar_import_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await File(path).writeAsBytes(bytes);
        avatarPath = path;
      }
    }

    String? chatBg;
    final bgData = a['chat_background'] as String?;
    if (bgData != null) {
      if (bgData.startsWith('#')) {
        chatBg = bgData;
      } else if (bgData.startsWith('data:image/')) {
        final parts = bgData.split(';base64,');
        if (parts.length == 2) {
          final mime = parts[0].replaceFirst('data:', '');
          final ext = mime.contains('png') ? 'png' : 'jpg';
          final bytes = base64Decode(parts[1]);
          final path = '${dir.path}/bg_import_${DateTime.now().millisecondsSinceEpoch}.$ext';
          await File(path).writeAsBytes(bytes);
          chatBg = path;
        }
      }
    }

    return Agent(
      name: a['name'] as String? ?? 'Imported',
      gender: a['gender'] as String? ?? '',
      description: a['description'] as String? ?? '',
      persona: a['persona'] as String? ?? '',
      avatarColor: a['avatar_color'] as int? ?? 0xFFE8F5E9,
      avatarPath: avatarPath,
      chatBackground: chatBg,
    );
  }
}
