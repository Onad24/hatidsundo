import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/message_model.dart';
import 'package:intl/intl.dart';

/// Chat bubble widget
class ChatBubble extends StatelessWidget {
  final MessageModel message;
  final bool isCurrentUser;
  final String? senderName;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isCurrentUser,
    this.senderName,
  });

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('h:mm a');

    return Padding(
      padding: EdgeInsets.only(
        left: isCurrentUser ? 48 : 16,
        right: isCurrentUser ? 16 : 48,
        top: 4,
        bottom: 4,
      ),
      child: Column(
        crossAxisAlignment: isCurrentUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Sender name for admin/system messages
          if (!isCurrentUser && (message.isFromAdmin || message.isFromSystem))
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                message.isFromAdmin ? 'Admin' : 'System',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: message.isFromAdmin
                      ? AppTheme.primaryColor
                      : AppTheme.neutral500,
                ),
              ),
            ),

          // Bubble
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _getBubbleColor(),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isCurrentUser ? 16 : 4),
                bottomRight: Radius.circular(isCurrentUser ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Content based on type
                if (message.isTextMessage)
                  Text(
                    message.content,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 15,
                      color: isCurrentUser ? Colors.white : AppTheme.neutral800,
                    ),
                  )
                else if (message.isLocationMessage)
                  _buildLocationContent()
                else
                  Text(
                    message.content,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 15,
                      color: isCurrentUser ? Colors.white : AppTheme.neutral800,
                    ),
                  ),

                // Timestamp
                const SizedBox(height: 4),
                Text(
                  timeFormat.format(message.createdAt),
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 10,
                    color: isCurrentUser
                        ? Colors.white.withValues(alpha: 0.7)
                        : AppTheme.neutral400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getBubbleColor() {
    if (isCurrentUser) {
      return AppTheme.primaryColor;
    }
    if (message.isFromAdmin) {
      return AppTheme.primaryColor.withValues(alpha: 0.1);
    }
    if (message.isFromSystem) {
      return AppTheme.neutral200;
    }
    return Colors.white;
  }

  Widget _buildLocationContent() {
    final lat = message.metadata?['lat'] as double?;
    final lng = message.metadata?['lng'] as double?;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isCurrentUser
                ? Colors.white.withValues(alpha: 0.2)
                : AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.location_on_rounded,
            color: isCurrentUser ? Colors.white : AppTheme.primaryColor,
            size: 24,
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isCurrentUser ? Colors.white : AppTheme.neutral800,
              ),
            ),
            if (lat != null && lng != null)
              Text(
                '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 11,
                  color: isCurrentUser
                      ? Colors.white.withValues(alpha: 0.7)
                      : AppTheme.neutral500,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Chat input field
class ChatInputField extends StatefulWidget {
  final Function(String) onSend;
  final VoidCallback? onLocationPressed;
  final bool isLoading;

  const ChatInputField({
    super.key,
    required this.onSend,
    this.onLocationPressed,
    this.isLoading = false,
  });

  @override
  State<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<ChatInputField> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    widget.onSend(text);
    _controller.clear();
    setState(() => _hasText = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Location button
            if (widget.onLocationPressed != null)
              IconButton(
                onPressed: widget.onLocationPressed,
                icon: const Icon(Icons.location_on_outlined),
                color: AppTheme.neutral500,
              ),

            // Text field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.neutral100,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _controller,
                  onChanged: (value) {
                    setState(() => _hasText = value.trim().isNotEmpty);
                  },
                  onSubmitted: (_) => _handleSend(),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  textInputAction: TextInputAction.send,
                  maxLines: 4,
                  minLines: 1,
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Send button
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _hasText ? AppTheme.primaryColor : AppTheme.neutral200,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: widget.isLoading
                    ? null
                    : (_hasText ? _handleSend : null),
                icon: widget.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        Icons.send_rounded,
                        color: _hasText ? Colors.white : AppTheme.neutral400,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
