class ShortTermMessage {
  final String id;
  final String role;
  final String content;
  final String? agentId;
  final DateTime timestamp;

  ShortTermMessage({required this.id, required this.role, required this.content, this.agentId, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {'id': id, 'role': role, 'content': content};
  Map<String, dynamic> toMap() => {'id': id, 'role': role, 'content': content, 'agent_id': agentId, 'timestamp': timestamp.millisecondsSinceEpoch};

  factory ShortTermMessage.fromMap(Map<String, dynamic> map) => ShortTermMessage(
    id: map['id'] as String, role: map['role'] as String, content: map['content'] as String,
    agentId: map['agent_id'] as String?,
    timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
  );

  Map<String, dynamic> toOpenAiMessage() => {'role': role, 'content': content};
}
