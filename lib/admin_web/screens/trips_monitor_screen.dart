import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../widgets/admin_sidebar.dart';

final activeTripsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final supabase = Supabase.instance.client;
  return supabase
      .from('trips')
      .stream(primaryKey: ['id'])
      .eq('status', 'in_progress')
      .order('created_at', ascending: false);
});

class TripsMonitorScreen extends ConsumerWidget {
  const TripsMonitorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTrips = ref.watch(activeTripsProvider);

    return Scaffold(
      body: Row(
        children: [
          const AdminSidebar(activeItem: 'Active Trips'),
          Expanded(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Active Trips Monitor'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ref.refresh(activeTripsProvider),
                  ),
                ],
              ),
              body: activeTrips.when(
                data: (trips) {
                  if (trips.isEmpty) {
                    return const Center(
                      child: Text('No active trips currently.'),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: trips.length,
                    itemBuilder: (context, index) {
                      final trip = trips[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.directions_car),
                          ),
                          title: Text(
                            'Trip ${trip['id'].toString().substring(0, 8)}...',
                          ),
                          subtitle: Text(
                            'Status: ${trip['status']}\nPickup: ${trip['pickup_address'] ?? 'Unknown'}\nDropoff: ${trip['dest_address'] ?? 'Unknown'}',
                          ),
                          isThreeLine: true,
                          trailing: Chip(
                            label: Text(
                              trip['status'].toString().toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                            backgroundColor: AppTheme.primaryColor,
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error loading trips: $e')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
