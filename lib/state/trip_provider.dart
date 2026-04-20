import 'dart:async';

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
      print('DEBUG: Realtime trip update received: status=${trip.status}, riderId=${trip.riderId}');
      state = state.copyWith(activeTrip: trip);

      // If trip ended, clear subscription and polling
      if (!trip.isActive) {
        _tripSubscription?.cancel();
        _pollTimer?.cancel();
      }
    });

    // Polling fallback every 5 seconds — ensures updates even if Realtime fails
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      try {
        final trip = await _tripService.getTripById(tripId);
        if (trip != null && mounted) {
          final current = state.activeTrip;
          // Only update state if something actually changed
          if (current == null ||
              current.status != trip.status ||
              current.riderId != trip.riderId) {
            print('DEBUG: Poll detected trip change: status=${trip.status}, riderId=${trip.riderId}');
            state = state.copyWith(activeTrip: trip);
            if (!trip.isActive) {
              _tripSubscription?.cancel();
              _pollTimer?.cancel();
            }
          }
        }
      } catch (e) {
        print('DEBUG: Poll trip error: $e');
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
  }) async {
    print('DEBUG requestRide: userId=$_userId');
    if (_userId == null) {
      print('DEBUG requestRide: userId is null, returning');
      return null;
    }

    state = state.copyWith(isLoading: true);
    try {
      print('DEBUG requestRide: calling createTrip');
      final trip = await _tripService.createTrip(
        clientId: _userId,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        pickupAddress: pickupAddress,
        destLat: destLat,
        destLng: destLng,
        destAddress: destAddress,
        nearestDriverDistanceKm: nearestDriverDistanceKm,
      );
      print('DEBUG requestRide: trip created with id=${trip.id}');

      state = state.copyWith(activeTrip: trip, isLoading: false);
      _subscribeToTripUpdates(trip.id);
      return trip;
    } catch (e, st) {
      print('DEBUG requestRide ERROR: $e');
      print('DEBUG requestRide STACK: $st');
      state = state.copyWith(error: e.toString(), isLoading: false);
      return null;
    }
  }

  /// Accept a ride (rider)
  Future<bool> acceptRide(String tripId) async {
    print('DEBUG acceptRide: tripId=$tripId, userId=$_userId');
    if (_userId == null) {
      print('DEBUG acceptRide: userId is null, returning false');
      return false;
    }

    state = state.copyWith(isLoading: true);
    try {
      // DEBUG: Check rider status
      try {
        final profile = await _tripService.supabaseService.client
            .from('rider_profiles')
            .select()
            .eq('user_id', _userId)
            .maybeSingle();
        print('DEBUG acceptRide check: Rider Profile = $profile');
        if (profile != null && profile['status'] != 'approved') {
          print(
            'DEBUG acceptRide: RIDER NOT APPROVED (status=${profile['status']}). RLS will block update.',
          );
        }
      } catch (e) {
        print('DEBUG acceptRide check: Could not fetch profile: $e');
      }

      // DEBUG: Check trip status
      try {
        final tripCheck = await _tripService.supabaseService.client
            .from('trips')
            .select()
            .eq('id', tripId)
            .maybeSingle();
        print('DEBUG acceptRide check: Trip = $tripCheck');
      } catch (e) {
        print('DEBUG acceptRide check: Could not fetch trip: $e');
      }

      print('DEBUG acceptRide: calling acceptTrip...');
      final trip = await _tripService.acceptTrip(tripId, _userId);

      print(
        'DEBUG acceptRide: success! trip.status=${trip.status}, trip.riderId=${trip.riderId}',
      );
      state = state.copyWith(activeTrip: trip, isLoading: false);
      _subscribeToTripUpdates(trip.id);
      return true;
    } catch (e, st) {
      print('DEBUG acceptRide ERROR: $e');
      print('DEBUG acceptRide STACK: $st');
      state = state.copyWith(error: e.toString(), isLoading: false);
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
      final trip = await _tripService.cancelTrip(
        state.activeTrip!.id,
        cancelledBy: _userId,
        reason: reason,
      );
      state = state.copyWith(activeTrip: trip);
      _tripSubscription?.cancel();
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
/// Uses a StreamProvider with Supabase Realtime so new requests appear
/// automatically without the rider needing to toggle offline/online.
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

  // Merged stream: Realtime events + periodic polling every 5 seconds
  final controller = StreamController<List<TripModel>>();

  // 1. Realtime subscription
  final realtimeSub = tripService.subscribePendingTripChanges().listen(
    (_) async {
      try {
        print('DEBUG: Realtime pending trip change detected, re-fetching...');
        final trips = await fetchPending();
        if (!controller.isClosed) controller.add(trips);
      } catch (e) {
        print('DEBUG: Realtime pending re-fetch error: $e');
      }
    },
  );

  // 2. Polling fallback every 5 seconds
  final pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
    try {
      final trips = await fetchPending();
      if (!controller.isClosed) controller.add(trips);
    } catch (e) {
      print('DEBUG: Poll pending trips error: $e');
    }
  });

  ref.onDispose(() {
    realtimeSub.cancel();
    pollTimer.cancel();
    controller.close();
  });

  yield* controller.stream;
});
