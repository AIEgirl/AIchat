import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ai_agent.dart';
import '../providers/agent_provider.dart';
import '../pages/create_agent_page.dart';

class AgentListPanel extends StatelessWidget {
  const AgentListPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AgentProvider>(
      builder: (context, provider, _) {
        return Container(
          width: MediaQuery.of(context).size.width * 0.78,
          color: Colors.white,
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreateAgentPage()),
                    );
                  },
                  child: provider.hasAgents
                      ? _buildAgentList(context, provider)
                      : _buildEmptyState(),
                ),
              ),
              _buildBottomCreate(context, provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 20,
        bottom: 16,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '我的 AI 智能体',
            style: TextStyle(
              color: Color(0xFF1A1A2E),
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '左滑关闭 · 点击空白处可创建',
            style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentList(BuildContext context, AgentProvider provider) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: provider.agents.length,
      itemBuilder: (context, index) {
        final agent = provider.agents[index];
        final isSelected = index == provider.selectedAgentIndex;
        return _AgentTile(
          agent: agent,
          isSelected: isSelected,
          onTap: () {
            provider.selectAgent(index);
            Navigator.of(context).pop();
          },
          onLongPress: () => _showAgentOptions(context, provider, agent),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF0F0F5),
            ),
            child: const Icon(Icons.smart_toy_outlined, size: 36, color: Color(0xFFCCCCCC)),
          ),
          const SizedBox(height: 16),
          const Text(
            '还没有 AI 智能体',
            style: TextStyle(color: Color(0xFF888888), fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            '点击空白处开始创建',
            style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCreate(BuildContext context, AgentProvider provider) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 12,
        left: 16,
        right: 16,
        top: 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A6CF7),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateAgentPage()),
            );
          },
          icon: const Icon(Icons.add, size: 20),
          label: const Text('创建智能体', style: TextStyle(fontSize: 15)),
        ),
      ),
    );
  }

  void _showAgentOptions(
      BuildContext context, AgentProvider provider, AIAgent agent) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Color(0xFF4A6CF7)),
                title: const Text('编辑', style: TextStyle(color: Color(0xFF1A1A2E))),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CreateAgentPage(editAgent: agent),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('删除', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  provider.deleteAgent(agent.id);
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentTile extends StatelessWidget {
  final AIAgent agent;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _AgentTile({
    required this.agent,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Material(
        color: isSelected ? const Color(0xFFEBF0FF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                _buildAvatar(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agent.name,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF4A6CF7)
                              : const Color(0xFF1A1A2E),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (agent.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          agent.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    agent.aiModel,
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 10),
                  ),
                ),
                if (isSelected)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.check_circle, color: Color(0xFF4A6CF7), size: 18),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final hasImage = agent.backgroundImagePath != null &&
        agent.backgroundImagePath!.isNotEmpty &&
        File(agent.backgroundImagePath!).existsSync();

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFFF0F0F5),
        image: hasImage
            ? DecorationImage(
                image: FileImage(File(agent.backgroundImagePath!)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: hasImage
          ? null
          : Center(
              child: Text(
                agent.name.isNotEmpty ? agent.name[0].toUpperCase() : 'A',
                style: const TextStyle(
                  color: Color(0xFFBBBBBB),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
    );
  }
}
