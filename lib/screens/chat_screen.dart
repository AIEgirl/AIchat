import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../services/database_service.dart';
import '../services/plugin_manager.dart';
import '../l10n/app_localizations.dart';
import 'memory_screen.dart';
import 'plan_screen.dart';
import 'settings_screen.dart';
import '../providers/agent_provider.dart';
import '../providers/memory_provider.dart';
import '../models/agent.dart';
import 'agent_create_screen.dart';
import 'agent_list_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _sendAnimCtrl;
  late final Animation<double> _sendScale;

  @override
  void initState() {
    super.initState();
    _sendAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _sendScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.85), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.0), weight: 1),
    ]).animate(_sendAnimCtrl);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final planService = ref.read(planServiceProvider);
      planService.onPlanTriggered = (message) {
        ref.read(chatProvider.notifier).addSystemMessage(message);
      };
      final notificationService = ref.read(notificationServiceProvider);
      notificationService.onNotificationTapped = (id) {
        ref.read(planServiceProvider).deliverFromNotification(id);
      };
      notificationService.onAiMessageTapped = (payload) {
        if (payload != null && payload.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(payload.length > 100 ? '${payload.substring(0, 100)}...' : payload)),
          );
        }
      };
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _sendAnimCtrl.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _sendAnimCtrl.forward(from: 0);
    ref.read(chatProvider.notifier).sendMessage(text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _onDeleteMessage(ChatMessage message) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.delete_outline, size: 40, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(l10n.get('confirmDelete'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(l10n.get('deleteMessageConfirm'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('cancel')))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () { ref.read(chatProvider.notifier).deleteMessage(message); Navigator.pop(ctx); },
              child: Text(l10n.get('delete')),
            )),
          ]),
        ])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final settings = ref.watch(settingsProvider);
    final model = settings.effectiveModel;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      drawer: _buildDrawer(),
      appBar: AppBar(
        leading: Builder(builder: (ctx) => IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(ctx).openDrawer())),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.get('appTitle'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(model.isNotEmpty ? model : l10n.get('noModel'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(l10n.get('online'), style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ),
          IconButton(icon: const Icon(Icons.bug_report), tooltip: l10n.get('debugLogs'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugLogScreen()))),
          IconButton(icon: const Icon(Icons.storage), tooltip: l10n.get('memoryManagement'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemoryScreen()))),
          IconButton(icon: const Icon(Icons.schedule), tooltip: l10n.get('plannedMessages'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen()))),
        ],
      ),
      body: Builder(builder: (ctx) {
        final agent = ref.watch(agentProvider).currentAgent;
        final bg = agent?.chatBackground;
        Widget body = Column(children: [
          Expanded(
            child: chatState.messages.isEmpty && !chatState.isLoading
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      return _AnimatedBubble(
                        key: ValueKey(chatState.messages[index].dbId ?? chatState.messages[index].timestamp.millisecondsSinceEpoch),
                        message: chatState.messages[index],
                        onDelete: () => _onDeleteMessage(chatState.messages[index]),
                        index: index,
                      );
                    },
                  ),
          ),
          if (chatState.isLoading) const BouncingDotsIndicator(),
          if (chatState.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(chatState.error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          _buildPluginButtons(),
          _buildInputArea(),
        ]);
        if (bg != null) {
          if (bg.startsWith('#')) {
            body = Container(color: Color(int.parse(bg.substring(1), radix: 16) | 0xFF000000), child: body);
          } else if (File(bg).existsSync()) {
            body = Container(decoration: BoxDecoration(image: DecorationImage(image: FileImage(File(bg)), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.white.withAlpha(204), BlendMode.dstATop))), child: body);
          }
        }
        return body;
      }),
    );
  }

  Widget _buildDrawer() {
    final state = ref.watch(agentProvider);
    final current = state.currentAgent;
    return Drawer(
      child: SafeArea(
        child: Column(children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              _agentAvatar(current),
              const SizedBox(height: 8),
              Text(current?.name ?? '无智能体', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (current?.description.isNotEmpty == true) Text(current!.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ]),
          ),
          if (state.agents.length > 1) ...[
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('切换智能体', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600))),
            ...state.agents.map((a) => ListTile(
              leading: _agentAvatar(a, radius: 18, fontSize: 14),
              title: Text(a.name),
              subtitle: a.description.isNotEmpty ? Text(a.description, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
              trailing: a.id == current?.id ? Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)) : null,
            onTap: () {
              if (a.id != current?.id) {
                Navigator.pop(context);
                ref.read(agentProvider.notifier).setActiveAgent(a.id);
                ref.read(memoryServiceProvider).setAgentId(a.id);
                ref.read(memoryServiceProvider).loadShortTermFromDb(ref.read(settingsProvider).maxShortTermRounds);
                ref.read(chatProvider.notifier).reloadChatFromDb();
              }
            },
            )).toList(),
            const Divider(),
          ],
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('创建新智能体'),
            onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentCreateScreen())); },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('管理智能体'),
            onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentListScreen())); },
          ),
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('设置'),
            onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())); },
          ),
        ]),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(l10n.get('startChat'), style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Text(l10n.get('startChatSub'), style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
      ]),
    );
  }

  Widget _agentAvatar(Agent? agent, {double radius = 28, double fontSize = 24}) {
    if (agent?.avatarPath != null && agent!.avatarPath!.isNotEmpty && File(agent.avatarPath!).existsSync()) {
      return ClipOval(child: Image.file(File(agent.avatarPath!), width: radius * 2, height: radius * 2, fit: BoxFit.cover));
    }
    return CircleAvatar(radius: radius, backgroundColor: agent != null ? Color(agent.avatarColor) : Colors.grey, child: Text(agent?.name.isNotEmpty == true ? agent!.name[0] : '?', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)));
  }

  Widget _buildPluginButtons() {
    final buttons = PluginManager.instance.getAllButtons();
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: buttons.map((b) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ActionChip(
            avatar: b.icon != null ? Icon(_resolveIcon(b.icon!), size: 16) : null,
            label: Text(b.label),
            onPressed: () {
              final text = b.onClick();
              if (text.isNotEmpty) {
                _controller.text += _controller.text.isEmpty ? text : '\n$text';
                _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
              }
            },
          ),
        )).toList()),
      ),
    );
  }

  Widget _buildInputArea() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(26), blurRadius: 4, offset: const Offset(0, -1))],
      ),
      child: SafeArea(
        child: Row(children: [
          IconButton(icon: const Icon(Icons.add), tooltip: l10n.get('attachmentMenu'), onPressed: _showAttachmentMenu),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(hintText: l10n.get('typeMessage'), border: InputBorder.none),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ScaleTransition(
            scale: _sendScale,
            child: IconButton(
              icon: Icon(Icons.send_rounded, color: Theme.of(context).colorScheme.primary),
              onPressed: _sendMessage,
            ),
          ),
        ]),
      ),
    );
  }

  IconData _resolveIcon(String name) {
    switch (name) {
      case 'touch_app': return Icons.touch_app;
      case 'favorite': return Icons.favorite;
      case 'star': return Icons.star;
      case 'waving_hand': return Icons.waving_hand;
      case 'thumb_up': return Icons.thumb_up;
      case 'send': return Icons.send;
      case 'mic': return Icons.mic;
      default: return Icons.extension;
    }
  }

  void _showAttachmentMenu() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.cleaning_services), title: Text(l10n.get('clearShortTermMemory')),
              onTap: () { ref.read(chatProvider.notifier).clearChat(); Navigator.pop(ctx); }),
            ListTile(leading: const Icon(Icons.edit_note), title: Text(l10n.get('editLongTermMemory')),
              onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const MemoryScreen())); }),
            ListTile(leading: const Icon(Icons.schedule), title: Text(l10n.get('viewPlannedMessages')),
              onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen())); }),
          ]),
        ),
      ),
    );
  }
}

