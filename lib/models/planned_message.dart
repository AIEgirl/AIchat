class PlannedMessage {
  final int? id;
  final DateTime scheduledTime;
  final String message;
  final bool delivered;

  PlannedMessage({
    this.id,
    required this.scheduledTime,
    required this.message,
    this.delivered = false,
  });

  PlannedMessage copyWith({
    int? id,
    DateTime? scheduledTime,
    String? message,
    bool? delivered,
  }) {
    return PlannedMessage(
      id: id ?? this.id,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      message: message ?? this.message,
      delivered: delivered ?? this.delivered,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'scheduled_time': scheduledTime.millisecondsSinceEpoch,
        'message': message,
        'delivered': delivered ? 1 : 0,
      };

  factory PlannedMessage.fromMap(Map<String, dynamic> map) => PlannedMessage(
        id: map['id'] as int?,
        scheduledTime:
            DateTime.fromMillisecondsSinceEpoch(map['scheduled_time'] as int),
        message: map['message'] as String,
        delivered: (map['delivered'] as int) == 1,
      );
}
