class LongTermMemory {
  final String id; // L001, L002, ...
  final String field; // time/location/current_events/characters/relationships/goals/thoughts/status/to_do
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  LongTermMemory({
    required this.id,
    required this.field,
    required this.content,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  LongTermMemory copyWith({
    String? id,
    String? field,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LongTermMemory(
      id: id ?? this.id,
      field: field ?? this.field,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 系统提示词中对长期记忆条目的格式化字符串
  String toPromptLine() => '$id [$field]: $content';

  Map<String, dynamic> toMap() => {
        'id': id,
        'field': field,
        'content': content,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory LongTermMemory.fromMap(Map<String, dynamic> map) => LongTermMemory(
        id: map['id'] as String,
        field: map['field'] as String,
        content: map['content'] as String,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );

  /// 所有支持的有效字段名
  static const validFields = [
    'time',
    'location',
    'current_events',
    'characters',
    'relationships',
    'goals',
    'thoughts',
    'status',
    'to_do',
  ];
}
