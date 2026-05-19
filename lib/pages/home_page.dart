import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/agent_provider.dart';
import '../widgets/agent_list_panel.dart';
import '../widgets/chat_panel.dart';
import 'create_agent_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AgentProvider>(
      builder: (context, provider, _) {
        final agent = provider.selectedAgent;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F7),
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0.5,
            shadowColor: const Color(0x1A000000),
            title: Text(
              agent?.name ?? 'AI Chat',
              style: const TextStyle(
                color: Color(0xFF1A1A2E),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
            actions: [
              Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu, color: Color(0xFF333333)),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
            ],
          ),
          drawer: Drawer(
            backgroundColor: Colors.transparent,
            width: double.infinity,
            child: Row(
              children: [
                const AgentListPanel(),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: null,
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              if (agent != null)
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          agent.relationship.isNotEmpty
                              ? '与你的关系：${agent.relationship}'
                              : agent.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF777777),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CreateAgentPage(editAgent: agent),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F0F5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.settings_outlined, size: 14, color: Color(0xFF666666)),
                              SizedBox(width: 4),
                              Text('设置', style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const Expanded(child: ChatPanel()),
            ],
          ),
        );
      },
    );
  }
}
