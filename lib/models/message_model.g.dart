// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MessageModel _$MessageModelFromJson(Map<String, dynamic> json) => MessageModel(
  id: json['id'] as String,
  tripId: json['trip_id'] as String,
  senderId: json['sender_id'] as String,
  senderRole: $enumDecode(_$SenderRoleEnumMap, json['sender_role']),
  content: json['content'] as String,
  messageType: json['message_type'] as String? ?? 'text',
  metadata: json['metadata'] as Map<String, dynamic>?,
  isRead: json['is_read'] as bool? ?? false,
  readAt: json['read_at'] == null
      ? null
      : DateTime.parse(json['read_at'] as String),
  createdAt: DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$MessageModelToJson(MessageModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trip_id': instance.tripId,
      'sender_id': instance.senderId,
      'sender_role': _$SenderRoleEnumMap[instance.senderRole]!,
      'content': instance.content,
      'message_type': instance.messageType,
      'metadata': instance.metadata,
      'is_read': instance.isRead,
      'read_at': instance.readAt?.toIso8601String(),
      'created_at': instance.createdAt.toIso8601String(),
    };

const _$SenderRoleEnumMap = {
  SenderRole.client: 'client',
  SenderRole.rider: 'rider',
  SenderRole.admin: 'admin',
  SenderRole.system: 'system',
};
