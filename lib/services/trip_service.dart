import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../models/trip_model.dart';
import 'supabase_service.dart';
import 'osrm_service.dart';

/// Trip service for managing ride lifecycle
class TripService {
  final SupabaseService _supabaseService;
  final OsrmService _osrmService;
  final Uuid _uuid = const Uuid();

  // In-memory fare settings cache (avoids repeated DB reads for data that
  // rarely changes; admin updates take effect within the TTL window)
  Map<String, dynamic>? _cachedFareSettings;
  DateTime? _fareSettingsCachedAt;
  static const Duration _fareSettingsTtl = Duration(minutes: 10);

  // Cached broadcast channels keyed by trip ID — reused on every route broadcast
  final Map<String, RealtimeChannel> _routeBroadcastChannels = {};

  TripService(this._supabaseService, this._osrmService);

  // Expose for debugging
  SupabaseService get supabaseService => _supabaseService;

  /// Create a new trip request
  Future<TripModel> createTrip({
    required String clientId,
    required double pickupLat,
    required double pickupLng,
    String? pickupAddress,
    required double destLat,
    required double destLng,
    String? destAddress,
    String paymentMethod = 'cash',
    double? nearestDriverDistanceKm,
    String? vehicleType,
  }) async {
    debugPrint('createTrip: starting for client $clientId');

    // Get route info for fare estimation
    final route = await _osrmService.getRoute(
      startLat: pickupLat,
      startLng: pickupLng,
      endLat: destLat,
      endLng: destLng,
    );
    debugPrint('createTrip: got route, distance=${route.distanceKm}km');

    // Fetch fare settings from database with in-memory caching.
    // Settings rarely change, so we cache for 10 minutes to avoid a
    // round-trip on every ride request.
    double baseFare = 25.0;
    double perKmRate = 8.0;
    double nightRateMultiplier = 1.2;
    int nightStartHour = 21;
    int nightEndHour = 5;
    try {
      final now = DateTime.now();
      final cacheExpired = _fareSettingsCachedAt == null ||
          now.difference(_fareSettingsCachedAt!) > _fareSettingsTtl;

      if (cacheExpired) {
        _cachedFareSettings = await _supabaseService
            .from('fare_settings')
            .select()
            .eq('id', 1)
            .single();
        _fareSettingsCachedAt = now;
        debugPrint('Fare settings fetched from DB and cached.');
      } else {
        debugPrint('Fare settings served from cache.');
      }

      final fareRow = _cachedFareSettings!;
      baseFare = (fareRow['base_fare'] as num?)?.toDouble() ?? 25.0;
      // Use per-vehicle-type base fare and rate if available
      switch (vehicleType) {
        case 'motorcycle':
          baseFare =
              (fareRow['base_fare_motorcycle'] as num?)?.toDouble() ?? 20.0;
          perKmRate =
              (fareRow['per_km_rate_motorcycle'] as num?)?.toDouble() ?? 6.0;
          break;
        case 'suv':
          baseFare = (fareRow['base_fare_suv'] as num?)?.toDouble() ?? 35.0;
          perKmRate = (fareRow['per_km_rate_suv'] as num?)?.toDouble() ?? 12.0;
          break;
        case 'sedan':
          baseFare = (fareRow['base_fare_sedan'] as num?)?.toDouble() ?? 25.0;
          perKmRate = (fareRow['per_km_rate_sedan'] as num?)?.toDouble() ?? 8.0;
          break;
        default:
          perKmRate = (fareRow['per_km_rate'] as num?)?.toDouble() ?? 8.0;
      }
      nightRateMultiplier =
          (fareRow['night_rate_multiplier'] as num?)?.toDouble() ?? 1.2;
      nightStartHour = (fareRow['night_start_hour'] as int?) ?? 21;
      nightEndHour = (fareRow['night_end_hour'] as int?) ?? 5;
    } catch (e) {
      debugPrint('Could not fetch fare settings, using defaults: $e');
    }

    final driverKm = nearestDriverDistanceKm ?? 0.0;
    final hour = DateTime.now().hour;
    final isNight = hour >= nightStartHour || hour < nightEndHour;
    final nightMultiplier = isNight ? nightRateMultiplier : 1.0;
    final estimatedFare =
        baseFare +
        (driverKm.floorToDouble() * perKmRate) +
        (route.distanceKm.floorToDouble() * perKmRate * nightMultiplier);

    final tripData = {
      'id': _uuid.v4(),
      'client_id': clientId,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'pickup_address': pickupAddress,
      'dest_lat': destLat,
      'dest_lng': destLng,
      'dest_address': destAddress,
      'status': AppConstants.tripStatusPending,
      'distance_km': route.distanceKm,
      'duration_min': route.durationMinutes,
      'fare_estimated': estimatedFare,
      'driver_pickup_distance_km': nearestDriverDistanceKm,
      'vehicle_type': vehicleType,
      'payment_method': paymentMethod,
      'payment_status': AppConstants.paymentPending,
      'route_polyline': route.polyline,
      'created_at': DateTime.now().toIso8601String(),
    };

    debugPrint('createTrip: inserting into Supabase...');
    final result = await _supabaseService
        .from(AppConstants.tripsTable)
        .insert(tripData)
        .select()
        .single();
    debugPrint('createTrip: insert successful, id=${result['id']}');

    // Notify nearby riders via match_driver (sends FCM push notifications)
    try {
      final matchResponse = await _supabaseService.callFunction(
        'match_driver',
        body: {
          'trip_id': result['id'],
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
        },
      );
      debugPrint(
        'match_driver notified ${matchResponse.data?['notified_drivers'] ?? 0} drivers',
      );
    } catch (e) {
      // Notifications are optional - riders will see trips via realtime feed
      debugPrint('match_driver notification failed (optional): $e');
    }

    return TripModel.fromJson(result);
  }

