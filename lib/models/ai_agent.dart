class AIAgent {
  final String id;
  String name;
  String? backgroundImagePath;
  String description;
  String relationship;
  int memoryRounds;
  String aiModel;
  String? customInputFormat;
  String? customOutputFormat;
  String apiKey;
  final DateTime createdAt;

  AIAgent({
    required this.id,
    required this.name,
    this.backgroundImagePath,
    this.description = '',
    this.relationship = '',
    this.memoryRounds = 10,
    this.aiModel = 'DeepSeek',
    this.customInputFormat,
    this.customOutputFormat,
    this.apiKey = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  static const List<String> availableModels = [
    'Claude',
    'Gemini',
    'DeepSeek',
    'Kimi',
    'MiniMax',
    'ChatGPT',
    'Doubao',
    'GLM',
    'Custom',
  ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'backgroundImagePath': backgroundImagePath,
        'description': description,
        'relationship': relationship,
        'memoryRounds': memoryRounds,
        'aiModel': aiModel,
        'customInputFormat': customInputFormat,
        'customOutputFormat': customOutputFormat,
        'apiKey': apiKey,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AIAgent.fromJson(Map<String, dynamic> json) => AIAgent(
        id: json['id'] as String,
        name: json['name'] as String,
        backgroundImagePath: json['backgroundImagePath'] as String?,
        description: json['description'] as String? ?? '',
        relationship: json['relationship'] as String? ?? '',
        memoryRounds: json['memoryRounds'] as int? ?? 10,
        aiModel: json['aiModel'] as String? ?? 'DeepSeek',
        customInputFormat: json['customInputFormat'] as String?,
        customOutputFormat: json['customOutputFormat'] as String?,
        apiKey: json['apiKey'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  AIAgent copyWith({
    String? name,
    String? backgroundImagePath,
    String? description,
    String? relationship,
    int? memoryRounds,
    String? aiModel,
    String? customInputFormat,
    String? customOutputFormat,
    String? apiKey,
    bool clearBackgroundImage = false,
  }) =>
      AIAgent(
        id: id,
        name: name ?? this.name,
        backgroundImagePath:
            clearBackgroundImage ? null : backgroundImagePath ?? this.backgroundImagePath,
        description: description ?? this.description,
        relationship: relationship ?? this.relationship,
        memoryRounds: memoryRounds ?? this.memoryRounds,
        aiModel: aiModel ?? this.aiModel,
        customInputFormat: customInputFormat ?? this.customInputFormat,
        customOutputFormat: customOutputFormat ?? this.customOutputFormat,
        apiKey: apiKey ?? this.apiKey,
        createdAt: createdAt,
      );
}
