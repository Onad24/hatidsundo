// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NotificationModel _$NotificationModelFromJson(Map<String, dynamic> json) =>
    NotificationModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: $enumDecode(_$NotificationTypeEnumMap, json['type']),
      title: json['title'] as String,
      body: json['body'] as String,
      payload: json['payload'] as Map<String, dynamic>? ?? const {},
      read: json['read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] == null
          ? null
          : DateTime.parse(json['read_at'] as String),
    );

Map<String, dynamic> _$NotificationModelToJson(NotificationModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'type': _$NotificationTypeEnumMap[instance.type]!,
      'title': instance.title,
      'body': instance.body,
      'payload': instance.payload,
      'read': instance.read,
      'created_at': instance.createdAt.toIso8601String(),
      'read_at': instance.readAt?.toIso8601String(),
    };

const _$NotificationTypeEnumMap = {
  NotificationType.rideRequest: 'ride_request',
  NotificationType.driverAssigned: 'driver_assigned',
  NotificationType.driverArriving: 'driver_arriving',
  NotificationType.tripStarted: 'trip_started',
  NotificationType.tripCompleted: 'trip_completed',
  NotificationType.feeDueReminder: 'fee_due_reminder',
  NotificationType.adminMessage: 'admin_message',
  NotificationType.chatMessage: 'chat_message',
  NotificationType.accountUpdate: 'account_update',
};
