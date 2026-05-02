import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/constants.dart';
import '../models/driver_location_model.dart';
import 'supabase_service.dart';

/// Location service for GPS tracking with batching
class LocationService {
  final SupabaseService _supabaseService;

  // Common state
  bool _isTracking = false;

  // Driver tracking state
  StreamSubscription<Position>? _driverPositionSubscription;
  Timer? _driverBatchTimer;
  final Queue<LocationUpdate> _driverLocationBuffer = Queue<LocationUpdate>();
  
  // Client tracking state
  StreamSubscription<Position>? _clientPositionSubscription;
  Timer? _clientBatchTimer;
  final Queue<LocationUpdate> _clientLocationBuffer = Queue<LocationUpdate>();

  LocationService(this._supabaseService);

  bool get isTracking => _isTracking;

  /// Check and request location permissions
  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Get current position
  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await checkPermissions();
      if (!hasPermission) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      );
    } catch (e) {
      debugPrint('Error getting current position: $e');
      return null;
    }
  }

  // =========================================================================
  // Client Tracking Methods
  // =========================================================================

  /// Start tracking for a client during an active trip
  Future<void> startClientTracking({
    required String clientId,
    required String tripId,
  }) async {
    if (_isTracking) return;

    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      throw Exception('Location permission not granted');
    }

    _isTracking = true;

    // Start position stream for client (1 minute intervals)
    _clientPositionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10, // Only if moved 10 meters
          ),
        ).listen((position) {
          _onClientPositionUpdate(position);
        });

    // We can use a 1-minute batch timer to flush
    _clientBatchTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _flushClientLocationBuffer(clientId, tripId),
    );
  }

  /// Handle client position update
  void _onClientPositionUpdate(Position position) {
    _clientLocationBuffer.add(
      LocationUpdate(
        lat: position.latitude,
        lng: position.longitude,
        timestamp: DateTime.now(),
      ),
    );

    while (_clientLocationBuffer.length > 10) {
      _clientLocationBuffer.removeFirst();
    }
  }

  /// Flush client location buffer and send to server
  Future<void> _flushClientLocationBuffer(String clientId, String tripId) async {
    if (_clientLocationBuffer.isEmpty) return;

    final updates = _clientLocationBuffer.toList();
    _clientLocationBuffer.clear();

    final latest = updates.last;

    try {
      final payload = {
        'client_id': clientId,
        'trip_id': tripId,
        'lat': latest.lat,
        'lng': latest.lng,
        'updated_at': latest.timestamp.toIso8601String(),
      };

      print(
        'DEBUG: Sending client location update for trip $tripId: Lat=${latest.lat}, Lng=${latest.lng}',
      );

      await _supabaseService
          .from('client_locations')
          .insert(payload); // We insert a new record for tracking history

    } catch (e) {
      print('DEBUG: Client location update failed: $e');
      debugPrint('Error sending client location update: $e');
      
      // Add back to buffer if failed to retry later
      if (_clientLocationBuffer.isEmpty) {
        _clientLocationBuffer.add(latest);
      }
    }
  }

  /// Stop client tracking explicitly
  Future<void> stopClientTracking() async {
    await _clientPositionSubscription?.cancel();
    _clientBatchTimer?.cancel();
    _clientLocationBuffer.clear();
    _clientPositionSubscription = null;
    _clientBatchTimer = null;
    
    // If driver tracking is also not active, we can mark isTracking false
    if (_driverPositionSubscription == null) {
      _isTracking = false;
    }
  }

  // =========================================================================

  /// Start tracking location with batching for driver mode
  Future<void> startTracking({
    required String driverId,
    int updateIntervalMs = AppConstants.gpsUpdateIntervalMs,
    int batchingDurationMs = AppConstants.gpsBatchingDurationMs,
    double minDistanceMeters = AppConstants.gpsMinDistanceMeters,
  }) async {
    if (_isTracking) return;

    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      throw Exception('Location permission not granted');
    }

    _isTracking = true;

    // Start position stream
    _driverPositionSubscription =
        Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: minDistanceMeters.toInt(),
          ),
        ).listen((position) {
          _onDriverPositionUpdate(position);
        });

    // Start batch timer
    _driverBatchTimer = Timer.periodic(
      Duration(milliseconds: batchingDurationMs),
      (_) => _flushDriverLocationBuffer(driverId),
    );
  }

  /// Handle driver position update
  void _onDriverPositionUpdate(Position position) {
    _driverLocationBuffer.add(
      LocationUpdate(
        lat: position.latitude,
        lng: position.longitude,
        heading: position.heading,
        speed: position.speed,
        timestamp: DateTime.now(),
      ),
    );

    // Limit buffer size
    while (_driverLocationBuffer.length > 100) {
      _driverLocationBuffer.removeFirst();
    }
  }

  /// Flush driver location buffer and send to server
  Future<void> _flushDriverLocationBuffer(String driverId) async {
    if (_driverLocationBuffer.isEmpty) return;

    final updates = _driverLocationBuffer.toList();
    _driverLocationBuffer.clear();

    // Get latest update for database
    final latest = updates.last;

    try {
      final payload = {
        'driver_id': driverId,
        'lat': latest.lat,
        'lng': latest.lng,
        'heading': latest.heading ?? 0.0,
        'speed': latest.speed ?? 0.0,
        'is_online': true,
        'is_available': true,
        'updated_at': latest.timestamp.toIso8601String(),
      };

      print(
        'DEBUG: Sending location update for $driverId: Lat=${latest.lat}, Lng=${latest.lng}',
      );

      // Update database with latest position
      // NOTE: We do NOT send the 'location' field.
      // The database computes it automatically from lat/lng.
      await _supabaseService
          .from(AppConstants.driversLocationsTable)
          .upsert(payload)
          .eq('driver_id', driverId);

      // Broadcast to realtime channel
      final channel = _supabaseService.channel(
        AppConstants.channelDriversPositions,
      );
      await channel.sendBroadcastMessage(
        event: 'location_update',
        payload: {
          'driver_id': driverId,
          'lat': latest.lat,
          'lng': latest.lng,
          'heading': latest.heading,
          'timestamp': latest.timestamp.toIso8601String(),
        },
      );
    } catch (e) {
      print('DEBUG: Location update failed: $e');
      debugPrint('Error sending location update: $e');
      // Re-add to buffer for retry
      _driverLocationBuffer.addAll(updates);
    }
  }

  /// Stop tracking location
  Future<void> stopTracking() async {
    _isTracking = false;
    
    await _driverPositionSubscription?.cancel();
    _driverBatchTimer?.cancel();
    _driverLocationBuffer.clear();
    
    _clientPositionSubscription?.cancel();
    _clientBatchTimer?.cancel();
    _clientLocationBuffer.clear();
  }

  /// Update driver online status
  Future<void> setOnlineStatus(String driverId, bool isOnline) async {
    print('DEBUG: Setting online status for $driverId to $isOnline');
    try {
      // Use update instead of upsert.
      // We don't want to create a row where lat/lng is missing.
      await _supabaseService
          .from(AppConstants.driversLocationsTable)
          .update({
            'is_online': isOnline,
            'is_available': isOnline,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('driver_id', driverId);
    } catch (e) {
      print('DEBUG: Status update failed (Normal if first time): $e');
    }
  }

  /// Get nearby drivers
  Future<List<DriverLocationModel>> getNearbyDrivers({
    required double lat,
    required double lng,
    double radiusMeters = AppConstants.nearbyDriversRadius,
  }) async {
    // Using PostGIS for efficient geospatial query
    // This assumes the RPC function exists in the database
    final response = await _supabaseService.client.rpc(
      'get_nearby_drivers',
      params: {'user_lat': lat, 'user_lng': lng, 'radius_meters': radiusMeters},
    );

    if (response == null) return [];

    return (response as List)
        .map((json) => DriverLocationModel.fromJson(json))
        .toList();
  }

  /// Subscribe to driver location updates
  Stream<DriverLocationModel> subscribeToDriverLocation(String driverId) {
    final controller = StreamController<DriverLocationModel>.broadcast();

    final channel = _supabaseService.channel('driver_$driverId');
    channel
        .onBroadcast(
          event: 'location_update',
          callback: (payload) {
            if (payload['driver_id'] == driverId) {
              controller.add(
                DriverLocationModel(
                  driverId: driverId,
                  lat: payload['lat'],
                  lng: payload['lng'],
                  heading: payload['heading'],
                  updatedAt: DateTime.parse(payload['timestamp']),
                ),
              );
            }
          },
        )
        .subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
    };

    return controller.stream;
  }

  /// Dispose resources
  void dispose() {
    stopTracking();
  }
}

/// Location service provider
final locationServiceProvider = Provider<LocationService>((ref) {
  final supabaseService = ref.watch(supabaseServiceProvider);
  return LocationService(supabaseService);
});
