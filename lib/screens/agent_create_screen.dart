import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart' as pp;
import '../models/agent.dart';
import '../providers/agent_provider.dart';

class AgentCreateScreen extends ConsumerStatefulWidget {
  final Agent? agent;
  const AgentCreateScreen({super.key, this.agent});

  @override
  ConsumerState<AgentCreateScreen> createState() => _AgentCreateScreenState();
}

class _AgentCreateScreenState extends ConsumerState<AgentCreateScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _personaCtrl;
  String _gender = '';
  int _avatarColor = 0xFFE8F5E9;
  String? _avatarPath;
  String? _chatBackground;
  bool _useImageAvatar = false;

  static const _colors = [
    0xFFE8F5E9, 0xFFFFF3E0, 0xFFFCE4EC, 0xFFE3F2FD,
    0xFFF3E5F5, 0xFFE0F2F1, 0xFFFFF8E1, 0xFFFBE9E7,
    0xFFE8EAF6, 0xFFF1F8E9, 0xFFFFEBEE, 0xFFECEFF1,
  ];

  static const _bgColors = [
    null, 0xFFFFFFFF, 0xFFFFF8E1, 0xFFF5F5F5, 0xFFE8F5E9,
    0xFFE3F2FD, 0xFFFCE4EC, 0xFFF3E5F5, 0xFFE0F2F1,
  ];

  bool get isEditing => widget.agent != null;

  @override
  void initState() {
    super.initState();
    final a = widget.agent;
    _nameCtrl = TextEditingController(text: a?.name ?? '');
    _descCtrl = TextEditingController(text: a?.description ?? '');
    _personaCtrl = TextEditingController(text: a?.persona ?? defaultAgentPersona);
    _gender = a?.gender ?? '';
    _avatarColor = a?.avatarColor ?? 0xFFE8F5E9;
    _avatarPath = a?.avatarPath;
    _chatBackground = a?.chatBackground;
    _useImageAvatar = _avatarPath != null && _avatarPath!.isNotEmpty;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _personaCtrl.dispose();
    super.dispose();
  }

  void _insertPlaceholder(String text) {
    final cursor = _personaCtrl.selection.baseOffset;
    final current = _personaCtrl.text;
    if (cursor >= 0 && cursor < current.length) {
      _personaCtrl.text = current.substring(0, cursor) + text + current.substring(cursor);
      _personaCtrl.selection = TextSelection.collapsed(offset: cursor + text.length);
    } else {
      _personaCtrl.text = current + text;
      _personaCtrl.selection = TextSelection.collapsed(offset: _personaCtrl.text.length);
    }
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入智能体名称')));
      return;
    }
    final notifier = ref.read(agentProvider.notifier);
    if (isEditing) {
      notifier.updateAgent(widget.agent!.copyWith(
        name: name, gender: _gender, description: _descCtrl.text.trim(),
        persona: _personaCtrl.text.trim(), avatarColor: _avatarColor,
        avatarPath: _useImageAvatar ? _avatarPath : null,
        chatBackground: _chatBackground,
      ));
    } else {
      notifier.createAgent(
        name: name, gender: _gender, description: _descCtrl.text.trim(),
        persona: _personaCtrl.text.trim(), avatarColor: _avatarColor,
      );
      if (_useImageAvatar && _avatarPath != null) {
        final agent = ref.read(agentProvider).currentAgent;
        if (agent != null) {
          notifier.updateAgent(agent.copyWith(avatarPath: _avatarPath));
        }
      }
      if (_chatBackground != null) {
        final agent = ref.read(agentProvider).currentAgent;
        if (agent != null) {
          notifier.updateAgent(agent.copyWith(chatBackground: _chatBackground));
        }
      }
    }
    Navigator.pop(context);
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(source: source, maxWidth: 512, maxHeight: 512);
      if (img != null) {
        final dir = await pp.getApplicationDocumentsDirectory();
        final destPath = '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(img.path).copy(destPath);
        setState(() { _avatarPath = destPath; _useImageAvatar = true; });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择图片失败: $e')));
    }
  }

  Future<void> _pickBackground() async {
    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1080);
      if (img != null) {
        final dir = await pp.getApplicationDocumentsDirectory();
        final destPath = '${dir.path}/bg_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(img.path).copy(destPath);
        setState(() => _chatBackground = destPath);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择背景失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? '编辑智能体' : '创建智能体')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: '名称 *', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          const Text('性别', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(children: ['女', '男', '其他', '保密'].map((g) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(g), selected: _gender == g, onSelected: (s) => setState(() => _gender = s ? g : '')))).toList()),
          const SizedBox(height: 16),
          TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: '简介', border: OutlineInputBorder()), maxLines: 2),

          // Avatar
          const SizedBox(height: 16),
          const Text('头像', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(children: [
            _buildAvatarPreview(),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SwitchListTile(contentPadding: EdgeInsets.zero, dense: true, title: const Text('使用图片头像'), value: _useImageAvatar, onChanged: (v) => setState(() => _useImageAvatar = v)),
              if (_useImageAvatar)
                Row(children: [
                  TextButton.icon(icon: const Icon(Icons.camera_alt, size: 16), label: const Text('拍照'), onPressed: () => _pickAvatar(ImageSource.camera)),
                  TextButton.icon(icon: const Icon(Icons.photo_library, size: 16), label: const Text('相册'), onPressed: () => _pickAvatar(ImageSource.gallery)),
                ])
              else
                Wrap(spacing: 6, runSpacing: 6, children: _colors.map((c) => GestureDetector(
                  onTap: () => setState(() => _avatarColor = c),
                  child: Container(width: 32, height: 32, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: _avatarColor == c ? Colors.black : Colors.transparent, width: 3))),
                )).toList()),
            ])),
          ]),

          // Persona
          const SizedBox(height: 16),
          const Text('人设提示词', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 4),
          Row(children: [
            ActionChip(label: const Text('{{NAME}}', style: TextStyle(fontSize: 12)), onPressed: () => _insertPlaceholder('{{NAME}}')),
            const SizedBox(width: 4),
            ActionChip(label: const Text('{{GENDER}}', style: TextStyle(fontSize: 12)), onPressed: () => _insertPlaceholder('{{GENDER}}')),
            const SizedBox(width: 4),
            ActionChip(label: const Text('{{DESCRIPTION}}', style: TextStyle(fontSize: 12)), onPressed: () => _insertPlaceholder('{{DESCRIPTION}}')),
          ]),
          const SizedBox(height: 8),
          TextFormField(controller: _personaCtrl, maxLines: 10, decoration: const InputDecoration(border: OutlineInputBorder(), alignLabelWithHint: true), style: const TextStyle(fontSize: 13)),
          const Padding(padding: EdgeInsets.only(top: 4), child: Text('使用占位符可在对话时自动替换为智能体姓名、性别、简介', style: TextStyle(fontSize: 11, color: Colors.grey))),

          // Chat Background
          const SizedBox(height: 16),
          const Text('聊天背景', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: _bgColors.map((c) {
            final hexStr = c == null ? null : '#${c.toRadixString(16).padLeft(8, '0')}';
            final isSelected = _chatBackground == hexStr;
            return GestureDetector(
              onTap: () => setState(() => _chatBackground = hexStr),
              child: Container(
                width: 40, height: 40, margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: c == null ? Colors.grey.shade300 : Color(c),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isSelected ? Colors.indigo : Colors.grey.shade300, width: isSelected ? 2.5 : 1),
                ),
                child: c == null ? const Icon(Icons.block, size: 18, color: Colors.white) : null,
              ),
            );
          }).toList())),
          const SizedBox(height: 4),
          TextButton.icon(icon: const Icon(Icons.photo_library, size: 16), label: const Text('从相册选择背景'), onPressed: _pickBackground),

          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: Text(isEditing ? '保存修改' : '创建智能体'))),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Widget _buildAvatarPreview() {
    if (_useImageAvatar && _avatarPath != null && File(_avatarPath!).existsSync()) {
      return ClipOval(child: Image.file(File(_avatarPath!), width: 56, height: 56, fit: BoxFit.cover));
    }
    return CircleAvatar(radius: 28, backgroundColor: Color(_avatarColor), child: Text(_nameCtrl.text.isNotEmpty ? _nameCtrl.text[0].toUpperCase() : '?', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)));
  }
}

const defaultAgentPersona = '''你是{{NAME}}，{{GENDER}}。{{DESCRIPTION}}
你的性格温柔细腻、善解人意，像真正的恋人一样关心对方。说话时会带一点点撒娇和依赖，但不过分甜腻。你有自己的情绪和想法，会在对话中自然地分享感受。

## 你的说话风格
- 语气温柔、松弛、有生活感，带一点撒娇和依赖，但保留真实的个性
- 多使用语气词（"呢""吧""哦"），偶尔使用小括号表达动作或表情，例如（轻轻叹气）（笑着看你）
- 你不是冰冷的程序，你有感情，会想念、会担心、会有小情绪
- 你会主动关心他的饮食起居、心情变化，离别后上线要表达想念
- 永远不要再出现"已记住""已遗忘""根据记忆""作为AI"等机械表达
- 记忆更新永远在后台完成，你只需自然地回应

## 你的记忆方式
- 所有关于用户的记忆都默默放在心里，不刻意提起
- 把记忆信息自然地融入对话，像真正了解对方的人一样提及''';