/// 带入场动画的聊天气泡
class _AnimatedBubble extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback onDelete;
  final int index;

  const _AnimatedBubble({super.key, required this.message, required this.onDelete, required this.index});

  @override
  State<_AnimatedBubble> createState() => _AnimatedBubbleState();
}

class _AnimatedBubbleState extends State<_AnimatedBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final l10n = AppLocalizations.of(context);
    final isUser = message.isUser;
    final alignment = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : Colors.grey.shade100;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: alignment,
            children: [
              if (message.isProactive)
                Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Text(l10n.get('proactiveMessage'), style: const TextStyle(fontSize: 10, color: Colors.deepOrange)),
                ),
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: isUser ? const Radius.circular(18) : const Radius.circular(4),
                    bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(18),
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 4, offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _showActionSheet(context),
                      child: Text(message.content, style: const TextStyle(fontSize: 15)),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Text(
                        DateFormat('HH:mm').format(message.timestamp),
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActionSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isUser = widget.message.isUser;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: Text(l10n.get('copyText')),
            onTap: () {
              Navigator.pop(ctx);
              Clipboard.setData(ClipboardData(text: widget.message.content));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.get('copied')), duration: const Duration(seconds: 1)));
            },
          ),
          if (!isUser && widget.message.toolLogs != null)
            ListTile(
              leading: const Icon(Icons.code),
              title: Text(l10n.get('viewToolCalls')),
              onTap: () {
                Navigator.pop(ctx);
                _showToolLogs(context);
              },
            ),
          if (!isUser && widget.message.toolLogs == null)
            ListTile(
              leading: const Icon(Icons.code, color: Colors.grey),
              title: Text(l10n.get('viewToolCalls'), style: const TextStyle(color: Colors.grey)),
              enabled: false,
            ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: Text(l10n.get('deleteMessage'), style: const TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(ctx);
              widget.onDelete();
            },
          ),
        ]),
      ),
    );
  }

  void _showToolLogs(BuildContext context) {
    if (widget.message.toolLogs == null) return;
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.get('toolCalls'), style: const TextStyle(fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.message.toolLogs!.length,
            itemBuilder: (_, i) {
              final log = widget.message.toolLogs![i];
              final formattedArgs = const JsonEncoder.withIndent('  ').convert(log.arguments);
              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${l10n.get('tool')}: ${log.toolName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('Args:', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 2, bottom: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                      child: Text(formattedArgs, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                    ),
                    Text('Result: ${log.result}', style: const TextStyle(fontSize: 13)),
                  ]),
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.get('close')))],
      ),
    );
  }
}

