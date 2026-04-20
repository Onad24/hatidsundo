import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../models/message_model.dart';
import 'supabase_service.dart';

/// Chat service for trip-scoped messaging
class ChatService {
  final SupabaseService _supabaseService;
  final Uuid _uuid = const Uuid();

  ChatService(this._supabaseService);

  /// Send a message
  Future<MessageModel> sendMessage({
    required String tripId,
    required String senderId,
    required SenderRole senderRole,
    required String content,
    String messageType = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    final messageData = {
      'id': _uuid.v4(),
      'trip_id': tripId,
      'sender_id': senderId,
      'sender_role': senderRole.name,
      'content': content,
      'message_type': messageType,
      'metadata': metadata,
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    };

    final result = await _supabaseService
        .from(AppConstants.messagesTable)
        .insert(messageData)
        .select()
        .single();

    return MessageModel.fromJson(result);
  }

  /// Send location message
  Future<MessageModel> sendLocationMessage({
    required String tripId,
    required String senderId,
    required SenderRole senderRole,
    required double lat,
    required double lng,
    String? label,
  }) async {
    return sendMessage(
      tripId: tripId,
      senderId: senderId,
      senderRole: senderRole,
      content: label ?? 'Shared location',
      messageType: 'location',
      metadata: {'lat': lat, 'lng': lng},
    );
  }

  /// Get messages for a trip
  Future<List<MessageModel>> getMessages(
    String tripId, {
    int limit = 50,
    String? beforeId,
  }) async {
    var query = _supabaseService
        .from(AppConstants.messagesTable)
        .select()
        .eq('trip_id', tripId)
        .order('created_at', ascending: false)
        .limit(limit);

    final result = await query;
    return (result as List)
        .map((j) => MessageModel.fromJson(j))
        .toList()
        .reversed
        .toList();
  }

  /// Mark messages as read
  Future<void> markAsRead(String tripId, String userId) async {
    await _supabaseService.client
        .from(AppConstants.messagesTable)
        .update({'is_read': true, 'read_at': DateTime.now().toIso8601String()})
        .eq('trip_id', tripId)
        .neq('sender_id', userId)
        .eq('is_read', false);
  }

  /// Get unread count
  Future<int> getUnreadCount(String tripId, String userId) async {
    final response = await _supabaseService.client
        .from(AppConstants.messagesTable)
        .select('id')
        .eq('trip_id', tripId)
        .neq('sender_id', userId)
        .eq('is_read', false);

    return (response as List).length;
  }

  /// Subscribe to new messages using Postgres Changes (Realtime).
  /// This is far more reliable than Broadcast because it uses the WAL
  /// and doesn't require the sender to manually relay the message.
  Stream<MessageModel> subscribeToMessages(String tripId) {
    final controller = StreamController<MessageModel>.broadcast();

    final channelName =
        'chat_${tripId}_${DateTime.now().millisecondsSinceEpoch}';
    final channel = _supabaseService
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: AppConstants.messagesTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'trip_id',
            value: tripId,
          ),
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              try {
                final message = MessageModel.fromJson(payload.newRecord);
                print(
                  'DEBUG: Realtime chat message received: ${message.content}',
                );
                controller.add(message);
              } catch (e) {
                print('DEBUG: Error parsing realtime chat message: $e');
              }
            }
          },
        )
        .subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
    };

    return controller.stream;
  }

  /// Admin: Get all messages for monitoring
  Future<List<MessageModel>> getAllMessagesForTrip(String tripId) async {
    final result = await _supabaseService
        .from(AppConstants.messagesTable)
        .select()
        .eq('trip_id', tripId)
        .order('created_at');

    return (result as List).map((j) => MessageModel.fromJson(j)).toList();
  }

  /// Admin: Send message as admin
  Future<MessageModel> sendAdminMessage({
    required String tripId,
    required String adminId,
    required String content,
  }) async {
    return sendMessage(
      tripId: tripId,
      senderId: adminId,
      senderRole: SenderRole.admin,
      content: content,
    );
  }

  /// Admin: Mute a user (prevent them from sending messages)
  Future<void> muteUser(String tripId, String userId) async {
    await _supabaseService.from('muted_users').insert({
      'trip_id': tripId,
      'user_id': userId,
      'muted_at': DateTime.now().toIso8601String(),
    });
  }

  /// Admin: Unmute a user
  Future<void> unmuteUser(String tripId, String userId) async {
    await _supabaseService
        .from('muted_users')
        .delete()
        .eq('trip_id', tripId)
        .eq('user_id', userId);
  }
}

/// Chat service provider
final chatServiceProvider = Provider<ChatService>((ref) {
  final supabaseService = ref.watch(supabaseServiceProvider);
  return ChatService(supabaseService);
});