  /// Accept a trip (for drivers) — uses atomic RPC to prevent race conditions.
  /// Only one rider can accept; concurrent attempts will fail gracefully.
  Future<TripModel> acceptTrip(String tripId, String riderId) async {
    final result = await _supabaseService.client.rpc(
      'accept_trip_rpc',
      params: {'p_trip_id': tripId},
    );

    if (result == null) {
      throw Exception('Trip is no longer available');
    }

    final tripData = result as Map<String, dynamic>;

    // Fetch driver info to include in notification
    String driverInfo = '';
    try {
      final profileResult = await _supabaseService.client
          .from('rider_profiles')
          .select('vehicle_color, vehicle_make, vehicle_model, plate_number')
          .eq('user_id', riderId)
          .maybeSingle();

      final userResult = await _supabaseService.client
          .from('users')
          .select('name, phone')
          .eq('id', riderId)
          .maybeSingle();

      final name = userResult?['name'] ?? 'Your driver';
      
      if (profileResult != null) {
        final vehicleColor = profileResult['vehicle_color'] ?? '';
        final vehicleMake = profileResult['vehicle_make'] ?? '';
        final vehicleModel = profileResult['vehicle_model'] ?? '';
        final plate = profileResult['plate_number'] ?? '';

        final vehicle = '$vehicleColor $vehicleMake $vehicleModel'.trim();
        if (vehicle.isNotEmpty || plate.isNotEmpty) {
          driverInfo = '\n\nDriver: $name\nVehicle: $vehicle\nPlate: $plate';
        } else {
          driverInfo = '\n\nDriver: $name';
        }
      } else {
        driverInfo = '\n\nDriver: $name';
      }
    } catch (e) {
      debugPrint('fetching driver info failed: $e');
      driverInfo = '\n\n[Error fetching info: $e]';
    }

    // Notify client that a driver was assigned
    _sendTripNotification(
      tripData['client_id'],
      tripId,
      'Driver On The Way',
      'A driver has accepted your ride request and is on the way!$driverInfo',
      'driver_assigned',
    );

    return TripModel.fromJson(tripData);
  }

  /// Update trip status to driver arriving
  Future<TripModel> markDriverArriving(String tripId) async {
    final result = await _supabaseService.client.rpc(
      'mark_driver_arriving_rpc',
      params: {'p_trip_id': tripId},
    );

    final tripData = result as Map<String, dynamic>;

    // Notify client that driver is arriving
    _sendTripNotification(
      tripData['client_id'],
      tripId,
      'Driver Arrived',
      'Your driver has arrived at the pickup location!',
      'driver_arriving',
    );

    return TripModel.fromJson(tripData);
  }

