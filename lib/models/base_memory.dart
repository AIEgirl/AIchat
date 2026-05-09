/// 基础记忆条目
/// type: setting (不可被AI遗忘) | event (AI可遗忘)
class BaseMemory {
  final String id; // B001, B002, ...
  final String type; // setting / event
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  BaseMemory({
    required this.id,
    required this.type,
    required this.content,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isSetting => type == 'setting';
  bool get isEvent => type == 'event';

  BaseMemory copyWith({
    String? id,
    String? type,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BaseMemory(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String toPromptLine() => '$id [$type]: $content';

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'content': content,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory BaseMemory.fromMap(Map<String, dynamic> map) => BaseMemory(
        id: map['id'] as String,
        type: map['type'] as String,
        content: map['content'] as String,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}
