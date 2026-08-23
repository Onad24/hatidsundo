import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/trip_model.dart';
import '../services/trip_service.dart';
import 'auth_provider.dart';
import 'location_provider.dart';

/// Active trip state
class TripState {
  final TripModel? activeTrip;
  final bool isLoading;
  final String? error;

  const TripState({this.activeTrip, this.isLoading = false, this.error});

  TripState copyWith({TripModel? activeTrip, bool? isLoading, String? error}) {
    return TripState(
      activeTrip: activeTrip ?? this.activeTrip,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  bool get hasActiveTrip => activeTrip != null && activeTrip!.isActive;
}

/// Trip state notifier
class TripNotifier extends StateNotifier<TripState> {
  final TripService _tripService;
  final String? _userId;
  final bool _isRider;
  StreamSubscription? _tripSubscription;
  Timer? _pollTimer;
  // Track the last realtime update time to skip polling when Realtime is healthy
  DateTime? _lastRealtimeAt;

  TripNotifier(this._tripService, this._userId, this._isRider)
    : super(const TripState()) {
    _loadActiveTrip();
  }

  Future<void> _loadActiveTrip() async {
    if (_userId == null) return;

    state = state.copyWith(isLoading: true);
    try {
      final trip = _isRider
          ? await _tripService.getActiveRiderTrip(_userId)
          : await _tripService.getActiveClientTrip(_userId);

      // Check if still mounted before updating state
      if (!mounted) return;

      state = state.copyWith(activeTrip: trip, isLoading: false);

      if (trip != null) {
        _subscribeToTripUpdates(trip.id);
      }
    } catch (e) {
      // Check if still mounted before updating state on error
      if (!mounted) return;
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  void _subscribeToTripUpdates(String tripId) {
    _tripSubscription?.cancel();
    _pollTimer?.cancel();

    // Realtime subscription
    _tripSubscription = _tripService.subscribeTripUpdates(tripId).listen((
      trip,
    ) {
      if (!mounted) return;
      _lastRealtimeAt = DateTime.now();
      debugPrint('Realtime trip update: status=${trip.status}, riderId=${trip.riderId}');
      state = state.copyWith(activeTrip: trip);

      // If trip ended, clear subscription and polling
      if (!trip.isActive) {
        _tripSubscription?.cancel();
        _pollTimer?.cancel();
      }
    });

    // Polling fallback every 15 seconds.
    // Skipped when Realtime is healthy (fired within the last 12s) to avoid
    // unnecessary DB reads. Only activates when Realtime is silent/flaky.
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) return;

      // Skip poll if realtime delivered an update recently
      final lastRt = _lastRealtimeAt;
      if (lastRt != null &&
          DateTime.now().difference(lastRt) < const Duration(seconds: 12)) {
        return;
      }

      try {
        final trip = await _tripService.getTripById(tripId);
        if (trip != null && mounted) {
          final current = state.activeTrip;
          // Only update state if something actually changed
          if (current == null ||
              current.status != trip.status ||
              current.riderId != trip.riderId) {
            debugPrint('Poll detected trip change: status=${trip.status}, riderId=${trip.riderId}');
            state = state.copyWith(activeTrip: trip);
            if (!trip.isActive) {
              _tripSubscription?.cancel();
              _pollTimer?.cancel();
            }
          }
        }
      } catch (e) {
        debugPrint('Poll trip error: $e');
      }
    });
  }

  /// Request a ride (client)
  Future<TripModel?> requestRide({
    required double pickupLat,
    required double pickupLng,
    String? pickupAddress,
    required double destLat,
    required double destLng,
    String? destAddress,
    double? nearestDriverDistanceKm,
    String? vehicleType,
  }) async {
    debugPrint('requestRide: userId=$_userId');
    if (_userId == null) {
      debugPrint('requestRide: userId is null, returning');
      return null;
    }

    state = state.copyWith(isLoading: true);
    try {
      debugPrint('requestRide: calling createTrip');
      final trip = await _tripService.createTrip(
        clientId: _userId,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        pickupAddress: pickupAddress,
        destLat: destLat,
        destLng: destLng,
        destAddress: destAddress,
        nearestDriverDistanceKm: nearestDriverDistanceKm,
        vehicleType: vehicleType,
      );
      debugPrint('requestRide: trip created with id=${trip.id}');

      state = state.copyWith(activeTrip: trip, isLoading: false);
      _subscribeToTripUpdates(trip.id);
      return trip;
    } catch (e, st) {
      debugPrint('requestRide ERROR: $e\n$st');
      state = state.copyWith(error: e.toString(), isLoading: false);
      return null;
    }
  }

  /// Accept a ride (rider) — atomic, only one rider can accept
  Future<bool> acceptRide(String tripId) async {
    if (_userId == null) return false;

    state = state.copyWith(isLoading: true);
    try {
      final trip = await _tripService.acceptTrip(tripId, _userId);
      state = state.copyWith(activeTrip: trip, isLoading: false);
      _subscribeToTripUpdates(trip.id);
      return true;
    } catch (e) {
      debugPrint('acceptRide ERROR: $e');
      // Provide a user-friendly error for race condition
      final errorMsg = e.toString().contains('no longer available')
          ? 'This ride was already accepted by another driver.'
          : e.toString();
      state = state.copyWith(error: errorMsg, isLoading: false);
      return false;
    }
  }

  /// Mark driver arriving
  Future<void> markArriving() async {
    if (state.activeTrip == null) return;

    try {
      final trip = await _tripService.markDriverArriving(state.activeTrip!.id);
      state = state.copyWith(activeTrip: trip);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Start trip
  Future<void> startTrip() async {
    if (state.activeTrip == null) return;

    try {
      final trip = await _tripService.startTrip(state.activeTrip!.id);
      state = state.copyWith(activeTrip: trip);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Complete trip
  Future<void> completeTrip() async {
    if (state.activeTrip == null) return;

    try {
      final trip = await _tripService.completeTrip(state.activeTrip!.id);
      state = state.copyWith(activeTrip: trip);
      _tripSubscription?.cancel();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Cancel trip
  Future<void> cancelTrip({String? reason}) async {
    if (state.activeTrip == null || _userId == null) return;

    try {
      final trip = state.activeTrip!;
      final updatedTrip = await _tripService.cancelTrip(
        trip.id,
        cancelledBy: _userId,
        reason: reason,
      );
      state = state.copyWith(activeTrip: updatedTrip);
      _tripSubscription?.cancel();

      // Send FCM notification to the other party
      final otherUserId = _isRider ? trip.clientId : trip.riderId;
      if (otherUserId != null) {
        _tripService.sendPushNotification(
          userId: otherUserId,
          title: 'Trip Cancelled',
          body: _isRider
              ? 'Your driver has cancelled the trip${reason != null ? ': $reason' : '.'}'
              : 'The passenger has cancelled the trip${reason != null ? ': $reason' : '.'}',
          data: {
            'type': 'trip_cancelled',
            'trip_id': trip.id,
            'reason': reason ?? '',
          },
        );
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// Rate trip
  Future<void> rateTrip(int rating, {String? comment}) async {
    if (state.activeTrip == null) return;

    await _tripService.rateTrip(
      state.activeTrip!.id,
      rating: rating,
      comment: comment,
    );
  }

  /// Clear active trip
  void clearTrip() {
    _tripSubscription?.cancel();
    state = const TripState();
  }

  /// Refresh
  Future<void> refresh() async {
    await _loadActiveTrip();
  }

  @override
  void dispose() {
    _tripSubscription?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }
}

/// Trip state provider
final tripStateProvider = StateNotifierProvider<TripNotifier, TripState>((ref) {
  final tripService = ref.watch(tripServiceProvider);
  final user = ref.watch(currentUserProvider);
  return TripNotifier(tripService, user?.id, user?.isRider ?? false);
});

/// Trip history provider
final tripHistoryProvider = FutureProvider.family<List<TripModel>, int>((
  ref,
  limit,
) async {
  final tripService = ref.watch(tripServiceProvider);
  final user = ref.watch(currentUserProvider);

  if (user == null) return [];

  if (user.isRider) {
    return tripService.getRiderTripHistory(user.id, limit: limit);
  } else {
    return tripService.getClientTripHistory(user.id, limit: limit);
  }
});

/// Pending trips provider for riders to see available ride requests.
/// Uses Supabase Realtime for instant updates when new requests arrive.
/// A 30-second fallback poll fires only when Realtime has been silent,
/// acting as a dead-man's switch without generating constant DB load.
final pendingTripsProvider = StreamProvider<List<TripModel>>((ref) async* {
  final tripService = ref.watch(tripServiceProvider);
  final user = ref.watch(currentUserProvider);
  final driverState = ref.watch(driverOnlineProvider);

  // Only stream if user is a rider and online
  if (user == null || !user.isRider || !driverState.isOnline) {
    yield [];
    return;
  }

  // Use driver's current position
  final position = driverState.currentPosition;
  if (position == null) {
    yield [];
    return;
  }

  // Helper to fetch pending trips
  Future<List<TripModel>> fetchPending() => tripService.getPendingTripsNearby(
    lat: position.latitude,
    lng: position.longitude,
    radiusKm: 10.0,
  );

  // Emit the initial fetch immediately
  yield await fetchPending();

  // Merged stream: Realtime events + 30-second fallback poll
  final controller = StreamController<List<TripModel>>();

  // Track last realtime event time to suppress redundant polls
  DateTime? lastRealtimeAt;

  // 1. Realtime subscription — fires immediately on any trip insert/update
  final realtimeSub = tripService.subscribePendingTripChanges().listen(
    (_) async {
      try {
        debugPrint('Realtime pending trip change detected, re-fetching...');
        lastRealtimeAt = DateTime.now();
        final trips = await fetchPending();
        if (!controller.isClosed) controller.add(trips);
      } catch (e) {
        debugPrint('Realtime pending re-fetch error: $e');
      }
    },
  );

  // 2. Fallback poll every 30 seconds — skipped when Realtime is healthy.
  // Only fires when Realtime has been silent for >28s (i.e., is flaky/offline).
  final pollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
    final lastRt = lastRealtimeAt;
    if (lastRt != null &&
        DateTime.now().difference(lastRt) < const Duration(seconds: 28)) {
      return; // Realtime is healthy, skip this poll cycle
    }
    try {
      final trips = await fetchPending();
      if (!controller.isClosed) controller.add(trips);
    } catch (e) {
      debugPrint('Poll pending trips error: $e');
    }
  });

  ref.onDispose(() {
    realtimeSub.cancel();
    pollTimer.cancel();
    controller.close();
  });

  yield* controller.stream;
});
