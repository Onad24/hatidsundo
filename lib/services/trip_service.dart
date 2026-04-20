import 'dart:async';

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
  }) async {
    print('DEBUG createTrip: starting for client $clientId');

    // Get route info for fare estimation
    final route = await _osrmService.getRoute(
      startLat: pickupLat,
      startLng: pickupLng,
      endLat: destLat,
      endLng: destLng,
    );
    print('DEBUG createTrip: got route, distance=${route.distanceKm}km');

    // Fare = ₱25 base + floor(driver→pickup km) × ₱8 + floor(pickup→dest km) × ₱8
    // Night rate (9PM–5AM): distance component × 1.2
    const baseFare = 25.0;
    const perKmRate = 8.0;
    final driverKm = nearestDriverDistanceKm ?? 0.0;
    final nightMultiplier = AppConstants.isNightTime(DateTime.now())
        ? AppConstants.nightRateMultiplier
        : 1.0;
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
      'payment_method': paymentMethod,
      'payment_status': AppConstants.paymentPending,
      'route_polyline': route.polyline,
      'created_at': DateTime.now().toIso8601String(),
    };

    print('DEBUG createTrip: inserting into Supabase...');
    final result = await _supabaseService
        .from(AppConstants.tripsTable)
        .insert(tripData)
        .select()
        .single();
    print('DEBUG createTrip: insert successful, id=${result['id']}');

    // Call match_driver Edge Function (non-blocking - trip is already saved)
    print('DEBUG createTrip: calling match_driver function...');
    try {
      await _supabaseService.callFunction(
        'match_driver',
        body: {
          'trip_id': result['id'],
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
        },
      );
      print('DEBUG createTrip: match_driver called');
    } catch (e) {
      // Edge Function may not be deployed - trip is already saved, so continue
      print('DEBUG createTrip: match_driver failed (optional): $e');
    }

    return TripModel.fromJson(result);
  }

  /// Accept a trip (for drivers)
  Future<TripModel> acceptTrip(String tripId, String riderId) async {
    final result = await _supabaseService
        .from(AppConstants.tripsTable)
        .update({
          'rider_id': riderId,
          'status': AppConstants.tripStatusAccepted,
          'accepted_at': DateTime.now().toIso8601String(),
        })
        .eq('id', tripId)
        .eq('status', AppConstants.tripStatusPending)
        .select()
        .single();

    // Notify client via Edge Function (best-effort)
    try {
      await _supabaseService.callFunction(
        'trip_update',
        body: {'trip_id': tripId, 'event': 'driver_assigned'},
      );
    } catch (e) {
      print('WARNING: trip_update notification failed (non-blocking): $e');
    }

    return TripModel.fromJson(result);
  }

  /// Update trip status to driver arriving
  Future<TripModel> markDriverArriving(String tripId) async {
    final result = await _supabaseService.client.rpc(
      'mark_driver_arriving_rpc',
      params: {'p_trip_id': tripId},
    );

    return TripModel.fromJson(result as Map<String, dynamic>);
  }

  /// Start the trip
  Future<TripModel> startTrip(String tripId) async {
    final result = await _supabaseService.client.rpc(
      'start_trip_rpc',
      params: {'p_trip_id': tripId},
    );

    return TripModel.fromJson(result as Map<String, dynamic>);
  }

  /// Complete the trip
  Future<TripModel> completeTrip(String tripId) async {
    print('DEBUG completeTrip: starting for tripId=$tripId');

    final result = await _supabaseService.client.rpc(
      'complete_trip_rpc',
      params: {'p_trip_id': tripId},
    );

    print('DEBUG completeTrip: RPC result=$result');
    return TripModel.fromJson(result as Map<String, dynamic>);
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

  /// Subscribe to trip updates
  Stream<TripModel> subscribeTripUpdates(String tripId) {
    final controller = StreamController<TripModel>.broadcast();

    final channelName = 'trip_${tripId}_${DateTime.now().millisecondsSinceEpoch}';
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

    final channelName = 'pending_trips_feed_${DateTime.now().millisecondsSinceEpoch}';
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
}

/// Trip service provider
final tripServiceProvider = Provider<TripService>((ref) {
  final supabaseService = ref.watch(supabaseServiceProvider);
  final osrmService = ref.watch(osrmServiceProvider);
  return TripService(supabaseService, osrmService);
});
