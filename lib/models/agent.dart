import 'package:uuid/uuid.dart';

class Agent {
  final String id;
  final String name;
  final String gender;
  final String description;
  final String persona;
  final int avatarColor;
  final String? avatarPath;
  final String? chatBackground;
  final bool isActive;
  final int createdAt;
  final int updatedAt;

  Agent({
    String? id,
    required this.name,
    this.gender = '',
    this.description = '',
    required this.persona,
    this.avatarColor = 0xFFE8F5E9,
    this.avatarPath,
    this.chatBackground,
    this.isActive = false,
    int? createdAt,
    int? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  Agent copyWith({
    String? id, String? name, String? gender, String? description, String? persona,
    int? avatarColor, String? avatarPath, String? chatBackground,
    bool? isActive, int? createdAt, int? updatedAt,
  }) {
    return Agent(
      id: id ?? this.id, name: name ?? this.name, gender: gender ?? this.gender,
      description: description ?? this.description, persona: persona ?? this.persona,
      avatarColor: avatarColor ?? this.avatarColor, avatarPath: avatarPath ?? this.avatarPath,
      chatBackground: chatBackground ?? this.chatBackground,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'gender': gender, 'description': description,
    'persona': persona, 'avatar_color': avatarColor,
    'avatar_path': avatarPath, 'chat_background': chatBackground,
    'is_active': isActive ? 1 : 0, 'created_at': createdAt, 'updated_at': updatedAt,
  };

  factory Agent.fromMap(Map<String, dynamic> map) => Agent(
    id: map['id'] as String, name: map['name'] as String,
    gender: map['gender'] as String? ?? '', description: map['description'] as String? ?? '',
    persona: map['persona'] as String, avatarColor: map['avatar_color'] as int? ?? 0xFFE8F5E9,
    avatarPath: map['avatar_path'] as String?,
    chatBackground: map['chat_background'] as String?,
    isActive: (map['is_active'] as int?) == 1,
    createdAt: map['created_at'] as int, updatedAt: map['updated_at'] as int,
  );
}
