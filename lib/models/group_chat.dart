import 'package:uuid/uuid.dart';

class GroupChat {
  final String id;
  final String name;
  final String description;
  final int avatarColor;
  final String? groupPersona;
  final String speechMode;
  final bool isSimulatorMode;
  final String? worldSetting;
  final int createdAt;
  final int updatedAt;

  GroupChat({
    String? id,
    required this.name,
    this.description = '',
    this.avatarColor = 0xFFE8F5E9,
    this.groupPersona,
    this.speechMode = 'free',
    this.isSimulatorMode = false,
    this.worldSetting,
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
    bool? isSimulatorMode,
    String? worldSetting,
    int? updatedAt,
  }) {
    return GroupChat(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarColor: avatarColor ?? this.avatarColor,
      groupPersona: groupPersona ?? this.groupPersona,
      speechMode: speechMode ?? this.speechMode,
      isSimulatorMode: isSimulatorMode ?? this.isSimulatorMode,
      worldSetting: worldSetting ?? this.worldSetting,
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
        'simulator_mode': isSimulatorMode ? 1 : 0,
        'world_setting': worldSetting,
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
        isSimulatorMode: (map['simulator_mode'] as int?) == 1,
        worldSetting: map['world_setting'] as String?,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
      );
}
