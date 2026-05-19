import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ai_agent.dart';
import '../models/chat_message.dart';
import '../providers/agent_provider.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  int _lastMessageCount = 0;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AgentProvider>(
      builder: (context, provider, _) {
        if (!provider.hasSelectedAgent) {
          return _buildEmptyChat();
        }
        return _buildChatView(context, provider);
      },
    );
  }

  Widget _buildEmptyChat() {
    return Container(
      color: const Color(0xFFF5F5F7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEEEEEE),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4A6CF7).withAlpha(25),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(Icons.chat_bubble_outline, size: 44, color: Color(0xFFCCCCCC)),
            ),
            const SizedBox(height: 28),
            const Text(
              'AI Chat',
              style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 22,
                fontWeight: FontWeight.w300,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '从左侧滑动选择 AI 智能体开始聊天',
              style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatView(BuildContext context, AgentProvider provider) {
    final agent = provider.selectedAgent!;
    final messages = provider.currentMessages;

    if (messages.length > _lastMessageCount) {
      _scrollToBottom();
    }
    _lastMessageCount = messages.length;

    return GestureDetector(
      onTap: () => _focusNode.unfocus(),
      child: Container(
        color: const Color(0xFFF5F5F7),
        child: Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? _buildWelcomeMessage(agent)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        return _MessageBubble(message: msg, agent: agent);
                      },
                    ),
            ),
            _buildInputBar(context, provider),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeMessage(AIAgent agent) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AgentAvatar(agent: agent, size: 72),
            const SizedBox(height: 16),
            Text(
              agent.name,
              style: const TextStyle(
                color: Color(0xFF1A1A2E),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (agent.relationship.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                agent.relationship,
                style: const TextStyle(color: Color(0xFF999999), fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF000000).withAlpha(6),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                agent.description.isNotEmpty ? agent.description : '开始和${agent.name}对话吧',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF777777),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(BuildContext context, AgentProvider provider) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: const Color(0xFF000000).withAlpha(10))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _focusNode,
                style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 15),
                decoration: const InputDecoration(
                  hintText: '输入消息...',
                  hintStyle: TextStyle(color: Color(0xFFBBBBBB)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onSubmitted: (text) => _sendMessage(provider),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF4A6CF7),
              borderRadius: BorderRadius.circular(24),
            ),
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: () => _sendMessage(provider),
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage(AgentProvider provider) {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    provider.sendMessage(text);
    _scrollToBottom();
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final AIAgent agent;

  const _MessageBubble({required this.message, required this.agent});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            _AgentAvatar(agent: agent, size: 32),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF4A6CF7) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF000000).withAlpha(isUser ? 10 : 6),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isUser ? Colors.white : const Color(0xFF1A1A2E),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEBF0FF),
              ),
              child: const Icon(Icons.person, size: 18, color: Color(0xFF4A6CF7)),
            ),
          ],
        ],
      ),
    );
  }
}

class _AgentAvatar extends StatelessWidget {
  final AIAgent agent;
  final double size;

  const _AgentAvatar({required this.agent, required this.size});

  @override
  Widget build(BuildContext context) {
    final hasImage = agent.backgroundImagePath != null &&
        agent.backgroundImagePath!.isNotEmpty &&
        File(agent.backgroundImagePath!).existsSync();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
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
                style: TextStyle(
                  color: const Color(0xFFBBBBBB),
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
    );
  }
}
