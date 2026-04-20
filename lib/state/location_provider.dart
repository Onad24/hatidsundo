import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models/driver_location_model.dart';
import '../services/location_service.dart';
import 'auth_provider.dart';

/// Driver online state
class DriverOnlineState {
  final bool isOnline;
  final bool isAvailable;
  final Position? currentPosition;
  final bool isTracking;
  final String? error;

  const DriverOnlineState({
    this.isOnline = false,
    this.isAvailable = false,
    this.currentPosition,
    this.isTracking = false,
    this.error,
  });

  DriverOnlineState copyWith({
    bool? isOnline,
    bool? isAvailable,
    Position? currentPosition,
    bool? isTracking,
    String? error,
  }) {
    return DriverOnlineState(
      isOnline: isOnline ?? this.isOnline,
      isAvailable: isAvailable ?? this.isAvailable,
      currentPosition: currentPosition ?? this.currentPosition,
      isTracking: isTracking ?? this.isTracking,
      error: error,
    );
  }
}

/// Driver online notifier
class DriverOnlineNotifier extends StateNotifier<DriverOnlineState> {
  final LocationService _locationService;
  final String? _driverId;

  DriverOnlineNotifier(this._locationService, this._driverId)
    : super(const DriverOnlineState());

  /// Toggle online status
  Future<bool> toggleOnline() async {
    if (_driverId == null) return false;

    try {
      if (state.isOnline) {
        // Go offline
        await _locationService.stopTracking();
        await _locationService.setOnlineStatus(_driverId, false);
        state = state.copyWith(
          isOnline: false,
          isAvailable: false,
          isTracking: false,
        );
      } else {
        // Go online
        final position = await _locationService.getCurrentPosition();
        if (position == null) {
          state = state.copyWith(error: 'Could not get location');
          return false;
        }

        await _locationService.setOnlineStatus(_driverId, true);
        await _locationService.startTracking(driverId: _driverId);

        state = state.copyWith(
          isOnline: true,
          isAvailable: true,
          currentPosition: position,
          isTracking: true,
        );
      }
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Set availability (can accept rides)
  void setAvailable(bool available) {
    state = state.copyWith(isAvailable: available);
  }

  /// Update position
  void updatePosition(Position position) {
    state = state.copyWith(currentPosition: position);
  }

  @override
  void dispose() {
    _locationService.stopTracking();
    super.dispose();
  }
}

/// Driver online state provider
final driverOnlineProvider =
    StateNotifierProvider<DriverOnlineNotifier, DriverOnlineState>((ref) {
      final locationService = ref.watch(locationServiceProvider);
      final user = ref.watch(currentUserProvider);
      return DriverOnlineNotifier(locationService, user?.id);
    });

/// Nearby drivers provider
final nearbyDriversProvider =
    FutureProvider.family<
      List<DriverLocationModel>,
      ({double lat, double lng})
    >((ref, coords) async {
      final locationService = ref.watch(locationServiceProvider);
      return locationService.getNearbyDrivers(lat: coords.lat, lng: coords.lng);
    });

/// Current position provider (FutureProvider for async access)
final currentPositionProvider = FutureProvider<Position?>((ref) async {
  final locationService = ref.watch(locationServiceProvider);
  return locationService.getCurrentPosition();
});

/// Current position state provider (StateProvider for sync access)
final currentPositionStateProvider = StateProvider<Position?>((ref) => null);
