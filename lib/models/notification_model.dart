import 'package:json_annotation/json_annotation.dart';

part 'notification_model.g.dart';

/// Notification types
enum NotificationType {
  @JsonValue('ride_request')
  rideRequest,
  @JsonValue('driver_assigned')
  driverAssigned,
  @JsonValue('driver_arriving')
  driverArriving,
  @JsonValue('trip_started')
  tripStarted,
  @JsonValue('trip_completed')
  tripCompleted,
  @JsonValue('fee_due_reminder')
  feeDueReminder,
  @JsonValue('admin_message')
  adminMessage,
  @JsonValue('chat_message')
  chatMessage,
  @JsonValue('account_update')
  accountUpdate,
}

/// Push notification model
@JsonSerializable()
class NotificationModel {
  final String id;
  @JsonKey(name: 'user_id')
  final String userId;
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final bool read;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'read_at')
  final DateTime? readAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.payload = const {},
    this.read = false,
    required this.createdAt,
    this.readAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) =>
      _$NotificationModelFromJson(json);

  Map<String, dynamic> toJson() => _$NotificationModelToJson(this);

  NotificationModel copyWith({
    String? id,
    String? userId,
    NotificationType? type,
    String? title,
    String? body,
    Map<String, dynamic>? payload,
    bool? read,
    DateTime? createdAt,
    DateTime? readAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      payload: payload ?? this.payload,
      read: read ?? this.read,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  bool get isUnread => !read;
}
