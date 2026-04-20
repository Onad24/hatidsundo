import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state/state.dart';
import '../../widgets/chat_bubble.dart';

/// Rider chat screen
class ChatScreen extends ConsumerWidget {
  final String tripId;

  const ChatScreen({super.key, required this.tripId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatNotifierProvider(tripId));
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat with Passenger'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: chatState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : chatState.messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    reverse: true,
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      final message = chatState
                          .messages[chatState.messages.length - 1 - index];
                      return ChatBubble(
                        message: message,
                        isCurrentUser: message.senderId == currentUser?.id,
                      );
                    },
                  ),
          ),
          ChatInputField(
            onSend: (text) {
              ref.read(chatNotifierProvider(tripId).notifier).sendMessage(text);
            },
            onLocationPressed: () async {
              final position = await ref.read(currentPositionProvider.future);
              if (position != null) {
                ref
                    .read(chatNotifierProvider(tripId).notifier)
                    .sendLocation(
                      position.latitude,
                      position.longitude,
                      label: 'My current location',
                    );
              }
            },
            isLoading: chatState.isSending,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 64,
            color: AppTheme.neutral300,
          ),
          SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.neutral500,
            ),
          ),
        ],
      ),
    );
  }
}
