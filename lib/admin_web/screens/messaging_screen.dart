import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../widgets/admin_sidebar.dart';

final recentMessagesProvider = StreamProvider<List<Map<String, dynamic>>>((
  ref,
) {
  final supabase = Supabase.instance.client;
  return supabase
      .from('messages')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(50);
});

class MessagingScreen extends ConsumerWidget {
  const MessagingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentMessages = ref.watch(recentMessagesProvider);

    return Scaffold(
      body: Row(
        children: [
          const AdminSidebar(activeItem: 'Messages'),
          Expanded(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Live Messages Monitor'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ref.refresh(recentMessagesProvider),
                  ),
                ],
              ),
              body: recentMessages.when(
                data: (messages) {
                  if (messages.isEmpty) {
                    return const Center(child: Text('No messages found.'));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      // We only have sender_id.

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.neutral200,
                          child: const Icon(
                            Icons.person,
                            color: AppTheme.neutral600,
                          ),
                        ),
                        title: Text(msg['content'] ?? ''),
                        subtitle: Text(
                          'Trip ID: ${msg['trip_id']}\nSender: ${msg['sender_id']}',
                        ),
                        trailing: Text(
                          msg['created_at'].toString().substring(11, 16),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Error loading messages: $e')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