  /// Start the trip
  Future<TripModel> startTrip(String tripId) async {
    final result = await _supabaseService.client.rpc(
      'start_trip_rpc',
      params: {'p_trip_id': tripId},
    );

    final tripData = result as Map<String, dynamic>;

    // Notify client that trip started
    _sendTripNotification(
      tripData['client_id'],
      tripId,
      'Trip Started',
      'Your trip has started. Enjoy the ride!',
      'trip_started',
    );

    return TripModel.fromJson(tripData);
  }

  /// Complete the trip
  Future<TripModel> completeTrip(String tripId) async {
    debugPrint('completeTrip: starting for tripId=$tripId');

    final result = await _supabaseService.client.rpc(
      'complete_trip_rpc',
      params: {'p_trip_id': tripId},
    );

    debugPrint('completeTrip: RPC result=$result');
    final tripData = result as Map<String, dynamic>;

    // Notify client that trip is completed
    final fare = tripData['fare_final'] ?? tripData['fare_estimated'] ?? 0;
    _sendTripNotification(
      tripData['client_id'],
      tripId,
      'Trip Completed',
      'Your trip is complete. Fare: ₱${(fare as num).toStringAsFixed(0)}',
      'trip_completed',
    );

    return TripModel.fromJson(tripData);
  }

  /// Send a push notification to a user about a trip event (fire-and-forget)
  void _sendTripNotification(
    String? userId,
    String tripId,
    String title,
    String body,
    String type,
  ) {
    if (userId == null) return;
    _supabaseService
        .callFunction(
          'send_notification',
          body: {
            'user_id': userId,
            'title': title,
            'body': body,
            'data': {'type': type, 'trip_id': tripId},
          },
        )
        .catchError((e) {
          debugPrint('WARNING: $type notification failed (non-blocking): $e');
          return FunctionResponse(status: -1);
        });
  }

  /// Cancel the trip
  Future<TripModel> cancelTrip(
    String tripId, {
    required String cancelledBy,
    String? reason,
  }) async {
    final result = await _supabaseService
        .from(AppConstants.tripsTable)
        .update({
          'status': AppConstants.tripStatusCancelled,
          'cancelled_by': cancelledBy,
          'cancellation_reason': reason,
        })
        .eq('id', tripId)
        .select()
        .single();

    return TripModel.fromJson(result);
  }

  /// Rate and review the trip
  Future<void> rateTrip(
    String tripId, {
    required int rating,
    String? comment,
  }) async {
    await _supabaseService
        .from(AppConstants.tripsTable)
        .update({'rating': rating, 'rating_comment': comment})
        .eq('id', tripId);
  }

  /// Get trip by ID
  Future<TripModel?> getTripById(String tripId) async {
    final result = await _supabaseService
        .from(AppConstants.tripsTable)
        .select()
        .eq('id', tripId)
        .maybeSingle();

    if (result == null) return null;
    return TripModel.fromJson(result);
  }

  /// Get active trip for client
  Future<TripModel?> getActiveClientTrip(String clientId) async {
    final result = await _supabaseService
        .from(AppConstants.tripsTable)
        .select()
        .eq('client_id', clientId)
        .inFilter('status', [
          AppConstants.tripStatusPending,
          AppConstants.tripStatusAccepted,
          AppConstants.tripStatusDriverArriving,
          AppConstants.tripStatusInProgress,
        ])
        .order('created_at', ascending: false)
        .maybeSingle();

    if (result == null) return null;
    return TripModel.fromJson(result);
  }

  /// Get active trip for rider
  Future<TripModel?> getActiveRiderTrip(String riderId) async {
    final result = await _supabaseService
        .from(AppConstants.tripsTable)
        .select()
        .eq('rider_id', riderId)
        .inFilter('status', [
          AppConstants.tripStatusAccepted,
          AppConstants.tripStatusDriverArriving,
          AppConstants.tripStatusInProgress,
        ])
        .order('created_at', ascending: false)
        .maybeSingle();

    if (result == null) return null;
    return TripModel.fromJson(result);
  }

