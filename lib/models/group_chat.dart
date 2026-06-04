import 'package:uuid/uuid.dart';

class GroupChat {
  final String id;
  final String name;
  final String description;
  final int avatarColor;
  final String? groupPersona;
  final String speechMode;
  final int createdAt;
  final int updatedAt;

  GroupChat({
    String? id,
    required this.name,
    this.description = '',
    this.avatarColor = 0xFFE8F5E9,
    this.groupPersona,
    this.speechMode = 'free',
    int? createdAt,
    int? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  GroupChat copyWith({
    String? name,
    String? description,
    int? avatarColor,
    String? groupPersona,
    String? speechMode,
    int? updatedAt,
  }) {
    return GroupChat(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarColor: avatarColor ?? this.avatarColor,
      groupPersona: groupPersona ?? this.groupPersona,
      speechMode: speechMode ?? this.speechMode,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'avatar_color': avatarColor,
        'group_persona': groupPersona,
        'speech_mode': speechMode,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory GroupChat.fromMap(Map<String, dynamic> map) => GroupChat(
        id: map['id'] as String,
        name: map['name'] as String,
        description: (map['description'] as String?) ?? '',
        avatarColor: (map['avatar_color'] as int?) ?? 0xFFE8F5E9,
        groupPersona: map['group_persona'] as String?,
        speechMode: (map['speech_mode'] as String?) ?? 'free',
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
      );
}