/// 跳动圆点加载指示器
class BouncingDotsIndicator extends StatefulWidget {
  const BouncingDotsIndicator({super.key});

  @override
  State<BouncingDotsIndicator> createState() => _BouncingDotsIndicatorState();
}

class _BouncingDotsIndicatorState extends State<BouncingDotsIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _dot(0), const SizedBox(width: 6), _dot(1), const SizedBox(width: 6), _dot(2),
      ]),
    );
  }

  Widget _dot(int index) {
    final delay = index * 0.2;
    final anim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 0.5),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 0.5),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Interval(delay, delay + 0.4, curve: Curves.easeInOut)));

    return AnimatedBuilder(
      animation: anim,
      builder: (_, child) => Transform.scale(scale: anim.value, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle))),
    );
  }
}

/// 调试日志页面
class DebugLogScreen extends ConsumerStatefulWidget {
  const DebugLogScreen({super.key});
  @override
  ConsumerState<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends ConsumerState<DebugLogScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final logs = await DatabaseService.getDebugLogs();
    setState(() { _logs = logs; _loading = false; });
  }

  Future<void> _exportLogs() async {
    final sb = StringBuffer();
    sb.writeln('=== AI Chat 调试日志 ===');
    sb.writeln('导出时间: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    sb.writeln('');

    for (final log in _logs) {
      final ts = DateTime.fromMillisecondsSinceEpoch(log['timestamp'] as int);
      sb.writeln('--- ${DateFormat('yyyy-MM-dd HH:mm:ss').format(ts)} ---');
      sb.writeln('请求: ${log['request_summary']}');
      sb.writeln('响应: ${log['response_summary']}');
      if (log['error'] != null) sb.writeln('错误: ${log['error']}');
      sb.writeln('耗时: ${log['duration_ms'] ?? 0}ms');
      sb.writeln('');
    }

    try {
      final dir = await path_provider.getApplicationDocumentsDirectory();
      final file = File('${dir.path}/debug_logs_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.txt');
      await file.writeAsString(sb.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('日志已导出到: ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('debugLogTitle')),
        actions: [
          IconButton(icon: const Icon(Icons.delete_sweep), tooltip: l10n.get('clearLogs'), onPressed: () async {
            await DatabaseService.clearDebugLogs();
            _loadLogs();
          }),
          IconButton(icon: const Icon(Icons.file_download), tooltip: l10n.get('exportLogs'), onPressed: _exportLogs),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? Center(child: Text(l10n.get('noLogs')))
              : ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (_, i) {
                    final log = _logs[i];
                    final ts = DateTime.fromMillisecondsSinceEpoch(log['timestamp'] as int);
                    final hasError = log['error'] != null;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: ExpansionTile(
                        leading: Icon(hasError ? Icons.error : Icons.check_circle, color: hasError ? Colors.red : Colors.green, size: 20),
                        title: Text(DateFormat('MM-dd HH:mm:ss').format(ts), style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                        subtitle: Text('${log['request_summary']} | ${log['response_summary']} | ${log['duration_ms'] ?? 0}ms', style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                        children: [
                          Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('请求: ${log['request_summary']}', style: const TextStyle(fontSize: 12)),
                            Text('响应: ${log['response_summary']}', style: const TextStyle(fontSize: 12)),
                            Text('耗时: ${log['duration_ms'] ?? 0}ms', style: const TextStyle(fontSize: 12)),
                            if (log['error'] != null) Text('错误: ${log['error']}', style: const TextStyle(fontSize: 12, color: Colors.red)),
                          ])),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
