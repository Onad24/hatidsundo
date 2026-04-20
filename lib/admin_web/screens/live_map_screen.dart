import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/driver_location_model.dart';
import '../../widgets/map_widget.dart';
import '../widgets/admin_sidebar.dart';

final activeDriversProvider = StreamProvider<List<DriverLocationModel>>((ref) {
  final supabase = Supabase.instance.client;
  return supabase
      .from('driver_locations')
      .stream(primaryKey: ['driver_id'])
      .map(
        (data) =>
            data.map((json) => DriverLocationModel.fromJson(json)).toList(),
      );
});

class LiveMapScreen extends ConsumerWidget {
  const LiveMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeDrivers = ref.watch(activeDriversProvider);

    return Scaffold(
      body: Row(
        children: [
          const AdminSidebar(activeItem: 'Live Map'),
          Expanded(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Live Map - Active Drivers'),
                automaticallyImplyLeading: false,
              ),
              body: activeDrivers.when(
                data: (drivers) {
                  // On web, maplibre_gl may not work — show a list fallback
                  if (kIsWeb) {
                    return _buildWebFallback(drivers);
                  }
                  return AppMapWidget(
                    initialCenter: const LatLng(
                      14.5995,
                      120.9842,
                    ), // Manila default
                    initialZoom: 12.0,
                    showUserLocation: false,
                    drivers: drivers,
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error loading map: $e')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebFallback(List<DriverLocationModel> drivers) {
    if (drivers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No active drivers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              'Drivers will appear here when they go online',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${drivers.length} active driver(s)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: drivers.length,
            itemBuilder: (context, index) {
              final driver = drivers[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: driver.isAvailable
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    child: Icon(
                      Icons.local_taxi,
                      color: driver.isAvailable ? Colors.green : Colors.orange,
                    ),
                  ),
                  title: Text('Driver ${driver.driverId.substring(0, 8)}...'),
                  subtitle: Text(
                    'Lat: ${driver.lat.toStringAsFixed(4)}, Lng: ${driver.lng.toStringAsFixed(4)}\n'
                    'Speed: ${driver.speed?.toStringAsFixed(1) ?? "N/A"} km/h',
                  ),
                  isThreeLine: true,
                  trailing: Chip(
                    label: Text(
                      driver.isAvailable ? 'Available' : 'Busy',
                      style: TextStyle(
                        fontSize: 11,
                        color: driver.isAvailable
                            ? Colors.green
                            : Colors.orange,
                      ),
                    ),
                    backgroundColor: driver.isAvailable
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
