import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/theme.dart';
import '../../services/services.dart';
import '../../state/state.dart';
import '../../widgets/map_widget.dart';

/// Request ride screen with pickup and destination selection
class RequestRideScreen extends ConsumerStatefulWidget {
  const RequestRideScreen({super.key});

  @override
  ConsumerState<RequestRideScreen> createState() => _RequestRideScreenState();
}

class _RequestRideScreenState extends ConsumerState<RequestRideScreen> {
  final _pickupController = TextEditingController();
  final _destController = TextEditingController();

  LatLng? _pickupLocation;
  LatLng? _destLocation;
  String? _pickupAddress;
  String? _destAddress;
  RouteInfo? _routeInfo;
  double?
  _nearestDriverDistanceKm; // distance from nearest available rider to pickup
  bool _isLoading = false;
  bool _selectingPickup = true;
  String _selectedVehicleType = 'sedan';

  // Search state
  List<LocationResult> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    final position = await ref.read(currentPositionProvider.future);
    if (position != null && mounted) {
      setState(() {
        _pickupLocation = LatLng(position.latitude, position.longitude);
        _pickupAddress = 'Current Location';
        _pickupController.text = 'Current Location';
      });
      // Optionally reverse geocode current location for accuracy
      _reverseGeocode(_pickupLocation!, isPickup: true);
    }
  }

  Future<void> _calculateRoute() async {
    if (_pickupLocation == null || _destLocation == null) return;

    setState(() => _isLoading = true);
    try {
      final osrmService = ref.read(osrmServiceProvider);
      final supabase = ref.read(supabaseServiceProvider);

      // Run route calculation and nearby drivers lookup IN PARALLEL
      // since they are independent — this halves the wait time.
      final routeFuture = osrmService.getRoute(
        startLat: _pickupLocation!.latitude,
        startLng: _pickupLocation!.longitude,
        endLat: _destLocation!.latitude,
        endLng: _destLocation!.longitude,
      );

      final driversFuture = supabase.client
          .rpc(
            'get_nearby_drivers',
            params: {
              'p_lat': _pickupLocation!.latitude,
              'p_lng': _pickupLocation!.longitude,
              'p_radius_km': 20.0, // wide radius for fare estimate
            },
          )
          .then<List?>((result) => result as List?)
          .catchError((e) {
            // Non-blocking: fare estimate will omit driver pickup distance
            debugPrint('Could not fetch nearby drivers for fare estimate: $e');
            return null;
          });

      final results = await Future.wait([routeFuture, driversFuture]);

      final route = results[0] as RouteInfo;
      final driversRaw = results[1] as List?;

      double? nearestDriverKm;
      if (driversRaw != null && driversRaw.isNotEmpty) {
        // Drivers are sorted nearest-first by the RPC
        nearestDriverKm = (driversRaw.first['distance_km'] as num?)?.toDouble();
      }

      if (mounted) {
        setState(() {
          _routeInfo = route;
          _nearestDriverDistanceKm = nearestDriverKm;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error calculating route: $e')));
      }
    }
  }

  void _onMapTap(LatLng location) {
    // Determine which field we are setting
    final isPickup = _selectingPickup;

    setState(() {
      if (isPickup) {
        _pickupLocation = location;
        _pickupAddress = 'Loading address...'; // Temporary
        _pickupController.text =
            'Pin at ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}';
        _selectingPickup = false; // Auto-advance
      } else {
        _destLocation = location;
        _destAddress = 'Loading address...'; // Temporary
        _destController.text =
            'Pin at ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}';
      }
    });

    // Reverse geocode
    _reverseGeocode(location, isPickup: isPickup);

    if (_pickupLocation != null && _destLocation != null) {
      _calculateRoute();
    }
  }

  Future<void> _reverseGeocode(
    LatLng location, {
    required bool isPickup,
  }) async {
    try {
      final result = await ref
          .read(geocodingServiceProvider)
          .reverseGeocode(location.latitude, location.longitude);
      if (mounted && result != null) {
        setState(() {
          if (isPickup) {
            _pickupAddress = result.name.isNotEmpty
                ? result.name
                : result.address;
            // Ensure address isn't too long for the field
            _pickupController.text = _pickupAddress ?? '';
          } else {
            _destAddress = result.name.isNotEmpty
                ? result.name
                : result.address;
            _destController.text = _destAddress ?? '';
          }
        });
      }
    } catch (e) {
      debugPrint('Reverse geocode error: $e');
    }
  }

  // Handle search input changes
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Don't search if query is empty or just coordinate strings we set ourselves
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearching = true);
      try {
        final results = await ref.read(geocodingServiceProvider).search(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  void _selectSearchResult(LocationResult result) {
    setState(() {
      final location = LatLng(result.lat, result.lng);

      if (_selectingPickup) {
        _pickupLocation = location;
        _pickupAddress = result.name.isNotEmpty ? result.name : result.address;
        _pickupController.text = _pickupAddress!;
        _selectingPickup = false; // Auto-advance
      } else {
        _destLocation = location;
        _destAddress = result.name.isNotEmpty ? result.name : result.address;
        _destController.text = _destAddress!;
      }

      _searchResults = []; // Clear results
      FocusScope.of(context).unfocus(); // Hide keyboard
    });

    if (_pickupLocation != null && _destLocation != null) {
      _calculateRoute();
    }
  }

  Future<void> _requestRide() async {
    if (_pickupLocation == null || _destLocation == null) return;

    setState(() => _isLoading = true);
    try {
      // If pickup is still "Current Location", re-fetch fresh GPS
      // so we don't send stale coordinates from when the screen opened
      if (_pickupAddress == 'Current Location') {
        final freshPos = await ref
            .read(locationServiceProvider)
            .getCurrentPosition();
        if (freshPos != null && mounted) {
          _pickupLocation = LatLng(freshPos.latitude, freshPos.longitude);
        }
      }

      final tripNotifier = ref.read(tripStateProvider.notifier);
      final trip = await tripNotifier.requestRide(
        pickupLat: _pickupLocation!.latitude,
        pickupLng: _pickupLocation!.longitude,
        pickupAddress: _pickupAddress,
        destLat: _destLocation!.latitude,
        destLng: _destLocation!.longitude,
        destAddress: _destAddress,
        nearestDriverDistanceKm: _nearestDriverDistanceKm,
        vehicleType: _selectedVehicleType,
      );

      if (trip != null && mounted) {
        context.go('/client/trip/${trip.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error requesting ride: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = _routeInfo != null
        ? polylineToLatLng(_routeInfo!.polyline)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Ride'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // Location inputs card
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
              boxShadow: AppTheme.cardShadow,
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Timeline indicator (Green dot -> line -> Red pin)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 14,
                        left: 4,
                        right: 12,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: AppTheme.successColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.successColor.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 2,
                            height: 38,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.neutral300,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: AppTheme.errorColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.errorColor.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Inputs column
                    Expanded(
                      child: Column(
                        children: [
                          _buildLocationInput(
                            controller: _pickupController,
                            icon: Icons.circle,
                            iconColor: AppTheme.successColor,
                            hint: 'Pickup location',
                            isSelected: _selectingPickup,
                            onTap: () =>
                                setState(() => _selectingPickup = true),
                          ),
                          const SizedBox(height: 10),
                          _buildLocationInput(
                            controller: _destController,
                            icon: Icons.location_on_rounded,
                            iconColor: AppTheme.errorColor,
                            hint: 'Where to?',
                            isSelected: !_selectingPickup,
                            onTap: () =>
                                setState(() => _selectingPickup = false),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Search Results Overlay
          if (_searchResults.isNotEmpty)
            Expanded(
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _searchResults.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, indent: 64),
                  itemBuilder: (context, index) {
                    final result = _searchResults[index];
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        result.name,
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        result.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 13,
                          color: AppTheme.neutral500,
                        ),
                      ),
                      onTap: () => _selectSearchResult(result),
                    );
                  },
                ),
              ),
            )
          else
            // Map
            Expanded(
              child: Stack(
                children: [
                  AppMapWidget(
                    initialCenter:
                        _pickupLocation ?? const LatLng(14.5995, 120.9842),
                    pickupMarker: _pickupLocation,
                    destinationMarker: _destLocation,
                    routePoints: routePoints,
                    onTap: _onMapTap,
                  ),

                  // Selection hint pill
                  Positioned(
                    top: 16,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusFull,
                        ),
                        border: Border.all(color: AppTheme.neutral200),
                        boxShadow: AppTheme.floatingShadow,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            color: AppTheme.primaryColor,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _selectingPickup
                                ? 'Tap map to choose pickup point'
                                : 'Tap map to set destination',
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.neutral800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_isSearching)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),

          // Route info and request button
          if (_searchResults.isEmpty) ...[
            if (_routeInfo != null)
              _buildRouteInfoPanel()
            else if (_pickupLocation != null &&
                _destLocation != null &&
                _isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationInput({
    required TextEditingController controller,
    required IconData icon,
    required Color iconColor,
    required String hint,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primaryColor.withValues(alpha: 0.06)
            : AppTheme.neutral400,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onTap: onTap,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintStyle: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 15,
                  color: AppTheme.neutral400,
                ),
              ),
              style: const TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: AppTheme.neutral400,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                _onSearchChanged('');
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.neutral200,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: AppTheme.neutral600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRouteInfoPanel() {
    final fareSettingsAsync = ref.watch(fareSettingsProvider);
    final fareSettings = fareSettingsAsync.valueOrNull ?? const FareSettings();

    final destKm = _routeInfo!.distanceKm;
    final driverKm = _nearestDriverDistanceKm ?? 0.0;
    final estimatedFare = fareSettings.calculateFare(
      destKm: destKm,
      driverPickupKm: driverKm,
      vehicleType: _selectedVehicleType,
    );
    final isNight = fareSettings.isNightTime(DateTime.now());
    final bool noDriversNearby = _nearestDriverDistanceKm == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Distance & duration summary bar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.neutral100,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.straighten_rounded,
                        size: 15,
                        color: AppTheme.neutral600,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${_routeInfo!.distanceKm.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.neutral800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.neutral100,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 15,
                        color: AppTheme.neutral600,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '~${_routeInfo!.durationMinutes} mins',
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.neutral800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (isNight)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    ),
                    child: const Text(
                      '🌙 Night rate',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.warningColor,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Vehicle type cards selector
            Row(
              children: [
                _buildVehicleTypeChip(
                  type: 'motorcycle',
                  icon: Icons.two_wheeler_rounded,
                  label: 'Motorcycle',
                  subtitle: '1 Passenger',
                  fare: fareSettings.calculateFare(
                    destKm: destKm,
                    driverPickupKm: driverKm,
                    vehicleType: 'motorcycle',
                  ),
                ),
                const SizedBox(width: 8),
                _buildVehicleTypeChip(
                  type: 'sedan',
                  icon: Icons.directions_car_rounded,
                  label: 'Sedan',
                  subtitle: '2-4 Seats',
                  fare: fareSettings.calculateFare(
                    destKm: destKm,
                    driverPickupKm: driverKm,
                    vehicleType: 'sedan',
                  ),
                ),
                const SizedBox(width: 8),
                _buildVehicleTypeChip(
                  type: 'suv',
                  icon: Icons.directions_car_filled_rounded,
                  label: 'SUV',
                  subtitle: '6-8 Seats',
                  fare: fareSettings.calculateFare(
                    destKm: destKm,
                    driverPickupKm: driverKm,
                    vehicleType: 'suv',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (noDriversNearby)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  '* Fare estimate excludes pickup distance (no nearby riders currently active)',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 11,
                    color: AppTheme.neutral500,
                  ),
                ),
              ),

            // Big Gradient Request Button
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.elevatedShadow,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isLoading ? null : _requestRide,
                  borderRadius: BorderRadius.circular(16),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                noDriversNearby
                                    ? 'Request Ride'
                                    : 'Confirm & Request',
                                style: const TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusFull,
                                  ),
                                ),
                                child: Text(
                                  '₱${estimatedFare.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleTypeChip({
    required String type,
    required IconData icon,
    required String label,
    String? subtitle,
    required double fare,
  }) {
    final isSelected = _selectedVehicleType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedVehicleType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withValues(alpha: 0.08)
                : AppTheme.neutral100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppTheme.primaryColor : AppTheme.neutral200,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 24,
                color: isSelected ? AppTheme.primaryColor : AppTheme.neutral600,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.neutral800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? AppTheme.primaryColor.withValues(alpha: 0.8)
                        : AppTheme.neutral500,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                '₱${fare.toStringAsFixed(0)}',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.neutral900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
