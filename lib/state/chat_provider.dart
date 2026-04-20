import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message_model.dart';
import '../services/chat_service.dart';
import 'auth_provider.dart';

/// Chat state
class ChatState {
  final List<MessageModel> messages;
  final bool isLoading;
  final bool isSending;
  final String? error;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
  });

  ChatState copyWith({
    List<MessageModel>? messages,
    bool? isLoading,
    bool? isSending,
    String? error,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: error,
    );
  }
}

/// Chat notifier for a specific trip
class ChatNotifier extends StateNotifier<ChatState> {
  final ChatService _chatService;
  final String _tripId;
  final String? _userId;
  final SenderRole _senderRole;
  StreamSubscription? _messageSubscription;
  Timer? _pollTimer;

  ChatNotifier(this._chatService, this._tripId, this._userId, this._senderRole)
    : super(const ChatState()) {
    _loadMessages();
    _subscribeToMessages();
    _startPolling();
  }

  Future<void> _loadMessages() async {
    state = state.copyWith(isLoading: true);
    try {
      final messages = await _chatService.getMessages(_tripId);
      if (!mounted) return;
      state = state.copyWith(messages: messages, isLoading: false);

      // Mark as read
      if (_userId != null) {
        await _chatService.markAsRead(_tripId, _userId);
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  void _subscribeToMessages() {
    _messageSubscription = _chatService.subscribeToMessages(_tripId).listen((
      message,
    ) {
      if (!mounted) return;
      // Add message if not already in list
      if (!state.messages.any((m) => m.id == message.id)) {
        state = state.copyWith(messages: [...state.messages, message]);
      }

      // Mark as read
      if (_userId != null && message.senderId != _userId) {
        _chatService.markAsRead(_tripId, _userId);
      }
    });
  }

  /// Poll for new messages every 3 seconds as a fallback
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      try {
        final messages = await _chatService.getMessages(_tripId);
        if (!mounted) return;

        // Only update if there are new messages
        if (messages.length != state.messages.length) {
          state = state.copyWith(messages: messages);

          // Mark as read
          if (_userId != null) {
            await _chatService.markAsRead(_tripId, _userId);
          }
        }
      } catch (e) {
        print('DEBUG: Chat poll error: $e');
      }
    });
  }

  /// Send a text message
  Future<void> sendMessage(String content) async {
    if (_userId == null || content.trim().isEmpty) return;

    state = state.copyWith(isSending: true);
    try {
      final message = await _chatService.sendMessage(
        tripId: _tripId,
        senderId: _userId,
        senderRole: _senderRole,
        content: content.trim(),
      );

      if (!mounted) return;

      // Add to local state immediately (might also come from subscription)
      if (!state.messages.any((m) => m.id == message.id)) {
        state = state.copyWith(
          messages: [...state.messages, message],
          isSending: false,
        );
      } else {
        state = state.copyWith(isSending: false);
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(error: e.toString(), isSending: false);
    }
  }

  /// Send location
  Future<void> sendLocation(double lat, double lng, {String? label}) async {
    if (_userId == null) return;

    state = state.copyWith(isSending: true);
    try {
      await _chatService.sendLocationMessage(
        tripId: _tripId,
        senderId: _userId,
        senderRole: _senderRole,
        lat: lat,
        lng: lng,
        label: label,
      );
      if (!mounted) return;
      state = state.copyWith(isSending: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(error: e.toString(), isSending: false);
    }
  }

  /// Refresh messages
  Future<void> refresh() async {
    await _loadMessages();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }
}

/// Chat notifier provider factory
final chatNotifierProvider =
    StateNotifierProvider.family<ChatNotifier, ChatState, String>((
      ref,
      tripId,
    ) {
      final chatService = ref.watch(chatServiceProvider);
      final user = ref.watch(currentUserProvider);

      final senderRole = user?.isRider == true
          ? SenderRole.rider
          : user?.isAdmin == true
          ? SenderRole.admin
          : SenderRole.client;

      return ChatNotifier(chatService, tripId, user?.id, senderRole);
    });

/// Unread count provider
final unreadCountProvider = FutureProvider.family<int, String>((
  ref,
  tripId,
) async {
  final chatService = ref.watch(chatServiceProvider);
  final user = ref.watch(currentUserProvider);

  if (user == null) return 0;
  return chatService.getUnreadCount(tripId, user.id);
});
