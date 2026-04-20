import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../models/trip_model.dart';
import '../../state/state.dart';
import '../../services/services.dart';
import '../../widgets/map_widget.dart';

/// Navigation screen for drivers with turn-by-turn directions
class NavigationScreen extends ConsumerStatefulWidget {
  final String tripId;

  const NavigationScreen({super.key, required this.tripId});

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  List<LatLng>? _routePoints;
  int? _etaMinutes;
  double? _routeDistanceKm;
  Timer? _routeUpdateTimer;
  bool _isRouteUpdating = false;
  bool _initialRouteLoaded = false;

  // Cache client info to avoid refetching on every rebuild
  Future<Map<String, dynamic>?>? _clientInfoFuture;
  String? _cachedClientId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchRoute();
      _fetchClientInfo();
      // Periodically refresh route every 10 seconds
      _routeUpdateTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _fetchRoute(),
      );
    });
  }

  void _fetchClientInfo() {
    final trip = ref.read(tripStateProvider).activeTrip;
    if (trip == null) return;
    final clientId = trip.clientId;
    if (_cachedClientId == clientId) return;
    _cachedClientId = clientId;
    setState(() {
      _clientInfoFuture = ref
          .read(riderServiceProvider)
          .getClientInfo(clientId);
    });
  }

  @override
  void dispose() {
    _routeUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchRoute() async {
    if (_isRouteUpdating || !mounted) return;

    final trip = ref.read(tripStateProvider).activeTrip;
    if (trip == null) return;

    // Only compute route for active navigation states
    if (trip.status == TripStatus.completed ||
        trip.status == TripStatus.cancelled ||
        trip.status == TripStatus.pending) {
      return;
    }

    setState(() {
      _isRouteUpdating = true;
    });

    try {
      // Invalidate cached position so we always get a fresh GPS read
      ref.invalidate(currentPositionProvider);
      final position = await ref.read(currentPositionProvider.future);
      if (position == null || !mounted) {
        setState(() => _isRouteUpdating = false);
        return;
      }

      // Determine destination based on trip status
      double endLat, endLng;
      if (trip.status == TripStatus.inProgress) {
        // Heading to destination
        endLat = trip.destLat;
        endLng = trip.destLng;
      } else {
        // accepted / driverArriving → heading to pickup
        endLat = trip.pickupLat;
        endLng = trip.pickupLng;
      }

      final osrmService = ref.read(osrmServiceProvider);
      final route = await osrmService.getRoute(
        startLat: position.latitude,
        startLng: position.longitude,
        endLat: endLat,
        endLng: endLng,
      );

      if (mounted) {
        setState(() {
          _routePoints = polylineToLatLng(route.polyline);
          _etaMinutes = route.durationMinutes;
          _routeDistanceKm = route.distanceKm;
          _initialRouteLoaded = true;
          _isRouteUpdating = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching rider route: $e');
      if (mounted) {
        setState(() {
          _isRouteUpdating = false;
          // On first failure, fallback to static trip route
          if (!_initialRouteLoaded) {
            final trip = ref.read(tripStateProvider).activeTrip;
            if (trip?.routePolyline != null) {
              _routePoints = polylineToLatLng(trip!.routePolyline!);
            }
            _initialRouteLoaded = true;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripState = ref.watch(tripStateProvider);
    final trip = tripState.activeTrip;

    // Re-fetch route when trip status changes
    ref.listen(tripStateProvider, (previous, next) {
      final prevStatus = previous?.activeTrip?.status;
      final nextStatus = next.activeTrip?.status;
      if (prevStatus != nextStatus && nextStatus != null) {
        // Handle cancellation by the client
        if (nextStatus == TripStatus.cancelled) {
          _routeUpdateTimer?.cancel();
          final reason = next.activeTrip?.cancellationReason;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Trip Cancelled'),
              content: Text(
                reason != null && reason.isNotEmpty
                    ? 'The passenger cancelled this trip.\n\nReason: $reason'
                    : 'The passenger cancelled this trip.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.go(Routes.riderHome);
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
        _fetchRoute();
      }
      // Also refresh client info if clientId changes (shouldn't happen normally)
      final nextClientId = next.activeTrip?.clientId;
      if (nextClientId != null && nextClientId != _cachedClientId) {
        _fetchClientInfo();
      }
    });

    if (trip == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Use dynamic route if available, otherwise fallback to static
    final displayRoute =
        _routePoints ??
        (trip.routePolyline != null
            ? polylineToLatLng(trip.routePolyline!)
            : null);

    // Determine which marker to emphasize based on status
    final bool headingToPickup =
        trip.status == TripStatus.accepted ||
        trip.status == TripStatus.driverArriving;

    return Scaffold(
      body: Stack(
        children: [
          // Full screen map with route
          AppMapWidget(
            initialCenter: headingToPickup
                ? LatLng(trip.pickupLat, trip.pickupLng)
                : LatLng(trip.destLat, trip.destLng),
            pickupMarker: LatLng(trip.pickupLat, trip.pickupLng),
            destinationMarker: LatLng(trip.destLat, trip.destLng),
            routePoints: displayRoute,
            showUserLocation: true,
          ),

          // Top bar with back and chat
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildCircleButton(
                    icon: Icons.close_rounded,
                    onPressed: () => context.go(Routes.riderHome),
                  ),
                  const Spacer(),
                  // ETA badge
                  if (_etaMinutes != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 16,
                            color: headingToPickup
                                ? AppTheme.primaryColor
                                : AppTheme.successColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$_etaMinutes min',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: headingToPickup
                                  ? AppTheme.primaryColor
                                  : AppTheme.successColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  _buildCircleButton(
                    icon: Icons.chat_rounded,
                    onPressed: () =>
                        context.push('/rider/trip/${trip.id}/chat'),
                  ),
                ],
              ),
            ),
          ),

          // Bottom panel with trip info and actions
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomPanel(context, trip),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: AppTheme.cardShadow,
      ),
      child: IconButton(
        icon: Icon(icon, color: AppTheme.neutral700),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildBottomPanel(BuildContext context, TripModel trip) {
    String actionText;
    VoidCallback actionHandler;
    Color actionColor;
    String statusLabel;
    IconData statusIcon;

    switch (trip.status) {
      case TripStatus.accepted:
        actionText = 'I\'ve Arrived';
        actionHandler = () =>
            ref.read(tripStateProvider.notifier).markArriving();
        actionColor = AppTheme.primaryColor;
        statusLabel = 'Heading to pickup';
        statusIcon = Icons.directions_car_rounded;
        break;
      case TripStatus.driverArriving:
        actionText = 'Start Trip';
        actionHandler = () => ref.read(tripStateProvider.notifier).startTrip();
        actionColor = AppTheme.successColor;
        statusLabel = 'Arriving at pickup';
        statusIcon = Icons.pin_drop_rounded;
        break;
      case TripStatus.inProgress:
        actionText = 'Complete Trip';
        actionHandler = () async {
          await ref.read(tripStateProvider.notifier).completeTrip();
          if (context.mounted) {
            context.go(Routes.riderHome);
          }
        };
        actionColor = AppTheme.successColor;
        statusLabel = 'En route to destination';
        statusIcon = Icons.navigation_rounded;
        break;
      case TripStatus.completed:
        actionText = 'Done';
        actionHandler = () => context.go(Routes.riderHome);
        actionColor = AppTheme.successColor;
        statusLabel = 'Trip completed';
        statusIcon = Icons.check_circle_rounded;
        break;
      default:
        actionText = 'Continue';
        actionHandler = () {};
        actionColor = AppTheme.primaryColor;
        statusLabel = 'Trip in progress';
        statusIcon = Icons.local_taxi_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.neutral300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Status row
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(statusIcon, color: actionColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: actionColor,
                        ),
                      ),
                      if (trip.status == TripStatus.accepted ||
                          trip.status == TripStatus.driverArriving)
                        Text(
                          trip.pickupAddress ?? 'Pickup location',
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 13,
                            color: AppTheme.neutral500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      else if (trip.status == TripStatus.inProgress)
                        Text(
                          trip.destAddress ?? 'Destination',
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 13,
                            color: AppTheme.neutral500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Passenger info
            FutureBuilder<Map<String, dynamic>?>(
              future: _clientInfoFuture,
              builder: (context, snapshot) {
                final clientName =
                    snapshot.data?['name'] as String? ?? 'Passenger';
                final avatarUrl = snapshot.data?['avatar_url'] as String?;
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppTheme.primaryColor.withValues(
                        alpha: 0.1,
                      ),
                      backgroundImage: avatarUrl != null
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl == null
                          ? const Icon(
                              Icons.person,
                              color: AppTheme.primaryColor,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            clientName,
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Text(
                            'Passenger',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 13,
                              color: AppTheme.neutral500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chat_rounded),
                      color: AppTheme.primaryColor,
                      onPressed: () =>
                          context.push('/rider/trip/${trip.id}/chat'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // Trip info row with live data
            Row(
              children: [
                Expanded(
                  child: _buildTripInfoItem(
                    icon: Icons.straighten_rounded,
                    label: 'Distance',
                    value:
                        '${(_routeDistanceKm ?? trip.distanceKm)?.toStringAsFixed(1) ?? '—'} km',
                  ),
                ),
                Expanded(
                  child: _buildTripInfoItem(
                    icon: Icons.schedule_rounded,
                    label: 'ETA',
                    value: '${_etaMinutes ?? trip.durationMin ?? '—'} min',
                  ),
                ),
                Expanded(
                  child: _buildTripInfoItem(
                    icon: Icons.payments_rounded,
                    label: 'Fare',
                    value:
                        '₱${(trip.fareFinal ?? trip.fareEstimated).toStringAsFixed(0)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Action button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: actionHandler,
                style: ElevatedButton.styleFrom(backgroundColor: actionColor),
                child: Text(actionText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.neutral400, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Outfit',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Outfit',
            fontSize: 12,
            color: AppTheme.neutral500,
          ),
        ),
      ],
    );
  }
}
