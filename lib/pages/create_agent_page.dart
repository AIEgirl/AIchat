import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/ai_agent.dart';
import '../providers/agent_provider.dart';

class CreateAgentPage extends StatefulWidget {
  final AIAgent? editAgent;

  const CreateAgentPage({super.key, this.editAgent});

  @override
  State<CreateAgentPage> createState() => _CreateAgentPageState();
}

class _CreateAgentPageState extends State<CreateAgentPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final Uuid _uuid = const Uuid();

  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _relationshipController;
  late TextEditingController _customInputController;
  late TextEditingController _customOutputController;
  late TextEditingController _apiKeyController;
  late int _memoryRounds;
  late String _selectedModel;
  String? _backgroundImagePath;
  bool _isCustomModel = false;
  bool _obscureApiKey = true;

  bool get isEditing => widget.editAgent != null;

  @override
  void initState() {
    super.initState();
    final agent = widget.editAgent;
    _nameController = TextEditingController(text: agent?.name ?? '');
    _descriptionController = TextEditingController(text: agent?.description ?? '');
    _relationshipController = TextEditingController(text: agent?.relationship ?? '');
    _customInputController = TextEditingController(text: agent?.customInputFormat ?? '');
    _customOutputController = TextEditingController(text: agent?.customOutputFormat ?? '');
    _apiKeyController = TextEditingController(text: agent?.apiKey ?? '');
    _memoryRounds = agent?.memoryRounds ?? 10;
    _selectedModel = agent?.aiModel ?? 'DeepSeek';
    _backgroundImagePath = agent?.backgroundImagePath;
    _isCustomModel = _selectedModel == 'Custom';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _relationshipController.dispose();
    _customInputController.dispose();
    _customOutputController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (image != null) {
      setState(() => _backgroundImagePath = image.path);
    }
  }

  void _removeImage() {
    setState(() => _backgroundImagePath = null);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<AgentProvider>();

    if (_selectedModel == 'Custom') {
      if (_customInputController.text.trim().isEmpty ||
          _customOutputController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('自定义模式下需要填写输入和输出格式')),
        );
        return;
      }
    }

    if (isEditing) {
      final updated = widget.editAgent!.copyWith(
        name: _nameController.text.trim(),
        backgroundImagePath: _backgroundImagePath,
        description: _descriptionController.text.trim(),
        relationship: _relationshipController.text.trim(),
        memoryRounds: _memoryRounds,
        aiModel: _selectedModel,
        customInputFormat: _isCustomModel ? _customInputController.text.trim() : null,
        customOutputFormat: _isCustomModel ? _customOutputController.text.trim() : null,
        apiKey: _apiKeyController.text.trim(),
        clearBackgroundImage: _backgroundImagePath == null,
      );
      provider.updateAgent(widget.editAgent!.id, updated);
    } else {
      final agent = AIAgent(
        id: _uuid.v4(),
        name: _nameController.text.trim(),
        backgroundImagePath: _backgroundImagePath,
        description: _descriptionController.text.trim(),
        relationship: _relationshipController.text.trim(),
        memoryRounds: _memoryRounds,
        aiModel: _selectedModel,
        customInputFormat: _isCustomModel ? _customInputController.text.trim() : null,
        customOutputFormat: _isCustomModel ? _customOutputController.text.trim() : null,
        apiKey: _apiKeyController.text.trim(),
      );
      provider.addAgent(agent);
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text(isEditing ? '编辑智能体' : '创建 AI 智能体'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0.5,
        shadowColor: const Color(0x1A000000),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存', style: TextStyle(color: Color(0xFF4A6CF7), fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            _buildImagePicker(),
            const SizedBox(height: 28),
            _buildSectionTitle('基本信息'),
            const SizedBox(height: 12),
            _buildNameField(),
            const SizedBox(height: 14),
            _buildDescriptionField(),
            const SizedBox(height: 14),
            _buildRelationshipField(),
            const SizedBox(height: 28),
            _buildSectionTitle('模型配置'),
            const SizedBox(height: 12),
            _buildModelSelector(),
            const SizedBox(height: 14),
            _buildApiKeyField(),
            if (_isCustomModel) ...[
              const SizedBox(height: 14),
              _buildCustomFormatFields(),
            ],
            const SizedBox(height: 14),
            _buildMemoryRounds(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF888888),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildImagePicker() {
    final hasImage = _backgroundImagePath != null &&
        _backgroundImagePath!.isNotEmpty &&
        File(_backgroundImagePath!).existsSync();

    return GestureDetector(
      onTap: _pickImage,
      child: Center(
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.white,
            image: hasImage
                ? DecorationImage(
                    image: FileImage(File(_backgroundImagePath!)),
                    fit: BoxFit.cover,
                  )
                : null,
            border: hasImage
                ? null
                : Border.all(color: const Color(0xFFDDDDDD), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withAlpha(8),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              if (!hasImage)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, color: Color(0xFFBBBBBB), size: 32),
                      SizedBox(height: 6),
                      Text(
                        '设置背景图',
                        style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              if (hasImage)
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: _removeImage,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Color(0xAA000000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 14),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return _StyledTextField(
      controller: _nameController,
      label: '名称',
      hint: '给你的 AI 起个名字',
      icon: Icons.smart_toy_outlined,
      validator: (v) => (v == null || v.trim().isEmpty) ? '请输入名称' : null,
    );
  }

  Widget _buildDescriptionField() {
    return _StyledTextField(
      controller: _descriptionController,
      label: '简介（AI 设定）',
      hint: '描述 AI 的性格、能力、背景等',
      icon: Icons.description_outlined,
      maxLines: 4,
    );
  }

  Widget _buildRelationshipField() {
    return _StyledTextField(
      controller: _relationshipController,
      label: '与用户的关系',
      hint: '例如：知心好友、工作助手、灵魂伴侣',
      icon: Icons.favorite_border,
    );
  }

  Widget _buildModelSelector() {
    return _StyledCard(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedModel,
          isExpanded: true,
          dropdownColor: Colors.white,
          icon: const Icon(Icons.expand_more, color: Color(0xFF888888)),
          style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 15),
          items: AIAgent.availableModels.map((model) {
            return DropdownMenuItem(
              value: model,
              child: Text(model),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedModel = value!;
              _isCustomModel = value == 'Custom';
            });
          },
        ),
      ),
    );
  }

  Widget _buildApiKeyField() {
    return _StyledCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.vpn_key_outlined, size: 16, color: Color(0xFF888888)),
              const SizedBox(width: 6),
              Text(
                '$_selectedModel API Key',
                style: TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _apiKeyController,
                  obscureText: _obscureApiKey,
                  style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: '输入 API Key（选填）',
                    hintStyle: TextStyle(color: Color(0xFFCCCCCC), fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _obscureApiKey = !_obscureApiKey),
                child: Icon(
                  _obscureApiKey ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 18,
                  color: const Color(0xFFBBBBBB),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomFormatFields() {
    return Column(
      children: [
        _StyledTextField(
          controller: _customInputController,
          label: '自定义输入格式',
          hint: '例如：{"role": "user", "content": "..."}',
          icon: Icons.input,
          maxLines: 2,
        ),
        const SizedBox(height: 14),
        _StyledTextField(
          controller: _customOutputController,
          label: '自定义输出格式',
          hint: '例如：{"role": "assistant", "content": "..."}',
          icon: Icons.output,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildMemoryRounds() {
    return _StyledCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.memory, color: Color(0xFF888888), size: 18),
              const SizedBox(width: 8),
              const Text(
                '记忆轮数',
                style: TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEBF0FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_memoryRounds 轮',
                  style: const TextStyle(
                    color: Color(0xFF4A6CF7),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: const SliderThemeData(
              activeTrackColor: Color(0xFF4A6CF7),
              inactiveTrackColor: Color(0xFFEEEEEE),
              thumbColor: Color(0xFF4A6CF7),
              overlayColor: Color(0x1A4A6CF7),
            ),
            child: Slider(
              value: _memoryRounds.toDouble(),
              min: 1,
              max: 50,
              divisions: 49,
              onChanged: (v) => setState(() => _memoryRounds = v.round()),
            ),
          ),
          const Text(
            'AI 会记住最近设定的对话轮数',
            style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final String? Function(String?)? validator;

  const _StyledTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return _StyledCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF888888)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 14),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
            validator: validator,
          ),
        ],
      ),
    );
  }
}

class _StyledCard extends StatelessWidget {
  final Widget child;

  const _StyledCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withAlpha(6),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}