  /// Get pending trips for riders to accept
  Future<List<TripModel>> getPendingTripsNearby({
    required double lat,
    required double lng,
    double radiusKm = 5.0,
  }) async {
    // This would use PostGIS for efficient spatial queries
    final result = await _supabaseService.client.rpc(
      'get_pending_trips_nearby',
      params: {'driver_lat': lat, 'driver_lng': lng, 'radius_km': radiusKm},
    );

    if (result == null) return [];
    return (result as List).map((j) => TripModel.fromJson(j)).toList();
  }

  /// Get trip history for client
  Future<List<TripModel>> getClientTripHistory(
    String clientId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final result = await _supabaseService
        .from(AppConstants.tripsTable)
        .select()
        .eq('client_id', clientId)
        .inFilter('status', [
          AppConstants.tripStatusCompleted,
          AppConstants.tripStatusCancelled,
        ])
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (result as List).map((j) => TripModel.fromJson(j)).toList();
  }

  /// Get trip history for rider
  Future<List<TripModel>> getRiderTripHistory(
    String riderId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final result = await _supabaseService
        .from(AppConstants.tripsTable)
        .select()
        .eq('rider_id', riderId)
        .eq('status', AppConstants.tripStatusCompleted)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (result as List).map((j) => TripModel.fromJson(j)).toList();
  }

  /// Subscribe to trip updates.
  /// Uses a stable channel name (no timestamp) so channels can be reused
  /// and cleaned up correctly on cancellation.
  Stream<TripModel> subscribeTripUpdates(String tripId) {
    final controller = StreamController<TripModel>.broadcast();

    final channelName = 'trip_$tripId';
    final channel = _supabaseService
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: AppConstants.tripsTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: tripId,
          ),
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              controller.add(TripModel.fromJson(payload.newRecord));
            }
          },
        )
        .subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
    };

    return controller.stream;
  }

  /// Subscribe to changes in the pending trips table (for rider feed).
  /// Emits a void signal whenever a trip is inserted or updated (e.g. new
  /// ride request or a trip status changes away from pending).
  Stream<void> subscribePendingTripChanges() {
    final controller = StreamController<void>.broadcast();

    final channelName =
        'pending_trips_feed_${DateTime.now().millisecondsSinceEpoch}';
    final channel = _supabaseService
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: AppConstants.tripsTable,
          callback: (_) => controller.add(null),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: AppConstants.tripsTable,
          callback: (_) => controller.add(null),
        )
        .subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
    };

    return controller.stream;
  }

  /// Broadcast a route polyline update from rider to client.
  /// Reuses a cached channel per trip ID to avoid creating a new channel
  /// object on every 10-second navigation update cycle.
  Future<void> broadcastRouteUpdate({
    required String tripId,
    required String polyline,
    required double etaMinutes,
    required double distanceKm,
  }) async {
    try {
      final channel = _routeBroadcastChannels.putIfAbsent(
        tripId,
        () => _supabaseService.channel('trip_route_$tripId'),
      );
      await channel.sendBroadcastMessage(
        event: 'route_update',
        payload: {
          'polyline': polyline,
          'eta_minutes': etaMinutes,
          'distance_km': distanceKm,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('broadcastRouteUpdate error: $e');
    }
  }

  /// Subscribe to route updates for a trip (used by client)
  Stream<Map<String, dynamic>> subscribeRouteUpdates(String tripId) {
    final controller = StreamController<Map<String, dynamic>>.broadcast();

    final channel = _supabaseService.channel('trip_route_sub_$tripId');
    channel
        .onBroadcast(
          event: 'route_update',
          callback: (payload) {
            debugPrint('Received route broadcast for trip $tripId');
            controller.add(payload);
          },
        )
        .subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
    };

    return controller.stream;
  }

  /// Send an FCM notification via Edge Function
  Future<void> sendPushNotification({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _supabaseService.callFunction(
        'send_notification',
        body: {
          'user_id': userId,
          'title': title,
          'body': body,
          'data': data ?? {},
        },
      );
    } catch (e) {
      debugPrint('sendPushNotification failed (non-blocking): $e');
    }
  }
}

/// Trip service provider
final tripServiceProvider = Provider<TripService>((ref) {
  final supabaseService = ref.watch(supabaseServiceProvider);
  final osrmService = ref.watch(osrmServiceProvider);
  return TripService(supabaseService, osrmService);
});
