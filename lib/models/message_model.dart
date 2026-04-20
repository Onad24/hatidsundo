import 'package:json_annotation/json_annotation.dart';

part 'message_model.g.dart';

/// Sender role for messages
enum SenderRole {
  @JsonValue('client')
  client,
  @JsonValue('rider')
  rider,
  @JsonValue('admin')
  admin,
  @JsonValue('system')
  system,
}

/// Message model for trip chat
@JsonSerializable()
class MessageModel {
  final String id;
  @JsonKey(name: 'trip_id')
  final String tripId;
  @JsonKey(name: 'sender_id')
  final String senderId;
  @JsonKey(name: 'sender_role')
  final SenderRole senderRole;
  final String content;
  @JsonKey(name: 'message_type')
  final String messageType; // text, image, location
  @JsonKey(name: 'metadata')
  final Map<String, dynamic>? metadata;
  @JsonKey(name: 'is_read')
  final bool isRead;
  @JsonKey(name: 'read_at')
  final DateTime? readAt;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  const MessageModel({
    required this.id,
    required this.tripId,
    required this.senderId,
    required this.senderRole,
    required this.content,
    this.messageType = 'text',
    this.metadata,
    this.isRead = false,
    this.readAt,
    required this.createdAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) =>
      _$MessageModelFromJson(json);

  Map<String, dynamic> toJson() => _$MessageModelToJson(this);

  MessageModel copyWith({
    String? id,
    String? tripId,
    String? senderId,
    SenderRole? senderRole,
    String? content,
    String? messageType,
    Map<String, dynamic>? metadata,
    bool? isRead,
    DateTime? readAt,
    DateTime? createdAt,
  }) {
    return MessageModel(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      senderId: senderId ?? this.senderId,
      senderRole: senderRole ?? this.senderRole,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      metadata: metadata ?? this.metadata,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool isReadBy(String userId) {
    if (senderId == userId) return true;
    return isRead;
  }

  bool get isFromClient => senderRole == SenderRole.client;
  bool get isFromRider => senderRole == SenderRole.rider;
  bool get isFromAdmin => senderRole == SenderRole.admin;
  bool get isFromSystem => senderRole == SenderRole.system;
  bool get isTextMessage => messageType == 'text';
  bool get isImageMessage => messageType == 'image';
  bool get isLocationMessage => messageType == 'location';
}
