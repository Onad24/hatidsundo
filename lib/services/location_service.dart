import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../models/driver_location_model.dart';
import 'supabase_service.dart';

/// Location service for GPS tracking with batching
class LocationService {
  final SupabaseService _supabaseService;

  // Driver tracking state
  bool _isDriverTracking = false;
  StreamSubscription<Position>? _driverPositionSubscription;
  Timer? _driverBatchTimer;
  final Queue<LocationUpdate> _driverLocationBuffer = Queue<LocationUpdate>();

  // Client tracking state
  bool _isClientTracking = false;
  StreamSubscription<Position>? _clientPositionSubscription;
  Timer? _clientBatchTimer;
  final Queue<LocationUpdate> _clientLocationBuffer = Queue<LocationUpdate>();

  // Driver location broadcast channel (reused across flushes)
  RealtimeChannel? _driverBroadcastChannel;

  // Cached driver location subscription channel (reused, unsubscribed on new call)
  RealtimeChannel? _driverLocationChannel;

  LocationService(this._supabaseService);

  bool get isTracking => _isDriverTracking || _isClientTracking;

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

  /// Start tracking for a client during an active trip.
  /// Independent of driver tracking — uses its own flag.
  Future<void> startClientTracking({
    required String clientId,
    required String tripId,
  }) async {
    if (_isClientTracking) return;

    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      throw Exception('Location permission not granted');
    }

    _isClientTracking = true;

    // Start position stream for client
    _clientPositionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10, // Only update if moved 10 meters
          ),
        ).listen((position) {
          _onClientPositionUpdate(position);
        });

    // Flush buffered position to server every 1 minute
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

  /// Flush client location buffer and send to server.
  /// Uses upsert (keyed on client_id) to avoid unbounded row growth.
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

      debugPrint('Sending client location update for trip $tripId: Lat=${latest.lat}, Lng=${latest.lng}');

      // Upsert so only one row per client is kept (prevents unbounded growth)
      await _supabaseService
          .from('client_locations')
          .upsert(payload, onConflict: 'client_id');
    } catch (e) {
      debugPrint('Error sending client location update: $e');
      // Add back to buffer for retry on next flush
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
    _isClientTracking = false;
  }

  // =========================================================================

  /// Start tracking location with batching for driver mode.
  /// Independent of client tracking — uses its own flag.
  Future<void> startTracking({
    required String driverId,
    int updateIntervalMs = AppConstants.gpsUpdateIntervalMs,
    int batchingDurationMs = AppConstants.gpsBatchingDurationMs,
    double minDistanceMeters = AppConstants.gpsMinDistanceMeters,
  }) async {
    if (_isDriverTracking) return;

    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      throw Exception('Location permission not granted');
    }

    _isDriverTracking = true;

    // Pre-subscribe to the broadcast channel so it's ready on first flush
    _driverBroadcastChannel ??= _supabaseService.channel(
      AppConstants.channelDriversPositions,
    );

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

  /// Flush driver location buffer and send to server.
  /// Reuses the pre-subscribed broadcast channel to avoid creating a new
  /// channel object on every flush.
  Future<void> _flushDriverLocationBuffer(String driverId) async {
    if (_driverLocationBuffer.isEmpty) return;

    final updates = _driverLocationBuffer.toList();
    _driverLocationBuffer.clear();

    // Use only the latest GPS sample
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

      debugPrint('Sending location update for $driverId: Lat=${latest.lat}, Lng=${latest.lng}');

      // NOTE: We do NOT send the 'location' field.
      // The database trigger computes it automatically from lat/lng.
      await _supabaseService
          .from(AppConstants.driversLocationsTable)
          .upsert(payload)
          .eq('driver_id', driverId);

      // Reuse cached broadcast channel — avoids a new channel object every flush
      final channel = _driverBroadcastChannel ??
          _supabaseService.channel(AppConstants.channelDriversPositions);
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
      debugPrint('Error sending location update: $e');
      // Re-add to buffer for retry on next cycle
      _driverLocationBuffer.addAll(updates);
    }
  }

  /// Stop all tracking (driver + client)
  Future<void> stopTracking() async {
    _isDriverTracking = false;
    _isClientTracking = false;

    await _driverPositionSubscription?.cancel();
    _driverBatchTimer?.cancel();
    _driverLocationBuffer.clear();
    _driverPositionSubscription = null;
    _driverBatchTimer = null;

    await _driverBroadcastChannel?.unsubscribe();
    _driverBroadcastChannel = null;

    await _clientPositionSubscription?.cancel();
    _clientBatchTimer?.cancel();
    _clientLocationBuffer.clear();
    _clientPositionSubscription = null;
    _clientBatchTimer = null;
  }

  /// Update driver online status
  Future<void> setOnlineStatus(String driverId, bool isOnline) async {
    debugPrint('Setting online status for $driverId to $isOnline');
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
      // Normal on first login before driver has a location row
      debugPrint('Status update failed (normal if first time): $e');
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

  /// Subscribe to driver location updates.
  /// Unsubscribes the previous channel for this driver before creating a new
  /// one, preventing stale channel accumulation on repeated calls.
  Stream<DriverLocationModel> subscribeToDriverLocation(String driverId) {
    final controller = StreamController<DriverLocationModel>.broadcast();

    // Unsubscribe any existing channel for this driver before creating a new one
    _driverLocationChannel?.unsubscribe();
    final channel = _supabaseService.channel('driver_$driverId');
    _driverLocationChannel = channel;

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
      if (_driverLocationChannel == channel) {
        _driverLocationChannel = null;
      }
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
