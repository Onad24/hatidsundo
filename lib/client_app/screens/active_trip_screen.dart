import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../models/trip_model.dart';
import '../../models/driver_location_model.dart';

import '../../state/state.dart';
import '../../services/services.dart';
import '../../widgets/map_widget.dart';

/// Active trip screen with realtime tracking
class ActiveTripScreen extends ConsumerStatefulWidget {
  final String tripId;

  const ActiveTripScreen({super.key, required this.tripId});

  @override
  ConsumerState<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends ConsumerState<ActiveTripScreen> {
  StreamSubscription<DriverLocationModel>? _driverSubscription;
  StreamSubscription<Map<String, dynamic>>? _routeSubscription;
  DriverLocationModel? _driverLocation;
  List<LatLng>? _dynamicRoutePoints;
  String? _lastRoutePolyline;
  Timer? _routeUpdateDebouncer;
  Timer? _periodicRouteRefresh;
  bool _isRouteUpdating = false;
  DateTime? _lastSubscriptionUpdate;

  // Cache driver info future so it doesn't re-fire on every rebuild
  Future<Map<String, dynamic>?>? _driverInfoFuture;
  String? _cachedRiderId;

  @override
  void initState() {
    super.initState();
    // Defer processing until after build to access ref
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeTracking();
      final trip = ref.read(tripStateProvider).activeTrip;
      if (trip != null &&
          (trip.status == TripStatus.accepted ||
           trip.status == TripStatus.driverArriving ||
           trip.status == TripStatus.inProgress)) {
        _startClientTracking(trip.id, trip.clientId);
      }
      _initializeTracking();
    });
  }

  void _startClientTracking(String tripId, String clientId) {
    try {
      ref.read(locationServiceProvider).startClientTracking(
        clientId: clientId,
        tripId: tripId,
      );
    } catch (e) {
      debugPrint('Failed to start client tracking: $e');
    }
  }

  void _stopClientTracking() {
    try {
      ref.read(locationServiceProvider).stopClientTracking();
    } catch (e) {
      debugPrint('Failed to stop client tracking: $e');
    }
  }

  @override
  void didUpdateWidget(ActiveTripScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tripId != oldWidget.tripId) {
      _cleanupTracking();
      _initializeTracking();
    }
  }

  @override
  void dispose() {
    _cleanupTracking();
    _routeSubscription?.cancel();
    _routeUpdateDebouncer?.cancel();
    _periodicRouteRefresh?.cancel();
    _stopClientTracking();
    super.dispose();
  }

  void _cleanupTracking() {
    _driverSubscription?.cancel();
    _driverSubscription = null;
    _routeSubscription?.cancel();
    _routeSubscription = null;
    _periodicRouteRefresh?.cancel();
    _periodicRouteRefresh = null;
  }

  void _initializeTracking() {
    final tripState = ref.read(tripStateProvider);
    final trip = tripState.activeTrip;

    if (trip != null && trip.riderId != null) {
      _subscribeToDriver(trip.riderId!);
      _fetchDriverInfo(trip.riderId!);
    }

    // Subscribe to route broadcasts from rider
    _subscribeToRouteUpdates();

    // Periodic route refresh every 10 seconds as fallback
    _periodicRouteRefresh = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshRouteFromDriver(),
    );
  }

  void _fetchDriverInfo(String riderId) {
    if (_cachedRiderId == riderId) return; // already fetched for this rider
    _cachedRiderId = riderId;
    setState(() {
      _driverInfoFuture = ref.read(riderServiceProvider).getDriverInfo(riderId);
    });
  }

  void _subscribeToDriver(String driverId) {
    _driverSubscription?.cancel();
    _driverSubscription = ref
        .read(locationServiceProvider)
        .subscribeToDriverLocation(driverId)
        .listen((location) {
          if (mounted) {
            setState(() {
              _driverLocation = location;
            });
            _debouncedRouteUpdate(location);
          }
        });
  }

  /// Subscribe to route broadcasts from the rider's navigation screen
  void _subscribeToRouteUpdates() {
    _routeSubscription?.cancel();
    _routeSubscription = ref
        .read(tripServiceProvider)
        .subscribeRouteUpdates(widget.tripId)
        .listen((payload) {
          if (!mounted) return;
          
          final trip = ref.read(tripStateProvider).activeTrip;
          if (trip == null) return;
          
          // Only use broadcast route when driver is heading to pickup.
          // When in progress, client routing is local based on GPS.
          if (trip.status == TripStatus.inProgress) return;

          // 10-second throttle on subscription updates to avoid rapid jitter
          if (_lastSubscriptionUpdate != null &&
              DateTime.now().difference(_lastSubscriptionUpdate!) < const Duration(seconds: 10)) {
            return;
          }
          _lastSubscriptionUpdate = DateTime.now();

          final polyline = payload['polyline'] as String?;
          if (polyline != null && polyline != _lastRoutePolyline) {
            setState(() {
              _dynamicRoutePoints = polylineToLatLng(polyline);
              _lastRoutePolyline = polyline;
            });
          }
        });
  }

  /// Debounced route update when driver location changes
  void _debouncedRouteUpdate(DriverLocationModel driverLoc) {
    if (_isRouteUpdating) return;

    // Cancel previous debouncer before creating a new one
    _routeUpdateDebouncer?.cancel();
    _routeUpdateDebouncer = Timer(const Duration(seconds: 3), () {
      _fetchRouteFromOsrm(driverLoc);
    });
  }

  /// Periodic fallback: refresh route using latest driver location
  void _refreshRouteFromDriver() {
    if (_driverLocation == null || _isRouteUpdating) return;
    _fetchRouteFromOsrm(_driverLocation!);
  }

  /// Fetch route from OSRM based on driver's current position
  Future<void> _fetchRouteFromOsrm(DriverLocationModel driverLoc) async {
    final trip = ref.read(tripStateProvider).activeTrip;
    if (trip == null || !mounted) return;

    // Only do local OSRM routing when the trip is actually in progress (picked up).
    if (trip.status != TripStatus.inProgress) {
      return;
    }

    setState(() {
      _isRouteUpdating = true;
    });

    try {
      final osrmService = ref.read(osrmServiceProvider);
      
      final route = await osrmService.getRoute(
        startLat: driverLoc.lat,
        startLng: driverLoc.lng,
        endLat: trip.destLat,
        endLng: trip.destLng,
      );

      if (mounted && route.polyline != _lastRoutePolyline) {
        setState(() {
          _dynamicRoutePoints = polylineToLatLng(route.polyline);
          _lastRoutePolyline = route.polyline;
        });
      }
    } catch (e) {
      debugPrint('Error updating route: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRouteUpdating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripState = ref.watch(tripStateProvider);
    final trip = tripState.activeTrip;

    // Monitor trip status changes
    ref.listen(tripStateProvider, (previous, next) {
      final prevTrip = previous?.activeTrip;
      final nextTrip = next.activeTrip;

      if (nextTrip == null) return;

      // Handle driver assignment
      if (nextTrip.riderId != null && prevTrip?.riderId != nextTrip.riderId) {
        _subscribeToDriver(nextTrip.riderId!);
        _fetchDriverInfo(nextTrip.riderId!);
      }

      // Handle client tracking based on status transition
      if (nextTrip.status != prevTrip?.status) {
        if (nextTrip.status == TripStatus.accepted ||
            nextTrip.status == TripStatus.driverArriving ||
            nextTrip.status == TripStatus.inProgress) {
          _startClientTracking(nextTrip.id, nextTrip.clientId);
        } else if (nextTrip.status == TripStatus.completed) {
          _stopClientTracking();
        } else if (nextTrip.status == TripStatus.cancelled) {
          _stopClientTracking();
        }
      }
    });

    if (trip == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Determine which route to display
    // Prefer dynamic route (from broadcast or OSRM re-fetch) over static
    List<LatLng>? displayRoute;

    if (_dynamicRoutePoints != null &&
        (trip.status == TripStatus.accepted ||
            trip.status == TripStatus.driverArriving ||
            trip.status == TripStatus.inProgress)) {
      // Use live route from rider broadcast or our own OSRM fetch
      displayRoute = _dynamicRoutePoints;
    } else if (trip.routePolyline != null) {
      // Fallback to static route (pickup -> destination)
      displayRoute = polylineToLatLng(trip.routePolyline!);
    }

    // Drivers list for map
    final drivers = _driverLocation != null
        ? [_driverLocation!]
        : <DriverLocationModel>[];

    return Scaffold(
      body: Stack(
        children: [
          // Map with tracking
          AppMapWidget(
            initialCenter: LatLng(trip.pickupLat, trip.pickupLng),
            pickupMarker: LatLng(trip.pickupLat, trip.pickupLng),
            destinationMarker: LatLng(trip.destLat, trip.destLng),
            routePoints: displayRoute,
            drivers: drivers,
          ),

          // Back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: AppTheme.cardShadow,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => context.go(Routes.clientHome),
                ),
              ),
            ),
          ),

          // Bottom panel
          DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.25,
            maxChildSize: 0.6,
            builder: (context, scrollController) {
              return _buildBottomPanel(context, scrollController, trip);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(
    BuildContext context,
    ScrollController scrollController,
    TripModel trip,
  ) {
    return Container(
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
      child: SingleChildScrollView(
        controller: scrollController,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.neutral300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Status
              _buildStatusHeader(trip),
              const SizedBox(height: 20),

              // Driver info (when assigned)
              if (trip.riderId != null) ...[
                _buildDriverInfo(trip),
                const SizedBox(height: 16),
              ],

              // Location info
              _buildLocationInfo(trip),
              const SizedBox(height: 20),

              // Action buttons
              _buildActionButtons(trip),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHeader(TripModel trip) {
    String statusText;
    String statusSubtext;
    Color statusColor;
    IconData statusIcon;

    switch (trip.status) {
      case TripStatus.pending:
      case TripStatus.offered:
        statusText = 'Finding your driver';
        statusSubtext = 'Please wait while we find a driver near you';
        statusColor = AppTheme.warningColor;
        statusIcon = Icons.search_rounded;
        break;
      case TripStatus.accepted:
        statusText = 'Driver assigned!';
        statusSubtext = 'Your driver is on the way to pick you up';
        statusColor = AppTheme.primaryColor;
        statusIcon = Icons.local_taxi_rounded;
        break;
      case TripStatus.driverArriving:
        statusText = 'Driver is arriving';
        statusSubtext = 'Your driver is almost at the pickup location';
        statusColor = AppTheme.secondaryColor;
        statusIcon = Icons.pin_drop_rounded;
        break;
      case TripStatus.inProgress:
        statusText = 'On the way';
        statusSubtext = 'Heading to your destination';
        statusColor = AppTheme.successColor;
        statusIcon = Icons.directions_car_rounded;
        break;
      case TripStatus.completed:
        statusText = 'Trip completed';
        statusSubtext = 'Thank you for riding with us!';
        statusColor = AppTheme.successColor;
        statusIcon = Icons.check_circle_rounded;
        break;
      case TripStatus.cancelled:
        statusText = 'Trip cancelled';
        statusSubtext = trip.cancellationReason ?? 'This trip was cancelled';
        statusColor = AppTheme.errorColor;
        statusIcon = Icons.cancel_rounded;
        break;
    }

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(statusIcon, color: statusColor),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusText,
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
              Text(
                statusSubtext,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 13,
                  color: AppTheme.neutral500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDriverInfo(TripModel trip) {
    // If future hasn't been set yet, fetch now (safety net)
    if (_driverInfoFuture == null && trip.riderId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchDriverInfo(trip.riderId!);
      });
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: _driverInfoFuture,
      builder: (context, snapshot) {
        // Still waiting on the future
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.neutral100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        // Data came back (possibly null if RLS blocked it)
        final driver = snapshot.data;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.neutral100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                backgroundImage: driver?['avatar_url'] != null
                    ? NetworkImage(driver!['avatar_url'])
                    : null,
                child: driver?['avatar_url'] == null
                    ? const Icon(Icons.person, color: AppTheme.primaryColor)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver?['name'] ?? 'Your Driver',
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: AppTheme.warningColor,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            driver != null
                                ? '${driver['rating']} • ${driver['vehicle']}'
                                : 'Driver assigned',
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 12,
                              color: AppTheme.neutral500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Chat button
              IconButton(
                icon: const Icon(Icons.chat_rounded),
                color: AppTheme.primaryColor,
                onPressed: () {
                  context.push('/client/trip/${trip.id}/chat');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocationInfo(TripModel trip) {
    return Column(
      children: [
        // Pickup
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: AppTheme.successColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pickup',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      color: AppTheme.neutral500,
                    ),
                  ),
                  Text(
                    trip.pickupAddress ?? 'Pickup location',
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),

        // Connector
        Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Row(
            children: [
              Container(width: 2, height: 24, color: AppTheme.neutral300),
            ],
          ),
        ),

        // Destination
        Row(
          children: [
            const Icon(
              Icons.location_on_rounded,
              color: AppTheme.errorColor,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Destination',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      color: AppTheme.neutral500,
                    ),
                  ),
                  Text(
                    trip.destAddress ?? 'Destination',
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons(TripModel trip) {
    if (trip.isCompleted) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context.go(Routes.clientHome),
          child: const Text('Back to Home'),
        ),
      );
    }

    if (trip.isCancelled) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context.go(Routes.clientHome),
          child: const Text('Back to Home'),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _showCancelDialog(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.errorColor,
              side: const BorderSide(color: AppTheme.errorColor),
            ),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () {
              if (trip.riderId != null) {
                context.push('/client/trip/${trip.id}/chat');
              }
            },
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const Text('Chat'),
          ),
        ),
      ],
    );
  }

  void _showCancelDialog() {
    String? selectedReason;
    final otherController = TextEditingController();
    final reasons = [
      'Changed my mind',
      'Driver is taking too long',
      'Found another ride',
      'Incorrect pickup location',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cancel Trip'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please select a reason:',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 14,
                    color: AppTheme.neutral500,
                  ),
                ),
                const SizedBox(height: 8),
                ...reasons.map(
                  (reason) => RadioListTile<String>(
                    title: Text(
                      reason,
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 14,
                      ),
                    ),
                    value: reason,
                    groupValue: selectedReason,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (value) {
                      setDialogState(() => selectedReason = value);
                    },
                  ),
                ),
                if (selectedReason == 'Other') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: otherController,
                    decoration: InputDecoration(
                      hintText: 'Please specify...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    maxLines: 2,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
            TextButton(
              onPressed: selectedReason == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      final reason = selectedReason == 'Other'
                          ? (otherController.text.trim().isNotEmpty
                              ? otherController.text.trim()
                              : 'Other')
                          : selectedReason;
                      ref
                          .read(tripStateProvider.notifier)
                          .cancelTrip(reason: reason);
                    },
              style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
              child: const Text('Cancel Trip'),
            ),
          ],
        ),
      ),
    );
  }
}
